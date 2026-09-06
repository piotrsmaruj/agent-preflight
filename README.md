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

If `swift test` fails to find the testing framework, see
[Building with Command Line Tools only](#building-with-command-line-tools-only).

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

Formatting is enforced with the same command CI runs; `--strict` turns findings into a non-zero exit
status instead of a warning:

```bash
swift format lint --strict --recursive Package.swift Sources Tests
```

The `.swift-format` file at the repository root pins the formatter configuration explicitly, so a different swift-format build formats this repository identically.

The following opt-in smoke tests access the currently signed-in provider accounts. They never run in CI and must not be attached to public bug reports with verbose network logging:

```bash
AGENT_PREFLIGHT_LIVE_CLAUDE=1 swift test --filter testLiveClaudeUsageWhenExplicitlyEnabled
AGENT_PREFLIGHT_LIVE_CODEX=1 swift test --filter testLiveCodexUsageWhenExplicitlyEnabled
```

## Known limitations

Claude's OAuth usage endpoint and foreign Keychain payload are internal contracts and may change. Missing/stale windows intentionally disable comparison. Builds are ad-hoc signed and not notarized in v0.1.

## Troubleshooting

| Displayed message | Action |
|---|---|
| Codex executable not found. Set its path in Settings. | Set the absolute path in Settings or make `codex` available in PATH. |
| Run `codex login`, then refresh. / Run `claude login`, then refresh. | Sign in to the named provider CLI, then refresh. |
| Allow access to Claude Code credentials in Keychain, then refresh. | Refresh again and approve access to `Claude Code-credentials`. |
| Claude credentials are unsupported. Run `claude logout && claude login`. | Re-create the Claude credential, then refresh. |
| The provider did not respond within 5 seconds. Refresh to try again. | Check connectivity and refresh after 30 seconds. |
| The provider rejected the current login. Sign in again, then refresh. | Sign in with the provider CLI again, then refresh. |
| Usage lookup is rate limited. Wait a moment, then refresh. | Wait a few minutes, then refresh manually. |
| This provider version returned an unsupported usage format. | Check for a newer Agent Preflight release and report only app/provider versions plus the displayed error category. |
| Codex app-server exited before returning usage. | Confirm `codex app-server --listen stdio://` starts from your shell, then refresh. |
| Codex app-server returned an invalid protocol response. | Update the Codex CLI, then refresh. |
| Claude usage endpoint returned an unexpected response. Refresh to try again. | Refresh; if it persists, check for a newer Agent Preflight release. |
| Usage could not be reached. Check the network, then refresh. | Check connectivity and refresh. |

Never paste a Keychain dump, auth file, bearer token, authorization header, cookie, or unredacted provider response into Agent Preflight or a GitHub issue.

### Building with Command Line Tools only

Plain `swift test` requires a full Xcode toolchain, because the Swift Testing framework is resolved from the Xcode developer directory. Continuous integration uses such a toolchain, so the plain command is the supported one there.

On a machine that only has the Command Line Tools installed, `swift build` works unchanged but `swift test` fails to locate `Testing.framework`. Run the tests from the repository root with the framework search paths pointed at the Command Line Tools developer directory:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path .build -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

Append `--filter '<SuiteName|testName>'` for a focused run. The same fallback flags apply to `swift build -c release` if it reports a sandbox or module-cache permission error.

## License

MIT
