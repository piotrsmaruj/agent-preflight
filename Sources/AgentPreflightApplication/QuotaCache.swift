import AgentPreflightDomain

public protocol QuotaCache: Sendable {
  func load() async throws -> [ProviderIdentifier: QuotaSnapshot]
  func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws
}
