import AgentPreflightDomain
import SwiftUI

/// The popover: limits first, then the task size, then the recommendation derived from them.
public struct MenuBarContentView: View {
  private static let clockTickSeconds = 60

  @ObservedObject private var model: AppViewModel

  public init(model: AppViewModel) { self.model = model }

  public var body: some View {
    VStack(spacing: 12) {
      header
      ForEach(model.providerCards) { ProviderCardView(model: $0) }
      Picker("Task size", selection: $model.selectedTaskSize) {
        Text("S").tag(TaskSize.small)
        Text("M").tag(TaskSize.medium)
        Text("L").tag(TaskSize.large)
      }
      .pickerStyle(.segmented)
      .accessibilityLabel("Planned task size")
      RecommendationCardView(model: model.recommendation)
      footer
    }
    .padding(14)
    .frame(width: 360)
    .onAppear { Task { await model.panelOpened() } }
    .task { await tickClockUntilCancelled() }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Agent Preflight").font(.headline)
        Text(model.isRefreshing ? "Refreshing limits…" : "Subscription quota")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .disabled(model.isRefreshing)
      .accessibilityLabel("Refresh quota")
    }
  }

  private var footer: some View {
    HStack {
      Text(model.lastRefreshText).foregroundStyle(.secondary)
      Spacer()
      SettingsLink { Label("Settings", systemImage: "gearshape") }
    }
    .font(.caption)
  }

  /// Re-renders relative times without refetching. A cancelled sleep ends the loop, so closing the
  /// panel stops the timer instead of leaving a task behind.
  private func tickClockUntilCancelled() async {
    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(Self.clockTickSeconds))
      } catch {
        return
      }
      model.clockTicked()
    }
  }
}
