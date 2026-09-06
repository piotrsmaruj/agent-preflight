import AgentPreflightApplication
import Foundation

public struct CodexAppServerClient: Sendable {
  public static let arguments = ["app-server", "--listen", "stdio://"]
  private static let initializeRequestID = 0
  private static let rateLimitsRequestID = 1
  private let launcher: any JSONLineProcessLaunching
  private let timeoutSeconds: TimeInterval

  public init(launcher: any JSONLineProcessLaunching, timeoutSeconds: TimeInterval) {
    self.launcher = launcher
    self.timeoutSeconds = timeoutSeconds
  }

  public func readRateLimits(executableURL: URL) async throws -> Data {
    let session = try await launcher.launch(
      executableURL: executableURL,
      arguments: Self.arguments
    )
    return try await withTaskCancellationHandler {
      do {
        let response = try await withTimeout(seconds: timeoutSeconds) {
          try await withTaskCancellationHandler {
            try await exchange(session: session)
          } onCancel: {
            Task { await session.terminate() }
          }
        }
        await session.terminate()
        return response
      } catch {
        await session.terminate()
        throw error
      }
    } onCancel: {
      Task { await session.terminate() }
    }
  }

  private func exchange(session: any JSONLineProcessSession) async throws -> Data {
    try await session.send(
      message(
        method: "initialize",
        id: Self.initializeRequestID,
        params: [
          "clientInfo": [
            "name": "agent_preflight",
            "title": "Agent Preflight",
            "version": "0.1.0",
          ]
        ]
      )
    )
    _ = try await receiveResponse(id: Self.initializeRequestID, from: session)
    try await session.send(message(method: "initialized", id: nil, params: [:]))
    try await session.send(
      message(method: "account/rateLimits/read", id: Self.rateLimitsRequestID, params: nil)
    )
    return try await receiveResponse(id: Self.rateLimitsRequestID, from: session)
  }

  /// Skips notifications and responses to other requests until the awaited id arrives.
  private func receiveResponse(
    id: Int,
    from session: any JSONLineProcessSession
  ) async throws -> Data {
    while let line = try await session.receive() {
      let header: ResponseHeader
      do {
        header = try JSONDecoder().decode(ResponseHeader.self, from: line)
      } catch {
        throw ProviderFailure.protocolFailure
      }
      guard header.id == id else { continue }
      if let rpcError = header.error { throw Self.failure(for: rpcError) }
      return line
    }
    throw ProviderFailure.processFailure(exitCode: await session.waitForExit())
  }

  private func message(method: String, id: Int?, params: [String: Any]?) throws -> Data {
    var object: [String: Any] = ["method": method]
    if let id { object["id"] = id }
    if let params { object["params"] = params }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  /// codex-cli reports a missing login as a generic invalid-request code, so only the message
  /// separates it from a real protocol fault. The message itself is child-process output and is
  /// deliberately never carried into the thrown failure.
  private static let authenticationMessageKeywords = [
    "authentication", "authenticate", "login", "logged in", "not logged",
  ]

  private static func failure(for rpcError: RPCError) -> ProviderFailure {
    let message = rpcError.message?.lowercased() ?? ""
    let isAuthentication = authenticationMessageKeywords.contains { message.contains($0) }
    return isAuthentication ? .unauthenticated : .protocolFailure
  }

  private struct ResponseHeader: Decodable {
    let id: Int?
    let error: RPCError?
  }

  private struct RPCError: Decodable {
    let code: Int
    let message: String?
  }
}
