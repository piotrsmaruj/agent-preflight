import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

@Suite("Security boundary")
struct SecurityBoundaryTests {
  @Test("sensitive token always describes itself as redacted")
  func sensitiveTokenAlwaysDescribesItselfAsRedacted() throws {
    let token = try SensitiveToken("sk-ant-fixture-secret")

    #expect(String(describing: token) == "<redacted>")
    #expect(String(reflecting: token) == "<redacted>")
  }

  @Test("diagnostic events cannot carry raw errors or secrets")
  func diagnosticEventsCannotCarryRawErrorsOrSecrets() {
    let rendered = DiagnosticEvent.providerFailed(.claudeCode, .unauthorized).description

    #expect(rendered == "provider=claudeCode failure=unauthorized")
    #expect(!rendered.contains("sk-ant-fixture-secret"))
  }

  @Test("populated cache JSON contains only normalized snapshot fields")
  func populatedCacheJSONContainsOnlyNormalizedSnapshotFields() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)

    try await cache.save(Self.populatedSnapshots())

    let text = try String(
      contentsOf: directory.appendingPathComponent("quota-cache-v1.json"),
      encoding: .utf8
    )
    for expected in ["provider", "windows", "fetchedAt", "kind", "remaining", "value", "resetsAt"] {
      #expect(text.contains("\"\(expected)\""))
    }
    for forbidden in ["accessToken", "refreshToken", "Authorization", "Cookie"] {
      #expect(!text.localizedCaseInsensitiveContains(forbidden))
    }
  }

  private static func populatedSnapshots() throws -> [ProviderIdentifier: QuotaSnapshot] {
    let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
    let claudeCode = try QuotaSnapshot(
      provider: .claudeCode,
      windows: [
        QuotaWindow(kind: .short, remaining: RemainingPercentage(remaining: 78.5), resetsAt: nil),
        QuotaWindow(
          kind: .weekly,
          remaining: RemainingPercentage(remaining: 58),
          resetsAt: fetchedAt.addingTimeInterval(86_400)
        ),
      ],
      fetchedAt: fetchedAt
    )
    let codex = try QuotaSnapshot(
      provider: .codex,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: RemainingPercentage(remaining: 12.25),
          resetsAt: fetchedAt.addingTimeInterval(600)
        )
      ],
      fetchedAt: fetchedAt
    )
    return [.claudeCode: claudeCode, .codex: codex]
  }
}
