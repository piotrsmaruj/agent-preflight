import AgentPreflightApplication
import AgentPreflightInfrastructure
import CoreFoundation
import Foundation

enum ClaudeLiveUtilizationDiagnostic: Equatable, Sendable {
  case absent
  case null
  case zero
  case positive
  case outOfRange
  case nonNumeric
}

enum ClaudeLiveResetDiagnostic: Equatable, Sendable {
  case absent
  case null
  case parseable
  case unparseable
  case wrongType
}

enum ClaudeLiveWindowDiagnostic: Equatable, Sendable {
  case missing
  case null
  case object(
    utilization: ClaudeLiveUtilizationDiagnostic,
    resetsAt: ClaudeLiveResetDiagnostic
  )
  case wrongType
}

struct ClaudeLiveHTTPDiagnostic: Equatable, Sendable {
  let statusCode: Int
  let fiveHour: ClaudeLiveWindowDiagnostic
  let sevenDay: ClaudeLiveWindowDiagnostic

  static func classify(statusCode: Int, data: Data) -> Self {
    guard
      let value = try? JSONSerialization.jsonObject(with: data),
      let object = value as? [String: Any]
    else {
      return Self(statusCode: statusCode, fiveHour: .wrongType, sevenDay: .wrongType)
    }

    return Self(
      statusCode: statusCode,
      fiveHour: classifyWindow(named: "five_hour", in: object),
      sevenDay: classifyWindow(named: "seven_day", in: object)
    )
  }

  var summary: String {
    "http_status=\(statusCode) five_hour=\(fiveHour.summary) seven_day=\(sevenDay.summary)"
  }

  private static func classifyWindow(
    named name: String,
    in response: [String: Any]
  ) -> ClaudeLiveWindowDiagnostic {
    guard let value = response[name] else { return .missing }
    if value is NSNull { return .null }
    guard let object = value as? [String: Any] else { return .wrongType }
    return .object(
      utilization: classifyUtilization(in: object),
      resetsAt: classifyReset(in: object)
    )
  }

  private static func classifyUtilization(
    in window: [String: Any]
  ) -> ClaudeLiveUtilizationDiagnostic {
    guard let value = window["utilization"] else { return .absent }
    if value is NSNull { return .null }
    guard
      let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      return .nonNumeric
    }

    let utilization = number.doubleValue
    guard utilization.isFinite, (0...100).contains(utilization) else { return .outOfRange }
    return utilization == 0 ? .zero : .positive
  }

  private static func classifyReset(in window: [String: Any]) -> ClaudeLiveResetDiagnostic {
    guard let value = window["resets_at"] else { return .absent }
    if value is NSNull { return .null }
    guard let timestamp = value as? String else { return .wrongType }
    return isParseableTimestamp(timestamp) ? .parseable : .unparseable
  }

  private static func isParseableTimestamp(_ timestamp: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if formatter.date(from: timestamp) != nil { return true }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp) != nil
  }
}

actor ClaudeLiveHTTPDiagnosticRecorder {
  private var recordedSummary: String?

  func record(_ response: HTTPResponse) {
    recordedSummary =
      ClaudeLiveHTTPDiagnostic.classify(
        statusCode: response.statusCode,
        data: response.data
      ).summary
  }

  func summary() -> String? { recordedSummary }
}

struct ClaudeLiveDiagnosticHTTPClient<Base: HTTPClient>: HTTPClient {
  private let base: Base
  private let recorder: ClaudeLiveHTTPDiagnosticRecorder

  init(base: Base, recorder: ClaudeLiveHTTPDiagnosticRecorder) {
    self.base = base
    self.recorder = recorder
  }

  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    let response = try await base.send(request, redirectPolicy: redirectPolicy)
    await recorder.record(response)
    return response
  }
}

func safeProviderFailureCategory(_ failure: ProviderFailure) -> String {
  switch failure {
  case .executableMissing:
    "executable_missing"
  case .unauthenticated:
    "unauthenticated"
  case .keychainDenied:
    "keychain_denied"
  case .invalidCredential:
    "invalid_credential"
  case .timeout:
    "timeout"
  case .unauthorized:
    "unauthorized"
  case .rateLimited:
    "rate_limited"
  case .unsupportedPayload:
    "unsupported_payload"
  case .processFailure:
    "process_failure"
  case .protocolFailure:
    "protocol_failure"
  case .networkUnavailable:
    "network_unavailable"
  }
}

extension ClaudeLiveWindowDiagnostic {
  fileprivate var summary: String {
    switch self {
    case .missing:
      "missing"
    case .null:
      "null"
    case .object(let utilization, let resetsAt):
      "object(utilization=\(utilization.summary),resets_at=\(resetsAt.summary))"
    case .wrongType:
      "wrong_type"
    }
  }
}

extension ClaudeLiveUtilizationDiagnostic {
  fileprivate var summary: String {
    switch self {
    case .absent: "absent"
    case .null: "null"
    case .zero: "zero"
    case .positive: "positive"
    case .outOfRange: "out_of_range"
    case .nonNumeric: "non_numeric"
    }
  }
}

extension ClaudeLiveResetDiagnostic {
  fileprivate var summary: String {
    switch self {
    case .absent: "absent"
    case .null: "null"
    case .parseable: "parseable"
    case .unparseable: "unparseable"
    case .wrongType: "wrong_type"
    }
  }
}
