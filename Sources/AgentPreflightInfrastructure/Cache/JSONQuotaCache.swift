import AgentPreflightApplication
import AgentPreflightDomain
import Foundation

public actor JSONQuotaCache: QuotaCache {
  public static let fileName = "quota-cache-v1.json"
  private static let envelopeVersion = 1
  private static let directoryPermissions = 0o700
  private static let filePermissions = 0o600

  private let directory: URL
  private let fileManager: FileManager
  private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

  public init(directory: URL, fileManager: FileManager = .default) {
    self.directory = directory
    self.fileManager = fileManager
  }

  public static func live(fileManager: sending FileManager = .default) throws -> JSONQuotaCache {
    let base = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return JSONQuotaCache(
      directory: base.appendingPathComponent("Agent Preflight", isDirectory: true),
      fileManager: fileManager
    )
  }

  public func load() async throws -> [ProviderIdentifier: QuotaSnapshot] {
    try ensureDirectory()
    guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
    try restrictFilePermissions()
    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
    guard envelope.version == Self.envelopeVersion else { throw CacheError.unsupportedVersion }
    return try index(envelope.snapshots)
  }

  public func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws {
    try ensureDirectory()
    let envelope = Envelope(
      version: Self.envelopeVersion,
      snapshots: snapshots.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
    )
    let data = try JSONEncoder().encode(envelope)
    try data.write(to: fileURL, options: .atomic)
    try restrictFilePermissions()
  }

  private func index(
    _ snapshots: [QuotaSnapshot]
  ) throws -> [ProviderIdentifier: QuotaSnapshot] {
    var indexed: [ProviderIdentifier: QuotaSnapshot] = [:]
    for snapshot in snapshots {
      guard indexed.updateValue(snapshot, forKey: snapshot.provider) == nil else {
        throw CacheError.duplicateProvider
      }
    }
    return indexed
  }

  private func ensureDirectory() throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try fileManager.setAttributes(
      [.posixPermissions: Self.directoryPermissions],
      ofItemAtPath: directory.path
    )
  }

  private func restrictFilePermissions() throws {
    try fileManager.setAttributes(
      [.posixPermissions: Self.filePermissions],
      ofItemAtPath: fileURL.path
    )
  }

  private struct Envelope: Codable {
    let version: Int
    let snapshots: [QuotaSnapshot]
  }

  private enum CacheError: Error {
    case unsupportedVersion
    case duplicateProvider
  }
}
