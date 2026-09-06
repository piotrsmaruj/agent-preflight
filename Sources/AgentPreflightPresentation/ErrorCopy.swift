import AgentPreflightApplication
import AgentPreflightDomain

/// The single recovery step shown for every provider failure the application can report.
public enum ErrorCopy {
  public static func recovery(for provider: ProviderIdentifier, failure: ProviderFailure) -> String
  {
    switch failure {
    case .executableMissing: "Codex executable not found. Set its path in Settings."
    case .unauthenticated:
      provider == .codex ? "Run `codex login`, then refresh." : "Run `claude login`, then refresh."
    case .keychainDenied: "Allow access to Claude Code credentials in Keychain, then refresh."
    case .invalidCredential:
      "Claude credentials are unsupported. Run `claude logout && claude login`."
    case .timeout: "The provider did not respond within 5 seconds. Refresh to try again."
    case .unauthorized: "The provider rejected the current login. Sign in again, then refresh."
    case .rateLimited: "Usage lookup is rate limited. Wait a moment, then refresh."
    case .unsupportedPayload: "This provider version returned an unsupported usage format."
    case .processFailure: "Codex app-server exited before returning usage."
    case .protocolFailure:
      provider == .codex
        ? "Codex app-server returned an invalid protocol response."
        : "Claude usage endpoint returned an unexpected response. Refresh to try again."
    case .networkUnavailable: "Usage could not be reached. Check the network, then refresh."
    }
  }
}
