import AgentPreflightApplication
import Foundation

public protocol CodexExecutableLocating: Sendable {
  func locate() async throws -> URL
  func isExecutable(path: String) -> Bool
}

public struct CodexExecutableLocator: CodexExecutableLocating, ExecutablePathValidating {
  public static let standardCandidatePaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
  private let settings: any AppSettingsStore
  private let environmentPath: String
  private let isExecutableFile: @Sendable (String) -> Bool

  /// `FileManager` is not `Sendable`, so the file probe is injected as a `Sendable` closure.
  public init(
    settings: any AppSettingsStore,
    environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
    isExecutableFile: @escaping @Sendable (String) -> Bool = {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  ) {
    self.settings = settings
    self.environmentPath = environmentPath
    self.isExecutableFile = isExecutableFile
  }

  public func locate() async throws -> URL {
    if let manualPath = await settings.codexExecutablePath() {
      guard isExecutable(path: manualPath) else { throw ProviderFailure.executableMissing }
      return URL(fileURLWithPath: manualPath)
    }
    let searchPathCandidates = environmentPath.split(separator: ":").map { String($0) + "/codex" }
    let candidates = searchPathCandidates + Self.standardCandidatePaths
    guard let match = candidates.first(where: isExecutable) else {
      throw ProviderFailure.executableMissing
    }
    return URL(fileURLWithPath: match)
  }

  public func isExecutable(path: String) -> Bool {
    path.hasPrefix("/") && isExecutableFile(path)
  }
}
