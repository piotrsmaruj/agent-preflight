import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

@Suite("JSON quota cache")
struct JSONQuotaCacheTests {
  @Test("round trip creates a private directory and file")
  func roundTripCreatesPrivateDirectoryAndFile() async throws {
    let directory = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)
    let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
    let snapshot = try QuotaSnapshot(
      provider: .codex,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: RemainingPercentage(remaining: 70),
          resetsAt: fetchedAt.addingTimeInterval(600)
        )
      ],
      fetchedAt: fetchedAt
    )

    try await cache.save([.codex: snapshot])
    let loadedSnapshots = try await cache.load()

    let directoryMode = try Self.permissions(directory)
    let fileMode = try Self.permissions(directory.appendingPathComponent("quota-cache-v1.json"))

    #expect(loadedSnapshots[.codex] == snapshot)
    #expect(directoryMode == 0o700)
    #expect(fileMode == 0o600)
  }

  @Test("round trip preserves a window without a reset timestamp")
  func roundTripPreservesWindowWithoutResetTimestamp() async throws {
    let directory = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)
    let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
    let snapshot = try QuotaSnapshot(
      provider: .claudeCode,
      windows: [
        QuotaWindow(kind: .short, remaining: RemainingPercentage(remaining: 100), resetsAt: nil),
        QuotaWindow(
          kind: .weekly,
          remaining: RemainingPercentage(remaining: 42.5),
          resetsAt: fetchedAt.addingTimeInterval(86_400)
        ),
      ],
      fetchedAt: fetchedAt
    )

    try await cache.save([.claudeCode: snapshot])
    let loadedSnapshots = try await cache.load()

    let loaded = try #require(loadedSnapshots[.claudeCode])
    #expect(loaded == snapshot)
    #expect(loaded.windows[.short]?.resetsAt == nil)
  }

  @Test("round trip preserves a model-scoped weekly window with its scope label")
  func roundTripPreservesModelScopedWeeklyWindowWithScopeLabel() async throws {
    let directory = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)
    let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
    let snapshot = try QuotaSnapshot(
      provider: .claudeCode,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: RemainingPercentage(remaining: 46),
          resetsAt: fetchedAt.addingTimeInterval(3_600)
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: RemainingPercentage(remaining: 86),
          resetsAt: fetchedAt.addingTimeInterval(86_400)
        ),
        QuotaWindow(
          kind: .modelWeekly,
          remaining: RemainingPercentage(remaining: 86),
          resetsAt: fetchedAt.addingTimeInterval(86_400),
          scopeLabel: "Fable"
        ),
      ],
      fetchedAt: fetchedAt
    )

    try await cache.save([.claudeCode: snapshot])
    let loaded = try #require(try await cache.load()[.claudeCode])

    #expect(loaded == snapshot)
    #expect(loaded.windows[.modelWeekly]?.scopeLabel == "Fable")
  }

  @Test("load accepts a cache file written before scope labels existed")
  func loadAcceptsCacheFileWrittenBeforeScopeLabelsExisted() async throws {
    let directory = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyDocument = Data(
      #"{"version":1,"snapshots":[{"provider":"claudeCode","fetchedAt":810000000,"windows":[{"kind":"short","remaining":{"value":46},"resetsAt":810003600},{"kind":"weekly","remaining":{"value":86}}]}]}"#
        .utf8
    )
    try legacyDocument.write(to: directory.appendingPathComponent(JSONQuotaCache.fileName))

    let loaded = try #require(try await JSONQuotaCache(directory: directory).load()[.claudeCode])

    #expect(loaded.windows[.short]?.remaining.value == 46)
    #expect(loaded.windows[.short]?.scopeLabel == nil)
    #expect(loaded.windows[.weekly]?.resetsAt == nil)
    #expect(loaded.windows[.weekly]?.scopeLabel == nil)
  }

  @Test("load returns no snapshots when the cache file is absent")
  func loadReturnsNoSnapshotsWhenCacheFileIsAbsent() async throws {
    let directory = Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)

    let loadedSnapshots = try await cache.load()

    #expect(loadedSnapshots.isEmpty)
  }

  private static func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private static func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? NSNumber).intValue
  }
}
