#!/usr/bin/env bash
set -euo pipefail

readonly script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "$script_directory/.." && pwd)"
readonly app_name="Agent Preflight"
readonly executable_name="AgentPreflight"
readonly bundle_identifier="com.agentpreflight.app"
readonly output_root="${OUTPUT_ROOT:-$repository_root/dist}"
cd "$repository_root"
# `--show-bin-path` only reports the path, so the release binary is built explicitly first.
swift build -c release
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
