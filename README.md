# Agent Preflight

Choose the safer subscription-backed coding agent before starting a task.

## What it does

- Shows remaining — or used — short-window and weekly quota for Codex and Claude Code.
- Shows Claude's model-scoped week (`Weekly · Fable`) next to the all-models week whenever the usage endpoint reports one.
- Recommends the safer option for an S, M, or L task using reserves you can edit.
- Follows the macOS theme, or stays light or dark whatever macOS does.
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

## First run

### The Keychain prompt

Opening the panel for the first time reads the existing `Claude Code-credentials` Keychain item, and macOS shows an access prompt naming `AgentPreflight`. Choose **Always Allow**. A one-time **Allow** grants that single read only, so the prompt returns on every refresh that is not suppressed by the 30-second cooldown.

The prompt also returns after every rebuild or repackage: each build is ad-hoc signed with a new identity, so macOS treats it as a different application and asks again. That is expected on a rebuild and is not the repeated-prompt behaviour caused by choosing **Allow**.

### Finding the Codex executable

An app launched from Finder inherits launchd's `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), not the `PATH` exported by your shell. Agent Preflight therefore finds `codex` automatically only at `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`. For any other location, set the absolute path in Settings.

Prefer a native `codex` binary; the Homebrew cask installs one. An npm shim starts with `#!/usr/bin/env node` and additionally needs `node` reachable from the app's `PATH`, which launchd's `PATH` does not provide; it fails with "Codex app-server exited before returning usage".

## Authentication and privacy

Codex remains responsible for its credentials through app-server. Agent Preflight asks macOS Keychain for the existing `Claude Code-credentials` item only during a user-initiated refresh. Tokens are held only for the request lifetime and are never cached or logged. See PRIVACY.md.

## Settings

| Setting | Effect | Takes effect |
|---|---|---|
| Theme | System, Light, or Dark. System follows macOS. | Immediately |
| Quota display | Remaining counts down to empty; Used counts up from zero. The progress bar follows the same direction, while the `Plenty`/`Low` state always describes the quota that is left. | Immediately |
| Task sizes | The short-window and weekly reserve each size requires, plus the neutral tolerance. | On **Save** |
| Codex executable | Absolute path used when discovery cannot find `codex`. | On **Save** |

Both percentages describe the same window, so they always add up to 100; the app rounds once and subtracts, rather than rounding each independently.

A reserve is a percentage between 1 and 100 and the neutral tolerance is between 0 and 1. Typed values are validated on save: a rejected entry is reported inline and never reaches the recommendation. **Restore defaults** puts the documented policy back.

## Recommendation policy

The default reserves, and what **Restore defaults** writes:

| Size | Short-window reserve | Weekly reserve |
|---|---:|---:|
| S | 15% | 5% |
| M | 35% | 10% |
| L | 60% | 20% |

For each provider the app takes the lower of `short remaining / required short` and `weekly remaining / required weekly`. When Claude reports a model-scoped week, the weekly ratio uses whichever of the two weekly windows has less quota left, and an explanation names that model. One safe provider wins. When both are safe, the larger minimum margin wins; a difference below the neutral tolerance (`0.10` by default) is neutral. Missing, stale, or expired data disables comparison. “Safer choice” is a conservative quota comparison, not a guarantee that a task will finish.

Editing the reserves changes only which provider the app calls safer; it cannot change what a provider actually meters. A reserve of zero is rejected because it would make every provider infinitely safe and silently disable the comparison.

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
| Codex executable not found. Set its path in Settings. | The app searches only `/opt/homebrew/bin/codex` and `/usr/local/bin/codex`; for any other location set the absolute path in Settings. |
| Run `codex login`, then refresh. / Run `claude login`, then refresh. | Sign in to the named provider CLI, then refresh. |
| Allow access to Claude Code credentials in Keychain, then refresh. | Refresh again and approve access to `Claude Code-credentials`. |
| Claude credentials are unsupported. Run `claude logout && claude login`. | Re-create the Claude credential, then refresh. |
| The provider did not respond within 5 seconds. Refresh to try again. | Check connectivity and refresh after 30 seconds. |
| The provider rejected the current login. Sign in again, then refresh. | Sign in with the provider CLI again, then refresh. |
| Usage lookup is rate limited. Wait a moment, then refresh. | Wait a few minutes, then refresh manually. |
| This provider version returned an unsupported usage format. | Check for a newer Agent Preflight release and report only app/provider versions plus the displayed error category. |
| Codex app-server exited before returning usage. | Confirm `codex app-server --listen stdio://` starts from your shell, then refresh. The app runs with launchd's `PATH`, not the shell's, so an npm shim that needs `node` on `PATH` fails here even when the shell command succeeds; point Settings at a native `codex` binary. |
| Codex app-server returned an invalid protocol response. | Update the Codex CLI, then refresh. |
| Claude usage endpoint returned an unexpected response. Refresh to try again. | Refresh; if it persists, check for a newer Agent Preflight release. |
| Usage could not be reached. Check the network, then refresh. | Check connectivity and refresh. |

Never paste a Keychain dump, auth file, bearer token, authorization header, cookie, or unredacted provider response into Agent Preflight or a GitHub issue.

### Building with Command Line Tools only

Plain `swift test` requires a full Xcode toolchain, because the Swift Testing framework is resolved from the Xcode developer directory. Continuous integration uses such a toolchain, so the plain command is the supported one there.

On a machine that only has the Command Line Tools installed, `swift build` works unchanged but `swift test` fails to locate `Testing.framework`. Run the tests from the repository root with the framework search paths pointed at the Command Line Tools developer directory:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path .build -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

The `-plugin-path` argument points at the Swift Testing macro plugin. Without it the build stops at `external macro implementation type 'TestingMacros.TestDeclarationMacro' could not be found`, because the Command Line Tools ship the plugin outside the directories the compiler searches by default.

Append `--filter '<SuiteName|testName>'` for a focused run. The same fallback flags apply to `swift build -c release` if it reports a sandbox or module-cache permission error.

## License

MIT
