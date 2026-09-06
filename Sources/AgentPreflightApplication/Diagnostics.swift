import AgentPreflightDomain

public enum DiagnosticEvent: Equatable, Sendable, CustomStringConvertible {
  case providerFailed(ProviderIdentifier, ProviderFailure)
  case cacheReadFailed
  case cacheWriteFailed

  public var description: String {
    switch self {
    case .providerFailed(let provider, let failure):
      "provider=\(provider.rawValue) failure=\(failure)"
    case .cacheReadFailed: "cache read failed"
    case .cacheWriteFailed: "cache write failed"
    }
  }
}

public protocol DiagnosticsSink: Sendable {
  func record(_ event: DiagnosticEvent) async
}
