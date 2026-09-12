import Foundation
import Testing

@testable import AgentPreflightDomain

@Suite("Task size policy")
struct TaskSizePolicyTests {
  @Test("a reserve outside the allowed percentages is rejected", arguments: [0, -1, 101, 100.5])
  func reserveOutsideAllowedPercentagesIsRejected(percentage: Double) {
    #expect(throws: TaskSizePolicyError.reserveOutOfRange(percentage)) {
      try ReserveRequirement(short: percentage, weekly: 10)
    }
    #expect(throws: TaskSizePolicyError.reserveOutOfRange(percentage)) {
      try ReserveRequirement(short: 10, weekly: percentage)
    }
  }

  @Test("a non-finite reserve is rejected")
  func nonFiniteReserveIsRejected() {
    #expect(throws: (any Error).self) {
      try ReserveRequirement(short: .nan, weekly: 10)
    }
    #expect(throws: (any Error).self) {
      try ReserveRequirement(short: .infinity, weekly: 10)
    }
  }

  @Test("the allowed boundaries are accepted")
  func allowedBoundariesAreAccepted() throws {
    let lowest = try ReserveRequirement(short: 1, weekly: 1)
    let highest = try ReserveRequirement(short: 100, weekly: 100)

    #expect(lowest.short == 1)
    #expect(highest.weekly == 100)
  }

  @Test("a neutral tolerance outside the allowed range is rejected", arguments: [-0.01, 1.5])
  func neutralToleranceOutsideAllowedRangeIsRejected(tolerance: Double) {
    #expect(throws: TaskSizePolicyError.neutralToleranceOutOfRange(tolerance)) {
      try TaskSizePolicy(
        small: ReserveRequirement(short: 15, weekly: 5),
        medium: ReserveRequirement(short: 35, weekly: 10),
        large: ReserveRequirement(short: 60, weekly: 20),
        neutralTolerance: tolerance
      )
    }
  }

  @Test("a custom policy survives a Codable round trip")
  func customPolicySurvivesCodableRoundTrip() throws {
    let policy = try TaskSizePolicy(
      small: ReserveRequirement(short: 20, weekly: 7),
      medium: ReserveRequirement(short: 45, weekly: 12),
      large: ReserveRequirement(short: 75, weekly: 25),
      neutralTolerance: 0.25
    )

    let decoded = try JSONDecoder().decode(
      TaskSizePolicy.self,
      from: try JSONEncoder().encode(policy)
    )

    #expect(decoded == policy)
  }

  /// Decoding runs the same validation as the initializer, so a hand-edited or corrupted
  /// preference cannot install a policy the engine would divide by.
  @Test("decoding rejects a reserve the initializer would reject")
  func decodingRejectsReserveTheInitializerWouldReject() throws {
    let payload = Data(
      """
      {"small":{"short":0,"weekly":5},"medium":{"short":35,"weekly":10},\
      "large":{"short":60,"weekly":20},"neutralTolerance":0.1}
      """.utf8
    )

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(TaskSizePolicy.self, from: payload)
    }
  }

  @Test("a custom policy changes which provider is safe")
  func customPolicyChangesWhichProviderIsSafe() throws {
    let now = Date(timeIntervalSince1970: 1_788_505_200)
    let snapshots = [
      ProviderIdentifier.codex: try snapshot(.codex, short: 50, weekly: 50, now: now),
      ProviderIdentifier.claudeCode: try snapshot(.claudeCode, short: 50, weekly: 50, now: now),
    ]
    let demanding = try TaskSizePolicy(
      small: ReserveRequirement(short: 90, weekly: 90),
      medium: TaskSizePolicy.default.medium,
      large: TaskSizePolicy.default.large,
      neutralTolerance: 0.10
    )

    let underDefault = RecommendationEngine().recommend(
      taskSize: .small,
      snapshots: snapshots,
      staleProviders: [],
      now: now
    )
    let underDemanding = RecommendationEngine(policy: demanding).recommend(
      taskSize: .small,
      snapshots: snapshots,
      staleProviders: [],
      now: now
    )

    #expect(underDefault.decision == .neutral)
    #expect(underDemanding.decision == .noSafeChoice)
  }

  private func snapshot(
    _ provider: ProviderIdentifier,
    short: Double,
    weekly: Double,
    now: Date
  ) throws -> QuotaSnapshot {
    try QuotaSnapshot(
      provider: provider,
      windows: [
        QuotaWindow(
          kind: .short,
          remaining: .init(remaining: short),
          resetsAt: now.addingTimeInterval(3_600)
        ),
        QuotaWindow(
          kind: .weekly,
          remaining: .init(remaining: weekly),
          resetsAt: now.addingTimeInterval(86_400)
        ),
      ],
      fetchedAt: now
    )
  }
}
