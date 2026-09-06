import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

public struct ClaudeUsageParser: Sendable {
  public init() {}

  public func parse(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    do {
      let response = try JSONDecoder().decode(Response.self, from: data)
      let windows = try [
        map(response.fiveHour, to: .short),
        map(response.sevenDay, to: .weekly),
      ].compactMap { $0 }
      guard !windows.isEmpty else { throw ProviderFailure.unsupportedPayload }
      return try QuotaSnapshot(provider: .claudeCode, windows: windows, fetchedAt: fetchedAt)
    } catch let error as ProviderFailure {
      throw error
    } catch {
      throw ProviderFailure.unsupportedPayload
    }
  }

  private func map(_ source: Window?, to kind: QuotaWindowKind) throws -> QuotaWindow? {
    guard let source else { return nil }
    if source.utilization == nil, source.resetsAt == nil { return nil }
    guard let utilization = source.utilization else {
      throw ProviderFailure.unsupportedPayload
    }
    let reset = try parseOptionalDate(source.resetsAt)
    return QuotaWindow(
      kind: kind,
      remaining: try RemainingPercentage.fromUsed(utilization),
      resetsAt: reset
    )
  }

  private func parseOptionalDate(_ value: String?) throws -> Date? {
    guard let value else { return nil }
    guard let date = parseDate(value) else { throw ProviderFailure.unsupportedPayload }
    return date
  }

  private func parseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private struct Response: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
      case fiveHour = "five_hour"
      case sevenDay = "seven_day"
    }
  }

  private struct Window: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
      case utilization
      case resetsAt = "resets_at"
    }
  }
}
