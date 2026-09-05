import Foundation

public enum HTTPClientError: Error, Equatable, Sendable {
  case nonHTTPSRequest
  case invalidResponse
  case redirectRejected
  case transportFailure
}

public struct HTTPResponse: Sendable {
  public let data: Data
  public let statusCode: Int
  public let headers: [String: String]
  public let finalURL: URL

  public init(data: Data, statusCode: Int, headers: [String: String], finalURL: URL) {
    self.data = data
    self.statusCode = statusCode
    self.headers = headers
    self.finalURL = finalURL
  }
}

public struct SameHostRedirectPolicy: Sendable {
  public let origin: URL

  public init(origin: URL) { self.origin = origin }

  public func allows(_ proposedURL: URL) -> Bool {
    origin.scheme?.lowercased() == "https"
      && proposedURL.scheme?.lowercased() == "https"
      && origin.host?.lowercased() == proposedURL.host?.lowercased()
      && origin.port == proposedURL.port
  }
}

public protocol HTTPClient: Sendable {
  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse
}
