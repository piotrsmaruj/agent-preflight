import AgentPreflightPresentation
import SwiftUI

/// Menu-bar only: `LSUIElement` in `Resources/Info.plist` keeps the app out of the Dock, and the
/// scenes below are the app's whole surface.
@main
struct AgentPreflightApplication: App {
  @StateObject private var appViewModel: AppViewModel
  @StateObject private var settingsViewModel: SettingsViewModel

  init() {
    let dependencies = AppDependencies.live()
    _appViewModel = StateObject(wrappedValue: dependencies.appViewModel)
    _settingsViewModel = StateObject(wrappedValue: dependencies.settingsViewModel)
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: appViewModel)
    } label: {
      Label("Agent Preflight", systemImage: "gauge.with.dots.needle.50percent")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: settingsViewModel)
    }
  }
}
