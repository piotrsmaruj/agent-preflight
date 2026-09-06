# Agent Preflight — MVP Design

Date: 2026-09-04
Status: Approved in product-design discussion

## Summary

Agent Preflight is a small macOS menu-bar application for developers who use both Codex and Claude Code through subscription plans. It answers two questions before a larger coding task begins:

1. How much short-window and weekly quota remains for each agent?
2. Which agent currently has the safer quota margin for a small, medium, or large task?

The application is local-first. It has no account system, backend, analytics, or cloud synchronization. Version 0.1 is a free validation release published on GitHub. Paid functionality is considered only after demand is demonstrated.

## Problem

Subscription quota is spread across vendor-specific web pages, application settings, and interactive CLI commands. A user who wants to start a substantial task must inspect multiple interfaces, compare differently presented windows, and decide whether an agent is likely to run out during the work.

Existing quota monitors validate the pain but mostly stop at presenting raw values. Agent Preflight is positioned around the decision made from those values: selecting the agent with enough remaining capacity for the expected task size.

## Target User

A developer who:

- has active Codex and Claude Code subscriptions;
- uses both agents interchangeably rather than assigning each one a fixed role;
- checks limits before beginning larger work;
- wants a quick, conservative recommendation rather than a precise completion guarantee.

## Goals

- Show the remaining short-window and weekly quota for Codex and Claude Code.
- Show the reset time for every available window.
- Refresh data when the panel is opened and when the user explicitly requests it.
- Let the user classify planned work as S, M, or L.
- Recommend the provider with the safer quota margin and explain the deciding constraint.
- Keep credentials under the ownership of the vendor CLIs.
- Degrade independently when one provider is unavailable.
- Keep the implementation within a 10–15 hour target budget, conditional on the Claude integration spike succeeding.

## Non-goals for Version 0.1

- Launching or switching agents.
- Analyzing a written task description with an LLM.
- Predicting exact token consumption or guaranteeing task completion.
- Supporting multiple accounts or providers other than Codex and Claude Code.
- Background polling, reset notifications, or usage history.
- Payments, licensing, analytics, user accounts, or a backend.
- Mac App Store distribution, code signing, or notarization.

## User Experience

Agent Preflight runs only in the macOS menu bar and has no Dock icon. Clicking its icon opens a single popover that fits without scrolling.

The accepted layout is **limits first**:

1. Header with application name, last-refresh state, and refresh action.
2. Codex card with separate short-window and weekly rows.
3. Claude Code card with the same structure.
4. S/M/L segmented task-size control.
5. Recommendation card with the selected provider and a one-sentence explanation.
6. Footer with the age of the data and settings access.

Every quota row shows:

- percentage remaining;
- a progress bar representing the remaining percentage;
- an absolute or relative reset time;
- a textual state in addition to color.

The interface always presents **remaining** rather than consumed quota. Color is supplementary and never the only way to communicate state. VoiceOver labels expose provider, window, remaining percentage, and reset time.

## Domain Model

The domain is independent of SwiftUI, HTTP, processes, and Keychain.

### Core values

- `ProviderIdentifier`: `codex` or `claudeCode`.
- `QuotaWindowKind`: `short`, `weekly`, or the optional `modelWeekly`.
- `QuotaWindow`: remaining percentage, optional reset timestamp, kind, and an optional `scopeLabel` naming what a scoped window covers, such as the model of a model-scoped week.
- `QuotaSnapshot`: provider, available windows, and fetch timestamp.
- `TaskSize`: `small`, `medium`, or `large`.
- `TaskSizePolicy`: required remaining percentage per window for each task size.
- `Recommendation`: recommended provider, neutral choice, no safe choice, or unavailable, plus an explanation.

Only `short` and `weekly` are required from a provider; `QuotaWindowKind.requiredForRecommendation` names them so completeness is never derived from `allCases`. A snapshot without a `modelWeekly` window is complete, because only Claude Code meters a model-scoped week.

Percentages are validated at the infrastructure boundary and clamped only when a provider returns a small floating-point deviation outside 0–100. Structurally invalid data is rejected instead of silently converted.

Live compatibility finding: Claude can return valid utilization with a null reset for an idle window. Preserve the percentage and represent the missing reset explicitly. Display `Reset unavailable`; do not invent a timestamp. Windows with unknown reset times are excluded from cross-provider recommendations. A non-null malformed reset remains an unsupported payload.

### Provider boundary

Infrastructure adapters implement one interface:

```swift
protocol QuotaProvider {
    var identifier: ProviderIdentifier { get }
    func fetchSnapshot() async throws -> QuotaSnapshot
}
```

The application layer does not know where credentials or raw payloads originate. Provider implementations can change without changing recommendation rules or UI state.

## Architecture

The code follows four explicit boundaries:

### Domain

Owns quota values, task policies, recommendation rules, and validation-independent business concepts. It depends only on the Swift standard library and Foundation value types needed for dates.

### Application

Owns the refresh use case, concurrent provider coordination, cache policy, stale-data policy, and conversion into presentation state. It depends on `QuotaProvider`, `QuotaCache`, and `Clock` protocols.

### Infrastructure

Contains:

- `CodexQuotaProvider`;
- `ClaudeQuotaProvider`;
- `CodexAppServerClient`;
- `ClaudeCredentialReader`;
- HTTP client abstraction;
- local non-sensitive snapshot cache;
- executable discovery and process execution.

### Presentation

Contains the SwiftUI menu-bar scene, provider cards, task-size control, recommendation card, loading states, and actionable error messages. Views receive immutable presentation models and do not invoke infrastructure directly.

## Data Flow

1. The user opens the menu-bar panel.
2. The application checks whether the last successful refresh is younger than the 30-second request cooldown.
3. If refresh is required, both providers are fetched concurrently.
4. Each successful raw response is validated and normalized into `QuotaSnapshot`.
5. Each successful snapshot replaces that provider's cached snapshot independently.
6. The application marks snapshots older than 15 minutes as stale.
7. The recommendation engine evaluates fresh, complete snapshots against the selected task-size policy.
8. SwiftUI renders raw values first and the recommendation below them.

Opening the panel and pressing refresh count as user-initiated actions. Version 0.1 does not poll while the panel is closed.

## Provider Integrations

### Codex

The Codex adapter uses the documented local app-server interface:

1. Locate the user's `codex` executable using configured standard locations, the inherited process path, or a manual path override.
2. Start `codex app-server --listen stdio://` as a child process.
3. Complete the verified initialization handshake: an `initialize` request, then an id-less `initialized` notification. Messages are line-delimited JSON objects that carry no `jsonrpc` field, and while awaiting a correlated response the reader skips id-less notifications and responses addressed to another id.
4. Call `account/rateLimits/read`.
5. Map the returned primary and secondary/multi-bucket windows into short and weekly windows based on their reported duration.
6. Terminate the child process after the response or timeout, escalating SIGTERM to SIGKILL when the child outlives its grace period.

Codex manages its own OAuth credentials and refresh lifecycle. Agent Preflight never reads Codex tokens.

Live compatibility finding: the app-server `RateLimitWindow` schema declares both `resetsAt` and `windowDurationMins` as nullable. A null `resetsAt` is kept as an unknown reset; the percentage is preserved, `Reset unavailable` is displayed, and the window is excluded from cross-provider recommendations. A window whose `windowDurationMins` is missing is skipped, because its position in the payload does not identify it as short or weekly. A non-null but non-positive `resetsAt` or `windowDurationMins` is an unsupported payload.

### Claude Code

The Claude adapter uses the same OAuth usage resource used by Claude Code:

- `GET https://api.anthropic.com/api/oauth/usage`
- `Authorization: Bearer <access token>`
- `anthropic-beta: oauth-2025-04-20`

The access token is read from the existing Claude Code credential in macOS Keychain through the Security framework. The expected credential owner is the `Claude Code-credentials` item and its Claude OAuth payload. Credential identifiers and parsing rules are centralized in provider configuration rather than spread through the code.

Security constraints:

- The credential is read only as part of a user-initiated refresh.
- The token exists only in memory for the request lifetime.
- It is never copied to application preferences, the snapshot cache, diagnostics, or logs.
- The application does not ask for a password, session cookie, or manually pasted bearer token.
- A denied Keychain request remains denied until another explicit user action.
- A 401 response produces re-authentication guidance and does not trigger a hidden login flow.

Live compatibility finding: an idle window can return a valid `utilization` with a null `resets_at`. A null reset is kept as an unknown reset; the percentage is preserved, `Reset unavailable` is displayed, and the window is excluded from cross-provider recommendations. A non-null malformed reset is an unsupported payload.

The model-scoped week that `/usage` shows as `Weekly · <model>` comes from a newer optional `limits` array rather than from `five_hour`/`seven_day`, which keep carrying the session and the all-models week. The parser reads only the `limits` entries whose `kind` is `weekly_scoped` and that report a `percent`; when several are present it keeps the most consumed one, because that is the limit the task reaches first. Its `scope.model.display_name` becomes the window's `scopeLabel`, falling back to `Model` when the payload does not name it. An absent `limits` array simply produces no `modelWeekly` window, so older responses behave exactly as before.

This endpoint and the Claude credential shape are not a public compatibility contract. They are the primary maintenance risk and are isolated behind `ClaudeQuotaProvider` and fixture-tested parsers.

## Recommendation Policy

The default policy is intentionally conservative:

| Task size | Required short-window reserve | Required weekly reserve |
|---|---:|---:|
| S | 15% | 5% |
| M | 35% | 10% |
| L | 60% | 20% |

For provider `p` and selected task size `t`, the safety margin is:

```text
minimum(
  p.shortRemaining / t.requiredShortRemaining,
  p.bindingWeeklyRemaining / t.requiredWeeklyRemaining
)
```

The binding weekly window is the more constraining of the all-models week and, when the provider reports one, the model-scoped week; a tie keeps the all-models week. A failed weekly constraint is reported against that window, so the explanation names the model when the scoped week is the one below reserve. A model-scoped window that is present but has an unknown or already passed reset disables the provider's assessment, exactly like a missing required window.

Decision rules:

1. A provider is safe when both ratios are at least 1.0.
2. If only one provider is safe, recommend it.
3. If both are safe, recommend the provider with the larger safety margin.
4. If the absolute difference between the two dimensionless safety margins is below `0.10`, return a neutral recommendation: both are safe choices.
5. If neither is safe, return no safe choice and identify the failed constraints plus the nearest relevant reset.
6. If either provider lacks a required window, has stale data, or failed to refresh without a sufficiently fresh cache, do not make a cross-provider recommendation.

The copy uses “safer choice” and never claims that a task will finish. Default thresholds live in one `TaskSizePolicy` configuration and are not duplicated in UI code.

## Caching and Time

Only normalized, non-sensitive quota snapshots are persisted locally. Cache records contain provider identifiers, percentages, reset timestamps, and fetch timestamps.

- A fetch result younger than 30 seconds satisfies a new panel-open request.
- Data older than 15 minutes is visibly stale and excluded from recommendation.
- Reset countdowns use an injected clock and update locally without refetching.
- A passed reset timestamp does not automatically imply 100% remaining; that window becomes unknown until refreshed because usage may occur through another vendor surface.

## Error Handling

Provider failures are isolated and represented as typed application errors:

- executable missing;
- provider not authenticated;
- Keychain access denied;
- credential payload invalid;
- request timed out;
- unauthorized response;
- rate limited response;
- unsupported provider response;
- child process or protocol failure;
- network unavailable.

The UI keeps the last successful snapshot when available, marks it stale, and shows a provider-specific recovery action. An error from one provider never clears or blocks the other provider.

Timeouts are five seconds per provider. Version 0.1 performs no automatic retry; the user can retry explicitly. This avoids duplicate Keychain prompts and aggressive calls to an internal Claude resource.

## Security and Privacy

- No backend, analytics SDK, crash-upload service, or remote logging.
- Least-privilege access to one Claude Keychain item.
- No browser-cookie extraction.
- No storage of access or refresh tokens by Agent Preflight.
- No secrets, raw authorization headers, or credential payloads passed to `Logger`.
- Diagnostic messages contain provider, operation, typed error category, and timestamps only.
- HTTPS is mandatory for the Claude request; redirects to a different host are rejected.
- Child-process arguments never include secrets.
- The snapshot-cache directory is created with mode `0700`, and cache files are created with mode `0600`.

## Testing Strategy

### Unit tests

- All recommendation outcomes for S/M/L.
- Exact threshold boundaries.
- Neutral result within the 10% margin tolerance.
- No-safe-choice explanations and nearest-reset selection.
- Missing, stale, malformed, and partially available windows.
- Remaining-percentage conversion and timestamp formatting.

### Contract and parser tests

- Redacted Codex app-server response fixtures, including primary-only, primary/secondary, and multi-bucket shapes.
- Redacted Claude OAuth usage fixtures, including short, weekly, and optional model-specific windows.
- Unknown fields, missing optional values, invalid percentages, and changed envelope shapes.

### Infrastructure tests

- Mock JSON-RPC process transport for initialization, response correlation, timeout, malformed output, and non-zero exit.
- Mock HTTP transport for success, 401, 429, timeout, redirect rejection, and invalid JSON.
- Mock credential reader for success, absence, invalid shape, and access denial.
- Cache tests with an injected filesystem and clock.
- Log-capture tests asserting that token-like fixture values never appear.

### Presentation tests

- Loading, success, partial success, stale, unauthenticated, and total-failure states.
- Accessibility labels for both provider cards and all quota windows.
- Smoke test that the selected task size updates the recommendation without another network request.

Tests run through `swift test`. Live-account verification is a documented manual smoke test and is never part of CI.

## MVP Delivery Budget

| Work item | Target |
|---|---:|
| Claude credential and endpoint spike | 1 h |
| Domain models and provider contracts | 1.5 h |
| Codex adapter | 2 h |
| Claude adapter | 3 h |
| Menu-bar UI | 3 h |
| Recommendation, cache, and errors | 1.5 h |
| Tests, README, and local build | 2 h |
| **Total** | **14 h** |

The first hour is a stop/go spike. If Keychain access or the current Claude OAuth response cannot be made reliable without copying credentials or automating the interactive TUI, implementation stops and the design is revisited. The estimate covers source, tests, a local build, and GitHub documentation. Signing and notarization are a separate validation-stage investment.

## Definition of Done

Version 0.1 is complete when:

- it runs as a menu-bar-only application on macOS 14 or newer;
- real subscribed Codex and Claude Code accounts return their available quota windows;
- the UI shows remaining percentages and correct reset times;
- S/M/L produces the specified deterministic result and explanation;
- one provider can fail without affecting the other provider's display;
- stale and incomplete data never produce a confident recommendation;
- automated tests cover domain rules, parsers, error mapping, and secret redaction;
- no Agent Preflight storage or logs contain credentials;
- the repository documents installation, authentication expectations, privacy behavior, tests, and known Claude compatibility risk.

## Validation and Monetization

Version 0.1 is a free GitHub release containing the full basic flow. It is used to validate demand rather than to maximize first-release revenue.

The public version 0.1 code is licensed under MIT. Future Pro behavior is isolated behind public application interfaces and implemented in a separately distributed private Swift target or package; the free core remains buildable without it.

Further development requires either 100 GitHub stars or 30 active testers. If neither threshold is reached, the project remains a small portfolio utility.

After validation:

- Free keeps current limits, reset times, manual refresh, and the default recommendation.
- Pro is a one-time USD 15–20 purchase.
- The planned first Pro release includes configurable task policies, threshold/reset notifications, local history, and recommendations calibrated from prior local usage.
- Payments and licensing use a merchant-of-record rather than a custom billing backend.
- Recurring subscriptions are explicitly avoided while the product has no recurring hosted cost or ongoing service component.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Claude changes an internal endpoint or Keychain shape | Isolated adapter, fixture tests, fail-closed parsing, documented compatibility risk |
| Static task thresholds imply false precision | Conservative defaults, explicit explanation, “safer” wording, no completion promise |
| Existing free quota monitors dominate discovery | Position around pre-task agent selection, not general usage monitoring |
| Keychain prompt damages user trust | Prompt only after explicit action, explain purpose before first access, never copy credentials |
| Scope exceeds 15 hours | One-hour Claude stop/go spike and strict version 0.1 non-goals |
| Unsigned builds reduce adoption | Validate through source/local builds first; sign and notarize only after demand exists |

## References

- OpenAI Codex app-server documentation: <https://developers.openai.com/codex/app-server>
- Claude Code status-line quota fields: <https://code.claude.com/docs/en/statusline>
- Claude Code usage commands: <https://support.claude.com/en/articles/14553413-claude-code-cheatsheet>
- Competitive reference, CodexBar: <https://github.com/steipete/CodexBar>
- Competitive reference, OpenQuota: <https://github.com/deviffyy/OpenQuota>
