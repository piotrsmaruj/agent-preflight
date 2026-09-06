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

  @Test("cache JSON contains only normalized snapshot fields")
  func cacheJSONContainsOnlyNormalizedSnapshotFields() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = JSONQuotaCache(directory: directory)

    try await cache.save([:])

    let text = try String(
      contentsOf: directory.appendingPathComponent("quota-cache-v1.json"),
      encoding: .utf8
    )
    for forbidden in ["accessToken", "refreshToken", "Authorization", "Cookie"] {
      #expect(!text.localizedCaseInsensitiveContains(forbidden))
    }
  }
}
