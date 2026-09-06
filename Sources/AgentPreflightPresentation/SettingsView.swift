import SwiftUI

/// The only setting the MVP exposes: where the Codex executable lives when discovery cannot find it.
public struct SettingsView: View {
  @ObservedObject private var model: SettingsViewModel

  public init(model: SettingsViewModel) { self.model = model }

  public var body: some View {
    Form {
      Section("Codex executable") {
        TextField("/absolute/path/to/codex", text: $model.codexPath)
          .textFieldStyle(.roundedBorder)
        Text("Leave empty to search PATH, /opt/homebrew/bin, and /usr/local/bin.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let message = model.validationMessage {
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
        HStack {
          Button("Save") { Task { await model.save() } }
          Button("Use automatic discovery") {
            model.codexPath = ""
            Task { await model.save() }
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 460, height: 210)
    .task { await model.load() }
  }
}
