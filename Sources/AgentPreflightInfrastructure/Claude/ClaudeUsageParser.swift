import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

public struct ClaudeUsageParser: Sendable {
  /// The `limits` entry kind that carries the model-scoped week, such as "Weekly · Fable".
  private static let modelScopedWeeklyKind = "weekly_scoped"
  /// Stands in when the payload scopes a week to a model it does not name.
  private static let unnamedScopeLabel = "Model"

  public init() {}

  public func parse(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    do {
      let response = try JSONDecoder().decode(Response.self, from: data)
      let windows = try [
        map(response.fiveHour, to: .short),
        map(response.sevenDay, to: .weekly),
        modelWeeklyWindow(from: response.limits ?? []),
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

  /// Reads the model-scoped week from the newer `limits` array, keeping the most consumed entry.
  ///
  /// Several scoped weeks can be reported at once; the one with the least quota left is the one
  /// that will stop the task first, so it is the only one the app shows and reasons about.
  private func modelWeeklyWindow(from limits: [Limit]) throws -> QuotaWindow? {
    let scoped = limits.filter { $0.kind == Self.modelScopedWeeklyKind && $0.percent != nil }
    guard let tightest = scoped.max(by: { ($0.percent ?? 0) < ($1.percent ?? 0) }),
      let percent = tightest.percent
    else { return nil }
    return QuotaWindow(
      kind: .modelWeekly,
      remaining: try RemainingPercentage.fromUsed(percent),
      resetsAt: try parseOptionalDate(tightest.resetsAt),
      scopeLabel: tightest.scope?.model?.displayName ?? Self.unnamedScopeLabel
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
    let limits: [Limit]?

    enum CodingKeys: String, CodingKey {
      case fiveHour = "five_hour"
      case sevenDay = "seven_day"
      case limits
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

  private struct Limit: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
      case kind
      case percent
      case scope
      case resetsAt = "resets_at"
    }
  }

  private struct Scope: Decodable {
    let model: Model?
  }

  private struct Model: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
      case displayName = "display_name"
    }
  }
}
