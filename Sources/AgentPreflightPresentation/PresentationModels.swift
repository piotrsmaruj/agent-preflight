import AgentPreflightDomain

/// One quota window rendered for display, with every string already formatted.
public struct QuotaRowModel: Identifiable, Equatable, Sendable {
  public var id: QuotaWindowKind { kind }
  public let kind: QuotaWindowKind
  public let title: String
  public let remainingValue: Double?
  public let remainingText: String
  public let resetText: String
  public let stateText: String
  public let accessibilityLabel: String

  public init(
    kind: QuotaWindowKind,
    title: String,
    remainingValue: Double?,
    remainingText: String,
    resetText: String,
    stateText: String,
    accessibilityLabel: String
  ) {
    self.kind = kind
    self.title = title
    self.remainingValue = remainingValue
    self.remainingText = remainingText
    self.resetText = resetText
    self.stateText = stateText
    self.accessibilityLabel = accessibilityLabel
  }
}

/// One provider panel: its quota rows plus, when a fetch failed, the recovery step to take.
public struct ProviderCardModel: Identifiable, Equatable, Sendable {
  public var id: ProviderIdentifier { provider }
  public let provider: ProviderIdentifier
  public let title: String
  public let freshnessText: String
  public let rows: [QuotaRowModel]
  public let recoveryText: String?

  public init(
    provider: ProviderIdentifier,
    title: String,
    freshnessText: String,
    rows: [QuotaRowModel],
    recoveryText: String?
  ) {
    self.provider = provider
    self.title = title
    self.freshnessText = freshnessText
    self.rows = rows
    self.recoveryText = recoveryText
  }
}

public enum RecommendationTone: Equatable, Sendable {
  case positive
  case neutral
  case warning
  case unavailable
}

public struct RecommendationModel: Equatable, Sendable {
  public let title: String
  public let detail: String
  public let tone: RecommendationTone

  public init(title: String, detail: String, tone: RecommendationTone) {
    self.title = title
    self.detail = detail
    self.tone = tone
  }
}
