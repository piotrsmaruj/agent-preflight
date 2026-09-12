import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

@Suite("User defaults app settings store")
struct UserDefaultsAppSettingsStoreTests {
  @Test("an empty store reports the documented defaults")
  func emptyStoreReportsDocumentedDefaults() async throws {
    let defaults = try makeDefaults(#function)
    let store = UserDefaultsAppSettingsStore(defaults: defaults)

    #expect(await store.codexExecutablePath() == nil)
    #expect(await store.appearancePreference() == .system)
    #expect(await store.quotaDisplayMode() == .remaining)
    #expect(await store.taskSizePolicy() == .default)
  }

  @Test("every setting survives a write and a read")
  func everySettingSurvivesWriteAndRead() async throws {
    let defaults = try makeDefaults(#function)
    let store = UserDefaultsAppSettingsStore(defaults: defaults)
    let policy = try TaskSizePolicy(
      small: ReserveRequirement(short: 20, weekly: 7),
      medium: ReserveRequirement(short: 45, weekly: 12),
      large: ReserveRequirement(short: 75, weekly: 25),
      neutralTolerance: 0.25
    )

    await store.setCodexExecutablePath("  /usr/local/bin/codex  ")
    await store.setAppearancePreference(.dark)
    await store.setQuotaDisplayMode(.used)
    await store.setTaskSizePolicy(policy)

    #expect(await store.codexExecutablePath() == "/usr/local/bin/codex")
    #expect(await store.appearancePreference() == .dark)
    #expect(await store.quotaDisplayMode() == .used)
    #expect(await store.taskSizePolicy() == policy)
  }

  /// A preference written by a newer build, or corrupted on disk, must not brick the app.
  @Test("unreadable values fall back to the documented defaults")
  func unreadableValuesFallBackToDocumentedDefaults() async throws {
    let defaults = try makeDefaults(#function)
    defaults.set("sepia", forKey: UserDefaultsAppSettingsStore.appearanceKey)
    defaults.set("burned", forKey: UserDefaultsAppSettingsStore.quotaDisplayModeKey)
    defaults.set(Data("not a policy".utf8), forKey: UserDefaultsAppSettingsStore.taskSizePolicyKey)
    let store = UserDefaultsAppSettingsStore(defaults: defaults)

    #expect(await store.appearancePreference() == .system)
    #expect(await store.quotaDisplayMode() == .remaining)
    #expect(await store.taskSizePolicy() == .default)
  }

  @Test("a blank path clears the stored value")
  func blankPathClearsStoredValue() async throws {
    let defaults = try makeDefaults(#function)
    let store = UserDefaultsAppSettingsStore(defaults: defaults)
    await store.setCodexExecutablePath("/usr/local/bin/codex")

    await store.setCodexExecutablePath("   ")

    #expect(await store.codexExecutablePath() == nil)
  }

  /// Each test owns a suite named after itself and starts from an empty one, so an earlier run
  /// that crashed before cleanup cannot leak a value into this one.
  private func makeDefaults(_ suiteName: String) throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: "AgentPreflightTests.\(suiteName)"))
    defaults.removePersistentDomain(forName: "AgentPreflightTests.\(suiteName)")
    return defaults
  }
}
