import AgentPreflightApplication
import AgentPreflightDomain
import AgentPreflightInfrastructure
import AgentPreflightPresentation
import Foundation

/// The single production composition root: every live adapter is built here and nowhere else, so
/// the views and view models only ever see protocols and already-formatted values.
@MainActor
struct AppDependencies {
  let appViewModel: AppViewModel
  let settingsViewModel: SettingsViewModel

  static func live() -> Self {
    let clock = SystemClock()
    let settings = UserDefaultsAppSettingsStore()
    let locator = CodexExecutableLocator(settings: settings)
    let configuration = RefreshConfiguration.live
    let codex = CodexQuotaProvider(
      locator: locator,
      client: CodexAppServerClient(
        launcher: FoundationJSONLineProcessLauncher(),
        timeoutSeconds: configuration.providerTimeout
      ),
      parser: CodexRateLimitsParser(),
      clock: clock
    )
    let claudeConfiguration = ClaudeProviderConfiguration.live
    let claude = ClaudeQuotaProvider(
      credentialReader: KeychainClaudeCredentialReader(
        service: claudeConfiguration.keychainService),
      httpClient: URLSessionHTTPClient(),
      parser: ClaudeUsageParser(),
      clock: clock,
      configuration: claudeConfiguration,
      timeoutSeconds: configuration.providerTimeout
    )
    let useCase = RefreshQuotaUseCase(
      providers: [codex, claude],
      cache: makeCache(),
      clock: clock,
      diagnostics: OSDiagnosticsSink(),
      configuration: configuration
    )
    let appViewModel = AppViewModel(refreshUseCase: useCase, clock: clock)
    return Self(
      appViewModel: appViewModel,
      settingsViewModel: SettingsViewModel(
        settings: settings,
        validator: locator,
        onQuotaDisplayModeChange: { [weak appViewModel] in appViewModel?.quotaDisplayMode = $0 },
        onTaskSizePolicyChange: { [weak appViewModel] in appViewModel?.taskSizePolicy = $0 }
      )
    )
  }

  /// A cache that cannot be created must not take the app down; the fallback carries no secret and
  /// deliberately throws so `RefreshQuotaUseCase` emits typed `.cacheReadFailed` and
  /// `.cacheWriteFailed` events instead of logging the raw filesystem error.
  private static func makeCache() -> any QuotaCache {
    do {
      return try JSONQuotaCache.live()
    } catch {
      return UnavailableQuotaCache()
    }
  }
}

private actor UnavailableQuotaCache: QuotaCache {
  private enum Failure: Error { case unavailable }

  func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { throw Failure.unavailable }

  func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws {
    throw Failure.unavailable
  }
}
