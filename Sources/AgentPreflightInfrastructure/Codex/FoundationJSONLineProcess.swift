import AgentPreflightApplication
import Foundation

public protocol JSONLineProcessSession: Sendable {
  func send(_ data: Data) async throws
  func receive() async throws -> Data?
  func terminate() async
  func waitForExit() async -> Int32
}

public protocol JSONLineProcessLaunching: Sendable {
  func launch(executableURL: URL, arguments: [String]) async throws -> any JSONLineProcessSession
}

public struct FoundationJSONLineProcessLauncher: JSONLineProcessLaunching {
  public init() {}

  public func launch(
    executableURL: URL,
    arguments: [String]
  ) async throws -> any JSONLineProcessSession {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      return FoundationJSONLineProcessSession(
        process: process,
        input: input.fileHandleForWriting,
        output: output.fileHandleForReading
      )
    } catch {
      throw ProviderFailure.processFailure(exitCode: nil)
    }
  }
}

public actor FoundationJSONLineProcessSession: JSONLineProcessSession {
  private static let maximumLineBytes = 1_048_576
  private static let readChunkBytes = 4096
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private var receiveBuffer = Data()
  private var isTerminated = false

  init(process: Process, input: FileHandle, output: FileHandle) {
    self.process = process
    self.input = input
    self.output = output
  }

  public func send(_ data: Data) async throws {
    var line = data
    line.append(0x0A)
    try input.write(contentsOf: line)
  }

  public func receive() async throws -> Data? {
    while true {
      if let newline = receiveBuffer.firstIndex(of: 0x0A) {
        let line = receiveBuffer[..<newline]
        receiveBuffer.removeSubrange(...newline)
        return Data(line)
      }
      guard let chunk = try await Self.readChunk(from: output), !chunk.isEmpty else {
        return receiveBuffer.isEmpty ? nil : consumeBuffer()
      }
      receiveBuffer.append(chunk)
      guard receiveBuffer.count <= Self.maximumLineBytes else {
        throw ProviderFailure.protocolFailure
      }
    }
  }

  /// Idempotent: a cancelled read and its unwinding caller both ask for termination, and closing
  /// an already closed handle traps.
  public func terminate() async {
    guard !isTerminated else { return }
    isTerminated = true
    input.closeFile()
    if process.isRunning { process.terminate() }
    output.closeFile()
  }

  public func waitForExit() async -> Int32 {
    let runningProcess = process
    return await Task.detached(priority: .utility) {
      if runningProcess.isRunning { runningProcess.waitUntilExit() }
      return runningProcess.terminationStatus
    }.value
  }

  private func consumeBuffer() -> Data {
    defer { receiveBuffer.removeAll(keepingCapacity: false) }
    return receiveBuffer
  }

  /// `FileHandle.read(upToCount:)` waits for the full count or end of file, which stalls a
  /// line-delimited stream, so the available bytes are read straight from the descriptor.
  private nonisolated static func readChunk(from handle: FileHandle) async throws -> Data? {
    let descriptor = handle.fileDescriptor
    return try await Task.detached(priority: .utility) {
      try readAvailableBytes(descriptor: descriptor)
    }.value
  }

  private nonisolated static func readAvailableBytes(descriptor: Int32) throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: readChunkBytes)
    while true {
      let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
        read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
      }
      if bytesRead > 0 { return Data(buffer[..<bytesRead]) }
      if bytesRead == 0 { return nil }
      guard errno == EINTR else { throw ProviderFailure.protocolFailure }
    }
  }
}
