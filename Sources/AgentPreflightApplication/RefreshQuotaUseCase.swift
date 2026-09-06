import AgentPreflightDomain
import Foundation

public protocol RefreshQuotaUseCaseProtocol: Sendable {
  func current() async -> RefreshResult
  func refresh() async -> RefreshResult
}

public actor RefreshQuotaUseCase: RefreshQuotaUseCaseProtocol {
  private typealias ProviderOutcome = (ProviderIdentifier, Result<QuotaSnapshot, ProviderFailure>)

  private let providers: [any QuotaProvider]
  private let cache: any QuotaCache
  private let clock: any Clock
  private let diagnostics: any DiagnosticsSink
  private let configuration: RefreshConfiguration
  private var snapshots: [ProviderIdentifier: QuotaSnapshot] = [:]
  private var failures: [ProviderIdentifier: ProviderFailure] = [:]
  private var lastAttemptAt: Date?
  private var lastRefreshedProviders = Set<ProviderIdentifier>()
  private var didLoadCache = false

  public init(
    providers: [any QuotaProvider],
    cache: any QuotaCache,
    clock: any Clock,
    diagnostics: any DiagnosticsSink,
    configuration: RefreshConfiguration
  ) {
    self.providers = providers
    self.cache = cache
    self.clock = clock
    self.diagnostics = diagnostics
    self.configuration = configuration
  }

  public func current() async -> RefreshResult {
    await loadCacheIfNeeded()
    return makeResult(at: clock.now(), refreshedProviders: [])
  }

  public func refresh() async -> RefreshResult {
    await loadCacheIfNeeded()
    let now = clock.now()
    if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < configuration.cooldown {
      return makeResult(at: now, refreshedProviders: lastRefreshedProviders)
    }
    lastAttemptAt = now
    let outcomes = await fetchProviders()
    lastRefreshedProviders = await applyOutcomes(outcomes)
    await persistSnapshots()
    return makeResult(at: clock.now(), refreshedProviders: lastRefreshedProviders)
  }

  private func applyOutcomes(_ outcomes: [ProviderOutcome]) async -> Set<ProviderIdentifier> {
    var refreshed = Set<ProviderIdentifier>()
    for (provider, outcome) in outcomes {
      switch outcome {
      case .success(let snapshot):
        snapshots[provider] = snapshot
        failures[provider] = nil
        refreshed.insert(provider)
      case .failure(let failure):
        failures[provider] = failure
        await diagnostics.record(.providerFailed(provider, failure))
      }
    }
    return refreshed
  }

  private func fetchProviders() async -> [ProviderOutcome] {
    await withTaskGroup(of: ProviderOutcome.self) { group in
      for provider in providers {
        group.addTask {
          do {
            let snapshot = try await provider.fetchSnapshot()
            guard snapshot.provider == provider.identifier else {
              return (provider.identifier, .failure(.protocolFailure))
            }
            return (provider.identifier, .success(snapshot))
          } catch let failure as ProviderFailure {
            return (provider.identifier, .failure(failure))
          } catch {
            return (provider.identifier, .failure(.protocolFailure))
          }
        }
      }
      var outcomes: [ProviderOutcome] = []
      for await outcome in group { outcomes.append(outcome) }
      return outcomes
    }
  }

  private func loadCacheIfNeeded() async {
    guard !didLoadCache else { return }
    didLoadCache = true
    do { snapshots = try await cache.load() } catch { await diagnostics.record(.cacheReadFailed) }
  }

  private func persistSnapshots() async {
    do { try await cache.save(snapshots) } catch { await diagnostics.record(.cacheWriteFailed) }
  }

  private func makeResult(at now: Date, refreshedProviders: Set<ProviderIdentifier>)
    -> RefreshResult
  {
    let statuses = Dictionary(
      uniqueKeysWithValues: ProviderIdentifier.allCases.map { provider in
        let snapshot = snapshots[provider]
        let freshness = freshness(
          of: snapshot,
          provider: provider,
          refreshed: refreshedProviders,
          now: now
        )
        return (
          provider,
          ProviderStatus(
            provider: provider,
            snapshot: snapshot,
            freshness: freshness,
            failure: failures[provider]
          )
        )
      }
    )
    return RefreshResult(statuses: statuses, completedAt: now)
  }

  private func freshness(
    of snapshot: QuotaSnapshot?,
    provider: ProviderIdentifier,
    refreshed: Set<ProviderIdentifier>,
    now: Date
  ) -> SnapshotFreshness {
    guard let snapshot else { return .unavailable }
    if failures[provider] != nil
      || now.timeIntervalSince(snapshot.fetchedAt) > configuration.staleAfter
    {
      return .stale
    }
    return refreshed.contains(provider) ? .current : .cached
  }
}
