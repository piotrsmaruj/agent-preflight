/// Which appearance the app paints itself in, independent of the provider data it shows.
public enum AppearancePreference: String, CaseIterable, Codable, Sendable {
  /// Follow whatever macOS is currently set to.
  case system
  case light
  case dark
}

/// Which half of a quota window the panel puts in front of the reader.
///
/// Both halves describe the same window: `used` is the complement of `remaining`, so switching
/// changes only the wording and the direction the progress bar fills.
public enum QuotaDisplayMode: String, CaseIterable, Codable, Sendable {
  case remaining
  case used
}
