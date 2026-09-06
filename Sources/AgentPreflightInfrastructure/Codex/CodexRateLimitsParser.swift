import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

public struct CodexRateLimitsParser: Sendable {
  public static let weeklyDurationMinutes = 10_080
  public static let codexLimitID = "codex"

  public init() {}

  public func parse(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: data)
      guard envelope.error == nil, let limits = selectedLimits(from: envelope.result) else {
        throw ProviderFailure.unsupportedPayload
      }
      let windows = try [limits.primary, limits.secondary]
        .compactMap { $0 }
        .compactMap { try quotaWindow(from: $0) }
      guard !windows.isEmpty else { throw ProviderFailure.unsupportedPayload }
      return try QuotaSnapshot(provider: .codex, windows: windows, fetchedAt: fetchedAt)
    } catch let error as ProviderFailure {
      throw error
    } catch {
      throw ProviderFailure.unsupportedPayload
    }
  }

  private func selectedLimits(from result: ResultBody?) -> Limits? {
    if let direct = result?.rateLimits { return direct }
    if let codex = result?.rateLimitsByLimitId?[Self.codexLimitID] { return codex }
    guard let grouped = result?.rateLimitsByLimitId, grouped.count == 1 else { return nil }
    return grouped.values.first
  }

  /// Returns nil for a window without a duration: it cannot be classified as short or weekly.
  private func quotaWindow(from window: Window) throws -> QuotaWindow? {
    guard let durationMinutes = window.windowDurationMins else { return nil }
    guard durationMinutes > 0 else { throw ProviderFailure.unsupportedPayload }
    return QuotaWindow(
      kind: durationMinutes >= Self.weeklyDurationMinutes ? .weekly : .short,
      remaining: try RemainingPercentage.fromUsed(window.usedPercent),
      resetsAt: try resetDate(from: window.resetsAt)
    )
  }

  private func resetDate(from resetsAt: Int64?) throws -> Date? {
    guard let resetsAt else { return nil }
    guard resetsAt > 0 else { throw ProviderFailure.unsupportedPayload }
    return Date(timeIntervalSince1970: TimeInterval(resetsAt))
  }

  private struct Envelope: Decodable {
    let result: ResultBody?
    let error: RPCError?
  }

  private struct RPCError: Decodable {
    let code: Int
  }

  private struct ResultBody: Decodable {
    let rateLimits: Limits?
    let rateLimitsByLimitId: [String: Limits]?
  }

  private struct Limits: Decodable {
    let primary: Window?
    let secondary: Window?
  }

  private struct Window: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int64?
  }
}
