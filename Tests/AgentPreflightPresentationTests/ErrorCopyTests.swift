import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightPresentation

@Suite("Error copy")
struct ErrorCopyTests {
  @Test("a protocol failure names the provider that returned it")
  func protocolFailureNamesTheProviderThatReturnedIt() {
    #expect(
      ErrorCopy.recovery(for: .codex, failure: .protocolFailure)
        == "Codex app-server returned an invalid protocol response."
    )
    #expect(
      ErrorCopy.recovery(for: .claudeCode, failure: .protocolFailure)
        == "Claude usage endpoint returned an unexpected response. Refresh to try again."
    )
  }
}
