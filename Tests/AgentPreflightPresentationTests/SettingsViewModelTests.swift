import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightPresentation

@Suite("Settings view model")
@MainActor
struct SettingsViewModelTests {
  @Test("a relative path is rejected and an absolute one is saved trimmed")
  func relativePathIsRejectedAndAbsoluteOneIsSavedTrimmed() async {
    let store = SettingsStoreSpy()
    let model = makeModel(store: store)

    model.codexPath = "bin/codex"
    await model.saveCodexPath()

    #expect(model.codexPathMessage == "Choose an absolute executable file.")
    let rejectedValue = await store.path
    #expect(rejectedValue == nil)

    model.codexPath = " /opt/homebrew/bin/codex "
    await model.saveCodexPath()

    #expect(model.codexPathMessage == nil)
    let savedValue = await store.path
    #expect(savedValue == "/opt/homebrew/bin/codex")
  }

  @Test("automatic discovery clears the stored path")
  func automaticDiscoveryClearsStoredPath() async {
    let store = SettingsStoreSpy()
    let model = makeModel(store: store)
    model.codexPath = "/opt/homebrew/bin/codex"
    await model.saveCodexPath()

    await model.useAutomaticCodexDiscovery()

    #expect(model.codexPath.isEmpty)
    let storedValue = await store.path
    #expect(storedValue == nil)
  }

  @Test(
    "choosing a theme repaints and persists it immediately",
    arguments: [
      AppearancePreference.dark, .light, .system,
    ])
  func choosingThemeRepaintsAndPersistsImmediately(preference: AppearancePreference) async {
    let store = SettingsStoreSpy()
    let applier = AppearanceApplierSpy()
    let model = makeModel(store: store, applier: applier)

    model.appearance = preference
    await model.persistedChangesCompleted()

    #expect(applier.applied == [preference])
    let storedValue = await store.appearance
    #expect(storedValue == preference)
  }

  @Test("choosing a display mode announces and persists it immediately")
  func choosingDisplayModeAnnouncesAndPersistsImmediately() async {
    let store = SettingsStoreSpy()
    let announced = ValueSpy<QuotaDisplayMode>()
    let model = makeModel(store: store, onQuotaDisplayModeChange: { announced.record($0) })

    model.quotaDisplayMode = .used
    await model.persistedChangesCompleted()

    #expect(announced.values == [.used])
    let storedValue = await store.displayMode
    #expect(storedValue == .used)
  }

  @Test("loading applies the stored settings without writing them back")
  func loadingAppliesStoredSettingsWithoutWritingThemBack() async throws {
    let policy = try TaskSizePolicy(
      small: ReserveRequirement(short: 20, weekly: 7),
      medium: ReserveRequirement(short: 45, weekly: 12),
      large: ReserveRequirement(short: 75, weekly: 25),
      neutralTolerance: 0.25
    )
    let store = SettingsStoreSpy()
    await store.seed(appearance: .dark, displayMode: .used, policy: policy)
    let applier = AppearanceApplierSpy()
    let announcedMode = ValueSpy<QuotaDisplayMode>()
    let announcedPolicy = ValueSpy<TaskSizePolicy>()
    let model = makeModel(
      store: store,
      applier: applier,
      onQuotaDisplayModeChange: { announcedMode.record($0) },
      onTaskSizePolicyChange: { announcedPolicy.record($0) }
    )

    await model.load()
    await model.persistedChangesCompleted()

    #expect(model.appearance == .dark)
    #expect(model.quotaDisplayMode == .used)
    #expect(model.taskSizeDrafts.map(\.shortReserve) == [20, 45, 75])
    #expect(model.taskSizeDrafts.map(\.weeklyReserve) == [7, 12, 25])
    #expect(model.neutralTolerance == 0.25)
    #expect(applier.applied == [.dark])
    #expect(announcedMode.values == [.used])
    #expect(announcedPolicy.values == [policy])
    let writes = await store.writeCount
    #expect(writes == 0)
  }

  @Test("the drafts are labelled in the documented order")
  func draftsAreLabelledInDocumentedOrder() {
    let model = makeModel(store: SettingsStoreSpy())

    #expect(model.taskSizeDrafts.map(\.size) == [.small, .medium, .large])
    #expect(model.taskSizeDrafts.map(\.title) == ["Small", "Medium", "Large"])
  }

  @Test("valid reserves are saved and announced")
  func validReservesAreSavedAndAnnounced() async throws {
    let store = SettingsStoreSpy()
    let announced = ValueSpy<TaskSizePolicy>()
    let model = makeModel(store: store, onTaskSizePolicyChange: { announced.record($0) })

    model.taskSizeDrafts[0].shortReserve = 25
    model.taskSizeDrafts[0].weeklyReserve = 8
    model.neutralTolerance = 0.2
    await model.saveTaskSizePolicy()

    #expect(model.taskSizeMessage == nil)
    let stored = try #require(await store.policy)
    #expect(stored.small == (try ReserveRequirement(short: 25, weekly: 8)))
    #expect(stored.neutralTolerance == 0.2)
    #expect(announced.values == [stored])
  }

  @Test("an out-of-range reserve is reported and never persisted")
  func outOfRangeReserveIsReportedAndNeverPersisted() async {
    let store = SettingsStoreSpy()
    let announced = ValueSpy<TaskSizePolicy>()
    let model = makeModel(store: store, onTaskSizePolicyChange: { announced.record($0) })

    model.taskSizeDrafts[1].shortReserve = 0
    await model.saveTaskSizePolicy()

    #expect(model.taskSizeMessage == "Every reserve must be between 1% and 100%.")
    let stored = await store.policy
    #expect(stored == nil)
    #expect(announced.values.isEmpty)
  }

  @Test("an out-of-range tolerance is reported and never persisted")
  func outOfRangeToleranceIsReportedAndNeverPersisted() async {
    let store = SettingsStoreSpy()
    let model = makeModel(store: store)

    model.neutralTolerance = 4
    await model.saveTaskSizePolicy()

    #expect(model.taskSizeMessage == "The neutral tolerance must be between 0.0 and 1.0.")
    let stored = await store.policy
    #expect(stored == nil)
  }

  @Test("restoring defaults rewrites the drafts, the store, and the panel")
  func restoringDefaultsRewritesDraftsStoreAndPanel() async {
    let store = SettingsStoreSpy()
    let announced = ValueSpy<TaskSizePolicy>()
    let model = makeModel(store: store, onTaskSizePolicyChange: { announced.record($0) })
    model.taskSizeDrafts[0].shortReserve = 99
    model.neutralTolerance = 0.9

    await model.restoreDefaultTaskSizePolicy()

    #expect(model.taskSizeDrafts.map(\.shortReserve) == [15, 35, 60])
    #expect(model.neutralTolerance == TaskSizePolicy.default.neutralTolerance)
    #expect(model.taskSizeMessage == nil)
    let stored = await store.policy
    #expect(stored == TaskSizePolicy.default)
    #expect(announced.values == [TaskSizePolicy.default])
  }

  private func makeModel(
    store: SettingsStoreSpy,
    applier: AppearanceApplierSpy = AppearanceApplierSpy(),
    onQuotaDisplayModeChange: @escaping (QuotaDisplayMode) -> Void = { _ in },
    onTaskSizePolicyChange: @escaping (TaskSizePolicy) -> Void = { _ in }
  ) -> SettingsViewModel {
    SettingsViewModel(
      settings: store,
      validator: ExecutableValidatorStub(validPath: "/opt/homebrew/bin/codex"),
      appearanceApplier: applier,
      onQuotaDisplayModeChange: onQuotaDisplayModeChange,
      onTaskSizePolicyChange: onTaskSizePolicyChange
    )
  }
}

/// Records writes so a load can be proven not to echo what it just read back into the store.
private actor SettingsStoreSpy: AppSettingsStore {
  private(set) var path: String?
  private(set) var appearance: AppearancePreference = .system
  private(set) var displayMode: QuotaDisplayMode = .remaining
  private(set) var policy: TaskSizePolicy?
  private(set) var writeCount = 0

  func seed(
    appearance: AppearancePreference,
    displayMode: QuotaDisplayMode,
    policy: TaskSizePolicy
  ) {
    self.appearance = appearance
    self.displayMode = displayMode
    self.policy = policy
  }

  func codexExecutablePath() async -> String? { path }

  func setCodexExecutablePath(_ path: String?) async {
    writeCount += 1
    self.path = path
  }

  func appearancePreference() async -> AppearancePreference { appearance }

  func setAppearancePreference(_ preference: AppearancePreference) async {
    writeCount += 1
    appearance = preference
  }

  func quotaDisplayMode() async -> QuotaDisplayMode { displayMode }

  func setQuotaDisplayMode(_ mode: QuotaDisplayMode) async {
    writeCount += 1
    displayMode = mode
  }

  func taskSizePolicy() async -> TaskSizePolicy { policy ?? .default }

  func setTaskSizePolicy(_ policy: TaskSizePolicy) async {
    writeCount += 1
    self.policy = policy
  }
}

@MainActor
private final class AppearanceApplierSpy: AppearanceApplying {
  private(set) var applied: [AppearancePreference] = []

  func apply(_ preference: AppearancePreference) { applied.append(preference) }
}

@MainActor
private final class ValueSpy<Value> {
  private(set) var values: [Value] = []

  func record(_ value: Value) { values.append(value) }
}

private struct ExecutableValidatorStub: ExecutablePathValidating {
  let validPath: String

  func isExecutable(path: String) -> Bool { path == validPath }
}
