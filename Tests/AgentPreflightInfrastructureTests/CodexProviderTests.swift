import Foundation
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

@Suite("Codex provider")
struct CodexProviderTests {
  @Test("parser classifies five-hour and weekly windows by duration")
  func parserClassifiesFiveHourAndWeeklyWindowsByDuration() throws {
    let snapshot = try CodexRateLimitsParser().parse(
      fixture("codex-primary-secondary"),
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.provider == .codex)
    #expect(snapshot.windows[.short]?.remaining.value == 75)
    #expect(snapshot.windows[.short]?.resetsAt == Date(timeIntervalSince1970: 1_788_525_000))
    #expect(snapshot.windows[.weekly]?.remaining.value == 90)
    #expect(snapshot.windows[.weekly]?.resetsAt == Date(timeIntervalSince1970: 1_789_129_800))
  }

  @Test("parser does not invent a missing short window")
  func parserDoesNotInventMissingShortWindow() throws {
    let snapshot = try CodexRateLimitsParser().parse(
      fixture("codex-primary-weekly-only"),
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows[.short] == nil)
    #expect(snapshot.windows[.weekly]?.remaining.value == 69)
  }

  @Test("parser selects Codex from the grouped limit shape")
  func parserSelectsCodexFromGroupedLimitShape() throws {
    let snapshot = try CodexRateLimitsParser().parse(
      fixture("codex-grouped"),
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows[.short]?.remaining.value == 80)
    #expect(snapshot.windows[.weekly]?.remaining.value == 92)
  }

  @Test("parser preserves quota when the reset is null")
  func parserPreservesQuotaWhenResetIsNull() throws {
    let payload = Data(
      #"{"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":null}}}}"#
        .utf8
    )

    let snapshot = try CodexRateLimitsParser().parse(
      payload,
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows[.short]?.remaining.value == 60)
    #expect(snapshot.windows[.short]?.resetsAt == nil)
  }

  @Test("parser skips an unclassifiable window without a duration")
  func parserSkipsUnclassifiableWindowWithoutDuration() throws {
    let payload = Data(
      #"""
      {"result":{"rateLimits":{
        "primary":{"usedPercent":10,"windowDurationMins":null,"resetsAt":1788525000},
        "secondary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1789129800}
      }}}
      """#.utf8
    )

    let snapshot = try CodexRateLimitsParser().parse(
      payload,
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[.short] == nil)
    #expect(snapshot.windows[.weekly]?.remaining.value == 95)
  }

  @Test("parser rejects a payload whose only window has no duration")
  func parserRejectsPayloadWhoseOnlyWindowHasNoDuration() {
    let payload = Data(
      #"{"result":{"rateLimits":{"primary":{"usedPercent":10,"resetsAt":1788525000}}}}"#.utf8
    )

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try CodexRateLimitsParser().parse(
        payload,
        fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
      )
    }
  }

  @Test("parser rejects non-positive durations and resets")
  func parserRejectsNonPositiveDurationsAndResets() {
    let nonPositiveDuration = Data(
      #"{"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":0,"resetsAt":1788525000}}}}"#
        .utf8
    )
    let nonPositiveReset = Data(
      #"{"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":0}}}}"#
        .utf8
    )

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try CodexRateLimitsParser().parse(nonPositiveDuration, fetchedAt: Date())
    }
    #expect(throws: ProviderFailure.unsupportedPayload) {
      try CodexRateLimitsParser().parse(nonPositiveReset, fetchedAt: Date())
    }
  }

  @Test("locator uses a valid manual override before PATH")
  func locatorUsesValidManualOverrideBeforePath() async throws {
    let executable = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    #expect(FileManager.default.createFile(atPath: executable.path, contents: Data()))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: executable.path
    )
    defer { try? FileManager.default.removeItem(at: executable) }

    let locator = CodexExecutableLocator(
      settings: SettingsStoreStub(path: executable.path),
      environmentPath: "/unavailable"
    )

    #expect(try await locator.locate() == executable)
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
  }
}

extension CodexProviderTests {
  @Test("app server performs the handshake and correlates the rate-limit response")
  func appServerPerformsHandshakeAndCorrelatesRateLimitResponse() async throws {
    let expectedResponse = try fixture("codex-primary-secondary")
    let session = JSONLineSessionStub(incoming: [
      Data(#"{"method":"remoteControl/status/changed","params":{}}"#.utf8),
      Data(#"{"id":0,"result":{"userAgent":"codex"}}"#.utf8),
      expectedResponse,
    ])
    let client = CodexAppServerClient(
      launcher: ProcessLauncherStub(session: session),
      timeoutSeconds: 5
    )

    let response = try await client.readRateLimits(
      executableURL: URL(fileURLWithPath: "/fixture/codex")
    )

    #expect(response == expectedResponse)
    let messages = try await session.sentMessages()
    #expect(messages.map(\.method) == ["initialize", "initialized", "account/rateLimits/read"])
    #expect(messages.map(\.id) == [0, nil, 1])
    #expect(await session.wasTerminated)
  }

  @Test("app server maps the end of output to a process failure")
  func appServerMapsEndOfOutputToProcessFailure() async throws {
    let session = JSONLineSessionStub(incoming: [], exitCode: 9)
    let client = CodexAppServerClient(
      launcher: ProcessLauncherStub(session: session),
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.processFailure(exitCode: 9)) {
      try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
    }
  }

  @Test("app server timeout terminates the blocked process")
  func appServerTimeoutTerminatesBlockedProcess() async throws {
    let session = JSONLineSessionStub(incoming: [], blocksOnReceive: true)
    let client = CodexAppServerClient(
      launcher: ProcessLauncherStub(session: session),
      timeoutSeconds: 0.01
    )

    await #expect(throws: ProviderFailure.timeout) {
      try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
    }
    #expect(await session.wasTerminated)
  }

  @Test("app server rejects malformed JSON and RPC errors")
  func appServerRejectsMalformedJSONAndRPCError() async throws {
    let malformedClient = CodexAppServerClient(
      launcher: ProcessLauncherStub(
        session: JSONLineSessionStub(incoming: [
          Data("not-json".utf8)
        ])),
      timeoutSeconds: 5
    )
    let errorClient = CodexAppServerClient(
      launcher: ProcessLauncherStub(
        session: JSONLineSessionStub(incoming: [
          Data(#"{"id":0,"error":{"code":-32000}}"#.utf8)
        ])),
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.protocolFailure) {
      try await malformedClient.readRateLimits(
        executableURL: URL(fileURLWithPath: "/fixture/codex")
      )
    }
    await #expect(throws: ProviderFailure.protocolFailure) {
      try await errorClient.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
    }
  }

  @Test("app server maps an authentication RPC error to unauthenticated")
  func appServerMapsAuthenticationRPCErrorToUnauthenticated() async throws {
    let session = JSONLineSessionStub(incoming: [
      Data(#"{"id":0,"result":{"userAgent":"codex"}}"#.utf8),
      try fixture("codex-unauthenticated"),
    ])
    let client = CodexAppServerClient(
      launcher: ProcessLauncherStub(session: session),
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.unauthenticated) {
      try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
    }
    #expect(await session.wasTerminated)
  }

  @Test("app server keeps an unrelated RPC error message a protocol failure")
  func appServerKeepsUnrelatedRPCErrorMessageProtocolFailure() async throws {
    let client = CodexAppServerClient(
      launcher: ProcessLauncherStub(
        session: JSONLineSessionStub(incoming: [
          Data(#"{"id":0,"error":{"code":-32600,"message":"rate limit backend unavailable"}}"#.utf8)
        ])),
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.protocolFailure) {
      try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
    }
  }

  @Test("parser rejects out-of-range usage")
  func parserRejectsOutOfRangeUsage() {
    let payload = Data(
      #"""
      {
        "id":1,
        "result":{"rateLimits":{"primary":{
          "usedPercent":101,
          "windowDurationMins":300,
          "resetsAt":1788525000
        }}}
      }
      """#.utf8)

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try CodexRateLimitsParser().parse(
        payload,
        fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
      )
    }
  }

  @Test("provider composes locator, client, and parser")
  func providerComposesLocatorClientAndParser() async throws {
    let provider = CodexQuotaProvider(
      locator: ExecutableLocatorStub(executableURL: URL(fileURLWithPath: "/fixture/codex")),
      client: CodexAppServerClient(
        launcher: ProcessLauncherStub(
          session: JSONLineSessionStub(incoming: [
            Data(#"{"id":0,"result":{}}"#.utf8),
            try fixture("codex-primary-secondary"),
          ])
        ),
        timeoutSeconds: 5
      ),
      parser: CodexRateLimitsParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200))
    )

    let snapshot = try await provider.fetchSnapshot()

    #expect(provider.identifier == .codex)
    #expect(snapshot.fetchedAt == Date(timeIntervalSince1970: 1_788_505_200))
    #expect(snapshot.windows[.short]?.remaining.value == 75)
    #expect(snapshot.windows[.weekly]?.remaining.value == 90)
  }
}

extension CodexProviderTests {
  @Test("real session round-trips lines while the child stays alive")
  func realSessionRoundTripsLinesWhileChildStaysAlive() async throws {
    let session = try await launchEchoingChild()

    try await session.send(Data(#"{"id":0}"#.utf8))
    let first = try await receiveLine(from: session)
    try await session.send(Data(#"{"id":1}"#.utf8))
    let second = try await receiveLine(from: session)
    await session.terminate()

    #expect(first == Data(#"{"id":0}"#.utf8))
    #expect(second == Data(#"{"id":1}"#.utf8))
  }

  @Test("real session splits two lines delivered in one chunk")
  func realSessionSplitsTwoLinesDeliveredInOneChunk() async throws {
    let session = try await launchEchoingChild()
    var batchedLines = Data(#"{"id":0}"#.utf8)
    batchedLines.append(0x0A)
    batchedLines.append(contentsOf: Data(#"{"id":1}"#.utf8))

    try await session.send(batchedLines)
    let first = try await receiveLine(from: session)
    let second = try await receiveLine(from: session)
    await session.terminate()

    #expect(first == Data(#"{"id":0}"#.utf8))
    #expect(second == Data(#"{"id":1}"#.utf8))
  }

  @Test("real session termination is idempotent and reports an exit status")
  func realSessionTerminationIsIdempotentAndReportsExitStatus() async throws {
    let session = try await launchEchoingChild()

    await session.terminate()
    await session.terminate()
    let status = await session.waitForExit()

    #expect(status >= 0)
    #expect(await session.isChildRunning() == false)
  }

  @Test("real session reports end of output when the child exits")
  func realSessionReportsEndOfOutputWhenChildExits() async throws {
    let session = try await launchChild(
      executablePath: "/bin/echo",
      arguments: [#"{"id":0}"#]
    )

    let first = try await receiveLine(from: session)
    let second = try await receiveLine(from: session)
    let status = await session.waitForExit()
    await session.terminate()

    #expect(first == Data(#"{"id":0}"#.utf8))
    #expect(second == nil)
    #expect(status == 0)
  }

  @Test(
    "termination escalates to SIGKILL when the child ignores SIGTERM",
    .enabled(
      if: FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"),
      "Requires /usr/bin/perl to run a child that ignores SIGTERM"
    )
  )
  func terminationEscalatesToSIGKILLWhenChildIgnoresSIGTERM() async throws {
    let session = try await launchChild(
      executablePath: "/usr/bin/perl",
      arguments: [
        "-e", #"$SIG{TERM} = "IGNORE"; $| = 1; print "ready\n"; sleep 1 while 1;"#,
      ]
    )
    // The child announces itself once the handler is installed, so SIGTERM cannot win a startup race.
    #expect(try await receiveLine(from: session) == Data("ready".utf8))

    let startedTerminatingAt = Date()
    await session.terminate()
    let terminationSeconds = Date().timeIntervalSince(startedTerminatingAt)
    let status = await session.waitForExit()

    #expect(terminationSeconds < 5)
    #expect(await session.isChildRunning() == false)
    #expect(status == SIGKILL)
  }

  @Test("client maps a silent real child to a timeout and leaves no process behind")
  func clientMapsSilentRealChildToTimeout() async throws {
    let launcher = FixedChildProcessLauncher(
      executableURL: URL(fileURLWithPath: "/bin/dd"),
      arguments: ["of=/dev/null"]
    )
    let client = CodexAppServerClient(launcher: launcher, timeoutSeconds: 0.2)

    await #expect(throws: ProviderFailure.timeout) {
      try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/bin/dd"))
    }

    let session = try #require(await launcher.launchedSession)
    #expect(await session.isChildRunning() == false)
  }

  private func launchEchoingChild() async throws -> FoundationJSONLineProcessSession {
    try await launchChild(executablePath: "/bin/cat")
  }

  private func launchChild(
    executablePath: String,
    arguments: [String] = []
  ) async throws -> FoundationJSONLineProcessSession {
    let session = try await FoundationJSONLineProcessLauncher().launch(
      executableURL: URL(fileURLWithPath: executablePath),
      arguments: arguments
    )
    return try #require(session as? FoundationJSONLineProcessSession)
  }

  /// Bounds a read from a real child: an unanswered read ends when the watchdog stops the child.
  private func receiveLine(
    from session: FoundationJSONLineProcessSession,
    within seconds: Double = 3
  ) async throws -> Data? {
    let watchdog = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      await session.terminate()
    }
    defer { watchdog.cancel() }
    return try await session.receive()
  }
}

/// Launches one fixed real child, ignoring the executable and arguments the caller asks for.
private actor FixedChildProcessLauncher: JSONLineProcessLaunching {
  private let executableURL: URL
  private let arguments: [String]
  private(set) var launchedSession: FoundationJSONLineProcessSession?

  init(executableURL: URL, arguments: [String]) {
    self.executableURL = executableURL
    self.arguments = arguments
  }

  func launch(executableURL: URL, arguments: [String]) async throws -> any JSONLineProcessSession {
    let session = try await FoundationJSONLineProcessLauncher().launch(
      executableURL: self.executableURL,
      arguments: self.arguments
    )
    launchedSession = session as? FoundationJSONLineProcessSession
    return session
  }
}

extension CodexProviderTests {
  @Test(
    "live Codex usage works when explicitly enabled",
    .enabled(
      if: ProcessInfo.processInfo.environment["AGENT_PREFLIGHT_LIVE_CODEX"] == "1",
      "Set AGENT_PREFLIGHT_LIVE_CODEX=1 for an explicit app-server smoke test"
    )
  )
  func testLiveCodexUsageWhenExplicitlyEnabled() async throws {
    let suiteName = "AgentPreflightLiveCodexTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settings = UserDefaultsAppSettingsStore(
      defaults: try #require(UserDefaults(suiteName: suiteName))
    )
    let provider = CodexQuotaProvider(
      locator: CodexExecutableLocator(settings: settings),
      client: CodexAppServerClient(
        launcher: FoundationJSONLineProcessLauncher(),
        timeoutSeconds: 5
      ),
      parser: CodexRateLimitsParser(),
      clock: SystemClock()
    )

    do {
      let snapshot = try await provider.fetchSnapshot()
      #expect(!snapshot.windows.isEmpty)
      #expect(snapshot.windows.values.allSatisfy { (0...100).contains($0.remaining.value) })
    } catch let failure as ProviderFailure {
      Issue.record("Live Codex usage failed: failure=\(safeProviderFailureCategory(failure))")
    } catch {
      Issue.record("Live Codex usage failed: failure=unclassified_error")
    }
  }
}

private actor SettingsStoreStub: CodexPathSettingsStore {
  let path: String?

  init(path: String?) { self.path = path }

  func codexExecutablePath() async -> String? { path }

  func setCodexExecutablePath(_ path: String?) async {}
}

private struct FixedClock: Clock {
  let current: Date

  init(now: Date) { self.current = now }

  func now() -> Date { current }
}

private struct ExecutableLocatorStub: CodexExecutableLocating {
  let executableURL: URL

  func locate() async throws -> URL { executableURL }

  func isExecutable(path: String) -> Bool { path == executableURL.path }
}

private struct SentRPCMessage: Decodable, Sendable {
  let method: String
  let id: Int?
}

private actor JSONLineSessionStub: JSONLineProcessSession {
  private var incoming: [Data]
  private var sent: [Data] = []
  private let exitCode: Int32
  private let blocksOnReceive: Bool
  private(set) var wasTerminated = false

  init(incoming: [Data], exitCode: Int32 = 0, blocksOnReceive: Bool = false) {
    self.incoming = incoming
    self.exitCode = exitCode
    self.blocksOnReceive = blocksOnReceive
  }

  func send(_ data: Data) async throws { sent.append(data) }

  func receive() async throws -> Data? {
    if blocksOnReceive {
      try await Task.sleep(for: .seconds(60))
      return nil
    }
    return incoming.isEmpty ? nil : incoming.removeFirst()
  }

  func terminate() async { wasTerminated = true }

  func waitForExit() async -> Int32 { exitCode }

  func sentMessages() throws -> [SentRPCMessage] {
    try sent.map { try JSONDecoder().decode(SentRPCMessage.self, from: $0) }
  }
}

private struct ProcessLauncherStub: JSONLineProcessLaunching {
  let session: JSONLineSessionStub

  func launch(executableURL: URL, arguments: [String]) async throws -> any JSONLineProcessSession {
    #expect(executableURL.path == "/fixture/codex")
    #expect(arguments == ["app-server", "--listen", "stdio://"])
    return session
  }
}
