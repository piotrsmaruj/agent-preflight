import Foundation

public struct ClaudeProviderConfiguration: Sendable {
  public let usageURL: URL
  public let betaHeaderValue: String
  public let keychainService: String

  public static var live: Self {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
      preconditionFailure("Bundled Claude usage URL is invalid")
    }
    return Self(
      usageURL: url,
      betaHeaderValue: "oauth-2025-04-20",
      keychainService: "Claude Code-credentials"
    )
  }
}
