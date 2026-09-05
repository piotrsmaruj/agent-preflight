import AgentPreflightApplication
import Foundation
import Security

public enum KeychainCredentialResult: Sendable {
  case data(Data)
  case status(OSStatus)
}

public protocol KeychainCredentialLoading: Sendable {
  func loadGenericPassword(service: String) -> KeychainCredentialResult
}

public struct SecurityKeychainCredentialLoader: KeychainCredentialLoading, @unchecked Sendable {
  public init() {}

  public func loadGenericPassword(service: String) -> KeychainCredentialResult {
    // Keychain defaults to allowing authentication UI when no UI policy key is supplied.
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return .status(status) }
    return .data(data)
  }
}

public struct KeychainClaudeCredentialReader: ClaudeCredentialReader, @unchecked Sendable {
  private let service: String
  private let decoder: ClaudeCredentialDecoder
  private let loader: any KeychainCredentialLoading

  public init(
    service: String,
    decoder: ClaudeCredentialDecoder = .init(),
    loader: any KeychainCredentialLoading = SecurityKeychainCredentialLoader()
  ) {
    self.service = service
    self.decoder = decoder
    self.loader = loader
  }

  public func readAccessToken() throws -> SensitiveToken {
    switch loader.loadGenericPassword(service: service) {
    case .data(let data):
      return try decoder.decode(data)
    case .status(let status):
      throw map(status)
    }
  }

  private func map(_ status: OSStatus) -> ProviderFailure {
    switch status {
    case errSecItemNotFound:
      return .unauthenticated
    case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
      return .keychainDenied
    default:
      return .invalidCredential
    }
  }
}
