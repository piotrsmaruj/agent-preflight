import AgentPreflightPresentation
import SwiftUI

/// Menu-bar only: `LSUIElement` in `Resources/Info.plist` keeps the app out of the Dock, and the
/// scenes below are the app's whole surface.
@main
struct AgentPreflightApplication: App {
  @StateObject private var appViewModel: AppViewModel
  @StateObject private var settingsViewModel: SettingsViewModel

  /// Settings are read once at launch rather than when a view first appears, because the menu bar
  /// panel must already be painted in the chosen theme the first time it opens.
  init() {
    let dependencies = AppDependencies.live()
    _appViewModel = StateObject(wrappedValue: dependencies.appViewModel)
    _settingsViewModel = StateObject(wrappedValue: dependencies.settingsViewModel)
    let settingsViewModel = dependencies.settingsViewModel
    Task { @MainActor in await settingsViewModel.load() }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: appViewModel)
        .preferredColorScheme(settingsViewModel.appearance.colorScheme)
    } label: {
      Label("Agent Preflight", systemImage: "gauge.with.dots.needle.50percent")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: settingsViewModel)
        .preferredColorScheme(settingsViewModel.appearance.colorScheme)
    }
  }
}
