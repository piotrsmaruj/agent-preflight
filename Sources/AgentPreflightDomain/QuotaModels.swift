import Foundation

public enum ProviderIdentifier: String, CaseIterable, Codable, Sendable {
  case codex
  case claudeCode
}

public enum QuotaWindowKind: String, CaseIterable, Codable, Sendable {
  case short
  case weekly
  case modelWeekly

  /// The windows a provider must report before it can take part in a recommendation.
  ///
  /// `modelWeekly` is deliberately absent: only Claude Code exposes a model-scoped week, so a
  /// snapshot without one is complete rather than partial.
  public static let requiredForRecommendation: [QuotaWindowKind] = [.short, .weekly]
}

public enum QuotaModelError: Error, Equatable, Sendable {
  case percentageOutOfRange(Double)
  case duplicateWindow(QuotaWindowKind)
}

public struct RemainingPercentage: Codable, Equatable, Sendable {
  public static let providerDriftTolerance = 0.01
  public let value: Double

  public init(remaining value: Double) throws {
    guard value.isFinite,
      value >= -Self.providerDriftTolerance,
      value <= 100 + Self.providerDriftTolerance
    else {
      throw QuotaModelError.percentageOutOfRange(value)
    }
    self.value = min(100, max(0, value))
  }

  public static func fromUsed(_ used: Double) throws -> Self {
    try Self(remaining: 100 - used)
  }

  private enum CodingKeys: String, CodingKey { case value }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(remaining: container.decode(Double.self, forKey: .value))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value, forKey: .value)
  }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
  public let kind: QuotaWindowKind
  public let remaining: RemainingPercentage
  public let resetsAt: Date?
  /// Names what the window is scoped to, such as the model of a model-scoped week; nil when the
  /// window covers everything the provider meters.
  public let scopeLabel: String?

  public init(
    kind: QuotaWindowKind,
    remaining: RemainingPercentage,
    resetsAt: Date?,
    scopeLabel: String? = nil
  ) {
    self.kind = kind
    self.remaining = remaining
    self.resetsAt = resetsAt
    self.scopeLabel = scopeLabel
  }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
  public let provider: ProviderIdentifier
  public let windows: [QuotaWindowKind: QuotaWindow]
  public let fetchedAt: Date

  public init(
    provider: ProviderIdentifier,
    windows: [QuotaWindow],
    fetchedAt: Date
  ) throws {
    var indexedWindows: [QuotaWindowKind: QuotaWindow] = [:]
    for window in windows {
      guard indexedWindows.updateValue(window, forKey: window.kind) == nil else {
        throw QuotaModelError.duplicateWindow(window.kind)
      }
    }
    self.provider = provider
    self.windows = indexedWindows
    self.fetchedAt = fetchedAt
  }

  public func window(_ kind: QuotaWindowKind, validAt date: Date) -> QuotaWindow? {
    guard let window = windows[kind], let resetsAt = window.resetsAt, resetsAt > date else {
      return nil
    }
    return window
  }

  private enum CodingKeys: String, CodingKey { case provider, windows, fetchedAt }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      provider: container.decode(ProviderIdentifier.self, forKey: .provider),
      windows: container.decode([QuotaWindow].self, forKey: .windows),
      fetchedAt: container.decode(Date.self, forKey: .fetchedAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(provider, forKey: .provider)
    try container.encode(
      windows.values.sorted { $0.kind.rawValue < $1.kind.rawValue },
      forKey: .windows
    )
    try container.encode(fetchedAt, forKey: .fetchedAt)
  }
}
