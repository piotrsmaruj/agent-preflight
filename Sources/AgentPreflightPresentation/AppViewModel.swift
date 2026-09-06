import AgentPreflightApplication
import AgentPreflightDomain
import Combine
import Foundation

/// Panel state: provider cards, the recommendation for the selected task size, and refresh status.
///
/// Every published value is derived from the latest `RefreshResult` plus the current time, so
/// changing the task size or ticking the clock re-renders without touching a provider.
@MainActor
public final class AppViewModel: ObservableObject {
  @Published public var selectedTaskSize: TaskSize { didSet { render() } }
  @Published public private(set) var providerCards: [ProviderCardModel]
  @Published public private(set) var recommendation: RecommendationModel
  @Published public private(set) var isRefreshing = false
  @Published public private(set) var lastRefreshText = "Not refreshed"

  private let refreshUseCase: any RefreshQuotaUseCaseProtocol
  private let recommendationEngine: RecommendationEngine
  private let clock: any Clock
  private let formatter: PresentationFormatter
  private var latestResult: RefreshResult?

  public init(
    refreshUseCase: any RefreshQuotaUseCaseProtocol,
    recommendationEngine: RecommendationEngine,
    clock: any Clock,
    formatter: PresentationFormatter = .init(),
    selectedTaskSize: TaskSize = .medium
  ) {
    self.refreshUseCase = refreshUseCase
    self.recommendationEngine = recommendationEngine
    self.clock = clock
    self.formatter = formatter
    self.selectedTaskSize = selectedTaskSize
    self.providerCards = ProviderIdentifier.allCases.map { provider in
      ProviderCardModel(
        provider: provider,
        title: formatter.providerTitle(provider),
        freshnessText: "Loading",
        rows: [],
        recoveryText: nil
      )
    }
    self.recommendation = RecommendationModel(
      title: "Recommendation unavailable",
      detail: "Waiting for fresh quota data.",
      tone: .unavailable
    )
  }

  public func panelOpened() async {
    latestResult = await refreshUseCase.current()
    render()
    await refresh()
  }

  public func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    latestResult = await refreshUseCase.refresh()
    isRefreshing = false
    render()
  }

  public func clockTicked() { render() }

  private func render() {
    guard let result = latestResult else { return }
    let now = clock.now()
    providerCards = ProviderIdentifier.allCases.map { provider in
      makeCard(status: result.statuses[provider], provider: provider, now: now)
    }
    let oldestFetch = result.statuses.values.compactMap { $0.snapshot?.fetchedAt }.min()
    lastRefreshText = oldestFetch.map { formatter.ageText($0, now: now) } ?? "Not refreshed"
    let decision = recommendationEngine.recommend(
      taskSize: selectedTaskSize,
      snapshots: result.eligibleSnapshots,
      staleProviders: result.staleProviders,
      now: now
    )
    recommendation = makeRecommendation(decision, now: now)
  }

  private func makeCard(
    status: ProviderStatus?,
    provider: ProviderIdentifier,
    now: Date
  ) -> ProviderCardModel {
    let windows = status?.snapshot.map { Array($0.windows.values) } ?? []
    let rows =
      windows
      .sorted { sortIndex($0.kind) < sortIndex($1.kind) }
      .map { formatter.row(provider: provider, window: $0, now: now) }
    return ProviderCardModel(
      provider: provider,
      title: formatter.providerTitle(provider),
      freshnessText: cardFreshnessText(status: status, windows: windows),
      rows: rows,
      recoveryText: status?.failure.map { ErrorCopy.recovery(for: provider, failure: $0) }
    )
  }

  private func cardFreshnessText(status: ProviderStatus?, windows: [QuotaWindow]) -> String {
    let base = freshnessText(status?.freshness ?? .unavailable)
    let isComplete = QuotaWindowKind.allCases.allSatisfy { status?.snapshot?.windows[$0] != nil }
    return windows.isEmpty || isComplete ? base : "\(base) · Incomplete"
  }

  private func makeRecommendation(_ value: Recommendation, now: Date) -> RecommendationModel {
    switch value.decision {
    case .provider(let provider):
      let isOnlySafe = value.reason == .onlySafe(provider)
      return RecommendationModel(
        title: "Safer choice: \(formatter.providerTitle(provider))",
        detail: isOnlySafe
          ? "Only this provider meets both reserves for the selected task size."
          : "It has the larger minimum quota margin across both windows.",
        tone: .positive
      )
    case .neutral:
      return RecommendationModel(
        title: "Both look safe",
        detail: "Their minimum quota margins differ by less than 10%.",
        tone: .neutral
      )
    case .noSafeChoice:
      let reset =
        value.nearestRelevantReset
        .map { formatter.resetText($0, now: now).lowercased() } ?? "reset time unavailable"
      let failures = value.failures.map { formatter.failureLabel($0) }.joined(separator: ", ")
      return RecommendationModel(
        title: "No safe choice",
        detail: "Below reserve: \(failures); \(reset).",
        tone: .warning
      )
    case .unavailable:
      return RecommendationModel(
        title: "Recommendation unavailable",
        detail: "Fresh short-window and weekly data is required from both providers.",
        tone: .unavailable
      )
    }
  }

  private func freshnessText(_ freshness: SnapshotFreshness) -> String {
    switch freshness {
    case .current: "Current"
    case .cached: "Cached"
    case .stale: "Stale"
    case .unavailable: "Unavailable"
    }
  }

  private func sortIndex(_ kind: QuotaWindowKind) -> Int {
    kind == .short ? 0 : 1
  }
}
