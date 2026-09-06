import Foundation
import Testing

@testable import AgentPreflightDomain

@Suite("Recommendation engine")
struct RecommendationEngineTests {
  private let now = Date(timeIntervalSince1970: 1_788_505_200)

  @Test("default policy contains the exact approved reserves")
  func defaultPolicyContainsExactApprovedReserves() {
    let policy = TaskSizePolicy.default

    #expect(policy.requirement(for: .small) == ReserveRequirement(short: 15, weekly: 5))
    #expect(policy.requirement(for: .medium) == ReserveRequirement(short: 35, weekly: 10))
    #expect(policy.requirement(for: .large) == ReserveRequirement(short: 60, weekly: 20))
    #expect(policy.neutralTolerance == 0.10)
  }

  @Test("the only safe provider is recommended at the exact boundary")
  func onlySafeProviderIsRecommendedAtExactBoundary() throws {
    let result = RecommendationEngine().recommend(
      taskSize: .medium,
      snapshots: [
        .codex: try snapshot(.codex, short: 35, weekly: 10),
        .claudeCode: try snapshot(.claudeCode, short: 34, weekly: 40),
      ],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .provider(.codex))
    #expect(result.reason == .onlySafe(.codex))
  }

  @Test("the larger minimum safety margin wins")
  func largerMinimumSafetyMarginWins() throws {
    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [
        .codex: try snapshot(.codex, short: 45, weekly: 15),
        .claudeCode: try snapshot(.claudeCode, short: 30, weekly: 10),
      ],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .provider(.codex))
    #expect(result.reason == .largerMargin(.codex))
  }

  @Test("a margin difference below the tolerance is neutral")
  func differenceBelowToleranceIsNeutral() throws {
    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [
        .codex: try snapshot(.codex, short: 30, weekly: 10),
        .claudeCode: try snapshot(.claudeCode, short: 31, weekly: 10.2),
      ],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .neutral)
    #expect(result.reason == .marginsWithinTolerance)
  }

  @Test("a margin difference at the tolerance chooses the larger margin")
  func differenceAtToleranceChoosesLargerMargin() throws {
    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [
        .codex: try snapshot(.codex, short: 30, weekly: 10),
        .claudeCode: try snapshot(.claudeCode, short: 31.5, weekly: 10.5),
      ],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .provider(.claudeCode))
    #expect(result.reason == .largerMargin(.claudeCode))
  }

  /// Pins the `>=` boundary itself: every value here is exactly representable in binary
  /// floating point, so the margin difference equals the tolerance with no rounding slack
  /// and the case fails the moment the comparison becomes a strict `>`.
  @Test("a margin difference of exactly the tolerance chooses the larger margin")
  func differenceOfExactlyToleranceChoosesLargerMargin() throws {
    let policy = TaskSizePolicy(
      small: ReserveRequirement(short: 16, weekly: 16),
      medium: TaskSizePolicy.default.medium,
      large: TaskSizePolicy.default.large,
      neutralTolerance: 0.125
    )

    let result = RecommendationEngine(policy: policy).recommend(
      taskSize: .small,
      snapshots: [
        .codex: try snapshot(.codex, short: 32, weekly: 32),
        .claudeCode: try snapshot(.claudeCode, short: 34, weekly: 34),
      ],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .provider(.claudeCode))
    #expect(result.reason == .largerMargin(.claudeCode))
  }

  @Test("neither safe returns every failed constraint and the nearest reset")
  func neitherSafeReturnsEveryFailedConstraintAndNearestReset() throws {
    let codex = try snapshot(.codex, short: 20, weekly: 9, shortReset: 900, weeklyReset: 3_600)
    let claude = try snapshot(
      .claudeCode,
      short: 34,
      weekly: 8,
      shortReset: 1_800,
      weeklyReset: 7_200
    )

    let result = RecommendationEngine().recommend(
      taskSize: .medium,
      snapshots: [.codex: codex, .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .noSafeChoice)
    #expect(result.reason == .insufficientQuota)
    #expect(result.failures.count == 4)
    #expect(result.nearestRelevantReset == now.addingTimeInterval(900))
  }

  @Test("a missing, stale or passed window makes the recommendation unavailable")
  func missingStaleOrPassedWindowMakesRecommendationUnavailable() throws {
    let complete = try snapshot(.codex, short: 90, weekly: 90)
    let partial = try weeklyOnlySnapshot(.claudeCode, weekly: 90)

    #expect(
      RecommendationEngine().recommend(
        taskSize: .small,
        snapshots: [.codex: complete, .claudeCode: partial],
        staleProviders: [],
        now: now
      ).decision == .unavailable
    )

    let passedReset = try snapshot(.claudeCode, short: 90, weekly: 90, shortReset: -1)
    #expect(
      RecommendationEngine().recommend(
        taskSize: .small,
        snapshots: [.codex: complete, .claudeCode: passedReset],
        staleProviders: [],
        now: now
      ).decision == .unavailable
    )

    #expect(
      RecommendationEngine().recommend(
        taskSize: .small,
        snapshots: [
          .codex: complete,
          .claudeCode: try snapshot(.claudeCode, short: 90, weekly: 90),
        ],
        staleProviders: [.claudeCode],
        now: now
      ).decision == .unavailable
    )
  }

  @Test("a window without a known reset makes the recommendation unavailable")
  func unknownShortResetMakesRecommendationUnavailable() throws {
    let complete = try snapshot(.codex, short: 90, weekly: 90)
    let unknownShortReset = try snapshotWithUnknownShortReset(
      .claudeCode,
      short: 90,
      weekly: 90
    )

    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [.codex: complete, .claudeCode: unknownShortReset],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .unavailable)
    #expect(result.reason == .incompleteOrStaleData)
  }

  @Test("a tighter model-scoped week becomes the reported weekly constraint")
  func tighterModelScopedWeekBecomesReportedWeeklyConstraint() throws {
    let claude = try scopedSnapshot(.claudeCode, short: 90, weekly: 50, scoped: 5)

    let result = RecommendationEngine().recommend(
      taskSize: .medium,
      snapshots: [.codex: try snapshot(.codex, short: 20, weekly: 50), .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .noSafeChoice)
    let weeklyFailures = result.failures.filter { $0.provider == .claudeCode }
    #expect(weeklyFailures.count == 1)
    #expect(weeklyFailures.first?.window == .modelWeekly)
    #expect(weeklyFailures.first?.scopeLabel == "Fable")
    #expect(weeklyFailures.first?.remaining == 5)
    #expect(weeklyFailures.first?.required == 10)
  }

  @Test("a tighter model-scoped week lowers the safety margin")
  func tighterModelScopedWeekLowersSafetyMargin() throws {
    let claude = try scopedSnapshot(.claudeCode, short: 30, weekly: 50, scoped: 7.5)

    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [.codex: try snapshot(.codex, short: 30, weekly: 25), .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .provider(.codex))
    #expect(result.reason == .largerMargin(.codex))
  }

  @Test("a looser model-scoped week leaves the all-models week binding")
  func looserModelScopedWeekLeavesAllModelsWeekBinding() throws {
    let claude = try scopedSnapshot(.claudeCode, short: 90, weekly: 5, scoped: 50)

    let result = RecommendationEngine().recommend(
      taskSize: .medium,
      snapshots: [.codex: try snapshot(.codex, short: 20, weekly: 50), .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .noSafeChoice)
    let weeklyFailures = result.failures.filter { $0.provider == .claudeCode }
    #expect(weeklyFailures.count == 1)
    #expect(weeklyFailures.first?.window == .weekly)
    #expect(weeklyFailures.first?.scopeLabel == nil)
  }

  /// The live payload reports both weekly windows at the same utilization, so the tie decides the
  /// copy a user actually sees; it must stay on the all-models week rather than name a model.
  @Test("weekly windows that are tied leave the all-models week binding")
  func tiedWeeklyWindowsLeaveAllModelsWeekBinding() throws {
    let claude = try scopedSnapshot(.claudeCode, short: 90, weekly: 5, scoped: 5)

    let result = RecommendationEngine().recommend(
      taskSize: .medium,
      snapshots: [.codex: try snapshot(.codex, short: 20, weekly: 50), .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .noSafeChoice)
    let weeklyFailures = result.failures.filter { $0.provider == .claudeCode }
    #expect(weeklyFailures.count == 1)
    #expect(weeklyFailures.first?.window == .weekly)
    #expect(weeklyFailures.first?.scopeLabel == nil)
  }

  @Test("a model-scoped week without a known reset makes the recommendation unavailable")
  func modelScopedWeekWithoutKnownResetMakesRecommendationUnavailable() throws {
    let claude = try scopedSnapshot(
      .claudeCode, short: 90, weekly: 90, scoped: 90, scopedReset: nil)

    let result = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: [.codex: try snapshot(.codex, short: 90, weekly: 90), .claudeCode: claude],
      staleProviders: [],
      now: now
    )

    #expect(result.decision == .unavailable)
    #expect(result.reason == .incompleteOrStaleData)
  }

  private func snapshot(
    _ provider: ProviderIdentifier,
    short: Double,
    weekly: Double,
    shortReset: TimeInterval = 3_600,
    weeklyReset: TimeInterval = 86_400
  ) throws -> QuotaSnapshot {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: try RemainingPercentage(remaining: short),
          resetsAt: now.addingTimeInterval(shortReset)
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: try RemainingPercentage(remaining: weekly),
          resetsAt: now.addingTimeInterval(weeklyReset)
        ),
      ],
      fetchedAt: now
    )
  }

  private func scopedSnapshot(
    _ provider: ProviderIdentifier,
    short: Double,
    weekly: Double,
    scoped: Double,
    scopeLabel: String = "Fable",
    scopedReset: TimeInterval? = 86_400
  ) throws -> QuotaSnapshot {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: try RemainingPercentage(remaining: short),
          resetsAt: now.addingTimeInterval(3_600)
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: try RemainingPercentage(remaining: weekly),
          resetsAt: now.addingTimeInterval(86_400)
        ),
        QuotaWindow(
          kind: .modelWeekly,
          remaining: try RemainingPercentage(remaining: scoped),
          resetsAt: scopedReset.map { now.addingTimeInterval($0) },
          scopeLabel: scopeLabel
        ),
      ],
      fetchedAt: now
    )
  }

  private func weeklyOnlySnapshot(
    _ provider: ProviderIdentifier,
    weekly: Double
  ) throws -> QuotaSnapshot {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .weekly,
          remaining: try RemainingPercentage(remaining: weekly),
          resetsAt: now.addingTimeInterval(86_400)
        )
      ],
      fetchedAt: now
    )
  }

  private func snapshotWithUnknownShortReset(
    _ provider: ProviderIdentifier,
    short: Double,
    weekly: Double
  ) throws -> QuotaSnapshot {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: try RemainingPercentage(remaining: short),
          resetsAt: nil
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: try RemainingPercentage(remaining: weekly),
          resetsAt: now.addingTimeInterval(86_400)
        ),
      ],
      fetchedAt: now
    )
  }
}
