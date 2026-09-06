import AgentPreflightDomain
import Foundation

public struct RefreshConfiguration: Equatable, Sendable {
  public let providerTimeout: TimeInterval
  public let cooldown: TimeInterval
  public let staleAfter: TimeInterval

  public static let live = Self(providerTimeout: 5, cooldown: 30, staleAfter: 15 * 60)
}

public enum SnapshotFreshness: Equatable, Sendable {
  case current
  case cached
  case stale
  case unavailable
}

public struct ProviderStatus: Equatable, Sendable {
  public let provider: ProviderIdentifier
  public let snapshot: QuotaSnapshot?
  public let freshness: SnapshotFreshness
  public let failure: ProviderFailure?
}

public struct RefreshResult: Equatable, Sendable {
  public let statuses: [ProviderIdentifier: ProviderStatus]
  public let completedAt: Date

  public var eligibleSnapshots: [ProviderIdentifier: QuotaSnapshot] {
    statuses.compactMapValues { status in
      guard status.failure == nil,
        status.freshness == .current || status.freshness == .cached
      else { return nil }
      return status.snapshot
    }
  }

  public var staleProviders: Set<ProviderIdentifier> {
    Set(statuses.values.filter { $0.freshness == .stale }.map(\.provider))
  }
}
