#!/usr/bin/env bash
# Builds apps/desktop-ui/.build/Nora.app and prints its path. Extra arguments go to `swift build`.
# A real bundle, signed with the same local certificate every time, gives macOS a stable identity for the
# Accessibility and Microphone permissions, and carries the usage descriptions that voice input requires.
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null || true)" == *CommandLineTools* && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration" --product nora-ui "$@" >&2
binary="$(swift build -c "$configuration" --show-bin-path "$@")/nora-ui"
repo_root="$(cd ../.. && pwd)"
app=".build/Nora.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Nora"
sed "s|__NORA_REPO_ROOT__|$repo_root|g" Bundle/Info.plist > "$app/Contents/Info.plist"
scripts/sign.sh "$app" com.owlhacks.nora >&2

echo "$(pwd)/$app"
