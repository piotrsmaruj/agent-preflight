import AgentPreflightDomain
import Foundation

public enum ProviderFailure: Error, Equatable, Sendable {
  case executableMissing
  case unauthenticated
  case keychainDenied
  case invalidCredential
  case timeout
  case unauthorized
  case rateLimited(retryAfter: Date?)
  case unsupportedPayload
  case processFailure(exitCode: Int32?)
  case protocolFailure
  case networkUnavailable
}

public protocol QuotaProvider: Sendable {
  var identifier: ProviderIdentifier { get }
  func fetchSnapshot() async throws -> QuotaSnapshot
}
