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
