import Foundation
import Testing

@testable import AgentPreflightDomain

@Suite("Quota models")
struct QuotaModelsTests {
  @Test("used percentage converts to remaining percentage")
  func usedPercentageConvertsToRemainingPercentage() throws {
    #expect(try RemainingPercentage.fromUsed(21.5).value == 78.5)
  }

  @Test("tiny provider drift is clamped")
  func tinyProviderDriftIsClamped() throws {
    #expect(try RemainingPercentage(remaining: 100.005).value == 100)
    #expect(try RemainingPercentage(remaining: -0.005).value == 0)
  }

  @Test("structurally invalid percentage is rejected")
  func structurallyInvalidPercentageIsRejected() {
    #expect(throws: QuotaModelError.self) {
      try RemainingPercentage(remaining: 101)
    }
    #expect(throws: QuotaModelError.self) {
      try RemainingPercentage(remaining: .nan)
    }
    #expect(throws: QuotaModelError.self) {
      try JSONDecoder().decode(RemainingPercentage.self, from: Data(#"{"value":101}"#.utf8))
    }
  }

  @Test("duplicate window kinds are rejected")
  func duplicateWindowKindsAreRejected() throws {
    let date = Date(timeIntervalSince1970: 2_000_000_000)
    let percentage = try RemainingPercentage(remaining: 50)
    let first = QuotaWindow(kind: .short, remaining: percentage, resetsAt: date)
    let second = QuotaWindow(kind: .short, remaining: percentage, resetsAt: date)

    #expect(throws: QuotaModelError.self) {
      try QuotaSnapshot(provider: .codex, windows: [first, second], fetchedAt: date)
    }
  }

  @Test("a nil reset survives a Codable round trip")
  func nilResetSurvivesCodableRoundTrip() throws {
    let window = QuotaWindow(
      kind: .short,
      remaining: try RemainingPercentage(remaining: 100),
      resetsAt: nil
    )

    let encoded = try JSONEncoder().encode(window)
    let decoded = try JSONDecoder().decode(QuotaWindow.self, from: encoded)

    #expect(decoded == window)
    #expect(decoded.resetsAt == nil)
  }

  @Test("snapshot validity excludes unknown and expired resets")
  func snapshotValidityExcludesUnknownAndExpiredResets() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let futureReset = Date(timeIntervalSince1970: 2_000_003_600)
    let remaining = try RemainingPercentage(remaining: 100)
    let unknownReset = QuotaWindow(kind: .short, remaining: remaining, resetsAt: nil)
    let knownReset = QuotaWindow(kind: .weekly, remaining: remaining, resetsAt: futureReset)
    let snapshot = try QuotaSnapshot(
      provider: .claudeCode,
      windows: [unknownReset, knownReset],
      fetchedAt: now
    )

    #expect(snapshot.window(.short, validAt: now) == nil)
    #expect(snapshot.window(.weekly, validAt: now) == knownReset)
    #expect(snapshot.window(.weekly, validAt: futureReset) == nil)
  }
}
