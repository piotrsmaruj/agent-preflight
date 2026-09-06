import AgentPreflightApplication
import Foundation

public actor UserDefaultsAppSettingsStore: AppSettingsStore {
  public static let codexPathKey = "codexExecutablePath"
  private let defaults: UserDefaults

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
}
