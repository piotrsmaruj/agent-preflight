import AgentPreflightDomain

/// Where the Codex executable lives when automatic discovery cannot find it.
public protocol CodexPathSettingsStore: Sendable {
  func codexExecutablePath() async -> String?
  func setCodexExecutablePath(_ path: String?) async
}

/// The appearance the app paints itself in.
public protocol AppearanceSettingsStore: Sendable {
  func appearancePreference() async -> AppearancePreference
  func setAppearancePreference(_ preference: AppearancePreference) async
}

/// Whether quota windows read as remaining or as used.
public protocol QuotaDisplaySettingsStore: Sendable {
  func quotaDisplayMode() async -> QuotaDisplayMode
  func setQuotaDisplayMode(_ mode: QuotaDisplayMode) async
}

/// The reserves each task size requires, with the built-in policy as the fallback.
public protocol TaskSizePolicySettingsStore: Sendable {
  func taskSizePolicy() async -> TaskSizePolicy
  func setTaskSizePolicy(_ policy: TaskSizePolicy) async
}

/// Everything the Settings window edits. Collaborators that need one setting depend on the
/// narrower protocol above instead, so a new setting never widens their surface.
public protocol AppSettingsStore: CodexPathSettingsStore, AppearanceSettingsStore,
  QuotaDisplaySettingsStore, TaskSizePolicySettingsStore
{}

public protocol ExecutablePathValidating: Sendable {
  func isExecutable(path: String) -> Bool
}
