import SwiftUI

/// One provider panel rendered from an immutable model; it reads no infrastructure of its own.
public struct ProviderCardView: View {
  private let model: ProviderCardModel

  public init(model: ProviderCardModel) { self.model = model }

  public var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(model.title).font(.subheadline.weight(.semibold))
        Spacer()
        Text(model.freshnessText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if model.rows.isEmpty {
        Label("Quota windows unavailable", systemImage: "questionmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.rows) { QuotaRowView(model: $0) }
      }
      if let recovery = model.recoveryText {
        Label(recovery, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(11)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
  }
}

/// A single quota window. The whole row is one accessibility element so VoiceOver reads the
/// provider, window, remaining percent, reset, and text state as one sentence.
private struct QuotaRowView: View {
  let model: QuotaRowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(model.title).font(.caption)
        Spacer()
        Text(model.remainingText).font(.caption.weight(.medium))
      }
      if let remainingValue = model.remainingValue {
        ProgressView(value: remainingValue, total: 100)
          .tint(tint)
      }
      HStack {
        Text(model.resetText)
        Spacer()
        Text(model.stateText)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(model.accessibilityLabel)
  }

  private var tint: Color {
    switch model.stateText {
    case "Plenty": .green
    case "Available": .blue
    case "Low": .orange
    default: .red
    }
  }
}
