import AgentPreflightApplication
import Combine
import Foundation

/// Editing state for the Codex executable path, saved only after the validator accepts it.
@MainActor
public final class SettingsViewModel: ObservableObject {
  @Published public var codexPath = ""
  @Published public private(set) var validationMessage: String?

  private let settings: any AppSettingsStore
  private let validator: any ExecutablePathValidating

  public init(settings: any AppSettingsStore, validator: any ExecutablePathValidating) {
    self.settings = settings
    self.validator = validator
  }

  public func load() async {
    codexPath = await settings.codexExecutablePath() ?? ""
  }

  public func save() async {
    let normalized = codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.isEmpty || validator.isExecutable(path: normalized) else {
      validationMessage = "Choose an absolute executable file."
      return
    }
    await settings.setCodexExecutablePath(normalized.isEmpty ? nil : normalized)
    validationMessage = nil
  }
}
