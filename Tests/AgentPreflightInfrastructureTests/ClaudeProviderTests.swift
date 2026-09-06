import Foundation
import Security
import Testing

@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

@Suite("Claude provider")
struct ClaudeProviderTests {
  @Test("parser maps used utilization to remaining quota")
  func parserMapsUsedUtilizationToRemainingQuota() throws {
    let data = try fixture("claude-success")
    let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
    let snapshot = try ClaudeUsageParser().parse(data, fetchedAt: fetchedAt)

    #expect(snapshot.provider == .claudeCode)
    #expect(snapshot.windows[.short]?.remaining.value == 78.5)
    #expect(snapshot.windows[.weekly]?.remaining.value == 58)
  }

  @Test("parser keeps a valid partial snapshot")
  func parserKeepsAValidPartialSnapshot() throws {
    let snapshot = try ClaudeUsageParser().parse(
      fixture("claude-partial"),
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )
    #expect(snapshot.windows[.short] == nil)
    #expect(snapshot.windows[.weekly] != nil)
  }

  @Test("provider maps a successful HTTP response")
  func providerMapsSuccessfulHTTPResponse() async throws {
    let transport = HTTPClientSpy(statusCode: 200, data: try fixture("claude-success"))
    let provider = ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: transport,
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 5
    )
    let snapshot = try await provider.fetchSnapshot()
    #expect(snapshot.windows[.short]?.remaining.value == 78.5)
    #expect(snapshot.windows[.weekly]?.remaining.value == 58)
  }

  @Test("provider rejects a successful response served from a foreign final URL")
  func providerRejectsSuccessfulResponseFromForeignFinalURL() async throws {
    let transport = HTTPClientSpy(
      statusCode: 200,
      data: try fixture("claude-success"),
      finalURL: try #require(URL(string: "https://evil.example.com/api/oauth/usage"))
    )
    let provider = ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: transport,
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.protocolFailure) {
      try await provider.fetchSnapshot()
    }
  }

  @Test("credential decoder rejects a missing OAuth token")
  func credentialDecoderRejectsMissingOAuthToken() {
    #expect(throws: ProviderFailure.invalidCredential) {
      try ClaudeCredentialDecoder().decode(Data(#"{"mcpOAuth":{}}"#.utf8))
    }
  }

  @Test("provider builds the expected request and maps unauthorized")
  func providerBuildsExpectedRequestAndMapsUnauthorized() async throws {
    let transport = HTTPClientSpy(statusCode: 401, data: Data())
    let provider = ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: transport,
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 5
    )

    await #expect(throws: ProviderFailure.unauthorized) {
      try await provider.fetchSnapshot()
    }

    let request = try #require(await transport.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(
      request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token-never-log"
    )
  }

  private func fixture(_ name: String) throws -> Data {
    try loadFixture(name)
  }
}

extension ClaudeProviderTests {
  @Test("redirect policy rejects a different host and plain HTTP")
  func redirectPolicyRejectsDifferentHostAndPlainHTTP() throws {
    let origin = try #require(URL(string: "https://api.anthropic.com/api/oauth/usage"))
    let policy = SameHostRedirectPolicy(origin: origin)
    #expect(policy.allows(try #require(URL(string: "https://api.anthropic.com/next"))))
    #expect(!policy.allows(try #require(URL(string: "https://example.com/next"))))
    #expect(!policy.allows(try #require(URL(string: "http://api.anthropic.com/next"))))
    #expect(!policy.allows(try #require(URL(string: "https://api.anthropic.com:444/next"))))
  }

  @Test("Keychain reader maps missing and denied items without inspecting payloads")
  func keychainReaderMapsMissingAndDeniedItemsWithoutInspectingPayloads() async throws {
    let service = ClaudeProviderConfiguration.live.keychainService
    let missing = KeychainClaudeCredentialReader(
      service: service,
      loader: KeychainLoaderStub(result: .status(errSecItemNotFound))
    )
    let denied = KeychainClaudeCredentialReader(
      service: service,
      loader: KeychainLoaderStub(result: .status(errSecUserCanceled))
    )

    await #expect(throws: ProviderFailure.unauthenticated) {
      try await missing.readAccessToken()
    }
    await #expect(throws: ProviderFailure.keychainDenied) {
      try await denied.readAccessToken()
    }
  }

  @Test("Keychain reader decodes the expected Claude OAuth envelope")
  func keychainReaderDecodesExpectedClaudeOAuthEnvelope() async throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-secret"}}"#.utf8)
    let reader = KeychainClaudeCredentialReader(
      service: ClaudeProviderConfiguration.live.keychainService,
      loader: KeychainLoaderStub(result: .data(data))
    )

    #expect(String(describing: try await reader.readAccessToken()) == "<redacted>")
  }
}

extension ClaudeProviderTests {
  @Test("parser rejects an invalid percentage")
  func parserRejectsInvalidPercentage() {
    let invalidPercent = Data(
      #"{"five_hour":{"utilization":101,"resets_at":"2026-09-04T12:30:00Z"}}"#.utf8
    )

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try ClaudeUsageParser().parse(invalidPercent, fetchedAt: Date())
    }
  }

  @Test("parser preserves idle quota when the short reset is null")
  func parserPreservesIdleQuotaWhenShortResetIsNull() throws {
    let payload = Data(
      #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":0,"resets_at":"2026-09-10T08:00:00Z"}}"#
        .utf8
    )

    let snapshot = try ClaudeUsageParser().parse(
      payload,
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows[.short]?.remaining.value == 100)
    #expect(snapshot.windows[.short]?.resetsAt == nil)
    #expect(snapshot.windows[.weekly]?.remaining.value == 100)
    #expect(snapshot.windows[.weekly]?.resetsAt == Date(timeIntervalSince1970: 1_789_027_200))
  }

  @Test("parser preserves quota when both reset dates are missing")
  func parserPreservesQuotaWhenBothResetDatesAreMissing() throws {
    let payload = Data(
      #"{"five_hour":{"utilization":25},"seven_day":{"utilization":50}}"#.utf8
    )

    let snapshot = try ClaudeUsageParser().parse(
      payload,
      fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
    )

    #expect(snapshot.windows[.short]?.remaining.value == 75)
    #expect(snapshot.windows[.short]?.resetsAt == nil)
    #expect(snapshot.windows[.weekly]?.remaining.value == 50)
    #expect(snapshot.windows[.weekly]?.resetsAt == nil)
  }

  @Test("parser rejects a malformed non-null reset timestamp")
  func parserRejectsMalformedNonNullResetTimestamp() {
    let invalidTimestamp = Data(
      #"{"five_hour":{"utilization":20,"resets_at":"not-a-date"}}"#.utf8
    )

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try ClaudeUsageParser().parse(invalidTimestamp, fetchedAt: Date())
    }
  }

  @Test("provider maps a rate limit without logging the body")
  func providerMapsRateLimitWithoutLoggingBody() async throws {
    let transport = HTTPClientSpy(statusCode: 429, data: Data("fixture-secret-body".utf8))
    let provider = ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: transport,
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 5
    )

    do {
      _ = try await provider.fetchSnapshot()
      Issue.record("Expected rate limit")
    } catch let error as ProviderFailure {
      #expect(error == .rateLimited(retryAfter: nil))
      #expect(!String(describing: error).contains("fixture-secret-body"))
    }
  }

  @Test("provider reports a refused redirect as a protocol failure, not a network problem")
  func providerReportsRefusedRedirectAsProtocolFailure() async throws {
    for transportError in [
      HTTPClientError.redirectRejected, .nonHTTPSRequest, .invalidResponse,
    ] {
      await #expect(throws: ProviderFailure.protocolFailure) {
        try await makeProvider(httpClient: ThrowingHTTPClient(error: transportError))
          .fetchSnapshot()
      }
    }
  }

  @Test("provider reports a transport failure as an unreachable network")
  func providerReportsTransportFailureAsNetworkUnavailable() async throws {
    await #expect(throws: ProviderFailure.networkUnavailable) {
      try await makeProvider(httpClient: ThrowingHTTPClient(error: .transportFailure))
        .fetchSnapshot()
    }
  }

  private func makeProvider(httpClient: any HTTPClient) -> ClaudeQuotaProvider {
    ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: httpClient,
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 5
    )
  }

  @Test("provider cancels a blocked transport at timeout")
  func providerCancelsBlockedTransportAtTimeout() async throws {
    let provider = ClaudeQuotaProvider(
      credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
      httpClient: BlockingHTTPClient(),
      parser: ClaudeUsageParser(),
      clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
      configuration: .live,
      timeoutSeconds: 0.01
    )

    await #expect(throws: ProviderFailure.timeout) {
      try await provider.fetchSnapshot()
    }
  }
}

extension ClaudeProviderTests {
  @Test("live diagnostics distinguish missing, null, and object windows")
  func liveDiagnosticsDistinguishMissingNullAndObjectWindows() {
    let missing = ClaudeLiveHTTPDiagnostic.classify(statusCode: 200, data: Data(#"{}"#.utf8))
    let nullAndObject = ClaudeLiveHTTPDiagnostic.classify(
      statusCode: 200,
      data: Data(#"{"five_hour":null,"seven_day":{}}"#.utf8)
    )

    #expect(missing.fiveHour == .missing)
    #expect(missing.sevenDay == .missing)
    #expect(nullAndObject.fiveHour == .null)
    #expect(nullAndObject.sevenDay == .object(utilization: .absent, resetsAt: .absent))
  }

  @Test("live diagnostics classify utilization without retaining values")
  func liveDiagnosticsClassifyUtilizationWithoutRetainingValues() {
    let null = diagnosticForFiveHour(#"{"utilization":null}"#)
    let zero = diagnosticForFiveHour(#"{"utilization":0}"#)
    let positive = diagnosticForFiveHour(#"{"utilization":21.5}"#)
    let outOfRange = diagnosticForFiveHour(#"{"utilization":101}"#)
    let nonNumeric = diagnosticForFiveHour(#"{"utilization":"fixture-sensitive-value"}"#)

    #expect(null.fiveHour == .object(utilization: .null, resetsAt: .absent))
    #expect(zero.fiveHour == .object(utilization: .zero, resetsAt: .absent))
    #expect(positive.fiveHour == .object(utilization: .positive, resetsAt: .absent))
    #expect(outOfRange.fiveHour == .object(utilization: .outOfRange, resetsAt: .absent))
    #expect(nonNumeric.fiveHour == .object(utilization: .nonNumeric, resetsAt: .absent))
  }

  @Test("live diagnostics classify reset timestamps without retaining values")
  func liveDiagnosticsClassifyResetTimestampsWithoutRetainingValues() {
    let null = diagnosticForFiveHour(#"{"resets_at":null}"#)
    let fractional = diagnosticForFiveHour(
      #"{"resets_at":"2026-09-04T12:30:00.000Z"}"#
    )
    let wholeSeconds = diagnosticForFiveHour(
      #"{"resets_at":"2026-09-04T12:30:00Z"}"#
    )
    let unparseable = diagnosticForFiveHour(
      #"{"resets_at":"fixture-sensitive-timestamp"}"#
    )
    let wrongType = diagnosticForFiveHour(#"{"resets_at":123}"#)

    #expect(null.fiveHour == .object(utilization: .absent, resetsAt: .null))
    #expect(fractional.fiveHour == .object(utilization: .absent, resetsAt: .parseable))
    #expect(wholeSeconds.fiveHour == .object(utilization: .absent, resetsAt: .parseable))
    #expect(unparseable.fiveHour == .object(utilization: .absent, resetsAt: .unparseable))
    #expect(wrongType.fiveHour == .object(utilization: .absent, resetsAt: .wrongType))
  }

  @Test("diagnostic HTTP client records only allowlisted categories")
  func diagnosticHTTPClientRecordsOnlyAllowlistedCategories() async throws {
    let response = HTTPResponse(
      data: Data(
        #"{"five_hour":{"utilization":"fixture-secret-utilization","resets_at":"fixture-secret-reset","fixture-secret-key":"fixture-secret-body"},"seven_day":"fixture-secret-window"}"#
          .utf8
      ),
      statusCode: 418,
      headers: ["fixture-secret-header": "fixture-secret-header-value"],
      finalURL: try #require(
        URL(string: "https://api.anthropic.com/fixture-secret-account-path")
      )
    )
    let recorder = ClaudeLiveHTTPDiagnosticRecorder()
    let client = ClaudeLiveDiagnosticHTTPClient(
      base: FixedHTTPClient(response: response),
      recorder: recorder
    )
    var request = URLRequest(url: ClaudeProviderConfiguration.live.usageURL)
    request.setValue("Bearer fixture-secret-token", forHTTPHeaderField: "Authorization")

    _ = try await client.send(
      request,
      redirectPolicy: SameHostRedirectPolicy(origin: ClaudeProviderConfiguration.live.usageURL)
    )

    let summary = try #require(await recorder.summary())
    #expect(
      summary
        == "http_status=418 five_hour=object(utilization=non_numeric,resets_at=unparseable) seven_day=wrong_type"
    )
    #expect(!summary.contains("fixture-secret"))
    #expect(!summary.contains("Authorization"))
    #expect(!summary.contains("anthropic.com"))
  }

  @Test("live diagnostics redact associated failure values")
  func liveDiagnosticsRedactAssociatedFailureValues() {
    #expect(safeProviderFailureCategory(.unsupportedPayload) == "unsupported_payload")
    #expect(
      safeProviderFailureCategory(.rateLimited(retryAfter: Date(timeIntervalSince1970: 42)))
        == "rate_limited"
    )
    #expect(safeProviderFailureCategory(.processFailure(exitCode: 42)) == "process_failure")
  }

  @Test(
    "live Claude usage works when explicitly enabled",
    .enabled(
      if: ProcessInfo.processInfo.environment["AGENT_PREFLIGHT_LIVE_CLAUDE"] == "1",
      "Set AGENT_PREFLIGHT_LIVE_CLAUDE=1 for an explicit Keychain/API smoke test"
    )
  )
  func testLiveClaudeUsageWhenExplicitlyEnabled() async throws {
    let configuration = ClaudeProviderConfiguration.live
    let diagnosticRecorder = ClaudeLiveHTTPDiagnosticRecorder()
    let provider = ClaudeQuotaProvider(
      credentialReader: KeychainClaudeCredentialReader(service: configuration.keychainService),
      httpClient: ClaudeLiveDiagnosticHTTPClient(
        base: URLSessionHTTPClient(),
        recorder: diagnosticRecorder
      ),
      parser: ClaudeUsageParser(),
      clock: SystemClock(),
      configuration: configuration,
      timeoutSeconds: 5
    )

    do {
      let snapshot = try await provider.fetchSnapshot()
      #expect(!snapshot.windows.isEmpty)
      #expect(snapshot.windows.values.allSatisfy { (0...100).contains($0.remaining.value) })
    } catch let failure as ProviderFailure {
      let summary = await diagnosticRecorder.summary() ?? "http_status=not_observed"
      Issue.record(
        "Live Claude usage failed: failure=\(safeProviderFailureCategory(failure)) \(summary)"
      )
    } catch {
      let summary = await diagnosticRecorder.summary() ?? "http_status=not_observed"
      Issue.record("Live Claude usage failed: failure=unclassified_error \(summary)")
    }
  }

  private func diagnosticForFiveHour(_ object: String) -> ClaudeLiveHTTPDiagnostic {
    ClaudeLiveHTTPDiagnostic.classify(
      statusCode: 200,
      data: Data("{\"five_hour\":\(object)}".utf8)
    )
  }
}

/// The stub protocol keeps process-wide state, so these tests must not overlap each other.
@Suite("Redirect enforcement", .serialized)
struct URLSessionHTTPClientRedirectTests {
  private static let origin = URL(string: "https://api.anthropic.com/api/oauth/usage")!
  private static let authorizationHeader = "Bearer fixture-token-never-log"

  @Test("client refuses a foreign-host redirect and never forwards the token to it")
  func clientRefusesForeignHostRedirectAndNeverForwardsToken() async throws {
    ScriptedURLProtocol.reset(
      script: [.redirect(location: "https://evil.example.com/api/oauth/usage")]
    )
    defer { ScriptedURLProtocol.reset(script: []) }

    await #expect(throws: HTTPClientError.redirectRejected) {
      try await client().send(originRequest(), redirectPolicy: policy())
    }

    let recorded = ScriptedURLProtocol.recordedRequests()
    #expect(recorded.count == 1)
    #expect(recorded.allSatisfy { $0.url?.host != "evil.example.com" })
    #expect(
      recorded
        .filter { $0.value(forHTTPHeaderField: "Authorization") != nil }
        .allSatisfy { $0.url?.host == "api.anthropic.com" }
    )
  }

  @Test("client follows a same-host redirect and returns the final response")
  func clientFollowsSameHostRedirectAndReturnsFinalResponse() async throws {
    ScriptedURLProtocol.reset(
      script: [
        .redirect(location: "https://api.anthropic.com/api/oauth/usage-v2"),
        .success(statusCode: 200, body: try loadFixture("claude-success")),
      ]
    )
    defer { ScriptedURLProtocol.reset(script: []) }

    let response = try await client().send(originRequest(), redirectPolicy: policy())

    #expect(response.statusCode == 200)
    #expect(response.finalURL.host == "api.anthropic.com")
    #expect(response.data == (try loadFixture("claude-success")))
    #expect(ScriptedURLProtocol.recordedRequests().count == 2)
  }

  @Test("client rejects a plain HTTP request before it reaches the transport")
  func clientRejectsPlainHTTPRequestBeforeTransport() async throws {
    ScriptedURLProtocol.reset(script: [.success(statusCode: 200, body: Data())])
    defer { ScriptedURLProtocol.reset(script: []) }
    let insecureURL = try #require(URL(string: "http://api.anthropic.com/api/oauth/usage"))

    await #expect(throws: HTTPClientError.nonHTTPSRequest) {
      try await client().send(URLRequest(url: insecureURL), redirectPolicy: policy())
    }

    #expect(ScriptedURLProtocol.recordedRequests().isEmpty)
  }

  private func client() -> URLSessionHTTPClient {
    URLSessionHTTPClient(protocolClasses: [ScriptedURLProtocol.self])
  }

  private func policy() -> SameHostRedirectPolicy {
    SameHostRedirectPolicy(origin: Self.origin)
  }

  private func originRequest() -> URLRequest {
    var request = URLRequest(url: Self.origin)
    request.setValue(Self.authorizationHeader, forHTTPHeaderField: "Authorization")
    return request
  }
}

/// Answers requests from a scripted list and records every request the transport actually issued.
private final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
  enum ScriptedResponse: Sendable {
    case redirect(location: String)
    case success(statusCode: Int, body: Data)
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var script: [ScriptedResponse] = []
  nonisolated(unsafe) private static var recorded: [URLRequest] = []

  static func reset(script newScript: [ScriptedResponse]) {
    lock.withLock {
      script = newScript
      recorded = []
    }
  }

  static func recordedRequests() -> [URLRequest] {
    lock.withLock { recorded }
  }

  private static func nextResponse(for request: URLRequest) -> ScriptedResponse? {
    lock.withLock {
      recorded.append(request)
      return script.isEmpty ? nil : script.removeFirst()
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let scripted = Self.nextResponse(for: request) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    switch scripted {
    case .redirect(let location):
      let response = HTTPURLResponse(
        url: url,
        statusCode: 302,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": location]
      )!
      var redirected = URLRequest(url: URL(string: location)!)
      redirected.httpMethod = request.httpMethod
      // URLSession carries the original headers onto the proposed request, so the stub must too:
      // that is exactly what a foreign-host redirect would leak.
      redirected.allHTTPHeaderFields = request.allHTTPHeaderFields
      client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    case .success(let statusCode, let body):
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

private func loadFixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
  )
  return try Data(contentsOf: url)
}

private struct FixedClock: Clock {
  let current: Date
  init(now: Date) { self.current = now }
  func now() -> Date { current }
}

private struct CredentialReaderStub: ClaudeCredentialReader {
  let token: String
  func readAccessToken() async throws -> SensitiveToken { try SensitiveToken(token) }
}

private actor HTTPClientSpy: HTTPClient {
  private(set) var lastRequest: URLRequest?
  let response: HTTPResponse

  init(
    statusCode: Int,
    data: Data,
    finalURL: URL = ClaudeProviderConfiguration.live.usageURL
  ) {
    self.response = HTTPResponse(
      data: data,
      statusCode: statusCode,
      headers: [:],
      finalURL: finalURL
    )
  }

  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    lastRequest = request
    return response
  }
}

private struct KeychainLoaderStub: KeychainCredentialLoading {
  let result: KeychainCredentialResult

  func loadGenericPassword(service: String) async -> KeychainCredentialResult { result }
}

private struct BlockingHTTPClient: HTTPClient {
  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    try await Task.sleep(for: .seconds(60))
    throw HTTPClientError.transportFailure
  }
}

private struct ThrowingHTTPClient: HTTPClient {
  let error: HTTPClientError

  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    throw error
  }
}

private struct FixedHTTPClient: HTTPClient {
  let response: HTTPResponse

  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    response
  }
}
