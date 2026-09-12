import AgentPreflightApplication
import AgentPreflightDomain
import SwiftUI

/// Everything the app lets the reader configure: how it looks, how it reads quota, what a task
/// size costs, and where the Codex executable lives.
public struct SettingsView: View {
  @ObservedObject private var model: SettingsViewModel

  public init(model: SettingsViewModel) { self.model = model }

  public var body: some View {
    Form {
      appearanceSection
      quotaDisplaySection
      taskSizeSection
      codexExecutableSection
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 480, height: 620)
    .task { await model.load() }
  }

  private var appearanceSection: some View {
    Section("Appearance") {
      Picker("Theme", selection: $model.appearance) {
        ForEach(AppearancePreference.allCases, id: \.self) { preference in
          Text(Self.appearanceTitle(preference)).tag(preference)
        }
      }
      .pickerStyle(.segmented)
      Text("System follows the macOS setting.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var quotaDisplaySection: some View {
    Section("Quota display") {
      Picker("Show", selection: $model.quotaDisplayMode) {
        ForEach(QuotaDisplayMode.allCases, id: \.self) { mode in
          Text(Self.displayModeTitle(mode)).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      Text("Remaining counts down to empty; used counts up from zero.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var taskSizeSection: some View {
    Section("Task sizes") {
      HStack {
        Text("Size").frame(maxWidth: .infinity, alignment: .leading)
        Text("Short window").frame(width: 150, alignment: .leading)
        Text("Weekly").frame(width: 150, alignment: .leading)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      ForEach($model.taskSizeDrafts) { $draft in
        HStack {
          Text(draft.title).frame(maxWidth: .infinity, alignment: .leading)
          ReserveField(
            value: $draft.shortReserve,
            accessibilityLabel: "\(draft.title) short window reserve"
          )
          ReserveField(
            value: $draft.weeklyReserve,
            accessibilityLabel: "\(draft.title) weekly reserve"
          )
        }
      }
      HStack {
        Text("Neutral tolerance").frame(maxWidth: .infinity, alignment: .leading)
        TextField("", value: $model.neutralTolerance, format: .number.precision(.fractionLength(2)))
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 70)
          .accessibilityLabel("Neutral tolerance")
        Stepper("", value: $model.neutralTolerance, in: 0...1, step: 0.05).labelsHidden()
      }
      Text(
        """
        A reserve is the percentage a task of that size must leave untouched. \
        Providers whose margins differ by less than the tolerance are reported as a tie.
        """
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if let message = model.taskSizeMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("Save") { Task { await model.saveTaskSizePolicy() } }
        Button("Restore defaults") { Task { await model.restoreDefaultTaskSizePolicy() } }
      }
    }
  }

  private var codexExecutableSection: some View {
    Section("Codex executable") {
      TextField("/absolute/path/to/codex", text: $model.codexPath)
        .textFieldStyle(.roundedBorder)
      Text("Leave empty to search PATH, /opt/homebrew/bin, and /usr/local/bin.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let message = model.codexPathMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
      HStack {
        Button("Save") { Task { await model.saveCodexPath() } }
        Button("Use automatic discovery") { Task { await model.useAutomaticCodexDiscovery() } }
      }
    }
  }

  private static func appearanceTitle(_ preference: AppearancePreference) -> String {
    switch preference {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  private static func displayModeTitle(_ mode: QuotaDisplayMode) -> String {
    switch mode {
    case .remaining: "Remaining"
    case .used: "Used"
    }
  }
}

/// One reserve percentage, typed or stepped, bounded to the range the domain accepts.
private struct ReserveField: View {
  @Binding var value: Double
  let accessibilityLabel: String

  var body: some View {
    HStack(spacing: 4) {
      TextField("", value: $value, format: .number.precision(.fractionLength(0)))
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 60)
        .accessibilityLabel(accessibilityLabel)
      Text("%").foregroundStyle(.secondary)
      Stepper(
        "",
        value: $value,
        in: ReserveRequirement.allowedPercentages,
        step: 5
      )
      .labelsHidden()
    }
    .frame(width: 150, alignment: .leading)
  }
}
