import AgentPreflightApplication
import AppKit
import SwiftUI

extension AppearancePreference {
  /// `nil` hands the decision back to macOS, which is what `system` means.
  public var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  fileprivate var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}

/// Repaints the running application in the chosen appearance.
///
/// The menu bar panel is an AppKit panel that SwiftUI does not own end to end, so
/// `preferredColorScheme` alone leaves its chrome following macOS. Setting the application
/// appearance covers the panel, the Settings window, and every alert alike.
@MainActor
public protocol AppearanceApplying {
  func apply(_ preference: AppearancePreference)
}

public struct NSApplicationAppearanceApplier: AppearanceApplying {
  public init() {}

  public func apply(_ preference: AppearancePreference) {
    NSApplication.shared.appearance = preference.nsAppearance
  }
}
