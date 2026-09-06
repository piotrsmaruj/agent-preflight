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
      recommendationEngine: RecommendationEngine(),
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
      recommendationEngine: RecommendationEngine(),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    let row = try #require(model.providerCards.first?.rows.first)
    #expect(row.remainingText.contains("remaining"))
    #expect(row.accessibilityLabel.contains("remaining"))
    #expect(!row.stateText.isEmpty)
  }

  @Test("a partial failure keeps the healthy card and disables the recommendation")
  func partialFailureKeepsHealthyProviderCardAndDisablesRecommendation() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try partialFailureResult()),
      recommendationEngine: RecommendationEngine(),
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
      recommendationEngine: RecommendationEngine(),
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
      recommendationEngine: RecommendationEngine(),
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
      recommendationEngine: RecommendationEngine(),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    let short = try #require(
      model.providerCards.first { $0.provider == .codex }?.rows.first { $0.kind == .short }
    )
    #expect(short.stateText == "Unknown")
    #expect(short.remainingText == "Remaining unknown")
    #expect(short.remainingValue == nil)
    #expect(short.resetText == "Refresh required")
    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("no safe choice names the failed constraints and the nearest reset")
  func noSafeChoiceNamesFailedConstraintsAndNearestReset() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try insufficientResult()),
      recommendationEngine: RecommendationEngine(),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "No safe choice")
    #expect(model.recommendation.detail.contains("Codex short"))
    #expect(model.recommendation.detail.contains("Claude Code weekly"))
    #expect(model.recommendation.detail.contains("resets in 15m"))
  }

  @Test("a window with an unknown reset keeps its percentage and says so")
  func windowWithUnknownResetKeepsPercentageAndReportsMissingReset() throws {
    let window = QuotaWindow(kind: .short, remaining: try .init(remaining: 100), resetsAt: nil)

    let row = PresentationFormatter().row(provider: .codex, window: window, now: referenceDate)

    #expect(row.remainingText == "100% remaining")
    #expect(row.remainingValue == 100)
    #expect(row.resetText == "Reset unavailable")
    #expect(row.stateText == "Plenty")
    #expect(row.accessibilityLabel.contains("100% remaining"))
    #expect(row.accessibilityLabel.contains("Reset unavailable"))
  }

  @Test("an unknown reset in one window disables the recommendation")
  func unknownResetDisablesRecommendation() async throws {
    let model = AppViewModel(
      refreshUseCase: RefreshUseCaseStub(result: try unknownShortResetResult()),
      recommendationEngine: RecommendationEngine(),
      clock: FixedPresentationClock(now: referenceDate)
    )

    await model.panelOpened()

    #expect(model.recommendation.title == "Recommendation unavailable")
  }

  @Test("settings reject a relative path and save a trimmed absolute path")
  func settingsRejectRelativePathAndSaveValidatedAbsolutePath() async {
    let store = SettingsStoreSpy()
    let model = SettingsViewModel(
      settings: store,
      validator: ExecutableValidatorStub(validPath: "/opt/homebrew/bin/codex")
    )

    model.codexPath = "bin/codex"
    await model.save()

    #expect(model.validationMessage == "Choose an absolute executable file.")
    let rejectedValue = await store.path
    #expect(rejectedValue == nil)

    model.codexPath = " /opt/homebrew/bin/codex "
    await model.save()

    #expect(model.validationMessage == nil)
    let savedValue = await store.path
    #expect(savedValue == "/opt/homebrew/bin/codex")
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

private actor SettingsStoreSpy: AppSettingsStore {
  private(set) var path: String?

  func codexExecutablePath() async -> String? { path }

  func setCodexExecutablePath(_ path: String?) async { self.path = path }
}

private struct ExecutableValidatorStub: ExecutablePathValidating {
  let validPath: String

  func isExecutable(path: String) -> Bool { path == validPath }
}
