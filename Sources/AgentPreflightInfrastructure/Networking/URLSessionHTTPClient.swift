import Foundation

public struct URLSessionHTTPClient: HTTPClient {
  /// Test seam only: production callers leave this nil so the ephemeral configuration keeps the
  /// system protocol stack.
  private let protocolClasses: [AnyClass]?

  public init(protocolClasses: [AnyClass]? = nil) {
    self.protocolClasses = protocolClasses
  }

  public func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    guard request.url?.scheme?.lowercased() == "https" else {
      throw HTTPClientError.nonHTTPSRequest
    }
    let delegate = RedirectDelegate(policy: redirectPolicy)
    let session = makeSession(delegate: delegate)
    defer { session.invalidateAndCancel() }

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, let finalURL = http.url else {
        throw HTTPClientError.invalidResponse
      }
      if delegate.rejectedRedirect { throw HTTPClientError.redirectRejected }
      let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
        result[String(describing: pair.key)] = String(describing: pair.value)
      }
      return HTTPResponse(
        data: data,
        statusCode: http.statusCode,
        headers: headers,
        finalURL: finalURL
      )
    } catch let error as HTTPClientError {
      throw error
    } catch {
      throw HTTPClientError.transportFailure
    }
  }

  private func makeSession(delegate: RedirectDelegate) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    if let protocolClasses { configuration.protocolClasses = protocolClasses }
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let policy: SameHostRedirectPolicy
  private let lock = NSLock()
  private var redirectWasRejected = false

  init(policy: SameHostRedirectPolicy) { self.policy = policy }

  var rejectedRedirect: Bool { lock.withLock { redirectWasRejected } }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let url = request.url, policy.allows(url) else {
      lock.withLock { redirectWasRejected = true }
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
