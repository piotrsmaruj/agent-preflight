import AgentPreflightApplication
import AgentPreflightDomain
import Combine
import Foundation

/// Unvalidated editing state for one task size.
///
/// Reserves stay plain numbers while the reader types, because a partially typed value is not yet
/// a `ReserveRequirement`; the draft becomes one only when it is saved.
public struct TaskSizeDraft: Identifiable, Equatable, Sendable {
  public let size: TaskSize
  public let title: String
  public var shortReserve: Double
  public var weeklyReserve: Double

  public var id: TaskSize { size }

  public init(size: TaskSize, title: String, shortReserve: Double, weeklyReserve: Double) {
    self.size = size
    self.title = title
    self.shortReserve = shortReserve
    self.weeklyReserve = weeklyReserve
  }
}

/// Editing state for every setting the app exposes.
///
/// Pickers cannot produce an invalid value, so appearance and display mode persist and take effect
/// the moment they change. Typed values — the Codex path and the reserves — are validated and
/// persisted only on an explicit save, so a half-finished entry never reaches the recommendation.
@MainActor
public final class SettingsViewModel: ObservableObject {
  @Published public var codexPath = ""
  @Published public private(set) var codexPathMessage: String?

  @Published public var appearance: AppearancePreference = .system {
    didSet { applyAndPersistAppearance() }
  }
  @Published public var quotaDisplayMode: QuotaDisplayMode = .remaining {
    didSet { applyAndPersistQuotaDisplayMode() }
  }

  @Published public var taskSizeDrafts: [TaskSizeDraft]
  @Published public var neutralTolerance: Double
  @Published public private(set) var taskSizeMessage: String?

  private let settings: any AppSettingsStore
  private let validator: any ExecutablePathValidating
  private let appearanceApplier: any AppearanceApplying
  private let formatter: PresentationFormatter
  private let onQuotaDisplayModeChange: (QuotaDisplayMode) -> Void
  private let onTaskSizePolicyChange: (TaskSizePolicy) -> Void
  private var isLoading = false
  private var persistence: Task<Void, Never> = Task {}

  public init(
    settings: any AppSettingsStore,
    validator: any ExecutablePathValidating,
    appearanceApplier: any AppearanceApplying = NSApplicationAppearanceApplier(),
    formatter: PresentationFormatter = .init(),
    onQuotaDisplayModeChange: @escaping (QuotaDisplayMode) -> Void = { _ in },
    onTaskSizePolicyChange: @escaping (TaskSizePolicy) -> Void = { _ in }
  ) {
    self.settings = settings
    self.validator = validator
    self.appearanceApplier = appearanceApplier
    self.formatter = formatter
    self.onQuotaDisplayModeChange = onQuotaDisplayModeChange
    self.onTaskSizePolicyChange = onTaskSizePolicyChange
    self.taskSizeDrafts = Self.drafts(from: .default, formatter: formatter)
    self.neutralTolerance = TaskSizePolicy.default.neutralTolerance
  }

  /// Reads every persisted setting and applies the ones that change how the app already looks.
  ///
  /// The loading flag keeps the published setters from writing the value they just read back to
  /// the store, which would also fire the change callbacks during composition.
  public func load() async {
    let storedAppearance = await settings.appearancePreference()
    let storedDisplayMode = await settings.quotaDisplayMode()
    let storedPolicy = await settings.taskSizePolicy()
    isLoading = true
    codexPath = await settings.codexExecutablePath() ?? ""
    appearance = storedAppearance
    quotaDisplayMode = storedDisplayMode
    isLoading = false
    applyTaskSizePolicy(storedPolicy)
    appearanceApplier.apply(storedAppearance)
    onQuotaDisplayModeChange(storedDisplayMode)
    onTaskSizePolicyChange(storedPolicy)
  }

  /// Settings changed from a picker persist without blocking the UI, so the writes are chained
  /// behind one another: two quick toggles must land in the order the reader made them.
  public func persistedChangesCompleted() async { await persistence.value }

  public func saveCodexPath() async {
    let normalized = codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.isEmpty || validator.isExecutable(path: normalized) else {
      codexPathMessage = "Choose an absolute executable file."
      return
    }
    await settings.setCodexExecutablePath(normalized.isEmpty ? nil : normalized)
    codexPathMessage = nil
  }

  public func useAutomaticCodexDiscovery() async {
    codexPath = ""
    await saveCodexPath()
  }

  public func saveTaskSizePolicy() async {
    do {
      let policy = try policyFromDrafts()
      await settings.setTaskSizePolicy(policy)
      taskSizeMessage = nil
      onTaskSizePolicyChange(policy)
    } catch {
      taskSizeMessage = Self.message(for: error)
    }
  }

  public func restoreDefaultTaskSizePolicy() async {
    applyTaskSizePolicy(.default)
    await settings.setTaskSizePolicy(.default)
    taskSizeMessage = nil
    onTaskSizePolicyChange(.default)
  }

  private func policyFromDrafts() throws -> TaskSizePolicy {
    try TaskSizePolicy(
      small: requirement(for: .small),
      medium: requirement(for: .medium),
      large: requirement(for: .large),
      neutralTolerance: neutralTolerance
    )
  }

  private func requirement(for size: TaskSize) throws -> ReserveRequirement {
    guard let draft = taskSizeDrafts.first(where: { $0.size == size }) else {
      return TaskSizePolicy.default.requirement(for: size)
    }
    return try ReserveRequirement(short: draft.shortReserve, weekly: draft.weeklyReserve)
  }

  private func applyTaskSizePolicy(_ policy: TaskSizePolicy) {
    taskSizeDrafts = Self.drafts(from: policy, formatter: formatter)
    neutralTolerance = policy.neutralTolerance
  }

  private func applyAndPersistAppearance() {
    guard !isLoading else { return }
    let preference = appearance
    appearanceApplier.apply(preference)
    let settings = settings
    persist { await settings.setAppearancePreference(preference) }
  }

  private func applyAndPersistQuotaDisplayMode() {
    guard !isLoading else { return }
    let mode = quotaDisplayMode
    onQuotaDisplayModeChange(mode)
    let settings = settings
    persist { await settings.setQuotaDisplayMode(mode) }
  }

  private func persist(_ write: @escaping @Sendable () async -> Void) {
    let pending = persistence
    persistence = Task {
      await pending.value
      await write()
    }
  }

  private static func drafts(
    from policy: TaskSizePolicy,
    formatter: PresentationFormatter
  ) -> [TaskSizeDraft] {
    TaskSize.allCases.map { size in
      let requirement = policy.requirement(for: size)
      return TaskSizeDraft(
        size: size,
        title: formatter.taskSizeTitle(size),
        shortReserve: requirement.short,
        weeklyReserve: requirement.weekly
      )
    }
  }

  private static func message(for error: any Error) -> String {
    guard let policyError = error as? TaskSizePolicyError else {
      return "The task size policy could not be saved."
    }
    switch policyError {
    case .reserveOutOfRange:
      let range = ReserveRequirement.allowedPercentages
      return
        "Every reserve must be between \(Int(range.lowerBound))% and \(Int(range.upperBound))%."
    case .neutralToleranceOutOfRange:
      let range = TaskSizePolicy.allowedNeutralTolerances
      return "The neutral tolerance must be between \(range.lowerBound) and \(range.upperBound)."
    }
  }
}
