public protocol AppSettingsStore: Sendable {
  func codexExecutablePath() async -> String?
  func setCodexExecutablePath(_ path: String?) async
}

public protocol ExecutablePathValidating: Sendable {
  func isExecutable(path: String) -> Bool
}
