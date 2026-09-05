import AgentPreflightApplication
import Foundation

public struct SensitiveToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  fileprivate let rawValue: String
  public var description: String { "<redacted>" }
  public var debugDescription: String { "<redacted>" }

  public init(_ rawValue: String) throws {
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { throw ProviderFailure.invalidCredential }
    self.rawValue = normalized
  }

  func authorizationHeaderValue() -> String { "Bearer \(rawValue)" }
}

public protocol ClaudeCredentialReader: Sendable {
  func readAccessToken() throws -> SensitiveToken
}

public struct ClaudeCredentialDecoder: Sendable {
  public init() {}

  public func decode(_ data: Data) throws -> SensitiveToken {
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: data)
      guard let token = envelope.claudeAiOauth?.accessToken else {
        throw ProviderFailure.invalidCredential
      }
      return try SensitiveToken(token)
    } catch let error as ProviderFailure {
      throw error
    } catch {
      throw ProviderFailure.invalidCredential
    }
  }

  private struct Envelope: Decodable {
    let claudeAiOauth: OAuthCredential?
  }

  private struct OAuthCredential: Decodable {
    let accessToken: String?
  }
}
