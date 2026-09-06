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

  /// Renders one window; `weeklyTitle` lets a card that also shows a model-scoped week say which
  /// weekly window this row is, without the formatter knowing the rest of the card.
  public func row(
    provider: ProviderIdentifier,
    window: QuotaWindow,
    now: Date,
    weeklyTitle: String = "Weekly"
  ) -> QuotaRowModel {
    let percent = Int(window.remaining.value.rounded())
    let isExpired = isExpired(window.resetsAt, now: now)
    let windowTitle = title(window, weeklyTitle: weeklyTitle)
    let remainingText = isExpired ? "Remaining unknown" : "\(percent)% remaining"
    let reset = resetText(window.resetsAt, now: now)
    let state = stateText(percent: percent, reset: window.resetsAt, now: now)
    return QuotaRowModel(
      kind: window.kind,
      title: windowTitle,
      remainingValue: isExpired ? nil : window.remaining.value,
      remainingText: remainingText,
      resetText: reset,
      stateText: state,
      accessibilityLabel:
        "\(providerTitle(provider)), \(windowTitle), \(remainingText), \(reset), \(state)"
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
