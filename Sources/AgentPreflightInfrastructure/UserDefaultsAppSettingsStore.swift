import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

/// Settings persistence in `UserDefaults`.
///
/// Every read falls back to the documented default rather than failing: a preference written by a
/// newer build, hand-edited, or corrupted must leave the app usable, so an undecodable value is
/// treated exactly like an absent one.
public actor UserDefaultsAppSettingsStore: AppSettingsStore {
  public static let codexPathKey = "codexExecutablePath"
  public static let appearanceKey = "appearancePreference"
  public static let quotaDisplayModeKey = "quotaDisplayMode"
  public static let taskSizePolicyKey = "taskSizePolicy"

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public func codexExecutablePath() async -> String? {
    defaults.string(forKey: Self.codexPathKey)
  }

  public func setCodexExecutablePath(_ path: String?) async {
    let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalized, !normalized.isEmpty {
      defaults.set(normalized, forKey: Self.codexPathKey)
    } else {
      defaults.removeObject(forKey: Self.codexPathKey)
    }
  }

  public func appearancePreference() async -> AppearancePreference {
    rawValue(forKey: Self.appearanceKey) ?? .system
  }

  public func setAppearancePreference(_ preference: AppearancePreference) async {
    defaults.set(preference.rawValue, forKey: Self.appearanceKey)
  }

  public func quotaDisplayMode() async -> QuotaDisplayMode {
    rawValue(forKey: Self.quotaDisplayModeKey) ?? .remaining
  }

  public func setQuotaDisplayMode(_ mode: QuotaDisplayMode) async {
    defaults.set(mode.rawValue, forKey: Self.quotaDisplayModeKey)
  }

  public func taskSizePolicy() async -> TaskSizePolicy {
    guard let data = defaults.data(forKey: Self.taskSizePolicyKey),
      let policy = try? decoder.decode(TaskSizePolicy.self, from: data)
    else { return .default }
    return policy
  }

  public func setTaskSizePolicy(_ policy: TaskSizePolicy) async {
    guard let data = try? encoder.encode(policy) else { return }
    defaults.set(data, forKey: Self.taskSizePolicyKey)
  }

  private func rawValue<Value: RawRepresentable>(forKey key: String) -> Value?
  where Value.RawValue == String {
    defaults.string(forKey: key).flatMap(Value.init(rawValue:))
  }
}
