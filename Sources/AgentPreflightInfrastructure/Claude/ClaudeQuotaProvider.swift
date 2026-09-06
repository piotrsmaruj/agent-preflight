import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

public struct ClaudeQuotaProvider: QuotaProvider {
  public let identifier = ProviderIdentifier.claudeCode
  private let credentialReader: any ClaudeCredentialReader
  private let httpClient: any HTTPClient
  private let parser: ClaudeUsageParser
  private let clock: any Clock
  private let configuration: ClaudeProviderConfiguration
  private let timeoutSeconds: TimeInterval

  public init(
    credentialReader: any ClaudeCredentialReader,
    httpClient: any HTTPClient,
    parser: ClaudeUsageParser,
    clock: any Clock,
    configuration: ClaudeProviderConfiguration,
    timeoutSeconds: TimeInterval
  ) {
    self.credentialReader = credentialReader
    self.httpClient = httpClient
    self.parser = parser
    self.clock = clock
    self.configuration = configuration
    self.timeoutSeconds = timeoutSeconds
  }

  /// The credential read stays outside `withTimeout` on purpose: the timeout bounds the network
  /// request only, and a pending Keychain access prompt must never be raced by a network timer.
  public func fetchSnapshot() async throws -> QuotaSnapshot {
    let token = try await credentialReader.readAccessToken()
    let request = makeRequest(token: token)
    do {
      return try await withTimeout(seconds: timeoutSeconds) {
        let response = try await httpClient.send(
          request,
          redirectPolicy: SameHostRedirectPolicy(origin: configuration.usageURL)
        )
        guard SameHostRedirectPolicy(origin: configuration.usageURL).allows(response.finalURL)
        else {
          throw ProviderFailure.protocolFailure
        }
        return try map(response)
      }
    } catch let failure as ProviderFailure {
      throw failure
    } catch {
      throw ProviderFailure.networkUnavailable
    }
  }

  private func makeRequest(token: SensitiveToken) -> URLRequest {
    var request = URLRequest(url: configuration.usageURL)
    request.httpMethod = "GET"
    request.timeoutInterval = timeoutSeconds
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(configuration.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")
    request.setValue(token.authorizationHeaderValue(), forHTTPHeaderField: "Authorization")
    return request
  }

  private func map(_ response: HTTPResponse) throws -> QuotaSnapshot {
    switch response.statusCode {
    case 200:
      return try parser.parse(response.data, fetchedAt: clock.now())
    case 401, 403:
      throw ProviderFailure.unauthorized
    case 429:
      throw ProviderFailure.rateLimited(retryAfter: nil)
    case 500...599:
      throw ProviderFailure.networkUnavailable
    default:
      throw ProviderFailure.unsupportedPayload
    }
  }
}
