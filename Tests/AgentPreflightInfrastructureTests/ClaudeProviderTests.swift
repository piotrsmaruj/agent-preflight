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
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
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
  func keychainReaderMapsMissingAndDeniedItemsWithoutInspectingPayloads() throws {
    let service = ClaudeProviderConfiguration.live.keychainService
    let missing = KeychainClaudeCredentialReader(
      service: service,
      loader: KeychainLoaderStub(result: .status(errSecItemNotFound))
    )
    let denied = KeychainClaudeCredentialReader(
      service: service,
      loader: KeychainLoaderStub(result: .status(errSecUserCanceled))
    )

    #expect(throws: ProviderFailure.unauthenticated) {
      try missing.readAccessToken()
    }
    #expect(throws: ProviderFailure.keychainDenied) {
      try denied.readAccessToken()
    }
  }

  @Test("Keychain reader decodes the expected Claude OAuth envelope")
  func keychainReaderDecodesExpectedClaudeOAuthEnvelope() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-secret"}}"#.utf8)
    let reader = KeychainClaudeCredentialReader(
      service: ClaudeProviderConfiguration.live.keychainService,
      loader: KeychainLoaderStub(result: .data(data))
    )

    #expect(String(describing: try reader.readAccessToken()) == "<redacted>")
  }
}

extension ClaudeProviderTests {
  @Test("parser rejects an invalid percentage and timestamp")
  func parserRejectsInvalidPercentageAndTimestamp() {
    let invalidPercent = Data(
      #"{"five_hour":{"utilization":101,"resets_at":"2026-09-04T12:30:00Z"}}"#.utf8
    )
    let invalidTimestamp = Data(
      #"{"five_hour":{"utilization":20,"resets_at":"not-a-date"}}"#.utf8
    )

    #expect(throws: ProviderFailure.unsupportedPayload) {
      try ClaudeUsageParser().parse(invalidPercent, fetchedAt: Date())
    }
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

private struct FixedClock: Clock {
  let current: Date
  init(now: Date) { self.current = now }
  func now() -> Date { current }
}

private struct CredentialReaderStub: ClaudeCredentialReader {
  let token: String
  func readAccessToken() throws -> SensitiveToken { try SensitiveToken(token) }
}

private actor HTTPClientSpy: HTTPClient {
  private(set) var lastRequest: URLRequest?
  let response: HTTPResponse

  init(statusCode: Int, data: Data) {
    self.response = HTTPResponse(
      data: data,
      statusCode: statusCode,
      headers: [:],
      finalURL: ClaudeProviderConfiguration.live.usageURL
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

  func loadGenericPassword(service: String) -> KeychainCredentialResult { result }
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

private struct FixedHTTPClient: HTTPClient {
  let response: HTTPResponse

  func send(
    _ request: URLRequest,
    redirectPolicy: SameHostRedirectPolicy
  ) async throws -> HTTPResponse {
    response
  }
}
