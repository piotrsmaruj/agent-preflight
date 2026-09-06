import AgentPreflightApplication
import AgentPreflightDomain

public struct CodexQuotaProvider: QuotaProvider {
  public let identifier = ProviderIdentifier.codex
  private let locator: any CodexExecutableLocating
  private let client: CodexAppServerClient
  private let parser: CodexRateLimitsParser
  private let clock: any Clock

  public init(
    locator: any CodexExecutableLocating,
    client: CodexAppServerClient,
    parser: CodexRateLimitsParser,
    clock: any Clock
  ) {
    self.locator = locator
    self.client = client
    self.parser = parser
    self.clock = clock
  }

  public func fetchSnapshot() async throws -> QuotaSnapshot {
    let executableURL = try await locator.locate()
    let response = try await client.readRateLimits(executableURL: executableURL)
    return try parser.parse(response, fetchedAt: clock.now())
  }
}
