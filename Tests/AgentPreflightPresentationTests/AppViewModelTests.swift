import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightPresentation

@Suite("App view model")
@MainActor
struct AppViewModelTests {
  @Test("changing the task size recomputes without refreshing again")
  func changingTaskSizeRecomputesWithoutRefreshing() async throws {
    let useCase = RefreshUseCaseStub(result: try completeResult())
    let model = AppViewModel(
      refreshUseCase: useCase,
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()
    let callsAfterOpen = await useCase.refreshCalls
    model.selectedTaskSize = .large
    let callsAfterSelection = await useCase.refreshCalls

    #expect(callsAfterSelection == callsAfterOpen)
    #expect(!model.recommendation.title.isEmpty)
  }

  @Test("a quota row carries textual and accessible state")
  func quotaRowHasTextualAndAccessibleState() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try completeResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    let row = try #require(model.providerCards.first?.rows.first)
    #expect(row.percentageText.contains("remaining"))
    #expect(row.accessibilityLabel.contains("remaining"))
    #expect(!row.stateText.isEmpty)
  }

  @Test("a partial failure keeps the healthy card and disables the recommendation")
  func partialFailureKeepsHealthyProviderCardAndDisablesRecommendation() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try partialFailureResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.providerCards.first { $0.provider == .codex }?.rows.count == 2)
    #expect(model.recommendation.title == "Recommendation unavailable")
    #expect(model.providerCards.first { $0.provider == .claudeCode }?.recoveryText != nil)
  }

  @Test("a total failure keeps both recovery actions visible")
  func totalFailureKeepsBothRecoveryActionsVisible() async {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: totalFailureResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.providerCards.allSatisfy { $0.rows.isEmpty })
    #expect(model.providerCards.allSatisfy { $0.recoveryText != nil })
    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("initial and stale states use text labels")
  func initialAndStaleStatesUseTextLabels() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try staleResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    #expect(model.providerCards.map(\.freshnessText) == ["Loading", "Loading"])

    await model.panelOpened()

    #expect(model.providerCards.first { $0.provider == .codex }?.freshnessText == "Stale")
    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("a passed reset becomes unknown without inventing full quota")
  func passedResetBecomesUnknownWithoutInventingFullQuota() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try completeResult(shortResetOffset: -1)),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    let short = try #require(
      model.providerCards.first { $0.provider == .codex }?.rows.first { $0.kind == .short }
    )
    #expect(short.stateText == "Unknown")
    #expect(short.percentageText == "Remaining unknown")
    #expect(short.percentageValue == nil)
    #expect(short.resetText == "Refresh required")
    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("no safe choice names the failed constraints and the nearest reset")
  func noSafeChoiceNamesFailedConstraintsAndNearestReset() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try insufficientResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "No safe choice")
    #expect(model.recommendation.detail.contains("Codex short"))
    #expect(model.recommendation.detail.contains("Claude Code weekly"))
    #expect(model.recommendation.detail.contains("resets in 15m"))
  }

  @Test("the Claude card separates the all-models week from the model-scoped week")
  func claudeCardSeparatesAllModelsWeekFromModelScopedWeek() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try modelScopedWeeklyResult(scopedRemaining: 30)),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    let claude = try #require(model.providerCards.first { $0.provider == .claudeCode })
    let codex = try #require(model.providerCards.first { $0.provider == .codex })
    #expect(claude.rows.map(\.title) == ["Short window", "Weekly · all models", "Weekly · Fable"])
    #expect(codex.rows.map(\.title) == ["Short window", "Weekly"])
    #expect(model.providerCards.allSatisfy { !$0.freshnessText.contains("Incomplete") })
    #expect(claude.rows.last?.accessibilityLabel.contains("Weekly · Fable") == true)
  }

  @Test("no safe choice names the model-scoped week that binds the weekly constraint")
  func noSafeChoiceNamesModelScopedWeekThatBindsWeeklyConstraint() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try modelScopedWeeklyResult(scopedRemaining: 5)),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "No safe choice")
    #expect(model.recommendation.detail.contains("Codex short"))
    #expect(model.recommendation.detail.contains("Claude Code weekly (Fable)"))
    #expect(!model.recommendation.detail.contains("Claude Code weekly;"))
    #expect(model.recommendation.detail.contains("resets in 15m"))
  }

  @Test("a window with an unknown reset keeps its percentage and says so")
  func windowWithUnknownResetKeepsPercentageAndReportsMissingReset() throws {
    let window = QuotaWindow(kind: .short, remaining: try .init(remaining: 100), resetsAt: nil)

    let row = PresentationFormatter().row(provider: .codex, window: window, now: referenceDate)

    #expect(row.percentageText == "100% remaining")
    #expect(row.percentageValue == 100)
    #expect(row.resetText == "Reset unavailable")
    #expect(row.stateText == "Plenty")
    #expect(row.accessibilityLabel.contains("100% remaining"))
    #expect(row.accessibilityLabel.contains("Reset unavailable"))
  }

  @Test("an unknown reset in one window disables the recommendation")
  func unknownResetDisablesRecommendation() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try unknownShortResetResult()),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("switching to used percentages re-renders the rows without refreshing again")
  func switchingToUsedPercentagesRerendersRowsWithoutRefreshing() async throws {
    let useCase = RefreshUseCaseStub(result: try completeResult())
    let model = AppViewModel(
      refreshUseCase: useCase,
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()
    let callsAfterOpen = await useCase.refreshCalls
    model.quotaDisplayMode = .used
    let callsAfterSwitch = await useCase.refreshCalls

    let short = try #require(
      model.providerCards.first { $0.provider == .codex }?.rows.first { $0.kind == .short }
    )
    #expect(callsAfterSwitch == callsAfterOpen)
    #expect(short.percentageText == "20% used")
    #expect(short.percentageValue == 20)
    #expect(short.stateText == "Plenty")
    #expect(short.accessibilityLabel.contains("20% used"))
  }

  @Test("used percentages report an expired window as unknown usage")
  func usedPercentagesReportExpiredWindowAsUnknownUsage() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try completeResult(shortResetOffset: -1)),
      clock: FixedPresentationClock(now: referenceDate),
      quotaDisplayMode: .used
    )

    await model.panelOpened()

    let short = try #require(
      model.providerCards.first { $0.provider == .codex }?.rows.first { $0.kind == .short }
    )
    #expect(short.percentageText == "Usage unknown")
    #expect(short.percentageValue == nil)
  }

  /// Rounding once and subtracting keeps the two modes complementary; rounding each independently
  /// would show 60% remaining next to 41% used for the same window.
  @Test("the two display modes always add up to a hundred")
  func twoDisplayModesAlwaysAddUpToHundred() throws {
    let window = QuotaWindow(
      kind: .short,
      remaining: try .init(remaining: 59.5),
      resetsAt: referenceDate.addingTimeInterval(3_600)
    )
    let formatter = PresentationFormatter()

    let remaining = formatter.row(provider: .codex, window: window, now: referenceDate)
    let used = formatter.row(
      provider: .codex,
      window: window,
      now: referenceDate,
      displayMode: .used
    )

    #expect(remaining.percentageText == "60% remaining")
    #expect(used.percentageText == "40% used")
  }

  @Test("a stricter policy changes the recommendation without refreshing again")
  func stricterPolicyChangesRecommendationWithoutRefreshing() async throws {
    let useCase = RefreshUseCaseStub(result: try completeResult())
    let model = AppViewModel(
      refreshUseCase: useCase,
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()
    let callsAfterOpen = await useCase.refreshCalls
    #expect(model.recommendation.title != "No safe choice")

    model.taskSizePolicy = try TaskSizePolicy(
      small: ReserveRequirement(short: 95, weekly: 95),
      medium: ReserveRequirement(short: 95, weekly: 95),
      large: ReserveRequirement(short: 95, weekly: 95),
      neutralTolerance: 0.10
    )
    let callsAfterPolicy = await useCase.refreshCalls

    #expect(callsAfterPolicy == callsAfterOpen)
    #expect(model.recommendation.title == "No safe choice")
  }

  @Test("the neutral explanation quotes the configured tolerance")
  func neutralExplanationQuotesConfiguredTolerance() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try completeResult()),
      clock: FixedPresentationClock(now: referenceDate),
      taskSizePolicy: try TaskSizePolicy(
        small: TaskSizePolicy.default.small,
        medium: TaskSizePolicy.default.medium,
        large: TaskSizePolicy.default.large,
        neutralTolerance: 0.75
      )
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "Both look safe")
    #expect(model.recommendation.detail.contains("0.75"))
  }
}

private let referenceDate = Date(timeIntervalSince1970: 1_788_505_200)

private func completeResult(shortResetOffset: TimeInterval = 3_600) throws -> RefreshResult {
  let codex = try presentationSnapshot(.codex, shortResetOffset: shortResetOffset)
  let claude = try presentationSnapshot(.claudeCode, shortResetOffset: 3_600)
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: claude,
        freshness: .current,
        failure: nil
      ),
    ],
    completedAt: referenceDate
  )
}

private func partialFailureResult() throws -> RefreshResult {
  let codex = try presentationSnapshot(.codex, shortResetOffset: 3_600)
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: nil,
        freshness: .unavailable,
        failure: .unauthorized
      ),
    ],
    completedAt: referenceDate
  )
}

private func staleResult() throws -> RefreshResult {
  let codex = try presentationSnapshot(.codex, shortResetOffset: 3_600)
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .stale, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: nil,
        freshness: .unavailable,
        failure: nil
      ),
    ],
    completedAt: referenceDate
  )
}

private func totalFailureResult() -> RefreshResult {
  RefreshResult(
    statuses: [
      .codex: ProviderStatus(
        provider: .codex,
        snapshot: nil,
        freshness: .unavailable,
        failure: .executableMissing
      ),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: nil,
        freshness: .unavailable,
        failure: .keychainDenied
      ),
    ],
    completedAt: referenceDate
  )
}

private func insufficientResult() throws -> RefreshResult {
  let codex = try insufficientSnapshot(.codex, firstReset: 900)
  let claude = try insufficientSnapshot(.claudeCode, firstReset: 1_800)
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: claude,
        freshness: .current,
        failure: nil
      ),
    ],
    completedAt: referenceDate
  )
}

private func unknownShortResetResult() throws -> RefreshResult {
  let codex = try presentationSnapshot(.codex, shortResetOffset: 3_600)
  let claude = try QuotaSnapshot(
    provider: .claudeCode,
    windows: [
      QuotaWindow(kind: .short, remaining: .init(remaining: 60), resetsAt: nil),
      QuotaWindow(
        kind: .weekly,
        remaining: .init(remaining: 50),
        resetsAt: referenceDate.addingTimeInterval(86_400)
      ),
    ],
    fetchedAt: referenceDate
  )
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: claude,
        freshness: .current,
        failure: nil
      ),
    ],
    completedAt: referenceDate
  )
}

private func modelScopedWeeklyResult(scopedRemaining: Double) throws -> RefreshResult {
  let codex = try QuotaSnapshot(
    provider: .codex,
    windows: [
      QuotaWindow(
        kind: .short,
        remaining: .init(remaining: 20),
        resetsAt: referenceDate.addingTimeInterval(900)
      ),
      QuotaWindow(
        kind: .weekly,
        remaining: .init(remaining: 50),
        resetsAt: referenceDate.addingTimeInterval(86_400)
      ),
    ],
    fetchedAt: referenceDate
  )
  let claude = try QuotaSnapshot(
    provider: .claudeCode,
    windows: [
      QuotaWindow(
        kind: .short,
        remaining: .init(remaining: 90),
        resetsAt: referenceDate.addingTimeInterval(3_600)
      ),
      QuotaWindow(
        kind: .weekly,
        remaining: .init(remaining: 50),
        resetsAt: referenceDate.addingTimeInterval(86_400)
      ),
      QuotaWindow(
        kind: .modelWeekly,
        remaining: .init(remaining: scopedRemaining),
        resetsAt: referenceDate.addingTimeInterval(86_400),
        scopeLabel: "Fable"
      ),
    ],
    fetchedAt: referenceDate
  )
  return RefreshResult(
    statuses: [
      .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
      .claudeCode: ProviderStatus(
        provider: .claudeCode,
        snapshot: claude,
        freshness: .current,
        failure: nil
      ),
    ],
    completedAt: referenceDate
  )
}

private func insufficientSnapshot(
  _ provider: ProviderIdentifier,
  firstReset: TimeInterval
) throws -> QuotaSnapshot {
  try QuotaSnapshot(
    provider: provider,
    windows: [
      QuotaWindow(
        kind: .short,
        remaining: .init(remaining: 20),
        resetsAt: referenceDate.addingTimeInterval(firstReset)
      ),
      QuotaWindow(
        kind: .weekly,
        remaining: .init(remaining: 5),
        resetsAt: referenceDate.addingTimeInterval(86_400)
      ),
    ],
    fetchedAt: referenceDate
  )
}

private func presentationSnapshot(
  _ provider: ProviderIdentifier,
  shortResetOffset: TimeInterval
) throws -> QuotaSnapshot {
  try QuotaSnapshot(
    provider: provider,
    windows: [
      QuotaWindow(
        kind: .short,
        remaining: .init(remaining: provider == .codex ? 80 : 60),
        resetsAt: referenceDate.addingTimeInterval(shortResetOffset)
      ),
      QuotaWindow(
        kind: .weekly,
        remaining: .init(remaining: provider == .codex ? 70 : 50),
        resetsAt: referenceDate.addingTimeInterval(86_400)
      ),
    ],
    fetchedAt: referenceDate
  )
}

private struct FixedPresentationClock: Clock {
  let current: Date

  init(now: Date) { current = now }

  func now() -> Date { current }
}

private actor RefreshUseCaseStub: RefreshQuotaUseCaseProtocol {
  let result: RefreshResult
  private(set) var refreshCalls = 0

  init(result: RefreshResult) { self.result = result }

  func current() async -> RefreshResult { result }

  func refresh() async -> RefreshResult {
    refreshCalls += 1
    return result
  }
}
