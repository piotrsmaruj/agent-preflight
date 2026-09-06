import SwiftUI

/// The recommendation is textual first; the symbol and tint only reinforce the words.
public struct RecommendationCardView: View {
  private let model: RecommendationModel

  public init(model: RecommendationModel) { self.model = model }

  public var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: symbol).foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(model.title).font(.subheadline.weight(.semibold))
        Text(model.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(11)
    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
  }

  private var symbol: String {
    switch model.tone {
    case .positive: "checkmark.circle.fill"
    case .neutral: "equal.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .unavailable: "questionmark.circle.fill"
    }
  }

  private var tint: Color {
    switch model.tone {
    case .positive: .green
    case .neutral: .blue
    case .warning: .orange
    case .unavailable: .secondary
    }
  }
}
