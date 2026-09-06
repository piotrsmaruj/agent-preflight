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
    } catch {
      throw ProviderFailure.processFailure(exitCode: nil)
    }
    let inputHandle = input.fileHandleForWriting
    // Writing to a child that already exited must fail the send, never raise SIGPIPE on this app.
    _ = fcntl(inputHandle.fileDescriptor, F_SETNOSIGPIPE, 1)
    return FoundationJSONLineProcessSession(
      process: process,
      input: inputHandle,
      output: output.fileHandleForReading
    )
  }
}

public actor FoundationJSONLineProcessSession: JSONLineProcessSession {
  private static let maximumLineBytes = 1_048_576
  private static let readChunkBytes = 4096
  private static let signalGraceSeconds = 1.0
  private static let exitPollInterval = Duration.milliseconds(10)
  private static let unknownExitCode: Int32 = -1
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private var receiveBuffer = Data()
  private var terminationTask: Task<Void, Never>?

  init(process: Process, input: FileHandle, output: FileHandle) {
    self.process = process
    self.input = input
    self.output = output
  }

  public func send(_ data: Data) async throws {
    var line = data
    line.append(0x0A)
    do {
      try input.write(contentsOf: line)
    } catch {
      throw ProviderFailure.processFailure(exitCode: nil)
    }
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

  /// Every caller awaits the same bounded shutdown, so termination happens once and is finished
  /// before any of them continues.
  public func terminate() async {
    await (terminationTask ?? startTermination()).value
  }

  /// Bounded: the child gets a grace period after SIGTERM and is killed if it outlives it, so a
  /// wedged child cannot stall the caller.
  private func performTermination() async {
    input.closeFile()
    if process.isRunning {
      process.terminate()
      if await !childExited(within: Self.signalGraceSeconds) {
        kill(process.processIdentifier, SIGKILL)
        _ = await childExited(within: Self.signalGraceSeconds)
      }
    }
    // Closing output only after the child is gone means the reader has already seen end of output.
    output.closeFile()
  }

  private func startTermination() -> Task<Void, Never> {
    let task = Task { await performTermination() }
    terminationTask = task
    return task
  }

  public func waitForExit() async -> Int32 {
    if process.isRunning, await !childExited(within: Self.signalGraceSeconds) {
      await terminate()
    }
    return process.isRunning ? Self.unknownExitCode : process.terminationStatus
  }

  func isChildRunning() -> Bool { process.isRunning }

  /// Polls instead of blocking so the actor stays free; a cancelled sleep ends the wait at once.
  private func childExited(within seconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while process.isRunning {
      guard Date() < deadline else { return false }
      do {
        try await Task.sleep(for: Self.exitPollInterval)
      } catch {
        return !process.isRunning
      }
    }
    return true
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
