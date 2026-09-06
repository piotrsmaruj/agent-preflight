import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain

@Suite("Refresh quota use case")
struct RefreshQuotaUseCaseTests {
  @Test("providers refresh concurrently and succeed independently")
  func providersRefreshConcurrentlyAndSucceedIndependently() async throws {
    let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
    let probe = ConcurrencyProbe()
    let codex = ProviderStub(
      identifier: .codex,
      result: .success(try snapshot(.codex, at: clock.now())),
      probe: probe
    )
    let claude = ProviderStub(
      identifier: .claudeCode,
      result: .failure(.unauthorized),
      probe: probe
    )
    let useCase = RefreshQuotaUseCase(
      providers: [codex, claude],
      cache: MemoryCache(),
      clock: clock,
      diagnostics: DiagnosticsSpy(),
      configuration: .live
    )

    let result = await useCase.refresh()

    #expect(result.statuses[.codex]?.freshness == .current)
    #expect(result.statuses[.claudeCode]?.failure == .unauthorized)
    let maximumConcurrentCalls = await probe.maximumConcurrentCalls
    #expect(maximumConcurrentCalls == 2)
  }

  @Test("a second refresh inside the cooldown does not call providers again")
  func secondRefreshWithinCooldownDoesNotCallProvidersAgain() async throws {
    let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
    let provider = ProviderStub(
      identifier: .codex,
      result: .success(try snapshot(.codex, at: clock.now()))
    )
    let useCase = RefreshQuotaUseCase(
      providers: [provider],
      cache: MemoryCache(),
      clock: clock,
      diagnostics: DiagnosticsSpy(),
      configuration: .live
    )

    _ = await useCase.refresh()
    _ = await useCase.refresh()
    let callsInsideCooldown = await provider.callCount
    #expect(callsInsideCooldown == 1)

    clock.advance(by: 31)
    _ = await useCase.refresh()
    let callsAfterCooldown = await provider.callCount
    #expect(callsAfterCooldown == 2)
  }

  @Test("a failed refresh keeps the last snapshot but marks it stale")
  func failedRefreshKeepsLastSnapshotButMarksItStale() async throws {
    let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
    let cached = try snapshot(.claudeCode, at: clock.now().addingTimeInterval(-60))
    let cache = MemoryCache(initial: [.claudeCode: cached])
    let provider = ProviderStub(identifier: .claudeCode, result: .failure(.networkUnavailable))
    let useCase = RefreshQuotaUseCase(
      providers: [provider],
      cache: cache,
      clock: clock,
      diagnostics: DiagnosticsSpy(),
      configuration: .live
    )

    _ = await useCase.current()
    let result = await useCase.refresh()

    #expect(result.statuses[.claudeCode]?.snapshot == cached)
    #expect(result.statuses[.claudeCode]?.freshness == .stale)
    #expect(!result.eligibleSnapshots.keys.contains(.claudeCode))
  }

  @Test("a snapshot older than fifteen minutes is stale")
  func snapshotOlderThanFifteenMinutesIsStale() async throws {
    let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
    let cached = try snapshot(.codex, at: clock.now().addingTimeInterval(-901))
    let useCase = RefreshQuotaUseCase(
      providers: [],
      cache: MemoryCache(initial: [.codex: cached]),
      clock: clock,
      diagnostics: DiagnosticsSpy(),
      configuration: .live
    )

    let result = await useCase.current()

    #expect(result.statuses[.codex]?.freshness == .stale)
  }

  @Test("cache failures emit only typed diagnostics")
  func cacheFailuresEmitOnlyTypedDiagnostics() async {
    let diagnostics = DiagnosticsSpy()
    let useCase = RefreshQuotaUseCase(
      providers: [],
      cache: FailingCache(),
      clock: MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      diagnostics: diagnostics,
      configuration: .live
    )

    _ = await useCase.current()
    _ = await useCase.refresh()

    let events = await diagnostics.events
    #expect(events == [.cacheReadFailed, .cacheWriteFailed])
  }

  private func snapshot(_ provider: ProviderIdentifier, at fetchedAt: Date) throws -> QuotaSnapshot
  {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: .init(remaining: 70),
          resetsAt: fetchedAt.addingTimeInterval(3_600)
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: .init(remaining: 60),
          resetsAt: fetchedAt.addingTimeInterval(86_400)
        ),
      ],
      fetchedAt: fetchedAt
    )
  }
}

private final class MutableClock: Clock, @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  init(now: Date) { self.current = now }

  func now() -> Date { lock.withLock { current } }

  func advance(by interval: TimeInterval) { lock.withLock { current.addTimeInterval(interval) } }
}

private actor ProviderStub: QuotaProvider {
  nonisolated let identifier: ProviderIdentifier
  private let result: Result<QuotaSnapshot, ProviderFailure>
  private let probe: ConcurrencyProbe?
  private(set) var callCount = 0

  init(
    identifier: ProviderIdentifier,
    result: Result<QuotaSnapshot, ProviderFailure>,
    probe: ConcurrencyProbe? = nil
  ) {
    self.identifier = identifier
    self.result = result
    self.probe = probe
  }

  func fetchSnapshot() async throws -> QuotaSnapshot {
    callCount += 1
    if let probe { await probe.enter() }
    do { try await Task.sleep(for: .milliseconds(20)) } catch {
      if let probe { await probe.leave() }
      throw error
    }
    if let probe { await probe.leave() }
    return try result.get()
  }
}

private actor MemoryCache: QuotaCache {
  private var snapshots: [ProviderIdentifier: QuotaSnapshot]

  init(initial: [ProviderIdentifier: QuotaSnapshot] = [:]) { snapshots = initial }

  func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { snapshots }

  func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws {
    self.snapshots = snapshots
  }
}

private actor FailingCache: QuotaCache {
  private enum Failure: Error { case unavailable }

  func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { throw Failure.unavailable }

  func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws {
    throw Failure.unavailable
  }
}

private actor ConcurrencyProbe {
  private var concurrentCalls = 0
  private(set) var maximumConcurrentCalls = 0

  func enter() {
    concurrentCalls += 1
    maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
  }

  func leave() { concurrentCalls -= 1 }
}

private actor DiagnosticsSpy: DiagnosticsSink {
  private(set) var events: [DiagnosticEvent] = []

  func record(_ event: DiagnosticEvent) async { events.append(event) }
}
