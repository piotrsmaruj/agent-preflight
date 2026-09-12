import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

/// Turns domain quota values into the exact strings the panel shows.
///
/// Formatting is deterministic and locale-independent so tests can assert rendered copy.
/// A window keeps its percentage while its reset is in the future or unknown; only a reset
/// that has already passed makes the remaining quota unknowable, because the provider has
/// not yet confirmed the new window.
public struct PresentationFormatter: Sendable {
  public init() {}

  public func providerTitle(_ provider: ProviderIdentifier) -> String {
    provider == .codex ? "Codex" : "Claude Code"
  }

  public func taskSizeTitle(_ size: TaskSize) -> String {
    switch size {
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Large"
    }
  }

  /// Renders one window; `weeklyTitle` lets a card that also shows a model-scoped week say which
  /// weekly window this row is, without the formatter knowing the rest of the card. `displayMode`
  /// chooses which half of the window the reader sees, and never changes the textual state, which
  /// always warns about the quota that is left.
  public func row(
    provider: ProviderIdentifier,
    window: QuotaWindow,
    now: Date,
    weeklyTitle: String = "Weekly",
    displayMode: QuotaDisplayMode = .remaining
  ) -> QuotaRowModel {
    let remainingPercent = Int(window.remaining.value.rounded())
    let isExpired = isExpired(window.resetsAt, now: now)
    let windowTitle = title(window, weeklyTitle: weeklyTitle)
    let percentageText = percentageText(
      remainingPercent: remainingPercent,
      displayMode: displayMode,
      isExpired: isExpired
    )
    let reset = resetText(window.resetsAt, now: now)
    let state = stateText(percent: remainingPercent, reset: window.resetsAt, now: now)
    return QuotaRowModel(
      kind: window.kind,
      title: windowTitle,
      percentageValue: isExpired ? nil : percentageValue(window.remaining.value, mode: displayMode),
      percentageText: percentageText,
      resetText: reset,
      stateText: state,
      accessibilityLabel:
        "\(providerTitle(provider)), \(windowTitle), \(percentageText), \(reset), \(state)"
    )
  }

  public func resetText(_ reset: Date?, now: Date) -> String {
    guard let reset else { return "Reset unavailable" }
    let seconds = reset.timeIntervalSince(now)
    guard seconds > 0 else { return "Refresh required" }
    if seconds < 3_600 { return "Resets in \(max(1, Int(ceil(seconds / 60))))m" }
    if seconds < 86_400 { return "Resets in \(Int(ceil(seconds / 3_600)))h" }
    return "Resets in \(Int(ceil(seconds / 86_400)))d"
  }

  public func ageText(_ fetchedAt: Date, now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(fetchedAt))
    if seconds < 60 { return "Updated just now" }
    if seconds < 3_600 { return "Updated \(Int(seconds / 60))m ago" }
    return "Updated \(Int(seconds / 3_600))h ago"
  }

  public func failureLabel(_ failure: ConstraintFailure) -> String {
    "\(providerTitle(failure.provider)) \(windowLabel(failure))"
  }

  /// The used percentage is derived from the already rounded remaining one, so the two display
  /// modes always add up to 100 instead of disagreeing on a window sitting on a half percent.
  private func percentageText(
    remainingPercent: Int,
    displayMode: QuotaDisplayMode,
    isExpired: Bool
  ) -> String {
    switch (displayMode, isExpired) {
    case (.remaining, true): "Remaining unknown"
    case (.used, true): "Usage unknown"
    case (.remaining, false): "\(remainingPercent)% remaining"
    case (.used, false): "\(100 - remainingPercent)% used"
    }
  }

  private func percentageValue(_ remaining: Double, mode: QuotaDisplayMode) -> Double {
    mode == .remaining ? remaining : 100 - remaining
  }

  private func title(_ window: QuotaWindow, weeklyTitle: String) -> String {
    switch window.kind {
    case .short: "Short window"
    case .weekly: weeklyTitle
    case .modelWeekly: "Weekly · \(window.scopeLabel ?? "model")"
    }
  }

  private func windowLabel(_ failure: ConstraintFailure) -> String {
    switch failure.window {
    case .short: "short"
    case .weekly: "weekly"
    case .modelWeekly: "weekly (\(failure.scopeLabel ?? "model"))"
    }
  }

  private func stateText(percent: Int, reset: Date?, now: Date) -> String {
    guard !isExpired(reset, now: now) else { return "Unknown" }
    switch percent {
    case 60...100: return "Plenty"
    case 30..<60: return "Available"
    case 1..<30: return "Low"
    default: return "Exhausted"
    }
  }

  private func isExpired(_ reset: Date?, now: Date) -> Bool {
    guard let reset else { return false }
    return reset <= now
  }
}
