# Agent Preflight MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first macOS 14+ menu-bar app that shows Codex and Claude Code subscription quota windows and recommends the safer provider for an S, M, or L task.

**Architecture:** A Swift Package keeps strict Domain → Application → Infrastructure/Presentation boundaries and produces a native SwiftUI executable. Provider adapters normalize unstable external contracts into immutable domain snapshots; the application actor coordinates concurrent refresh, cooldown, cache, and stale state; SwiftUI renders presentation-only models. A deterministic packaging script creates the menu-bar-only `.app`, so development and CI require SwiftPM and Command Line Tools rather than a generated Xcode project.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI `MenuBarExtra`, Foundation, Security.framework, OSLog, XCTest, GitHub Actions on macOS.

**Spec:** `docs/superpowers/specs/2026-09-04-agent-preflight-design.md`

## Global Constraints

- Support macOS 14 or newer and build with Swift 6 language mode.
- Keep the app menu-bar-only: no Dock icon and one popover that fits without scrolling.
- Keep Domain independent of SwiftUI, HTTP, processes, Keychain, UserDefaults, and OSLog.
- Keep credentials owned by vendor CLIs; never persist or log access tokens, refresh tokens, authorization headers, cookies, or raw credential payloads.
- Read Claude credentials only after a user-initiated open or refresh; never trigger a hidden login or retry.
- Fetch Codex and Claude concurrently, isolate failures, apply a five-second timeout, a 30-second request cooldown, and a 15-minute stale threshold.
- Make no cross-provider recommendation when either provider is incomplete, stale, expired, or unavailable.
- Use remaining quota everywhere; color must never be the only status signal.
- Use the exact S/M/L reserves from the spec: S `15%/5%`, M `35%/10%`, L `60%/20%`; neutral margin tolerance is `0.10`.
- Persist only normalized numeric snapshots; create cache directories as `0700` and cache files as `0600`.
- Add no third-party runtime or test dependencies in version 0.1.
- Do not add analytics, a backend, accounts, payments, background polling, notifications, history, automatic agent launching, signing with a Developer ID, or notarization.
- Treat the Claude OAuth endpoint and Keychain payload as an internal compatibility contract; isolate both behind protocols and fixture tests.
- Keep public functions single-purpose and normally below 30 lines; use typed errors, dependency injection, and self-documenting names.
- Run all automated verification through `swift test`; live-account smoke tests remain explicit opt-in tests and never run in CI.
- Before every task commit, run `swift format --in-place --recursive Package.swift Sources Tests`, then `swift format lint --recursive Package.swift Sources Tests` and the task's listed tests.
- Full Xcode is currently unavailable in the development environment. Do not introduce an `.xcodeproj`; use `swift build`, `swift test`, and the packaging script below.

## Final File Map

```text
.
├── .github/workflows/ci.yml                 # deterministic macOS build and unit tests
├── .gitignore                               # SwiftPM and packaged-app outputs
├── LICENSE                                  # MIT license for public v0.1
├── Package.swift                            # target boundaries and Security linkage
├── PRIVACY.md                               # exact local-data and credential behavior
├── README.md                                # setup, use, tests, risks, troubleshooting
├── Resources/Info.plist                     # bundle metadata and LSUIElement
├── Scripts/package_app.sh                   # release build plus deterministic .app layout
├── Sources
│   ├── AgentPreflightDomain
│   │   ├── QuotaModels.swift              # providers, percentages, windows, snapshots
│   │   ├── Recommendation.swift           # structured decisions and failures
│   │   ├── RecommendationEngine.swift     # deterministic comparison algorithm
│   │   └── TaskSizePolicy.swift           # single source for S/M/L reserves
│   ├── AgentPreflightApplication
│   │   ├── AppSettingsStore.swift         # manual Codex path boundary
│   │   ├── Clock.swift                    # injectable current time
│   │   ├── Diagnostics.swift              # typed, secret-free diagnostic events
│   │   ├── ProviderContracts.swift        # adapter protocol and typed failures
│   │   ├── QuotaCache.swift               # normalized-cache boundary
│   │   ├── RefreshModels.swift            # freshness and aggregate state
│   │   ├── RefreshQuotaUseCase.swift      # concurrent refresh and cooldown
│   │   └── Timeout.swift                  # cancellation-aware timeout helper
│   ├── AgentPreflightInfrastructure
│   │   ├── Cache/JSONQuotaCache.swift     # atomic JSON persistence and permissions
│   │   ├── Claude/ClaudeCredentials.swift # secret wrapper and credential decoder
│   │   ├── Claude/ClaudeQuotaProvider.swift # request and status mapping
│   │   ├── Claude/ClaudeUsageParser.swift # OAuth usage DTO and normalization
│   │   ├── Claude/KeychainClaudeCredentialReader.swift # least-privilege Security query
│   │   ├── Codex/CodexAppServerClient.swift # JSON-RPC handshake and correlation
│   │   ├── Codex/CodexExecutableLocator.swift # override and standard-path discovery
│   │   ├── Codex/CodexQuotaProvider.swift # executable-to-snapshot adapter
│   │   ├── Codex/CodexRateLimitsParser.swift # app-server DTO and normalization
│   │   ├── Codex/FoundationJSONLineProcess.swift # direct child process transport
│   │   ├── Diagnostics/OSDiagnosticsSink.swift # privacy-safe unified logging
│   │   ├── Networking/HTTPClient.swift     # transport value types and redirect policy
│   │   ├── Networking/URLSessionHTTPClient.swift # ephemeral HTTPS transport
│   │   ├── ProviderConfiguration.swift    # external identifiers and URLs
│   │   └── UserDefaultsAppSettingsStore.swift # non-secret path preference
│   ├── AgentPreflightPresentation
│   │   ├── AppViewModel.swift             # panel lifecycle and selected task size
│   │   ├── ErrorCopy.swift                # provider-specific recovery text
│   │   ├── MenuBarContentView.swift       # accepted limits-first layout
│   │   ├── PresentationFormatter.swift    # deterministic percentages/reset copy
│   │   ├── PresentationModels.swift       # immutable rows/cards/recommendation
│   │   ├── ProviderCardView.swift         # card plus window rows
│   │   ├── RecommendationCardView.swift   # recommendation and rationale
│   │   ├── SettingsView.swift             # optional Codex executable override
│   │   └── SettingsViewModel.swift        # validates and saves the override
│   └── AgentPreflightApp
│       ├── AgentPreflightApp.swift         # MenuBarExtra and Settings scenes
│       └── AppDependencies.swift           # sole production composition root
└── Tests
    ├── AgentPreflightDomainTests
    │   ├── QuotaModelsTests.swift
    │   └── RecommendationEngineTests.swift
    ├── AgentPreflightApplicationTests
    │   └── RefreshQuotaUseCaseTests.swift
    ├── AgentPreflightInfrastructureTests
    │   ├── ClaudeProviderTests.swift
    │   ├── CodexProviderTests.swift
    │   ├── JSONQuotaCacheTests.swift
    │   ├── SecurityBoundaryTests.swift
    │   └── Fixtures/*.json
    └── AgentPreflightPresentationTests
        └── AppViewModelTests.swift
```

## External Contract Baseline

- Codex lifecycle and response fields come from the official app-server documentation: initialize once, send `initialized`, then call `account/rateLimits/read`; windows expose `usedPercent`, `windowDurationMins`, and Unix `resetsAt`.
- Claude currently uses `GET https://api.anthropic.com/api/oauth/usage`, `anthropic-beta: oauth-2025-04-20`, and a bearer token from `Claude Code-credentials`; `five_hour` and `seven_day` contain `utilization` from 0 through 100 and ISO-8601 `resets_at`.
- The Claude contract is not public/stable. Task 2 is a hard stop/go checkpoint before the remaining implementation budget is spent.

## Timeboxes and Stop Rule

- Timebox Task 1 to 20 minutes and the deterministic portion of Task 2 to 30 minutes.
- Reach Task 2 Step 18, the real Claude smoke test, within the first hour.
- If that checkpoint fails for the typed compatibility reasons listed there, stop the build; do not consume the remaining 13-hour budget on UI or Codex work.
- After a successful checkpoint, timebox Tasks 3–9 to 13 hours total, keeping the complete MVP within the approved 14-hour estimate.

---

### Task 1: Bootstrap the Package and Quota Domain Values

**Files:**
- Create: `Package.swift`
- Create: `Sources/AgentPreflightDomain/QuotaModels.swift`
- Create: `Tests/AgentPreflightDomainTests/QuotaModelsTests.swift`

**Interfaces:**
- Consumes: no project code.
- Produces: `ProviderIdentifier`, `QuotaWindowKind`, `RemainingPercentage`, `QuotaWindow`, `QuotaSnapshot`, and `QuotaModelError` as `Codable`, `Equatable`, and `Sendable` values.

- [ ] **Step 1: Add the initial package manifest**

Create `Package.swift` with only the first vertical slice:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPreflight",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentPreflightDomain", targets: ["AgentPreflightDomain"]),
    ],
    targets: [
        .target(name: "AgentPreflightDomain"),
        .testTarget(
            name: "AgentPreflightDomainTests",
            dependencies: ["AgentPreflightDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the failing quota-domain test**

Create `Tests/AgentPreflightDomainTests/QuotaModelsTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentPreflightDomain

final class QuotaModelsTests: XCTestCase {
    func testUsedPercentageConvertsToRemainingPercentage() throws {
        XCTAssertEqual(try RemainingPercentage.fromUsed(21.5).value, 78.5)
    }

    func testTinyProviderDriftIsClamped() throws {
        XCTAssertEqual(try RemainingPercentage(remaining: 100.005).value, 100)
        XCTAssertEqual(try RemainingPercentage(remaining: -0.005).value, 0)
    }

    func testStructurallyInvalidPercentageIsRejected() {
        XCTAssertThrowsError(try RemainingPercentage(remaining: 101))
        XCTAssertThrowsError(try RemainingPercentage(remaining: .nan))
        XCTAssertThrowsError(
            try JSONDecoder().decode(RemainingPercentage.self, from: Data(#"{"value":101}"#.utf8))
        )
    }

    func testDuplicateWindowKindsAreRejected() throws {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let percentage = try RemainingPercentage(remaining: 50)
        let first = QuotaWindow(kind: .short, remaining: percentage, resetsAt: date)
        let second = QuotaWindow(kind: .short, remaining: percentage, resetsAt: date)

        XCTAssertThrowsError(
            try QuotaSnapshot(provider: .codex, windows: [first, second], fetchedAt: date)
        )
    }
}
```

- [ ] **Step 3: Run the test and confirm the expected compile failure**

Run: `swift test --filter QuotaModelsTests`

Expected: FAIL because `RemainingPercentage`, `QuotaWindow`, and `QuotaSnapshot` do not exist.

- [ ] **Step 4: Implement the quota values and invariant checks**

Create `Sources/AgentPreflightDomain/QuotaModels.swift`:

```swift
import Foundation

public enum ProviderIdentifier: String, CaseIterable, Codable, Sendable {
    case codex
    case claudeCode
}

public enum QuotaWindowKind: String, CaseIterable, Codable, Sendable {
    case short
    case weekly
}

public enum QuotaModelError: Error, Equatable, Sendable {
    case percentageOutOfRange(Double)
    case duplicateWindow(QuotaWindowKind)
}

public struct RemainingPercentage: Codable, Equatable, Sendable {
    public static let providerDriftTolerance = 0.01
    public let value: Double

    public init(remaining value: Double) throws {
        guard value.isFinite,
              value >= -Self.providerDriftTolerance,
              value <= 100 + Self.providerDriftTolerance
        else {
            throw QuotaModelError.percentageOutOfRange(value)
        }
        self.value = min(100, max(0, value))
    }

    public static func fromUsed(_ used: Double) throws -> Self {
        try Self(remaining: 100 - used)
    }

    private enum CodingKeys: String, CodingKey { case value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(remaining: container.decode(Double.self, forKey: .value))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let kind: QuotaWindowKind
    public let remaining: RemainingPercentage
    public let resetsAt: Date

    public init(kind: QuotaWindowKind, remaining: RemainingPercentage, resetsAt: Date) {
        self.kind = kind
        self.remaining = remaining
        self.resetsAt = resetsAt
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderIdentifier
    public let windows: [QuotaWindowKind: QuotaWindow]
    public let fetchedAt: Date

    public init(
        provider: ProviderIdentifier,
        windows: [QuotaWindow],
        fetchedAt: Date
    ) throws {
        var indexedWindows: [QuotaWindowKind: QuotaWindow] = [:]
        for window in windows {
            guard indexedWindows.updateValue(window, forKey: window.kind) == nil else {
                throw QuotaModelError.duplicateWindow(window.kind)
            }
        }
        self.provider = provider
        self.windows = indexedWindows
        self.fetchedAt = fetchedAt
    }

    public func window(_ kind: QuotaWindowKind, validAt date: Date) -> QuotaWindow? {
        guard let window = windows[kind], window.resetsAt > date else { return nil }
        return window
    }

    private enum CodingKeys: String, CodingKey { case provider, windows, fetchedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            provider: container.decode(ProviderIdentifier.self, forKey: .provider),
            windows: container.decode([QuotaWindow].self, forKey: .windows),
            fetchedAt: container.decode(Date.self, forKey: .fetchedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(
            windows.values.sorted { $0.kind.rawValue < $1.kind.rawValue },
            forKey: .windows
        )
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}
```

- [ ] **Step 5: Run domain tests and formatting checks**

Run: `swift test --filter QuotaModelsTests`

Expected: PASS, 4 tests.

Run: `swift format --in-place --recursive Package.swift Sources Tests`

Run: `swift format lint --recursive Package.swift Sources Tests`

Expected: PASS with the bundled Swift Format 6.3.0.

- [ ] **Step 6: Commit the domain slice**

```bash
git add Package.swift Sources/AgentPreflightDomain Tests/AgentPreflightDomainTests
git commit -m "feat: add quota domain models"
```

---

### Task 2: Prove the Claude Keychain and Usage Path (Hard Stop/Go)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgentPreflightApplication/Clock.swift`
- Create: `Sources/AgentPreflightApplication/ProviderContracts.swift`
- Create: `Sources/AgentPreflightApplication/Timeout.swift`
- Create: `Sources/AgentPreflightInfrastructure/ProviderConfiguration.swift`
- Create: `Sources/AgentPreflightInfrastructure/Networking/HTTPClient.swift`
- Create: `Sources/AgentPreflightInfrastructure/Networking/URLSessionHTTPClient.swift`
- Create: `Sources/AgentPreflightInfrastructure/Claude/ClaudeCredentials.swift`
- Create: `Sources/AgentPreflightInfrastructure/Claude/KeychainClaudeCredentialReader.swift`
- Create: `Sources/AgentPreflightInfrastructure/Claude/ClaudeUsageParser.swift`
- Create: `Sources/AgentPreflightInfrastructure/Claude/ClaudeQuotaProvider.swift`
- Create: `Tests/AgentPreflightInfrastructureTests/Fixtures/claude-success.json`
- Create: `Tests/AgentPreflightInfrastructureTests/Fixtures/claude-partial.json`
- Create: `Tests/AgentPreflightInfrastructureTests/ClaudeProviderTests.swift`

**Interfaces:**
- Consumes: `QuotaSnapshot`, `QuotaWindow`, `RemainingPercentage`, `ProviderIdentifier` from Task 1.
- Produces: `Clock.now() -> Date`, `QuotaProvider.fetchSnapshot() async throws -> QuotaSnapshot`, `ProviderFailure`, `withTimeout(seconds:operation:)`, `ClaudeCredentialReader`, `HTTPClient`, `ClaudeUsageParser.parse(_:fetchedAt:)`, and `ClaudeQuotaProvider`.

- [ ] **Step 1: Extend the package for Application and Infrastructure**

Add these targets to `Package.swift` after `AgentPreflightDomain`:

```swift
.library(name: "AgentPreflightApplication", targets: ["AgentPreflightApplication"]),
.library(name: "AgentPreflightInfrastructure", targets: ["AgentPreflightInfrastructure"]),
```

Add these target declarations:

```swift
.target(
    name: "AgentPreflightApplication",
    dependencies: ["AgentPreflightDomain"]
),
.target(
    name: "AgentPreflightInfrastructure",
    dependencies: ["AgentPreflightDomain", "AgentPreflightApplication"],
    linkerSettings: [.linkedFramework("Security")]
),
.testTarget(
    name: "AgentPreflightInfrastructureTests",
    dependencies: ["AgentPreflightDomain", "AgentPreflightApplication", "AgentPreflightInfrastructure"],
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 2: Add redacted Claude response fixtures**

Create `Tests/AgentPreflightInfrastructureTests/Fixtures/claude-success.json`:

```json
{
  "five_hour": {"utilization": 21.5, "resets_at": "2026-09-04T12:30:00.000Z"},
  "seven_day": {"utilization": 42, "resets_at": "2026-09-10T08:00:00Z"},
  "seven_day_opus": null,
  "extra_usage": {"is_enabled": false}
}
```

Create `Tests/AgentPreflightInfrastructureTests/Fixtures/claude-partial.json`:

```json
{
  "five_hour": null,
  "seven_day": {"utilization": 42, "resets_at": "2026-09-10T08:00:00Z"}
}
```

- [ ] **Step 3: Write the failing Claude contract tests and local spies**

Create `Tests/AgentPreflightInfrastructureTests/ClaudeProviderTests.swift` with these first tests and local spies:

```swift
import Foundation
import Security
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

final class ClaudeProviderTests: XCTestCase {
    func testParserMapsUsedUtilizationToRemainingQuota() throws {
        let data = try fixture("claude-success")
        let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
        let snapshot = try ClaudeUsageParser().parse(data, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.provider, .claudeCode)
        XCTAssertEqual(snapshot.windows[.short]?.remaining.value, 78.5)
        XCTAssertEqual(snapshot.windows[.weekly]?.remaining.value, 58)
    }

    func testParserKeepsAValidPartialSnapshot() throws {
        let snapshot = try ClaudeUsageParser().parse(
            fixture("claude-partial"),
            fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
        )
        XCTAssertNil(snapshot.windows[.short])
        XCTAssertNotNil(snapshot.windows[.weekly])
    }

    func testProviderMapsSuccessfulHTTPResponse() async throws {
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
        XCTAssertEqual(snapshot.windows[.short]?.remaining.value, 78.5)
        XCTAssertEqual(snapshot.windows[.weekly]?.remaining.value, 58)
    }

    func testCredentialDecoderRejectsMissingOAuthToken() {
        XCTAssertThrowsError(
            try ClaudeCredentialDecoder().decode(Data(#"{"mcpOAuth":{}}"#.utf8))
        )
    }

    func testProviderBuildsExpectedRequestAndMapsUnauthorized() async throws {
        let transport = HTTPClientSpy(statusCode: 401, data: Data())
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
            XCTFail("Expected unauthorized")
        } catch let error as ProviderFailure {
            XCTAssertEqual(error, .unauthorized)
        }

        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token-never-log")
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
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

    func send(_ request: URLRequest, redirectPolicy: SameHostRedirectPolicy) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }
}
```

- [ ] **Step 4: Run the Claude tests and confirm the expected compile failure**

Run: `swift test --filter ClaudeProviderTests`

Expected: FAIL because the application contracts and Claude adapter types do not exist.

- [ ] **Step 5: Implement the clock and provider contracts**

Create `Sources/AgentPreflightApplication/Clock.swift`:

```swift
import Foundation

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
```

Create `Sources/AgentPreflightApplication/ProviderContracts.swift`:

```swift
import Foundation
import AgentPreflightDomain

public enum ProviderFailure: Error, Equatable, Sendable {
    case executableMissing
    case unauthenticated
    case keychainDenied
    case invalidCredential
    case timeout
    case unauthorized
    case rateLimited(retryAfter: Date?)
    case unsupportedPayload
    case processFailure(exitCode: Int32?)
    case protocolFailure
    case networkUnavailable
}

public protocol QuotaProvider: Sendable {
    var identifier: ProviderIdentifier { get }
    func fetchSnapshot() async throws -> QuotaSnapshot
}
```

- [ ] **Step 6: Implement the cancellation-aware timeout helper**

Create `Sources/AgentPreflightApplication/Timeout.swift`:

```swift
import Foundation

public func withTimeout<Value: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw ProviderFailure.timeout
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw ProviderFailure.timeout }
        return value
    }
}
```

- [ ] **Step 7: Centralize the Claude provider configuration**

Create `Sources/AgentPreflightInfrastructure/ProviderConfiguration.swift`:

```swift
import Foundation

public struct ClaudeProviderConfiguration: Sendable {
    public let usageURL: URL
    public let betaHeaderValue: String
    public let keychainService: String

    public static var live: Self {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            preconditionFailure("Bundled Claude usage URL is invalid")
        }
        return Self(
            usageURL: url,
            betaHeaderValue: "oauth-2025-04-20",
            keychainService: "Claude Code-credentials"
        )
    }
}
```

- [ ] **Step 8: Implement the redacted Claude credential boundary**

Create `Sources/AgentPreflightInfrastructure/Claude/ClaudeCredentials.swift`:

```swift
import Foundation
import AgentPreflightApplication

public struct SensitiveToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let rawValue: String
    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ProviderFailure.invalidCredential }
        self.rawValue = normalized
    }

    func authorizationHeaderValue() -> String { "Bearer \(rawValue)" }
}

public protocol ClaudeCredentialReader: Sendable {
    func readAccessToken() throws -> SensitiveToken
}

public struct ClaudeCredentialDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> SensitiveToken {
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard let token = envelope.claudeAiOauth?.accessToken else {
                throw ProviderFailure.invalidCredential
            }
            return try SensitiveToken(token)
        } catch let error as ProviderFailure {
            throw error
        } catch {
            throw ProviderFailure.invalidCredential
        }
    }

    private struct Envelope: Decodable {
        let claudeAiOauth: OAuthCredential?
    }

    private struct OAuthCredential: Decodable {
        let accessToken: String?
    }
}
```

- [ ] **Step 9: Implement the injectable Security.framework Keychain reader**

Create `Sources/AgentPreflightInfrastructure/Claude/KeychainClaudeCredentialReader.swift`:

```swift
import Foundation
import Security
import AgentPreflightApplication

public enum KeychainCredentialResult: Sendable {
    case data(Data)
    case status(OSStatus)
}

public protocol KeychainCredentialLoading: Sendable {
    func loadGenericPassword(service: String) -> KeychainCredentialResult
}

public struct SecurityKeychainCredentialLoader: KeychainCredentialLoading, @unchecked Sendable {
    public init() {}

    public func loadGenericPassword(service: String) -> KeychainCredentialResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return .status(status) }
        return .data(data)
    }
}

public struct KeychainClaudeCredentialReader: ClaudeCredentialReader, @unchecked Sendable {
    private let service: String
    private let decoder: ClaudeCredentialDecoder
    private let loader: any KeychainCredentialLoading

    public init(
        service: String,
        decoder: ClaudeCredentialDecoder = .init(),
        loader: any KeychainCredentialLoading = SecurityKeychainCredentialLoader()
    ) {
        self.service = service
        self.decoder = decoder
        self.loader = loader
    }

    public func readAccessToken() throws -> SensitiveToken {
        switch loader.loadGenericPassword(service: service) {
        case let .data(data):
            return try decoder.decode(data)
        case let .status(status):
            throw map(status)
        }
    }

    private func map(_ status: OSStatus) -> ProviderFailure {
        switch status {
        case errSecItemNotFound:
            return .unauthenticated
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .keychainDenied
        default:
            return .invalidCredential
        }
    }
}
```

- [ ] **Step 10: Define the HTTPS transport and redirect policy**

Create `Sources/AgentPreflightInfrastructure/Networking/HTTPClient.swift`:

```swift
import Foundation

public enum HTTPClientError: Error, Equatable, Sendable {
    case nonHTTPSRequest
    case invalidResponse
    case redirectRejected
    case transportFailure
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let finalURL: URL

    public init(data: Data, statusCode: Int, headers: [String: String], finalURL: URL) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.finalURL = finalURL
    }
}

public struct SameHostRedirectPolicy: Sendable {
    public let origin: URL

    public init(origin: URL) { self.origin = origin }

    public func allows(_ proposedURL: URL) -> Bool {
        origin.scheme?.lowercased() == "https"
            && proposedURL.scheme?.lowercased() == "https"
            && origin.host?.lowercased() == proposedURL.host?.lowercased()
            && origin.port == proposedURL.port
    }
}

public protocol HTTPClient: Sendable {
    func send(
        _ request: URLRequest,
        redirectPolicy: SameHostRedirectPolicy
    ) async throws -> HTTPResponse
}
```

- [ ] **Step 11: Implement the ephemeral URLSession transport**

Create `Sources/AgentPreflightInfrastructure/Networking/URLSessionHTTPClient.swift`:

```swift
import Foundation

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(
        _ request: URLRequest,
        redirectPolicy: SameHostRedirectPolicy
    ) async throws -> HTTPResponse {
        guard request.url?.scheme?.lowercased() == "https" else {
            throw HTTPClientError.nonHTTPSRequest
        }
        let delegate = RedirectDelegate(policy: redirectPolicy)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, let finalURL = http.url else {
                throw HTTPClientError.invalidResponse
            }
            if delegate.rejectedRedirect { throw HTTPClientError.redirectRejected }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                result[String(describing: pair.key)] = String(describing: pair.value)
            }
            return HTTPResponse(data: data, statusCode: http.statusCode, headers: headers, finalURL: finalURL)
        } catch let error as HTTPClientError {
            throw error
        } catch {
            throw HTTPClientError.transportFailure
        }
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: SameHostRedirectPolicy
    private let lock = NSLock()
    private var redirectWasRejected = false

    init(policy: SameHostRedirectPolicy) { self.policy = policy }

    var rejectedRedirect: Bool { lock.withLock { redirectWasRejected } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, policy.allows(url) else {
            lock.withLock { redirectWasRejected = true }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
```

- [ ] **Step 12: Test redirect and Keychain error policies**

Append this focused policy test to `ClaudeProviderTests`:

```swift
extension ClaudeProviderTests {
func testRedirectPolicyRejectsDifferentHostAndPlainHTTP() throws {
    let origin = try XCTUnwrap(URL(string: "https://api.anthropic.com/api/oauth/usage"))
    let policy = SameHostRedirectPolicy(origin: origin)
    XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://api.anthropic.com/next"))))
    XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://example.com/next"))))
    XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "http://api.anthropic.com/next"))))
    XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://api.anthropic.com:444/next"))))
}

func testKeychainReaderMapsMissingAndDeniedItemsWithoutInspectingPayloads() throws {
    let service = ClaudeProviderConfiguration.live.keychainService
    let missing = KeychainClaudeCredentialReader(
        service: service,
        loader: KeychainLoaderStub(result: .status(errSecItemNotFound))
    )
    let denied = KeychainClaudeCredentialReader(
        service: service,
        loader: KeychainLoaderStub(result: .status(errSecUserCanceled))
    )
    XCTAssertThrowsError(try missing.readAccessToken()) {
        XCTAssertEqual($0 as? ProviderFailure, .unauthenticated)
    }
    XCTAssertThrowsError(try denied.readAccessToken()) {
        XCTAssertEqual($0 as? ProviderFailure, .keychainDenied)
    }
}

func testKeychainReaderDecodesExpectedClaudeOAuthEnvelope() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-secret"}}"#.utf8)
    let reader = KeychainClaudeCredentialReader(
        service: ClaudeProviderConfiguration.live.keychainService,
        loader: KeychainLoaderStub(result: .data(data))
    )
    XCTAssertEqual(String(describing: try reader.readAccessToken()), "<redacted>")
}
}

private struct KeychainLoaderStub: KeychainCredentialLoading {
    let result: KeychainCredentialResult
    func loadGenericPassword(service: String) -> KeychainCredentialResult { result }
}
```

- [ ] **Step 13: Implement Claude response normalization**

Create `Sources/AgentPreflightInfrastructure/Claude/ClaudeUsageParser.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

public struct ClaudeUsageParser: Sendable {
    public init() {}

    public func parse(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            let windows = try [
                map(response.fiveHour, to: .short),
                map(response.sevenDay, to: .weekly),
            ].compactMap { $0 }
            guard !windows.isEmpty else { throw ProviderFailure.unsupportedPayload }
            return try QuotaSnapshot(provider: .claudeCode, windows: windows, fetchedAt: fetchedAt)
        } catch let error as ProviderFailure {
            throw error
        } catch {
            throw ProviderFailure.unsupportedPayload
        }
    }

    private func map(_ source: Window?, to kind: QuotaWindowKind) throws -> QuotaWindow? {
        guard let source else { return nil }
        if source.utilization == nil, source.resetsAt == nil { return nil }
        guard let utilization = source.utilization,
              let rawReset = source.resetsAt,
              let reset = parseDate(rawReset)
        else {
            throw ProviderFailure.unsupportedPayload
        }
        return QuotaWindow(
            kind: kind,
            remaining: try RemainingPercentage.fromUsed(utilization),
            resetsAt: reset
        )
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}
```

- [ ] **Step 14: Implement the Claude provider request and status mapping**

Create `Sources/AgentPreflightInfrastructure/Claude/ClaudeQuotaProvider.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

public struct ClaudeQuotaProvider: QuotaProvider {
    public let identifier = ProviderIdentifier.claudeCode
    private let credentialReader: any ClaudeCredentialReader
    private let httpClient: any HTTPClient
    private let parser: ClaudeUsageParser
    private let clock: any Clock
    private let configuration: ClaudeProviderConfiguration
    private let timeoutSeconds: TimeInterval

    public init(
        credentialReader: any ClaudeCredentialReader,
        httpClient: any HTTPClient,
        parser: ClaudeUsageParser,
        clock: any Clock,
        configuration: ClaudeProviderConfiguration,
        timeoutSeconds: TimeInterval
    ) {
        self.credentialReader = credentialReader
        self.httpClient = httpClient
        self.parser = parser
        self.clock = clock
        self.configuration = configuration
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetchSnapshot() async throws -> QuotaSnapshot {
        let token = try credentialReader.readAccessToken()
        let request = makeRequest(token: token)
        do {
            return try await withTimeout(seconds: timeoutSeconds) {
                let response = try await httpClient.send(
                    request,
                    redirectPolicy: SameHostRedirectPolicy(origin: configuration.usageURL)
                )
                guard SameHostRedirectPolicy(origin: configuration.usageURL).allows(response.finalURL) else {
                    throw ProviderFailure.protocolFailure
                }
                return try map(response)
            }
        } catch let failure as ProviderFailure {
            throw failure
        } catch {
            throw ProviderFailure.networkUnavailable
        }
    }

    private func makeRequest(token: SensitiveToken) -> URLRequest {
        var request = URLRequest(url: configuration.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")
        request.setValue(token.authorizationHeaderValue(), forHTTPHeaderField: "Authorization")
        return request
    }

    private func map(_ response: HTTPResponse) throws -> QuotaSnapshot {
        switch response.statusCode {
        case 200:
            return try parser.parse(response.data, fetchedAt: clock.now())
        case 401, 403:
            throw ProviderFailure.unauthorized
        case 429:
            throw ProviderFailure.rateLimited(retryAfter: nil)
        case 500...599:
            throw ProviderFailure.networkUnavailable
        default:
            throw ProviderFailure.unsupportedPayload
        }
    }
}
```

- [ ] **Step 15: Add malformed-data, rate-limit, and timeout tests**

Before running, append malformed-data, rate-limit, and timeout cases to `ClaudeProviderTests.swift`:

```swift
extension ClaudeProviderTests {
func testParserRejectsInvalidPercentageAndTimestamp() throws {
    let invalidPercent = Data(
        #"{"five_hour":{"utilization":101,"resets_at":"2026-09-04T12:30:00Z"}}"#.utf8
    )
    let invalidTimestamp = Data(
        #"{"five_hour":{"utilization":20,"resets_at":"not-a-date"}}"#.utf8
    )
    XCTAssertThrowsError(try ClaudeUsageParser().parse(invalidPercent, fetchedAt: Date()))
    XCTAssertThrowsError(try ClaudeUsageParser().parse(invalidTimestamp, fetchedAt: Date()))
}

func testProviderMapsRateLimitWithoutLoggingBody() async throws {
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
        XCTFail("Expected rate limit")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .rateLimited(retryAfter: nil))
        XCTAssertFalse(String(describing: error).contains("fixture-secret-body"))
    }
}

func testProviderCancelsBlockedTransportAtTimeout() async throws {
    let provider = ClaudeQuotaProvider(
        credentialReader: CredentialReaderStub(token: "fixture-token-never-log"),
        httpClient: BlockingHTTPClient(),
        parser: ClaudeUsageParser(),
        clock: FixedClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
        configuration: .live,
        timeoutSeconds: 0.01
    )
    do {
        _ = try await provider.fetchSnapshot()
        XCTFail("Expected timeout")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .timeout)
    }
}
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
```

- [ ] **Step 16: Run deterministic Claude tests**

Run: `swift test --filter ClaudeProviderTests`

Expected: PASS, including parser, partial/malformed data, credential absence/denial, headers, 401/429 mapping, timeout, secret-safe errors, and redirect policy.

- [ ] **Step 17: Add the opt-in live Claude smoke test**

Append this test to `ClaudeProviderTests`:

```swift
extension ClaudeProviderTests {
func testLiveClaudeUsageWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["AGENT_PREFLIGHT_LIVE_CLAUDE"] == "1" else {
        throw XCTSkip("Set AGENT_PREFLIGHT_LIVE_CLAUDE=1 for an explicit Keychain/API smoke test")
    }
    let configuration = ClaudeProviderConfiguration.live
    let provider = ClaudeQuotaProvider(
        credentialReader: KeychainClaudeCredentialReader(service: configuration.keychainService),
        httpClient: URLSessionHTTPClient(),
        parser: ClaudeUsageParser(),
        clock: SystemClock(),
        configuration: configuration,
        timeoutSeconds: 5
    )

    let snapshot = try await provider.fetchSnapshot()
    XCTAssertFalse(snapshot.windows.isEmpty)
    XCTAssertTrue(snapshot.windows.values.allSatisfy { (0...100).contains($0.remaining.value) })
}
}
```

- [ ] **Step 18: Run the hard stop/go checkpoint**

Run only after the user initiates it:

```bash
AGENT_PREFLIGHT_LIVE_CLAUDE=1 swift test --filter testLiveClaudeUsageWhenExplicitlyEnabled
```

Expected: macOS may show one Keychain access prompt; after approval the test passes without printing a token, credential JSON, headers, or response body.

**Hard checkpoint:** if this test returns `keychainDenied`, `invalidCredential`, `unauthorized`, or `unsupportedPayload` after Claude Code is logged in, stop execution here. Capture only the typed failure category, do not inspect or print credentials, and revisit the provider design before spending the remaining budget. Do not add cookie extraction, copied tokens, or TUI automation as a workaround.

- [ ] **Step 19: Commit the proven Claude slice**

```bash
git add Package.swift Sources/AgentPreflightApplication Sources/AgentPreflightInfrastructure Tests/AgentPreflightInfrastructureTests
git commit -m "feat: add secure Claude quota adapter"
```

---

### Task 3: Add the Codex App-Server Adapter

**Files:**
- Create: `Sources/AgentPreflightApplication/AppSettingsStore.swift`
- Create: `Sources/AgentPreflightInfrastructure/UserDefaultsAppSettingsStore.swift`
- Create: `Sources/AgentPreflightInfrastructure/Codex/CodexExecutableLocator.swift`
- Create: `Sources/AgentPreflightInfrastructure/Codex/FoundationJSONLineProcess.swift`
- Create: `Sources/AgentPreflightInfrastructure/Codex/CodexAppServerClient.swift`
- Create: `Sources/AgentPreflightInfrastructure/Codex/CodexRateLimitsParser.swift`
- Create: `Sources/AgentPreflightInfrastructure/Codex/CodexQuotaProvider.swift`
- Create: `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-primary-secondary.json`
- Create: `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-primary-weekly-only.json`
- Create: `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-grouped.json`
- Create: `Tests/AgentPreflightInfrastructureTests/CodexProviderTests.swift`

**Interfaces:**
- Consumes: `QuotaProvider`, `ProviderFailure`, `Clock`, `withTimeout`, and quota domain values.
- Produces: `AppSettingsStore`, `CodexExecutableLocating.locate() async throws -> URL`, `JSONLineProcessLaunching`, `CodexAppServerClient.readRateLimits(executableURL:)`, `CodexRateLimitsParser.parse(_:fetchedAt:)`, and `CodexQuotaProvider`.

- [ ] **Step 1: Add redacted Codex response fixtures**

Create `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-primary-secondary.json`:

```json
{
  "id": 1,
  "result": {
    "rateLimits": {
      "limitId": "codex",
      "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1788525000},
      "secondary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1789129800}
    }
  }
}
```

Create `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-primary-weekly-only.json`:

```json
{
  "id": 1,
  "result": {
    "rateLimits": {
      "limitId": "codex",
      "primary": {"usedPercent": 31, "windowDurationMins": 10080, "resetsAt": 1789129800},
      "secondary": null
    }
  }
}
```

Create `Tests/AgentPreflightInfrastructureTests/Fixtures/codex-grouped.json`:

```json
{
  "id": 1,
  "result": {
    "rateLimits": null,
    "rateLimitsByLimitId": {
      "codex": {
        "primary": {"usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1788525000},
        "secondary": {"usedPercent": 8, "windowDurationMins": 10080, "resetsAt": 1789129800}
      }
    }
  }
}
```

- [ ] **Step 2: Write the failing Codex parser and locator tests**

Create the initial `Tests/AgentPreflightInfrastructureTests/CodexProviderTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

final class CodexProviderTests: XCTestCase {
    func testParserClassifiesFiveHourAndWeeklyWindowsByDuration() throws {
        let snapshot = try CodexRateLimitsParser().parse(
            fixture("codex-primary-secondary"),
            fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
        )
        XCTAssertEqual(snapshot.windows[.short]?.remaining.value, 75)
        XCTAssertEqual(snapshot.windows[.weekly]?.remaining.value, 90)
    }

    func testParserDoesNotInventMissingShortWindow() throws {
        let snapshot = try CodexRateLimitsParser().parse(
            fixture("codex-primary-weekly-only"),
            fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
        )
        XCTAssertNil(snapshot.windows[.short])
        XCTAssertEqual(snapshot.windows[.weekly]?.remaining.value, 69)
    }

    func testParserSelectsCodexFromGroupedLimitShape() throws {
        let snapshot = try CodexRateLimitsParser().parse(
            fixture("codex-grouped"),
            fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
        )
        XCTAssertEqual(snapshot.windows[.short]?.remaining.value, 80)
        XCTAssertEqual(snapshot.windows[.weekly]?.remaining.value, 92)
    }

    func testLocatorUsesValidManualOverrideBeforePath() async throws {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        addTeardownBlock { try FileManager.default.removeItem(at: executable) }

        let locator = CodexExecutableLocator(
            settings: SettingsStoreStub(path: executable.path),
            environmentPath: "/unavailable"
        )
        let locatedExecutable = try await locator.locate()
        XCTAssertEqual(locatedExecutable, executable)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }
}

private actor SettingsStoreStub: AppSettingsStore {
    let path: String?
    init(path: String?) { self.path = path }
    func codexExecutablePath() async -> String? { path }
    func setCodexExecutablePath(_ path: String?) async {}
}
```

- [ ] **Step 3: Run tests and confirm the expected compile failure**

Run: `swift test --filter CodexProviderTests`

Expected: FAIL because the Codex parser, locator, and settings boundary do not exist.

- [ ] **Step 4: Add the application boundary for settings and path validation**

Create `Sources/AgentPreflightApplication/AppSettingsStore.swift`:

```swift
public protocol AppSettingsStore: Sendable {
    func codexExecutablePath() async -> String?
    func setCodexExecutablePath(_ path: String?) async
}

public protocol ExecutablePathValidating: Sendable {
    func isExecutable(path: String) -> Bool
}
```

- [ ] **Step 5: Persist the non-secret Codex path preference**

Create `Sources/AgentPreflightInfrastructure/UserDefaultsAppSettingsStore.swift`:

```swift
import Foundation
import AgentPreflightApplication

public actor UserDefaultsAppSettingsStore: AppSettingsStore {
    public static let codexPathKey = "codexExecutablePath"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func codexExecutablePath() async -> String? {
        defaults.string(forKey: Self.codexPathKey)
    }

    public func setCodexExecutablePath(_ path: String?) async {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            defaults.set(normalized, forKey: Self.codexPathKey)
        } else {
            defaults.removeObject(forKey: Self.codexPathKey)
        }
    }
}
```

- [ ] **Step 6: Implement deterministic Codex executable discovery**

Create `Sources/AgentPreflightInfrastructure/Codex/CodexExecutableLocator.swift`:

```swift
import Foundation
import AgentPreflightApplication

public protocol CodexExecutableLocating: Sendable {
    func locate() async throws -> URL
    func isExecutable(path: String) -> Bool
}

public struct CodexExecutableLocator: CodexExecutableLocating, ExecutablePathValidating {
    private let settings: any AppSettingsStore
    private let environmentPath: String
    private let fileManager: FileManager

    public init(
        settings: any AppSettingsStore,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        fileManager: FileManager = .default
    ) {
        self.settings = settings
        self.environmentPath = environmentPath
        self.fileManager = fileManager
    }

    public func locate() async throws -> URL {
        if let manual = await settings.codexExecutablePath() {
            guard isExecutable(path: manual) else { throw ProviderFailure.executableMissing }
            return URL(fileURLWithPath: manual)
        }
        let pathCandidates = environmentPath.split(separator: ":")
            .map { String($0) + "/codex" }
        let standardCandidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let match = (pathCandidates + standardCandidates).first(where: isExecutable) else {
            throw ProviderFailure.executableMissing
        }
        return URL(fileURLWithPath: match)
    }

    public func isExecutable(path: String) -> Bool {
        path.hasPrefix("/") && fileManager.isExecutableFile(atPath: path)
    }
}
```

- [ ] **Step 7: Implement the direct JSON-lines child-process boundary**

Create `Sources/AgentPreflightInfrastructure/Codex/FoundationJSONLineProcess.swift`:

```swift
import Foundation
import AgentPreflightApplication

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
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var receiveBuffer = Data()

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

    public func terminate() async {
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

    private nonisolated static func readChunk(from handle: FileHandle) async throws -> Data? {
        try await Task.detached(priority: .utility) {
            try handle.read(upToCount: 4096)
        }.value
    }
}
```

Keep the process direct: never invoke a shell and never place secrets in arguments. Blocking file/process waits stay on the utility detached tasks shown above; cancellation terminates the child and closes stdin.

- [ ] **Step 8: Add failing JSON-RPC handshake, correlation, and failure tests**

Append to `CodexProviderTests.swift`:

```swift
extension CodexProviderTests {
func testAppServerPerformsHandshakeAndCorrelatesRateLimitResponse() async throws {
    let session = JSONLineSessionStub(incoming: [
        Data(#"{"method":"server/notice","params":{}}"#.utf8),
        Data(#"{"id":0,"result":{"userAgent":"codex"}}"#.utf8),
        try fixture("codex-primary-secondary"),
    ])
    let client = CodexAppServerClient(
        launcher: ProcessLauncherStub(session: session),
        timeoutSeconds: 5
    )
    let response = try await client.readRateLimits(
        executableURL: URL(fileURLWithPath: "/fixture/codex")
    )

    XCTAssertEqual(response, try fixture("codex-primary-secondary"))
    let messages = try await session.sentMessages()
    XCTAssertEqual(messages.map(\.method), ["initialize", "initialized", "account/rateLimits/read"])
    XCTAssertEqual(messages.map(\.id), [0, nil, 1])
    let wasTerminated = await session.wasTerminated
    XCTAssertTrue(wasTerminated)
}

func testAppServerMapsEndOfOutputToProcessFailure() async throws {
    let session = JSONLineSessionStub(incoming: [], exitCode: 9)
    let client = CodexAppServerClient(
        launcher: ProcessLauncherStub(session: session),
        timeoutSeconds: 5
    )
    do {
        _ = try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
        XCTFail("Expected process failure")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .processFailure(exitCode: 9))
    }
}

func testAppServerTimeoutTerminatesBlockedProcess() async throws {
    let session = JSONLineSessionStub(incoming: [], blocksOnReceive: true)
    let client = CodexAppServerClient(
        launcher: ProcessLauncherStub(session: session),
        timeoutSeconds: 0.01
    )
    do {
        _ = try await client.readRateLimits(executableURL: URL(fileURLWithPath: "/fixture/codex"))
        XCTFail("Expected timeout")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .timeout)
    }
    let wasTerminated = await session.wasTerminated
    XCTAssertTrue(wasTerminated)
}

func testAppServerRejectsMalformedJSONAndRPCError() async throws {
    let malformed = JSONLineSessionStub(incoming: [Data("not-json".utf8)])
    let malformedClient = CodexAppServerClient(
        launcher: ProcessLauncherStub(session: malformed),
        timeoutSeconds: 5
    )
    do {
        _ = try await malformedClient.readRateLimits(
            executableURL: URL(fileURLWithPath: "/fixture/codex")
        )
        XCTFail("Expected protocol failure")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .protocolFailure)
    }

    let rpcError = JSONLineSessionStub(incoming: [
        Data(#"{"id":0,"error":{"code":-32000}}"#.utf8),
    ])
    let errorClient = CodexAppServerClient(
        launcher: ProcessLauncherStub(session: rpcError),
        timeoutSeconds: 5
    )
    do {
        _ = try await errorClient.readRateLimits(
            executableURL: URL(fileURLWithPath: "/fixture/codex")
        )
        XCTFail("Expected protocol failure")
    } catch let error as ProviderFailure {
        XCTAssertEqual(error, .protocolFailure)
    }
}

func testParserRejectsOutOfRangeUsage() throws {
    let payload = Data(#"""
    {
      "id":1,
      "result":{"rateLimits":{"primary":{
        "usedPercent":101,
        "windowDurationMins":300,
        "resetsAt":1788525000
      }}}
    }
    """#.utf8)
    XCTAssertThrowsError(
        try CodexRateLimitsParser().parse(
            payload,
            fetchedAt: Date(timeIntervalSince1970: 1_788_505_200)
        )
    )
}
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
        XCTAssertEqual(executableURL.path, "/fixture/codex")
        XCTAssertEqual(arguments, ["app-server", "--listen", "stdio://"])
        return session
    }
}
```

- [ ] **Step 9: Implement the app-server handshake and response correlation**

Create `Sources/AgentPreflightInfrastructure/Codex/CodexAppServerClient.swift`:

```swift
import Foundation
import AgentPreflightApplication

public struct CodexAppServerClient: Sendable {
    private let launcher: any JSONLineProcessLaunching
    private let timeoutSeconds: TimeInterval

    public init(launcher: any JSONLineProcessLaunching, timeoutSeconds: TimeInterval) {
        self.launcher = launcher
        self.timeoutSeconds = timeoutSeconds
    }

    public func readRateLimits(executableURL: URL) async throws -> Data {
        let session = try await launcher.launch(
            executableURL: executableURL,
            arguments: ["app-server", "--listen", "stdio://"]
        )
        return try await withTaskCancellationHandler {
            do {
                let result = try await withTimeout(seconds: timeoutSeconds) {
                    try await withTaskCancellationHandler {
                        try await exchange(session: session)
                    } onCancel: {
                        Task { await session.terminate() }
                    }
                }
                await session.terminate()
                return result
            } catch {
                await session.terminate()
                throw error
            }
        } onCancel: {
            Task { await session.terminate() }
        }
    }

    private func exchange(session: any JSONLineProcessSession) async throws -> Data {
        try await session.send(message(method: "initialize", id: 0, params: [
            "clientInfo": [
                "name": "agent_preflight",
                "title": "Agent Preflight",
                "version": "0.1.0",
            ],
        ]))
        _ = try await receiveResponse(id: 0, from: session)
        try await session.send(message(method: "initialized", id: nil, params: [:]))
        try await session.send(message(method: "account/rateLimits/read", id: 1, params: nil))
        return try await receiveResponse(id: 1, from: session)
    }

    private func receiveResponse(id: Int, from session: any JSONLineProcessSession) async throws -> Data {
        while let line = try await session.receive() {
            let header: ResponseHeader
            do { header = try JSONDecoder().decode(ResponseHeader.self, from: line) }
            catch { throw ProviderFailure.protocolFailure }
            guard header.id == id else { continue }
            guard header.error == nil else { throw ProviderFailure.protocolFailure }
            return line
        }
        let exitCode = await session.waitForExit()
        throw ProviderFailure.processFailure(exitCode: exitCode)
    }

    private func message(method: String, id: Int?, params: [String: Any]?) throws -> Data {
        var object: [String: Any] = ["method": method]
        if let id { object["id"] = id }
        if let params { object["params"] = params }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private struct ResponseHeader: Decodable {
        let id: Int?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int
    }
}
```

- [ ] **Step 10: Implement Codex response normalization**

Create `Sources/AgentPreflightInfrastructure/Codex/CodexRateLimitsParser.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

public struct CodexRateLimitsParser: Sendable {
    public static let weeklyDurationMinutes = 10_080
    public init() {}

    public func parse(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.error == nil, let limits = selectedLimits(from: envelope.result) else {
                throw ProviderFailure.unsupportedPayload
            }
            let windows = try [limits.primary, limits.secondary]
                .compactMap { $0 }
                .map(map)
            guard !windows.isEmpty else { throw ProviderFailure.unsupportedPayload }
            return try QuotaSnapshot(provider: .codex, windows: windows, fetchedAt: fetchedAt)
        } catch let error as ProviderFailure {
            throw error
        } catch {
            throw ProviderFailure.unsupportedPayload
        }
    }

    private func selectedLimits(from result: ResultBody?) -> Limits? {
        if let direct = result?.rateLimits { return direct }
        if let codex = result?.rateLimitsByLimitId?["codex"] { return codex }
        guard let grouped = result?.rateLimitsByLimitId, grouped.count == 1 else { return nil }
        return grouped.values.first
    }

    private func map(_ window: Window) throws -> QuotaWindow {
        guard window.windowDurationMins > 0, window.resetsAt > 0 else {
            throw ProviderFailure.unsupportedPayload
        }
        let kind: QuotaWindowKind = window.windowDurationMins >= Self.weeklyDurationMinutes
            ? .weekly
            : .short
        return QuotaWindow(
            kind: kind,
            remaining: try RemainingPercentage.fromUsed(window.usedPercent),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetsAt))
        )
    }

    private struct Envelope: Decodable {
        let result: ResultBody?
        let error: RPCError?
    }
    private struct RPCError: Decodable { let code: Int }
    private struct ResultBody: Decodable {
        let rateLimits: Limits?
        let rateLimitsByLimitId: [String: Limits]?
    }
    private struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
    }
    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: Int64
    }
}
```

- [ ] **Step 11: Compose the Codex quota provider**

Create `Sources/AgentPreflightInfrastructure/Codex/CodexQuotaProvider.swift`:

```swift
import AgentPreflightApplication
import AgentPreflightDomain

public struct CodexQuotaProvider: QuotaProvider {
    public let identifier = ProviderIdentifier.codex
    private let locator: any CodexExecutableLocating
    private let client: CodexAppServerClient
    private let parser: CodexRateLimitsParser
    private let clock: any Clock

    public init(
        locator: any CodexExecutableLocating,
        client: CodexAppServerClient,
        parser: CodexRateLimitsParser,
        clock: any Clock
    ) {
        self.locator = locator
        self.client = client
        self.parser = parser
        self.clock = clock
    }

    public func fetchSnapshot() async throws -> QuotaSnapshot {
        let executable = try await locator.locate()
        let response = try await client.readRateLimits(executableURL: executable)
        return try parser.parse(response, fetchedAt: clock.now())
    }
}
```

- [ ] **Step 12: Run deterministic Codex adapter tests**

Run: `swift test --filter CodexProviderTests`

Expected: PASS for duration mapping, primary-only behavior, manual path precedence, handshake ordering, response correlation, termination, and non-zero exit.

- [ ] **Step 13: Add the opt-in live Codex smoke test**

Add this opt-in test:

```swift
extension CodexProviderTests {
func testLiveCodexUsageWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["AGENT_PREFLIGHT_LIVE_CODEX"] == "1" else {
        throw XCTSkip("Set AGENT_PREFLIGHT_LIVE_CODEX=1 for an explicit app-server smoke test")
    }
    let suiteName = "AgentPreflightLiveCodexTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = UserDefaultsAppSettingsStore(defaults: defaults)
    let provider = CodexQuotaProvider(
        locator: CodexExecutableLocator(settings: settings),
        client: CodexAppServerClient(
            launcher: FoundationJSONLineProcessLauncher(),
            timeoutSeconds: 5
        ),
        parser: CodexRateLimitsParser(),
        clock: SystemClock()
    )
    let snapshot = try await provider.fetchSnapshot()
    XCTAssertFalse(snapshot.windows.isEmpty)
}
}
```

- [ ] **Step 14: Run live Codex verification**

Run explicitly: `AGENT_PREFLIGHT_LIVE_CODEX=1 swift test --filter testLiveCodexUsageWhenExplicitlyEnabled`

Expected: PASS with one or two available windows. A legitimate weekly-only response passes and is handled later as incomplete for recommendation.

- [ ] **Step 15: Commit the Codex adapter**

```bash
git add Sources/AgentPreflightApplication/AppSettingsStore.swift Sources/AgentPreflightInfrastructure Tests/AgentPreflightInfrastructureTests
git commit -m "feat: add Codex app-server quota adapter"
```

---

### Task 4: Implement the Deterministic S/M/L Recommendation Engine

**Files:**
- Create: `Sources/AgentPreflightDomain/TaskSizePolicy.swift`
- Create: `Sources/AgentPreflightDomain/Recommendation.swift`
- Create: `Sources/AgentPreflightDomain/RecommendationEngine.swift`
- Create: `Tests/AgentPreflightDomainTests/RecommendationEngineTests.swift`

**Interfaces:**
- Consumes: complete `QuotaSnapshot` values from Tasks 2 and 3.
- Produces: `TaskSize`, `ReserveRequirement`, `TaskSizePolicy.default`, `RecommendationDecision`, `RecommendationReason`, `ConstraintFailure`, and `RecommendationEngine.recommend(taskSize:snapshots:staleProviders:now:)`.

- [ ] **Step 1: Write failing policy and decision tests**

Create `Tests/AgentPreflightDomainTests/RecommendationEngineTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentPreflightDomain

final class RecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_505_200)

    func testDefaultPolicyContainsExactApprovedReserves() {
        let policy = TaskSizePolicy.default
        XCTAssertEqual(policy.requirement(for: .small), .init(short: 15, weekly: 5))
        XCTAssertEqual(policy.requirement(for: .medium), .init(short: 35, weekly: 10))
        XCTAssertEqual(policy.requirement(for: .large), .init(short: 60, weekly: 20))
        XCTAssertEqual(policy.neutralTolerance, 0.10)
    }

    func testOnlySafeProviderIsRecommendedAtExactBoundary() throws {
        let result = RecommendationEngine().recommend(
            taskSize: .medium,
            snapshots: [
                .codex: try snapshot(.codex, short: 35, weekly: 10),
                .claudeCode: try snapshot(.claudeCode, short: 34, weekly: 40),
            ],
            staleProviders: [],
            now: now
        )
        XCTAssertEqual(result.decision, .provider(.codex))
        XCTAssertEqual(result.reason, .onlySafe(.codex))
    }

    func testLargerMinimumSafetyMarginWins() throws {
        let result = RecommendationEngine().recommend(
            taskSize: .small,
            snapshots: [
                .codex: try snapshot(.codex, short: 45, weekly: 15),
                .claudeCode: try snapshot(.claudeCode, short: 30, weekly: 10),
            ],
            staleProviders: [],
            now: now
        )
        XCTAssertEqual(result.decision, .provider(.codex))
        XCTAssertEqual(result.reason, .largerMargin(.codex))
    }

    func testDifferenceBelowToleranceIsNeutral() throws {
        let result = RecommendationEngine().recommend(
            taskSize: .small,
            snapshots: [
                .codex: try snapshot(.codex, short: 30, weekly: 10),
                .claudeCode: try snapshot(.claudeCode, short: 31, weekly: 10.2),
            ],
            staleProviders: [],
            now: now
        )
        XCTAssertEqual(result.decision, .neutral)
        XCTAssertEqual(result.reason, .marginsWithinTolerance)
    }

    func testDifferenceAtToleranceChoosesLargerMargin() throws {
        let result = RecommendationEngine().recommend(
            taskSize: .small,
            snapshots: [
                .codex: try snapshot(.codex, short: 30, weekly: 10),
                .claudeCode: try snapshot(.claudeCode, short: 31.5, weekly: 10.5),
            ],
            staleProviders: [],
            now: now
        )
        XCTAssertEqual(result.decision, .provider(.claudeCode))
        XCTAssertEqual(result.reason, .largerMargin(.claudeCode))
    }

    func testNeitherSafeReturnsEveryFailedConstraintAndNearestReset() throws {
        let codex = try snapshot(.codex, short: 20, weekly: 9, shortReset: 900, weeklyReset: 3_600)
        let claude = try snapshot(.claudeCode, short: 34, weekly: 8, shortReset: 1_800, weeklyReset: 7_200)
        let result = RecommendationEngine().recommend(
            taskSize: .medium,
            snapshots: [.codex: codex, .claudeCode: claude],
            staleProviders: [],
            now: now
        )
        XCTAssertEqual(result.decision, .noSafeChoice)
        XCTAssertEqual(result.failures.count, 4)
        XCTAssertEqual(result.nearestRelevantReset, now.addingTimeInterval(900))
    }

    func testMissingStaleOrPassedWindowMakesRecommendationUnavailable() throws {
        let complete = try snapshot(.codex, short: 90, weekly: 90)
        let partial = try partialSnapshot(.claudeCode, weekly: 90)
        XCTAssertEqual(
            RecommendationEngine().recommend(
                taskSize: .small,
                snapshots: [.codex: complete, .claudeCode: partial],
                staleProviders: [],
                now: now
            ).decision,
            .unavailable
        )
        let passedReset = try snapshot(
            .claudeCode,
            short: 90,
            weekly: 90,
            shortReset: -1
        )
        XCTAssertEqual(
            RecommendationEngine().recommend(
                taskSize: .small,
                snapshots: [.codex: complete, .claudeCode: passedReset],
                staleProviders: [],
                now: now
            ).decision,
            .unavailable
        )
        XCTAssertEqual(
            RecommendationEngine().recommend(
                taskSize: .small,
                snapshots: [.codex: complete, .claudeCode: try snapshot(.claudeCode, short: 90, weekly: 90)],
                staleProviders: [.claudeCode],
                now: now
            ).decision,
            .unavailable
        )
    }

    private func snapshot(
        _ provider: ProviderIdentifier,
        short: Double,
        weekly: Double,
        shortReset: TimeInterval = 3_600,
        weeklyReset: TimeInterval = 86_400
    ) throws -> QuotaSnapshot {
        try QuotaSnapshot(provider: provider, windows: [
            QuotaWindow(kind: .short, remaining: .init(remaining: short), resetsAt: now.addingTimeInterval(shortReset)),
            QuotaWindow(kind: .weekly, remaining: .init(remaining: weekly), resetsAt: now.addingTimeInterval(weeklyReset)),
        ], fetchedAt: now)
    }

    private func partialSnapshot(_ provider: ProviderIdentifier, weekly: Double) throws -> QuotaSnapshot {
        try QuotaSnapshot(provider: provider, windows: [
            QuotaWindow(kind: .weekly, remaining: .init(remaining: weekly), resetsAt: now.addingTimeInterval(86_400)),
        ], fetchedAt: now)
    }
}
```

- [ ] **Step 2: Run tests and confirm the expected compile failure**

Run: `swift test --filter RecommendationEngineTests`

Expected: FAIL because policy and recommendation types do not exist.

- [ ] **Step 3: Implement the centralized task-size policy**

Create `Sources/AgentPreflightDomain/TaskSizePolicy.swift`:

```swift
public enum TaskSize: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large
}

public struct ReserveRequirement: Equatable, Sendable {
    public let short: Double
    public let weekly: Double
    public init(short: Double, weekly: Double) {
        self.short = short
        self.weekly = weekly
    }
}

public struct TaskSizePolicy: Equatable, Sendable {
    public let small: ReserveRequirement
    public let medium: ReserveRequirement
    public let large: ReserveRequirement
    public let neutralTolerance: Double

    public init(
        small: ReserveRequirement,
        medium: ReserveRequirement,
        large: ReserveRequirement,
        neutralTolerance: Double
    ) {
        self.small = small
        self.medium = medium
        self.large = large
        self.neutralTolerance = neutralTolerance
    }

    public static let `default` = Self(
        small: .init(short: 15, weekly: 5),
        medium: .init(short: 35, weekly: 10),
        large: .init(short: 60, weekly: 20),
        neutralTolerance: 0.10
    )

    public func requirement(for size: TaskSize) -> ReserveRequirement {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }
}
```

- [ ] **Step 4: Implement structured recommendation result values**

Create `Sources/AgentPreflightDomain/Recommendation.swift`:

```swift
import Foundation

public enum RecommendationDecision: Equatable, Sendable {
    case provider(ProviderIdentifier)
    case neutral
    case noSafeChoice
    case unavailable
}

public enum RecommendationReason: Equatable, Sendable {
    case onlySafe(ProviderIdentifier)
    case largerMargin(ProviderIdentifier)
    case marginsWithinTolerance
    case insufficientQuota
    case incompleteOrStaleData
}

public struct ConstraintFailure: Equatable, Sendable {
    public let provider: ProviderIdentifier
    public let window: QuotaWindowKind
    public let remaining: Double
    public let required: Double
    public let resetsAt: Date
}

public struct Recommendation: Equatable, Sendable {
    public let decision: RecommendationDecision
    public let reason: RecommendationReason
    public let failures: [ConstraintFailure]
    public let nearestRelevantReset: Date?
}
```

- [ ] **Step 5: Implement the minimum-margin algorithm**

Create `Sources/AgentPreflightDomain/RecommendationEngine.swift`:

```swift
import Foundation

public struct RecommendationEngine: Sendable {
    private let policy: TaskSizePolicy
    public init(policy: TaskSizePolicy = .default) { self.policy = policy }

    public func recommend(
        taskSize: TaskSize,
        snapshots: [ProviderIdentifier: QuotaSnapshot],
        staleProviders: Set<ProviderIdentifier>,
        now: Date
    ) -> Recommendation {
        guard staleProviders.isEmpty,
              let codex = assess(.codex, snapshots: snapshots, taskSize: taskSize, now: now),
              let claude = assess(.claudeCode, snapshots: snapshots, taskSize: taskSize, now: now)
        else {
            return unavailable()
        }
        return decide(codex, claude)
    }

    private func assess(
        _ provider: ProviderIdentifier,
        snapshots: [ProviderIdentifier: QuotaSnapshot],
        taskSize: TaskSize,
        now: Date
    ) -> Assessment? {
        guard let snapshot = snapshots[provider],
              let short = snapshot.window(.short, validAt: now),
              let weekly = snapshot.window(.weekly, validAt: now)
        else { return nil }
        let required = policy.requirement(for: taskSize)
        let failures = [
            failure(provider, window: short, required: required.short),
            failure(provider, window: weekly, required: required.weekly),
        ].compactMap { $0 }
        let margin = min(
            short.remaining.value / required.short,
            weekly.remaining.value / required.weekly
        )
        return Assessment(provider: provider, margin: margin, failures: failures)
    }

    private func failure(
        _ provider: ProviderIdentifier,
        window: QuotaWindow,
        required: Double
    ) -> ConstraintFailure? {
        guard window.remaining.value < required else { return nil }
        return ConstraintFailure(
            provider: provider,
            window: window.kind,
            remaining: window.remaining.value,
            required: required,
            resetsAt: window.resetsAt
        )
    }

    private func decide(_ first: Assessment, _ second: Assessment) -> Recommendation {
        if first.isSafe != second.isSafe {
            let winner = first.isSafe ? first.provider : second.provider
            return .init(decision: .provider(winner), reason: .onlySafe(winner), failures: [], nearestRelevantReset: nil)
        }
        if first.isSafe {
            guard abs(first.margin - second.margin) >= policy.neutralTolerance else {
                return .init(decision: .neutral, reason: .marginsWithinTolerance, failures: [], nearestRelevantReset: nil)
            }
            let winner = first.margin > second.margin ? first.provider : second.provider
            return .init(decision: .provider(winner), reason: .largerMargin(winner), failures: [], nearestRelevantReset: nil)
        }
        let failures = first.failures + second.failures
        return .init(
            decision: .noSafeChoice,
            reason: .insufficientQuota,
            failures: failures,
            nearestRelevantReset: failures.map(\.resetsAt).min()
        )
    }

    private func unavailable() -> Recommendation {
        .init(
            decision: .unavailable,
            reason: .incompleteOrStaleData,
            failures: [],
            nearestRelevantReset: nil
        )
    }

    private struct Assessment {
        let provider: ProviderIdentifier
        let margin: Double
        let failures: [ConstraintFailure]
        var isSafe: Bool { failures.isEmpty }
    }
}
```

- [ ] **Step 6: Run all domain tests**

Run: `swift test --filter AgentPreflightDomainTests`

Expected: PASS for all three policies, exact thresholds, only-safe, larger-margin, neutral, neither-safe, missing, stale, and passed-reset inputs.

- [ ] **Step 7: Commit the recommendation engine**

```bash
git add Sources/AgentPreflightDomain Tests/AgentPreflightDomainTests
git commit -m "feat: recommend provider by quota margin"
```

---

### Task 5: Coordinate Concurrent Refresh, Cooldown, Staleness, and Failure Isolation

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgentPreflightApplication/QuotaCache.swift`
- Create: `Sources/AgentPreflightApplication/Diagnostics.swift`
- Create: `Sources/AgentPreflightApplication/RefreshModels.swift`
- Create: `Sources/AgentPreflightApplication/RefreshQuotaUseCase.swift`
- Create: `Tests/AgentPreflightApplicationTests/RefreshQuotaUseCaseTests.swift`

**Interfaces:**
- Consumes: `[any QuotaProvider]`, `QuotaCache`, `Clock`, and typed `ProviderFailure`.
- Produces: `RefreshConfiguration.live`, `SnapshotFreshness`, `ProviderStatus`, `RefreshResult`, `RefreshQuotaUseCaseProtocol.current()` and `.refresh()`.

- [ ] **Step 1: Add the application test target**

Add to `Package.swift`:

```swift
.testTarget(
    name: "AgentPreflightApplicationTests",
    dependencies: ["AgentPreflightDomain", "AgentPreflightApplication"]
),
```

- [ ] **Step 2: Write failing refresh-orchestration tests and doubles**

Create `Tests/AgentPreflightApplicationTests/RefreshQuotaUseCaseTests.swift` with deterministic actors:

```swift
import Foundation
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain

final class RefreshQuotaUseCaseTests: XCTestCase {
    func testProvidersRefreshConcurrentlyAndSucceedIndependently() async throws {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
        let probe = ConcurrencyProbe()
        let codex = ProviderStub(identifier: .codex, result: .success(try snapshot(.codex, at: clock.now())), probe: probe)
        let claude = ProviderStub(identifier: .claudeCode, result: .failure(.unauthorized), probe: probe)
        let useCase = RefreshQuotaUseCase(
            providers: [codex, claude], cache: MemoryCache(), clock: clock,
            diagnostics: DiagnosticsSpy(), configuration: .live
        )

        let result = await useCase.refresh()
        XCTAssertEqual(result.statuses[.codex]?.freshness, .current)
        XCTAssertEqual(result.statuses[.claudeCode]?.failure, .unauthorized)
        let maximumConcurrentCalls = await probe.maximumConcurrentCalls
        XCTAssertEqual(maximumConcurrentCalls, 2)
    }

    func testSecondRefreshWithinCooldownDoesNotCallProvidersAgain() async throws {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
        let provider = ProviderStub(identifier: .codex, result: .success(try snapshot(.codex, at: clock.now())))
        let useCase = RefreshQuotaUseCase(
            providers: [provider], cache: MemoryCache(), clock: clock,
            diagnostics: DiagnosticsSpy(), configuration: .live
        )
        _ = await useCase.refresh()
        _ = await useCase.refresh()
        let callsInsideCooldown = await provider.callCount
        XCTAssertEqual(callsInsideCooldown, 1)
        clock.advance(by: 31)
        _ = await useCase.refresh()
        let callsAfterCooldown = await provider.callCount
        XCTAssertEqual(callsAfterCooldown, 2)
    }

    func testFailedRefreshKeepsLastSnapshotButMarksItStale() async throws {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
        let cached = try snapshot(.claudeCode, at: clock.now().addingTimeInterval(-60))
        let cache = MemoryCache(initial: [.claudeCode: cached])
        let provider = ProviderStub(identifier: .claudeCode, result: .failure(.networkUnavailable))
        let useCase = RefreshQuotaUseCase(
            providers: [provider], cache: cache, clock: clock,
            diagnostics: DiagnosticsSpy(), configuration: .live
        )
        _ = await useCase.current()
        let result = await useCase.refresh()
        XCTAssertEqual(result.statuses[.claudeCode]?.snapshot, cached)
        XCTAssertEqual(result.statuses[.claudeCode]?.freshness, .stale)
        XCTAssertFalse(result.eligibleSnapshots.keys.contains(.claudeCode))
    }

    func testSnapshotOlderThanFifteenMinutesIsStale() async throws {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200))
        let cached = try snapshot(.codex, at: clock.now().addingTimeInterval(-901))
        let useCase = RefreshQuotaUseCase(
            providers: [], cache: MemoryCache(initial: [.codex: cached]), clock: clock,
            diagnostics: DiagnosticsSpy(), configuration: .live
        )
        let result = await useCase.current()
        XCTAssertEqual(result.statuses[.codex]?.freshness, .stale)
    }

    func testCacheFailuresEmitOnlyTypedDiagnostics() async {
        let diagnostics = DiagnosticsSpy()
        let useCase = RefreshQuotaUseCase(
            providers: [],
            cache: FailingCache(),
            clock: MutableClock(now: Date(timeIntervalSince1970: 1_788_505_200)),
            diagnostics: diagnostics,
            configuration: .live
        )
        _ = await useCase.current()
        _ = await useCase.refresh()
        let events = await diagnostics.events
        XCTAssertEqual(events, [.cacheReadFailed, .cacheWriteFailed])
    }

    private func snapshot(_ provider: ProviderIdentifier, at fetchedAt: Date) throws -> QuotaSnapshot {
        try QuotaSnapshot(provider: provider, windows: [
            QuotaWindow(
                kind: .short,
                remaining: .init(remaining: 70),
                resetsAt: fetchedAt.addingTimeInterval(3_600)
            ),
            QuotaWindow(
                kind: .weekly,
                remaining: .init(remaining: 60),
                resetsAt: fetchedAt.addingTimeInterval(86_400)
            ),
        ], fetchedAt: fetchedAt)
    }
}

private final class MutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) { self.current = now }
    func now() -> Date { lock.withLock { current } }
    func advance(by interval: TimeInterval) { lock.withLock { current.addTimeInterval(interval) } }
}

private actor ProviderStub: QuotaProvider {
    nonisolated let identifier: ProviderIdentifier
    private let result: Result<QuotaSnapshot, ProviderFailure>
    private let probe: ConcurrencyProbe?
    private(set) var callCount = 0

    init(
        identifier: ProviderIdentifier,
        result: Result<QuotaSnapshot, ProviderFailure>,
        probe: ConcurrencyProbe? = nil
    ) {
        self.identifier = identifier
        self.result = result
        self.probe = probe
    }

    func fetchSnapshot() async throws -> QuotaSnapshot {
        callCount += 1
        if let probe { await probe.enter() }
        do { try await Task.sleep(for: .milliseconds(20)) }
        catch {
            if let probe { await probe.leave() }
            throw error
        }
        if let probe { await probe.leave() }
        return try result.get()
    }
}

private actor MemoryCache: QuotaCache {
    private var snapshots: [ProviderIdentifier: QuotaSnapshot]
    init(initial: [ProviderIdentifier: QuotaSnapshot] = [:]) { snapshots = initial }
    func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { snapshots }
    func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws { self.snapshots = snapshots }
}

private actor FailingCache: QuotaCache {
    private enum Failure: Error { case unavailable }
    func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { throw Failure.unavailable }
    func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws { throw Failure.unavailable }
}

private actor ConcurrencyProbe {
    private var concurrentCalls = 0
    private(set) var maximumConcurrentCalls = 0

    func enter() {
        concurrentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, concurrentCalls)
    }

    func leave() { concurrentCalls -= 1 }
}

private actor DiagnosticsSpy: DiagnosticsSink {
    private(set) var events: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) async { events.append(event) }
}
```

- [ ] **Step 3: Run orchestration tests and confirm the expected compile failure**

Run: `swift test --filter RefreshQuotaUseCaseTests`

Expected: FAIL because refresh/cache/diagnostic types do not exist.

- [ ] **Step 4: Define the normalized quota-cache boundary**

Create `Sources/AgentPreflightApplication/QuotaCache.swift`:

```swift
import AgentPreflightDomain

public protocol QuotaCache: Sendable {
    func load() async throws -> [ProviderIdentifier: QuotaSnapshot]
    func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws
}
```

- [ ] **Step 5: Define typed diagnostic events**

Create `Sources/AgentPreflightApplication/Diagnostics.swift`:

```swift
import AgentPreflightDomain

public enum DiagnosticEvent: Equatable, Sendable, CustomStringConvertible {
    case providerFailed(ProviderIdentifier, ProviderFailure)
    case cacheReadFailed
    case cacheWriteFailed

    public var description: String {
        switch self {
        case let .providerFailed(provider, failure): "provider=\(provider.rawValue) failure=\(failure)"
        case .cacheReadFailed: "cache read failed"
        case .cacheWriteFailed: "cache write failed"
        }
    }
}

public protocol DiagnosticsSink: Sendable {
    func record(_ event: DiagnosticEvent) async
}
```

- [ ] **Step 6: Define refresh configuration and result values**

Create `Sources/AgentPreflightApplication/RefreshModels.swift`:

```swift
import Foundation
import AgentPreflightDomain

public struct RefreshConfiguration: Equatable, Sendable {
    public let providerTimeout: TimeInterval
    public let cooldown: TimeInterval
    public let staleAfter: TimeInterval
    public static let live = Self(providerTimeout: 5, cooldown: 30, staleAfter: 15 * 60)
}

public enum SnapshotFreshness: Equatable, Sendable {
    case current
    case cached
    case stale
    case unavailable
}

public struct ProviderStatus: Equatable, Sendable {
    public let provider: ProviderIdentifier
    public let snapshot: QuotaSnapshot?
    public let freshness: SnapshotFreshness
    public let failure: ProviderFailure?
}

public struct RefreshResult: Equatable, Sendable {
    public let statuses: [ProviderIdentifier: ProviderStatus]
    public let completedAt: Date

    public var eligibleSnapshots: [ProviderIdentifier: QuotaSnapshot] {
        statuses.compactMapValues { status in
            guard status.failure == nil,
                  status.freshness == .current || status.freshness == .cached
            else { return nil }
            return status.snapshot
        }
    }

    public var staleProviders: Set<ProviderIdentifier> {
        Set(statuses.values.filter { $0.freshness == .stale }.map(\.provider))
    }
}
```

- [ ] **Step 7: Implement the concurrent refresh actor**

Create `Sources/AgentPreflightApplication/RefreshQuotaUseCase.swift`:

```swift
import Foundation
import AgentPreflightDomain

public protocol RefreshQuotaUseCaseProtocol: Sendable {
    func current() async -> RefreshResult
    func refresh() async -> RefreshResult
}

public actor RefreshQuotaUseCase: RefreshQuotaUseCaseProtocol {
    private let providers: [any QuotaProvider]
    private let cache: any QuotaCache
    private let clock: any Clock
    private let diagnostics: any DiagnosticsSink
    private let configuration: RefreshConfiguration
    private var snapshots: [ProviderIdentifier: QuotaSnapshot] = [:]
    private var failures: [ProviderIdentifier: ProviderFailure] = [:]
    private var lastAttemptAt: Date?
    private var lastRefreshedProviders = Set<ProviderIdentifier>()
    private var didLoadCache = false

    public init(
        providers: [any QuotaProvider],
        cache: any QuotaCache,
        clock: any Clock,
        diagnostics: any DiagnosticsSink,
        configuration: RefreshConfiguration
    ) {
        self.providers = providers
        self.cache = cache
        self.clock = clock
        self.diagnostics = diagnostics
        self.configuration = configuration
    }

    public func current() async -> RefreshResult {
        await loadCacheIfNeeded()
        return makeResult(at: clock.now(), refreshedProviders: [])
    }

    public func refresh() async -> RefreshResult {
        await loadCacheIfNeeded()
        let now = clock.now()
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < configuration.cooldown {
            return makeResult(at: now, refreshedProviders: lastRefreshedProviders)
        }
        lastAttemptAt = now
        let outcomes = await fetchProviders()
        var refreshed = Set<ProviderIdentifier>()
        for (provider, outcome) in outcomes {
            switch outcome {
            case let .success(snapshot):
                snapshots[provider] = snapshot
                failures[provider] = nil
                refreshed.insert(provider)
            case let .failure(failure):
                failures[provider] = failure
                await diagnostics.record(.providerFailed(provider, failure))
            }
        }
        lastRefreshedProviders = refreshed
        await persistSnapshots()
        return makeResult(at: clock.now(), refreshedProviders: refreshed)
    }

    private func fetchProviders() async -> [(ProviderIdentifier, Result<QuotaSnapshot, ProviderFailure>)] {
        await withTaskGroup(of: (ProviderIdentifier, Result<QuotaSnapshot, ProviderFailure>).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let snapshot = try await provider.fetchSnapshot()
                        guard snapshot.provider == provider.identifier else {
                            return (provider.identifier, .failure(.protocolFailure))
                        }
                        return (provider.identifier, .success(snapshot))
                    }
                    catch let failure as ProviderFailure { return (provider.identifier, .failure(failure)) }
                    catch { return (provider.identifier, .failure(.protocolFailure)) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }

    private func loadCacheIfNeeded() async {
        guard !didLoadCache else { return }
        didLoadCache = true
        do { snapshots = try await cache.load() }
        catch { await diagnostics.record(.cacheReadFailed) }
    }

    private func persistSnapshots() async {
        do { try await cache.save(snapshots) }
        catch { await diagnostics.record(.cacheWriteFailed) }
    }

    private func makeResult(at now: Date, refreshedProviders: Set<ProviderIdentifier>) -> RefreshResult {
        let statuses = Dictionary(uniqueKeysWithValues: ProviderIdentifier.allCases.map { provider in
            let snapshot = snapshots[provider]
            let freshness = freshness(of: snapshot, provider: provider, refreshed: refreshedProviders, now: now)
            return (provider, ProviderStatus(
                provider: provider, snapshot: snapshot, freshness: freshness, failure: failures[provider]
            ))
        })
        return RefreshResult(statuses: statuses, completedAt: now)
    }

    private func freshness(
        of snapshot: QuotaSnapshot?,
        provider: ProviderIdentifier,
        refreshed: Set<ProviderIdentifier>,
        now: Date
    ) -> SnapshotFreshness {
        guard let snapshot else { return .unavailable }
        if failures[provider] != nil || now.timeIntervalSince(snapshot.fetchedAt) > configuration.staleAfter {
            return .stale
        }
        return refreshed.contains(provider) ? .current : .cached
    }
}
```

- [ ] **Step 8: Run application and full unit tests**

Run: `swift test --filter RefreshQuotaUseCaseTests`

Expected: PASS for concurrent starts, provider isolation, cooldown, cache retention, and 15-minute staleness.

Run: `swift test`

Expected: all deterministic tests PASS; two live tests SKIP unless explicitly enabled.

- [ ] **Step 9: Commit refresh orchestration**

```bash
git add Package.swift Sources/AgentPreflightApplication Tests/AgentPreflightApplicationTests
git commit -m "feat: coordinate quota refresh and freshness"
```

---

### Task 6: Persist a Permission-Hardened Numeric Cache and Typed Diagnostics

**Files:**
- Create: `Sources/AgentPreflightInfrastructure/Cache/JSONQuotaCache.swift`
- Create: `Sources/AgentPreflightInfrastructure/Diagnostics/OSDiagnosticsSink.swift`
- Create: `Tests/AgentPreflightInfrastructureTests/JSONQuotaCacheTests.swift`
- Create: `Tests/AgentPreflightInfrastructureTests/SecurityBoundaryTests.swift`

**Interfaces:**
- Consumes: `QuotaCache`, `DiagnosticEvent`, and normalized `QuotaSnapshot` values.
- Produces: `JSONQuotaCache.live()`, `JSONQuotaCache(directory:fileManager:)`, and `OSDiagnosticsSink`.

- [ ] **Step 1: Write the failing cache round-trip and permission test**

Create `Tests/AgentPreflightInfrastructureTests/JSONQuotaCacheTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

final class JSONQuotaCacheTests: XCTestCase {
    func testRoundTripCreatesPrivateDirectoryAndFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let cache = JSONQuotaCache(directory: directory)
        let fetchedAt = Date(timeIntervalSince1970: 1_788_505_200)
        let snapshot = try QuotaSnapshot(provider: .codex, windows: [
            QuotaWindow(kind: .short, remaining: .init(remaining: 70), resetsAt: fetchedAt.addingTimeInterval(600)),
        ], fetchedAt: fetchedAt)

        try await cache.save([.codex: snapshot])
        let loadedSnapshots = try await cache.load()
        XCTAssertEqual(loadedSnapshots[.codex], snapshot)
        XCTAssertEqual(try permissions(directory), 0o700)
        XCTAssertEqual(try permissions(directory.appendingPathComponent("quota-cache-v1.json")), 0o600)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
```

- [ ] **Step 2: Write failing credential, diagnostic, and cache-content tests**

Create `Tests/AgentPreflightInfrastructureTests/SecurityBoundaryTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightInfrastructure

final class SecurityBoundaryTests: XCTestCase {
    func testSensitiveTokenAlwaysDescribesItselfAsRedacted() throws {
        let token = try SensitiveToken("sk-ant-fixture-secret")
        XCTAssertEqual(String(describing: token), "<redacted>")
        XCTAssertEqual(String(reflecting: token), "<redacted>")
    }

    func testDiagnosticEventsCannotCarryRawErrorsOrSecrets() {
        let rendered = DiagnosticEvent.providerFailed(.claudeCode, .unauthorized).description
        XCTAssertEqual(rendered, "provider=claudeCode failure=unauthorized")
        XCTAssertFalse(rendered.contains("sk-ant-fixture-secret"))
    }

    func testCacheJSONContainsOnlyNormalizedSnapshotFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let cache = JSONQuotaCache(directory: directory)
        try await cache.save([:])
        let text = try String(contentsOf: directory.appendingPathComponent("quota-cache-v1.json"))
        for forbidden in ["accessToken", "refreshToken", "Authorization", "Cookie"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden))
        }
    }
}
```

- [ ] **Step 3: Run tests and confirm the expected compile failure**

Run: `swift test --filter JSONQuotaCacheTests && swift test --filter SecurityBoundaryTests`

Expected: FAIL because the cache and OS diagnostics implementation do not exist.

- [ ] **Step 4: Implement atomic JSON storage and permissions**

Create `Sources/AgentPreflightInfrastructure/Cache/JSONQuotaCache.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

public actor JSONQuotaCache: QuotaCache {
    public static let fileName = "quota-cache-v1.json"
    private let directory: URL
    private let fileManager: FileManager
    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func live(fileManager: FileManager = .default) throws -> JSONQuotaCache {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return JSONQuotaCache(directory: base.appendingPathComponent("Agent Preflight", isDirectory: true))
    }

    public func load() async throws -> [ProviderIdentifier: QuotaSnapshot] {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.version == 1 else { throw CacheError.unsupportedVersion }
        var snapshots: [ProviderIdentifier: QuotaSnapshot] = [:]
        for snapshot in envelope.snapshots {
            guard snapshots.updateValue(snapshot, forKey: snapshot.provider) == nil else {
                throw CacheError.duplicateProvider
            }
        }
        return snapshots
    }

    public func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws {
        try ensureDirectory()
        let envelope = Envelope(version: 1, snapshots: snapshots.values.sorted {
            $0.provider.rawValue < $1.provider.rawValue
        })
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
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
```

- [ ] **Step 5: Implement typed OSLog output with no raw-error input**

Create `Sources/AgentPreflightInfrastructure/Diagnostics/OSDiagnosticsSink.swift`:

```swift
import OSLog
import AgentPreflightApplication

public actor OSDiagnosticsSink: DiagnosticsSink {
    private let logger: Logger

    public init(subsystem: String = "com.agentpreflight.app", category: String = "runtime") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(_ event: DiagnosticEvent) async {
        logger.error("\(event.description, privacy: .public)")
    }
}
```

- [ ] **Step 6: Run cache, security, and complete tests**

Run: `swift test --filter JSONQuotaCacheTests`

Expected: PASS with directory mode `0700` and file mode `0600`.

Run: `swift test --filter SecurityBoundaryTests`

Expected: PASS; no secret-bearing interface is available to diagnostics or cache.

Run: `swift test`

Expected: all deterministic tests PASS and live tests SKIP.

- [ ] **Step 7: Commit secure local persistence**

```bash
git add Sources/AgentPreflightInfrastructure/Cache Sources/AgentPreflightInfrastructure/Diagnostics Tests/AgentPreflightInfrastructureTests
git commit -m "feat: persist private quota cache"
```

---

### Task 7: Build Presentation Models, Recovery Copy, and Settings Validation

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgentPreflightPresentation/PresentationModels.swift`
- Create: `Sources/AgentPreflightPresentation/PresentationFormatter.swift`
- Create: `Sources/AgentPreflightPresentation/ErrorCopy.swift`
- Create: `Sources/AgentPreflightPresentation/AppViewModel.swift`
- Create: `Sources/AgentPreflightPresentation/SettingsViewModel.swift`
- Create: `Tests/AgentPreflightPresentationTests/AppViewModelTests.swift`

**Interfaces:**
- Consumes: `RefreshQuotaUseCaseProtocol`, `RecommendationEngine`, `AppSettingsStore`, `CodexExecutableLocating`, and `Clock`.
- Produces: `ProviderCardModel`, `QuotaRowModel`, `RecommendationModel`, `PresentationFormatter`, `AppViewModel`, and `SettingsViewModel` for SwiftUI only.

- [ ] **Step 1: Add the presentation library and test targets**

Add to `Package.swift`:

```swift
.library(name: "AgentPreflightPresentation", targets: ["AgentPreflightPresentation"]),
```

Add target declarations:

```swift
.target(
    name: "AgentPreflightPresentation",
    dependencies: ["AgentPreflightDomain", "AgentPreflightApplication"]
),
.testTarget(
    name: "AgentPreflightPresentationTests",
    dependencies: ["AgentPreflightDomain", "AgentPreflightApplication", "AgentPreflightPresentation"]
),
```

- [ ] **Step 2: Write failing presentation-state tests and doubles**

Create `Tests/AgentPreflightPresentationTests/AppViewModelTests.swift` with these cases:

```swift
import Foundation
import XCTest
@testable import AgentPreflightApplication
@testable import AgentPreflightDomain
@testable import AgentPreflightPresentation

@MainActor
final class AppViewModelTests: XCTestCase {
    func testChangingTaskSizeRecomputesWithoutRefreshing() async throws {
        let useCase = RefreshUseCaseStub(result: try completeResult())
        let model = AppViewModel(
            refreshUseCase: useCase,
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        let callsAfterOpen = await useCase.refreshCalls
        model.selectedTaskSize = .large
        let callsAfterSelection = await useCase.refreshCalls
        XCTAssertEqual(callsAfterSelection, callsAfterOpen)
        XCTAssertFalse(model.recommendation.title.isEmpty)
    }

    func testQuotaRowHasTextualAndAccessibleState() async throws {
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: try completeResult()),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        let row = try XCTUnwrap(model.providerCards.first?.rows.first)
        XCTAssertTrue(row.remainingText.contains("remaining"))
        XCTAssertTrue(row.accessibilityLabel.contains("remaining"))
        XCTAssertFalse(row.stateText.isEmpty)
    }

    func testPartialFailureKeepsHealthyProviderCardAndDisablesRecommendation() async throws {
        let result = try partialFailureResult()
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: result),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        XCTAssertEqual(model.providerCards.first { $0.provider == .codex }?.rows.count, 2)
        XCTAssertEqual(model.recommendation.title, "Recommendation unavailable")
        XCTAssertNotNil(model.providerCards.first { $0.provider == .claudeCode }?.recoveryText)
    }

    func testTotalFailureKeepsBothRecoveryActionsVisible() async {
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: totalFailureResult()),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        XCTAssertTrue(model.providerCards.allSatisfy { $0.rows.isEmpty })
        XCTAssertTrue(model.providerCards.allSatisfy { $0.recoveryText != nil })
        XCTAssertEqual(model.recommendation.title, "Recommendation unavailable")
    }

    func testInitialAndStaleStatesUseTextLabels() async throws {
        let stale = try staleResult()
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: stale),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        XCTAssertEqual(model.providerCards.map(\.freshnessText), ["Loading", "Loading"])
        await model.panelOpened()
        XCTAssertEqual(model.providerCards.first { $0.provider == .codex }?.freshnessText, "Stale")
        XCTAssertEqual(model.recommendation.title, "Recommendation unavailable")
    }

    func testPassedResetBecomesUnknownWithoutInventingFullQuota() async throws {
        let result = try completeResult(shortResetOffset: -1)
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: result),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        let short = try XCTUnwrap(
            model.providerCards.first { $0.provider == .codex }?.rows.first { $0.kind == .short }
        )
        XCTAssertEqual(short.stateText, "Unknown")
        XCTAssertEqual(short.remainingText, "Remaining unknown")
        XCTAssertNil(short.remainingValue)
        XCTAssertEqual(short.resetText, "Refresh required")
        XCTAssertEqual(model.recommendation.title, "Recommendation unavailable")
    }

    func testNoSafeChoiceNamesFailedConstraintsAndNearestReset() async throws {
        let model = AppViewModel(
            refreshUseCase: RefreshUseCaseStub(result: try insufficientResult()),
            recommendationEngine: RecommendationEngine(),
            clock: FixedPresentationClock(now: referenceDate)
        )
        await model.panelOpened()
        XCTAssertEqual(model.recommendation.title, "No safe choice")
        XCTAssertTrue(model.recommendation.detail.contains("Codex short"))
        XCTAssertTrue(model.recommendation.detail.contains("Claude Code weekly"))
        XCTAssertTrue(model.recommendation.detail.contains("resets in 15m"))
    }

    func testSettingsRejectRelativePathAndSaveValidatedAbsolutePath() async {
        let store = SettingsStoreSpy()
        let model = SettingsViewModel(
            settings: store,
            validator: ExecutableValidatorStub(validPath: "/opt/homebrew/bin/codex")
        )
        model.codexPath = "bin/codex"
        await model.save()
        XCTAssertEqual(model.validationMessage, "Choose an absolute executable file.")
        let rejectedValue = await store.path
        XCTAssertNil(rejectedValue)

        model.codexPath = " /opt/homebrew/bin/codex "
        await model.save()
        XCTAssertNil(model.validationMessage)
        let savedValue = await store.path
        XCTAssertEqual(savedValue, "/opt/homebrew/bin/codex")
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_788_505_200)

private func completeResult(shortResetOffset: TimeInterval = 3_600) throws -> RefreshResult {
    let codex = try presentationSnapshot(.codex, shortResetOffset: shortResetOffset)
    let claude = try presentationSnapshot(.claudeCode, shortResetOffset: 3_600)
    return RefreshResult(statuses: [
        .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
        .claudeCode: ProviderStatus(provider: .claudeCode, snapshot: claude, freshness: .current, failure: nil),
    ], completedAt: referenceDate)
}

private func partialFailureResult() throws -> RefreshResult {
    let codex = try presentationSnapshot(.codex, shortResetOffset: 3_600)
    return RefreshResult(statuses: [
        .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
        .claudeCode: ProviderStatus(
            provider: .claudeCode,
            snapshot: nil,
            freshness: .unavailable,
            failure: .unauthorized
        ),
    ], completedAt: referenceDate)
}

private func staleResult() throws -> RefreshResult {
    let codex = try presentationSnapshot(.codex, shortResetOffset: 3_600)
    return RefreshResult(statuses: [
        .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .stale, failure: nil),
        .claudeCode: ProviderStatus(provider: .claudeCode, snapshot: nil, freshness: .unavailable, failure: nil),
    ], completedAt: referenceDate)
}

private func totalFailureResult() -> RefreshResult {
    RefreshResult(statuses: [
        .codex: ProviderStatus(
            provider: .codex,
            snapshot: nil,
            freshness: .unavailable,
            failure: .executableMissing
        ),
        .claudeCode: ProviderStatus(
            provider: .claudeCode,
            snapshot: nil,
            freshness: .unavailable,
            failure: .keychainDenied
        ),
    ], completedAt: referenceDate)
}

private func insufficientResult() throws -> RefreshResult {
    let codex = try insufficientSnapshot(.codex, firstReset: 900)
    let claude = try insufficientSnapshot(.claudeCode, firstReset: 1_800)
    return RefreshResult(statuses: [
        .codex: ProviderStatus(provider: .codex, snapshot: codex, freshness: .current, failure: nil),
        .claudeCode: ProviderStatus(provider: .claudeCode, snapshot: claude, freshness: .current, failure: nil),
    ], completedAt: referenceDate)
}

private func insufficientSnapshot(
    _ provider: ProviderIdentifier,
    firstReset: TimeInterval
) throws -> QuotaSnapshot {
    try QuotaSnapshot(provider: provider, windows: [
        QuotaWindow(
            kind: .short,
            remaining: .init(remaining: 20),
            resetsAt: referenceDate.addingTimeInterval(firstReset)
        ),
        QuotaWindow(
            kind: .weekly,
            remaining: .init(remaining: 5),
            resetsAt: referenceDate.addingTimeInterval(86_400)
        ),
    ], fetchedAt: referenceDate)
}

private func presentationSnapshot(
    _ provider: ProviderIdentifier,
    shortResetOffset: TimeInterval
) throws -> QuotaSnapshot {
    try QuotaSnapshot(provider: provider, windows: [
        QuotaWindow(
            kind: .short,
            remaining: .init(remaining: provider == .codex ? 80 : 60),
            resetsAt: referenceDate.addingTimeInterval(shortResetOffset)
        ),
        QuotaWindow(
            kind: .weekly,
            remaining: .init(remaining: provider == .codex ? 70 : 50),
            resetsAt: referenceDate.addingTimeInterval(86_400)
        ),
    ], fetchedAt: referenceDate)
}

private struct FixedPresentationClock: Clock {
    let current: Date
    init(now: Date) { current = now }
    func now() -> Date { current }
}

private actor RefreshUseCaseStub: RefreshQuotaUseCaseProtocol {
    let result: RefreshResult
    private(set) var refreshCalls = 0
    init(result: RefreshResult) { self.result = result }
    func current() async -> RefreshResult { result }
    func refresh() async -> RefreshResult {
        refreshCalls += 1
        return result
    }
}

private actor SettingsStoreSpy: AppSettingsStore {
    private(set) var path: String?
    func codexExecutablePath() async -> String? { path }
    func setCodexExecutablePath(_ path: String?) async { self.path = path }
}

private struct ExecutableValidatorStub: ExecutablePathValidating {
    let validPath: String
    func isExecutable(path: String) -> Bool { path == validPath }
}
```

- [ ] **Step 3: Run tests and confirm the expected compile failure**

Run: `swift test --filter AppViewModelTests`

Expected: FAIL because presentation models and view models do not exist.

- [ ] **Step 4: Add immutable presentation models**

Create `Sources/AgentPreflightPresentation/PresentationModels.swift`:

```swift
import AgentPreflightDomain

public struct QuotaRowModel: Identifiable, Equatable, Sendable {
    public var id: QuotaWindowKind { kind }
    public let kind: QuotaWindowKind
    public let title: String
    public let remainingValue: Double?
    public let remainingText: String
    public let resetText: String
    public let stateText: String
    public let accessibilityLabel: String
}

public struct ProviderCardModel: Identifiable, Equatable, Sendable {
    public var id: ProviderIdentifier { provider }
    public let provider: ProviderIdentifier
    public let title: String
    public let freshnessText: String
    public let rows: [QuotaRowModel]
    public let recoveryText: String?
}

public enum RecommendationTone: Equatable, Sendable { case positive, neutral, warning, unavailable }

public struct RecommendationModel: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let tone: RecommendationTone
}
```

- [ ] **Step 5: Implement deterministic percentage, reset, and accessibility formatting**

Create `Sources/AgentPreflightPresentation/PresentationFormatter.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

public struct PresentationFormatter: Sendable {
    public init() {}

    public func providerTitle(_ provider: ProviderIdentifier) -> String {
        provider == .codex ? "Codex" : "Claude Code"
    }

    public func row(provider: ProviderIdentifier, window: QuotaWindow, now: Date) -> QuotaRowModel {
        let percent = Int(window.remaining.value.rounded())
        let state = stateText(percent: percent, reset: window.resetsAt, now: now)
        let reset = resetText(window.resetsAt, now: now)
        let windowTitle = window.kind == .short ? "Short window" : "Weekly"
        let isCurrentWindow = window.resetsAt > now
        let remainingText = isCurrentWindow ? "\(percent)% remaining" : "Remaining unknown"
        return QuotaRowModel(
            kind: window.kind,
            title: windowTitle,
            remainingValue: isCurrentWindow ? window.remaining.value : nil,
            remainingText: remainingText,
            resetText: reset,
            stateText: state,
            accessibilityLabel: "\(providerTitle(provider)), \(windowTitle), \(remainingText), \(reset), \(state)"
        )
    }

    public func resetText(_ reset: Date, now: Date) -> String {
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
        let window = failure.window == .short ? "short" : "weekly"
        return "\(providerTitle(failure.provider)) \(window)"
    }

    private func stateText(percent: Int, reset: Date, now: Date) -> String {
        guard reset > now else { return "Unknown" }
        switch percent {
        case 60...100: return "Plenty"
        case 30..<60: return "Available"
        case 1..<30: return "Low"
        default: return "Exhausted"
        }
    }
}
```

- [ ] **Step 6: Implement exhaustive provider recovery copy**

Create `Sources/AgentPreflightPresentation/ErrorCopy.swift` with an exhaustive switch. Use these exact outputs:

```swift
import AgentPreflightApplication
import AgentPreflightDomain

public enum ErrorCopy {
    public static func recovery(for provider: ProviderIdentifier, failure: ProviderFailure) -> String {
        switch failure {
        case .executableMissing: "Codex executable not found. Set its path in Settings."
        case .unauthenticated: provider == .codex ? "Run `codex login`, then refresh." : "Run `claude login`, then refresh."
        case .keychainDenied: "Allow access to Claude Code credentials in Keychain, then refresh."
        case .invalidCredential: "Claude credentials are unsupported. Run `claude logout && claude login`."
        case .timeout: "The provider did not respond within 5 seconds. Refresh to try again."
        case .unauthorized: "The provider rejected the current login. Sign in again, then refresh."
        case .rateLimited: "Usage lookup is rate limited. Wait a moment, then refresh."
        case .unsupportedPayload: "This provider version returned an unsupported usage format."
        case .processFailure: "Codex app-server exited before returning usage."
        case .protocolFailure: "Codex app-server returned an invalid protocol response."
        case .networkUnavailable: "Usage could not be reached. Check the network, then refresh."
        }
    }
}
```

- [ ] **Step 7: Implement panel state and structured recommendation copy**

Create `Sources/AgentPreflightPresentation/AppViewModel.swift`:

```swift
import Combine
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedTaskSize: TaskSize { didSet { render() } }
    @Published public private(set) var providerCards: [ProviderCardModel]
    @Published public private(set) var recommendation: RecommendationModel
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefreshText = "Not refreshed"

    private let refreshUseCase: any RefreshQuotaUseCaseProtocol
    private let recommendationEngine: RecommendationEngine
    private let clock: any Clock
    private let formatter: PresentationFormatter
    private var latestResult: RefreshResult?

    public init(
        refreshUseCase: any RefreshQuotaUseCaseProtocol,
        recommendationEngine: RecommendationEngine,
        clock: any Clock,
        formatter: PresentationFormatter = .init(),
        selectedTaskSize: TaskSize = .medium
    ) {
        self.refreshUseCase = refreshUseCase
        self.recommendationEngine = recommendationEngine
        self.clock = clock
        self.formatter = formatter
        self.selectedTaskSize = selectedTaskSize
        self.providerCards = ProviderIdentifier.allCases.map {
            ProviderCardModel(
                provider: $0,
                title: formatter.providerTitle($0),
                freshnessText: "Loading",
                rows: [],
                recoveryText: nil
            )
        }
        self.recommendation = RecommendationModel(
            title: "Recommendation unavailable",
            detail: "Waiting for fresh quota data.",
            tone: .unavailable
        )
    }

    public func panelOpened() async {
        latestResult = await refreshUseCase.current()
        render()
        await refresh()
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        latestResult = await refreshUseCase.refresh()
        isRefreshing = false
        render()
    }

    public func clockTicked() { render() }

    private func render() {
        guard let result = latestResult else { return }
        let now = clock.now()
        providerCards = ProviderIdentifier.allCases.map {
            makeCard(status: result.statuses[$0], provider: $0, now: now)
        }
        let fetchedAt = result.statuses.values.compactMap { $0.snapshot?.fetchedAt }.min()
        lastRefreshText = fetchedAt.map { formatter.ageText($0, now: now) } ?? "Not refreshed"
        let decision = recommendationEngine.recommend(
            taskSize: selectedTaskSize,
            snapshots: result.eligibleSnapshots,
            staleProviders: result.staleProviders,
            now: now
        )
        recommendation = makeRecommendation(decision, now: now)
    }

    private func makeCard(
        status: ProviderStatus?,
        provider: ProviderIdentifier,
        now: Date
    ) -> ProviderCardModel {
        let windows = status?.snapshot.map { Array($0.windows.values) } ?? []
        let rows = windows
            .sorted { sortIndex($0.kind) < sortIndex($1.kind) }
            .map { formatter.row(provider: provider, window: $0, now: now) }
        let recovery = status?.failure.map { ErrorCopy.recovery(for: provider, failure: $0) }
        let baseFreshness = freshnessText(status?.freshness ?? .unavailable)
        let isComplete = QuotaWindowKind.allCases.allSatisfy { status?.snapshot?.windows[$0] != nil }
        return ProviderCardModel(
            provider: provider,
            title: formatter.providerTitle(provider),
            freshnessText: !windows.isEmpty && !isComplete
                ? "\(baseFreshness) · Incomplete"
                : baseFreshness,
            rows: rows,
            recoveryText: recovery
        )
    }

    private func makeRecommendation(_ value: Recommendation, now: Date) -> RecommendationModel {
        switch value.decision {
        case let .provider(provider):
            let onlySafe = value.reason == .onlySafe(provider)
            return .init(
                title: "Safer choice: \(formatter.providerTitle(provider))",
                detail: onlySafe
                    ? "Only this provider meets both reserves for the selected task size."
                    : "It has the larger minimum quota margin across both windows.",
                tone: .positive
            )
        case .neutral:
            return .init(
                title: "Both look safe",
                detail: "Their minimum quota margins differ by less than 10%.",
                tone: .neutral
            )
        case .noSafeChoice:
            let reset = value.nearestRelevantReset
                .map { formatter.resetText($0, now: now).lowercased() }
                ?? "reset time unavailable"
            let failures = value.failures.map { formatter.failureLabel($0) }.joined(separator: ", ")
            return .init(
                title: "No safe choice",
                detail: "Below reserve: \(failures); \(reset).",
                tone: .warning
            )
        case .unavailable:
            return .init(
                title: "Recommendation unavailable",
                detail: "Fresh short-window and weekly data is required from both providers.",
                tone: .unavailable
            )
        }
    }

    private func freshnessText(_ freshness: SnapshotFreshness) -> String {
        switch freshness {
        case .current: "Current"
        case .cached: "Cached"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        }
    }

    private func sortIndex(_ kind: QuotaWindowKind) -> Int {
        kind == .short ? 0 : 1
    }
}
```

- [ ] **Step 8: Implement validated Codex-path settings state**

Create `Sources/AgentPreflightPresentation/SettingsViewModel.swift`:

```swift
import Combine
import Foundation
import AgentPreflightApplication

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var codexPath = ""
    @Published public private(set) var validationMessage: String?
    private let settings: any AppSettingsStore
    private let validator: any ExecutablePathValidating

    public init(settings: any AppSettingsStore, validator: any ExecutablePathValidating) {
        self.settings = settings
        self.validator = validator
    }

    public func load() async {
        codexPath = await settings.codexExecutablePath() ?? ""
    }

    public func save() async {
        let normalized = codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty || validator.isExecutable(path: normalized) else {
            validationMessage = "Choose an absolute executable file."
            return
        }
        await settings.setCodexExecutablePath(normalized.isEmpty ? nil : normalized)
        validationMessage = nil
    }
}
```

`CodexExecutableLocator` already conforms to the application-layer `ExecutablePathValidating` boundary from Task 3, so Presentation does not import Infrastructure.

- [ ] **Step 9: Run the complete presentation-state test table**

Run: `swift test --filter AppViewModelTests`

Expected: PASS for loading/success, task-size-only recomputation, partial failure, stale state, recovery copy, reset expiry, and accessibility text as asserted in Step 1.

Run: `swift test`

Expected: all deterministic tests PASS; live tests SKIP.

- [ ] **Step 10: Commit the presentation model layer**

```bash
git add Package.swift Sources/AgentPreflightPresentation Tests/AgentPreflightPresentationTests
git commit -m "feat: add quota presentation state"
```

---

### Task 8: Assemble the SwiftUI Menu-Bar App and Local Bundle

**Files:**
- Modify: `Package.swift`
- Modify: `.gitignore`
- Create: `Sources/AgentPreflightPresentation/MenuBarContentView.swift`
- Create: `Sources/AgentPreflightPresentation/ProviderCardView.swift`
- Create: `Sources/AgentPreflightPresentation/RecommendationCardView.swift`
- Create: `Sources/AgentPreflightPresentation/SettingsView.swift`
- Create: `Sources/AgentPreflightApp/AppDependencies.swift`
- Create: `Sources/AgentPreflightApp/AgentPreflightApp.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/package_app.sh`

**Interfaces:**
- Consumes: all tested domain, application, infrastructure, and presentation types.
- Produces: executable product `AgentPreflight`, menu-bar and Settings scenes, and `dist/Agent Preflight.app`.

- [ ] **Step 1: Add the executable product and target**

Add this product to `Package.swift`:

```swift
.executable(name: "AgentPreflight", targets: ["AgentPreflightApp"]),
```

Add this target:

```swift
.executableTarget(
    name: "AgentPreflightApp",
    dependencies: [
        "AgentPreflightDomain",
        "AgentPreflightApplication",
        "AgentPreflightInfrastructure",
        "AgentPreflightPresentation",
    ]
),
```

- [ ] **Step 2: Add a compiler-failing app shell**

Create the first compiler-failing `Sources/AgentPreflightApp/AgentPreflightApp.swift` shell:

```swift
import SwiftUI
import AgentPreflightPresentation

@main
struct AgentPreflightApplication: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        MenuBarExtra("Agent Preflight", systemImage: "gauge.with.dots.needle.50percent") {
            MenuBarContentView(model: dependencies.appViewModel)
        }
    }
}
```

Run: `swift build`

Expected: FAIL because composition and SwiftUI views do not exist yet.

- [ ] **Step 3: Implement the production composition root**

Create `Sources/AgentPreflightApp/AppDependencies.swift`:

```swift
import Foundation
import AgentPreflightApplication
import AgentPreflightDomain
import AgentPreflightInfrastructure
import AgentPreflightPresentation

@MainActor
struct AppDependencies {
    let appViewModel: AppViewModel
    let settingsViewModel: SettingsViewModel

    static func live() -> Self {
        let clock = SystemClock()
        let settings = UserDefaultsAppSettingsStore()
        let locator = CodexExecutableLocator(settings: settings)
        let configuration = RefreshConfiguration.live
        let codex = CodexQuotaProvider(
            locator: locator,
            client: CodexAppServerClient(
                launcher: FoundationJSONLineProcessLauncher(),
                timeoutSeconds: configuration.providerTimeout
            ),
            parser: CodexRateLimitsParser(),
            clock: clock
        )
        let claudeConfiguration = ClaudeProviderConfiguration.live
        let claude = ClaudeQuotaProvider(
            credentialReader: KeychainClaudeCredentialReader(service: claudeConfiguration.keychainService),
            httpClient: URLSessionHTTPClient(),
            parser: ClaudeUsageParser(),
            clock: clock,
            configuration: claudeConfiguration,
            timeoutSeconds: configuration.providerTimeout
        )
        let cache = makeCache()
        let useCase = RefreshQuotaUseCase(
            providers: [codex, claude], cache: cache, clock: clock,
            diagnostics: OSDiagnosticsSink(), configuration: configuration
        )
        return Self(
            appViewModel: AppViewModel(
                refreshUseCase: useCase,
                recommendationEngine: RecommendationEngine(),
                clock: clock
            ),
            settingsViewModel: SettingsViewModel(settings: settings, validator: locator)
        )
    }

    private static func makeCache() -> any QuotaCache {
        do { return try JSONQuotaCache.live() }
        catch { return UnavailableQuotaCache() }
    }
}

private actor UnavailableQuotaCache: QuotaCache {
    private enum Failure: Error { case unavailable }
    func load() async throws -> [ProviderIdentifier: QuotaSnapshot] { throw Failure.unavailable }
    func save(_ snapshots: [ProviderIdentifier: QuotaSnapshot]) async throws { throw Failure.unavailable }
}
```

The fallback cache carries no secret and deliberately throws, allowing `RefreshQuotaUseCase` to emit typed `.cacheReadFailed` and `.cacheWriteFailed` events without logging the raw filesystem error.

- [ ] **Step 4: Implement the limits-first popover hierarchy**

Create `Sources/AgentPreflightPresentation/MenuBarContentView.swift`:

```swift
import SwiftUI
import AgentPreflightDomain

public struct MenuBarContentView: View {
    @ObservedObject private var model: AppViewModel

    public init(model: AppViewModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 12) {
            header
            ForEach(model.providerCards) { ProviderCardView(model: $0) }
            Picker("Task size", selection: $model.selectedTaskSize) {
                Text("S").tag(TaskSize.small)
                Text("M").tag(TaskSize.medium)
                Text("L").tag(TaskSize.large)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Planned task size")
            RecommendationCardView(model: model.recommendation)
            HStack {
                Text(model.lastRefreshText).foregroundStyle(.secondary)
                Spacer()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { Task { await model.panelOpened() } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch is CancellationError { return }
                catch { return }
                model.clockTicked()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Preflight").font(.headline)
                Text(model.isRefreshing ? "Refreshing limits…" : "Subscription quota")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh quota")
        }
    }
}
```

- [ ] **Step 5: Implement provider cards and accessible quota rows**

Create `Sources/AgentPreflightPresentation/ProviderCardView.swift`:

```swift
import SwiftUI

public struct ProviderCardView: View {
    private let model: ProviderCardModel
    public init(model: ProviderCardModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(model.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.freshnessText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.rows.isEmpty {
                Label("Quota windows unavailable", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.rows) { QuotaRowView(model: $0) }
            }
            if let recovery = model.recoveryText {
                Label(recovery, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct QuotaRowView: View {
    let model: QuotaRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.title).font(.caption)
                Spacer()
                Text(model.remainingText).font(.caption.weight(.medium))
            }
            if let remainingValue = model.remainingValue {
                ProgressView(value: remainingValue, total: 100)
                    .tint(tint)
            }
            HStack {
                Text(model.resetText)
                Spacer()
                Text(model.stateText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var tint: Color {
        switch model.stateText {
        case "Plenty": .green
        case "Available": .blue
        case "Low": .orange
        default: .red
        }
    }
}
```

- [ ] **Step 6: Implement the textual recommendation card**

Create `Sources/AgentPreflightPresentation/RecommendationCardView.swift`:

```swift
import SwiftUI

public struct RecommendationCardView: View {
    private let model: RecommendationModel
    public init(model: RecommendationModel) { self.model = model }

    public var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title).font(.subheadline.weight(.semibold))
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private var symbol: String {
        switch model.tone {
        case .positive: "checkmark.circle.fill"
        case .neutral: "equal.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch model.tone {
        case .positive: .green
        case .neutral: .blue
        case .warning: .orange
        case .unavailable: .secondary
        }
    }
}
```

- [ ] **Step 7: Implement the Codex-path Settings form**

Create `Sources/AgentPreflightPresentation/SettingsView.swift`:

```swift
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var model: SettingsViewModel
    public init(model: SettingsViewModel) { self.model = model }

    public var body: some View {
        Form {
            Section("Codex executable") {
                TextField("/absolute/path/to/codex", text: $model.codexPath)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to search PATH, /opt/homebrew/bin, and /usr/local/bin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = model.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Save") { Task { await model.save() } }
                    Button("Use automatic discovery") {
                        model.codexPath = ""
                        Task { await model.save() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 210)
        .task { await model.load() }
    }
}
```

- [ ] **Step 8: Implement the menu-bar-only scenes**

Create `Sources/AgentPreflightApp/AgentPreflightApp.swift`:

```swift
import SwiftUI
import AgentPreflightPresentation

@main
struct AgentPreflightApplication: App {
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init() {
        let dependencies = AppDependencies.live()
        _appViewModel = StateObject(wrappedValue: dependencies.appViewModel)
        _settingsViewModel = StateObject(wrappedValue: dependencies.settingsViewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: appViewModel)
        } label: {
            Label("Agent Preflight", systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: settingsViewModel)
        }
    }
}
```

- [ ] **Step 9: Run the compiler integration gate**

Run: `swift build`

Expected: PASS with the exact interfaces defined by Tasks 1–8. A failure means the current task is incomplete; correct the mismatched definition and its owning test before advancing.

Run: `swift test`

Expected: all deterministic tests PASS and live tests SKIP.

- [ ] **Step 10: Add menu-bar-only bundle metadata**

Create `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AgentPreflight</string>
    <key>CFBundleIdentifier</key><string>com.agentpreflight.app</string>
    <key>CFBundleName</key><string>Agent Preflight</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 11: Add deterministic local packaging**

Create `Scripts/package_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "$script_directory/.." && pwd)"
readonly app_name="Agent Preflight"
readonly executable_name="AgentPreflight"
readonly bundle_identifier="com.agentpreflight.app"
readonly output_root="${OUTPUT_ROOT:-$repository_root/dist}"
cd "$repository_root"
readonly binary_directory="$(swift build -c release --show-bin-path)"
readonly bundle_path="$output_root/$app_name.app"
readonly contents_path="$bundle_path/Contents"

if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
    /bin/rm -rf -- "$bundle_path"
fi
mkdir -p "$contents_path/MacOS"
/usr/bin/ditto "$binary_directory/$executable_name" "$contents_path/MacOS/$executable_name"
/usr/bin/ditto "Resources/Info.plist" "$contents_path/Info.plist"
/usr/bin/codesign --force --sign - --identifier "$bundle_identifier" "$bundle_path"
/usr/bin/codesign --verify --deep --strict "$bundle_path"
echo "$bundle_path"
```

Run: `chmod +x Scripts/package_app.sh`

- [ ] **Step 12: Ignore local app bundles**

Append to `.gitignore`:

```gitignore
dist/
```

- [ ] **Step 13: Package and verify the actual app bundle**

Run:

```bash
bash -n Scripts/package_app.sh
Scripts/package_app.sh
plutil -lint "dist/Agent Preflight.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/Agent Preflight.app"
```

Expected: release build succeeds, plist is valid, ad-hoc signature verifies, and the script prints the app path.

- [ ] **Step 14: Smoke-test the actual app identity**

After user approval to launch a GUI app, run `open "dist/Agent Preflight.app"` and verify:

1. one menu-bar icon appears and no Dock icon appears;
2. the panel fits without scrolling in the accepted order;
3. first explicit open may request Claude Keychain access and no background/repeated prompt occurs;
4. both cards refresh independently and never expose raw JSON or credentials;
5. S/M/L changes the recommendation without another network request;
6. closing/reopening inside 30 seconds does not start another provider request;
7. VoiceOver reads provider, window, remaining percent, reset, and text state.

If the packaged app cannot obtain stable user-approved Keychain access, treat that as the same hard provider-design failure as Task 2; do not ship a build that repeatedly prompts.

- [ ] **Step 15: Commit the runnable app**

```bash
git add Package.swift .gitignore Sources/AgentPreflightApp Sources/AgentPreflightPresentation Resources Scripts
git commit -m "feat: assemble Agent Preflight menu app"
```

---

### Task 9: Add Public Documentation, CI, and Release Verification

**Files:**
- Create: `README.md`
- Create: `PRIVACY.md`
- Create: `LICENSE`
- Create: `.github/workflows/ci.yml`
- Modify: `docs/superpowers/specs/2026-09-04-agent-preflight-design.md` only if verified provider behavior differs from the approved assumptions.

**Interfaces:**
- Consumes: the complete package and bundle from Tasks 1–8.
- Produces: reproducible contributor setup, explicit privacy contract, MIT license, automated CI, and a recorded v0.1 verification result.

- [ ] **Step 1: Create the public README with executable commands and honest limitations**

Create `README.md` with this content:

````markdown
# Agent Preflight

Choose the safer subscription-backed coding agent before starting a task.

## What it does

- Shows remaining short-window and weekly quota for Codex and Claude Code.
- Recommends the safer option for an S, M, or L task using documented fixed reserves.
- Runs locally with no backend, analytics, account, or background polling.

## Requirements

- macOS 14+
- Swift 6 toolchain
- Codex CLI signed in with a ChatGPT subscription
- Claude Code signed in with a Claude subscription

## Build and run

```bash
swift test
Scripts/package_app.sh
open "dist/Agent Preflight.app"
```

Agent Preflight appears only in the menu bar. Open its panel to request fresh quota. The first Claude refresh can show a macOS Keychain prompt for the existing `Claude Code-credentials` item.

## Authentication and privacy

Codex remains responsible for its credentials through app-server. Agent Preflight asks macOS Keychain for the existing `Claude Code-credentials` item only during a user-initiated refresh. Tokens are held only for the request lifetime and are never cached or logged. See PRIVACY.md.

## Recommendation policy

| Size | Short-window reserve | Weekly reserve |
|---|---:|---:|
| S | 15% | 5% |
| M | 35% | 10% |
| L | 60% | 20% |

For each provider the app takes the lower of `short remaining / required short` and `weekly remaining / required weekly`. One safe provider wins. When both are safe, the larger minimum margin wins; a difference below `0.10` is neutral. Missing, stale, or expired data disables comparison. “Safer choice” is a conservative quota comparison, not a guarantee that a task will finish.

## Tests

Run deterministic tests and the release compiler gate:

```bash
swift test
swift build -c release
```

The following opt-in smoke tests access the currently signed-in provider accounts. They never run in CI and must not be attached to public bug reports with verbose network logging:

```bash
AGENT_PREFLIGHT_LIVE_CLAUDE=1 swift test --filter testLiveClaudeUsageWhenExplicitlyEnabled
AGENT_PREFLIGHT_LIVE_CODEX=1 swift test --filter testLiveCodexUsageWhenExplicitlyEnabled
```

## Known limitations

Claude's OAuth usage endpoint and foreign Keychain payload are internal contracts and may change. Missing/stale windows intentionally disable comparison. Builds are ad-hoc signed and not notarized in v0.1.

## Troubleshooting

| Message | Action |
|---|---|
| Codex executable not found | Set the absolute path in Settings or make `codex` available in PATH. |
| Provider is not authenticated | Run `codex login` or `claude login`, then refresh. |
| Keychain access denied | Refresh again and approve access to `Claude Code-credentials`. |
| Claude credential is unsupported | Run `claude logout && claude login`, then refresh. |
| Request timed out or network unavailable | Check connectivity and refresh after 30 seconds. |
| Usage lookup is rate limited | Wait a few minutes, then refresh manually. |
| Unsupported usage format | Check for a newer Agent Preflight release and report only app/provider versions plus the displayed error category. |

Never paste a Keychain dump, auth file, bearer token, authorization header, cookie, or unredacted provider response into Agent Preflight or a GitHub issue.

## License

MIT
````

- [ ] **Step 2: Document the exact privacy boundary and local deletion path**

Create `PRIVACY.md`:

```markdown
# Privacy

Agent Preflight is local-first. It has no Agent Preflight backend, account, analytics, telemetry, advertising SDK, remote logging, or crash-upload service.

## Network access

- Codex quota is requested through the locally installed `codex app-server`, which owns its authentication.
- Claude quota is requested directly from `https://api.anthropic.com/api/oauth/usage` using the existing Claude Code OAuth credential.
- No other destination receives quota or credential data.

## Credentials

Agent Preflight never stores Codex credentials. It reads only the macOS Keychain generic-password item whose service is `Claude Code-credentials`, and only after the user opens the panel or presses Refresh. The Claude access token exists in memory only while constructing and performing that request. Tokens, authorization headers, cookies, and raw credential payloads are excluded from cache and diagnostics.

## Local storage

The cache contains only provider identifiers, normalized remaining percentages, reset timestamps, and fetch timestamps. It is stored under the user's Application Support directory in `Agent Preflight/quota-cache-v1.json`. The directory uses permission mode `0700`; the file uses `0600`. The optional Codex executable path is a non-secret UserDefaults preference.

## Delete local data

Quit Agent Preflight, remove the `Agent Preflight` directory from your user Application Support directory, and clear the Codex executable field in Settings. Agent Preflight does not own vendor credentials; use the official `codex logout` or `claude logout` command if you separately want to revoke those sessions.

## Support reports

Report the Agent Preflight version, provider CLI version, and displayed typed error category. Never attach Keychain exports, auth files, bearer tokens, authorization headers, cookies, or unredacted API responses.
```

- [ ] **Step 3: Add the MIT license**

Create `LICENSE`:

```text
MIT License

Copyright (c) 2026 Agent Preflight contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Add dependency-free macOS CI**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: macos-14
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Format
        run: swift format lint --recursive Package.swift Sources Tests
      - name: Test
        run: swift test
      - name: Release build
        run: swift build -c release
```

Verify the workflow contains no secrets and cannot run either live test because neither opt-in environment variable is present.

- [ ] **Step 5: Run the complete automated release gate**

Run:

```bash
swift format --in-place --recursive Package.swift Sources Tests
swift test
swift format lint --recursive Package.swift Sources Tests
swift build -c release
bash -n Scripts/package_app.sh
Scripts/package_app.sh
plutil -lint "dist/Agent Preflight.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/Agent Preflight.app"
git diff --check
git status --short
```

Expected: all deterministic tests PASS; two live tests SKIP; release build, packaging, plist, signature, and whitespace checks PASS; status lists only Task 9 documentation/workflow changes.

- [ ] **Step 6: Run final opt-in real-account verification**

With the user explicitly opting in, run both live tests again and record only PASS/typed failure:

```bash
AGENT_PREFLIGHT_LIVE_CLAUDE=1 swift test --filter testLiveClaudeUsageWhenExplicitlyEnabled
AGENT_PREFLIGHT_LIVE_CODEX=1 swift test --filter testLiveCodexUsageWhenExplicitlyEnabled
```

- [ ] **Step 7: Run packaged-app failure-mode verification**

Then launch the packaged app with user approval and verify: fresh success; one provider logged out; network unavailable; manual Codex path invalid/cleared; expired reset shows `Refresh required`; cached snapshot older than 15 minutes shows `Stale`; and no case produces a cross-provider recommendation from incomplete/stale data. Inspect cache JSON keys and unified-log messages, never Keychain contents, to confirm no secret material is present.

- [ ] **Step 8: Commit the public v0.1 baseline**

```bash
git add README.md PRIVACY.md LICENSE .github docs/superpowers/specs
git commit -m "docs: prepare public MVP release"
```

- [ ] **Step 9: Confirm the definition of done**

Run: `git log --oneline --decorate -9` and `git status --short --branch`.

Expected: nine small implementation commits after the approved design commit, a clean worktree, and every Definition of Done item in the spec backed by an automated test or the explicit packaged-app checklist above. Do not create a GitHub repository, tag, release, Developer ID signature, or notarization request without a separate user instruction.
