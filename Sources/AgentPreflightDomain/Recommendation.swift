import Foundation

public enum RecommendationDecision: Equatable, Sendable {
  case provider(ProviderIdentifier)
  case neutral
  case noSafeChoice
  case unavailable
}

public enum RecommendationReason: Equatable, Sendable {
  case onlySafe(ProviderIdentifier)
  case largerMargin(ProviderIdentifier)
  case marginsWithinTolerance
  case insufficientQuota
  case incompleteOrStaleData
}

public struct ConstraintFailure: Equatable, Sendable {
  public let provider: ProviderIdentifier
  public let window: QuotaWindowKind
  public let remaining: Double
  public let required: Double
  public let resetsAt: Date
  public let scopeLabel: String?
}

public struct Recommendation: Equatable, Sendable {
  public let decision: RecommendationDecision
  public let reason: RecommendationReason
  public let failures: [ConstraintFailure]
  public let nearestRelevantReset: Date?
}
