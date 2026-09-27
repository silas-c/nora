#!/usr/bin/env bash
# Builds everything Nora needs and opens the app.
#   scripts/run.sh          practice mode: the real agent with a synthetic Canvas, nothing on this Mac changes
#   scripts/run.sh --live   live mode: the Swift helper controls this Mac (needs Accessibility permission)
# Other arguments go to `swift build`.
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null || true)" == *CommandLineTools* && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ui="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$ui/../.." && pwd)"

mode="--mock"
swift_args=()
for arg in "$@"; do
  case "$arg" in
    --live|--mock) mode="$arg" ;;
    *) swift_args+=("$arg") ;;
  esac
done

[[ -d "$repo/node_modules" ]] || (cd "$repo" && npm ci)
(cd "$repo" && npm run build --silent)
if [[ "$mode" == "--live" ]]; then
  swift build --package-path "$repo/apps/macos-helper" ${swift_args[@]+"${swift_args[@]}"}
fi
app="$("$ui/scripts/bundle.sh" ${swift_args[@]+"${swift_args[@]}"} | tail -1)"

# Replace a copy that is already running so the new build is the one on screen.
pkill -x Nora 2>/dev/null && sleep 1 || true

# -g keeps the app the person is using in front. Nora must not become that app.
open_args=(-g -n "$app")
[[ -n "${ELEVENLABS_API_KEY:-}" ]] && open_args+=(--env "ELEVENLABS_API_KEY=$ELEVENLABS_API_KEY")
open "${open_args[@]}" --args "$mode"
echo "Nora is running in ${mode#--} mode. Double-tap Command for the listening notch; Control-H hides it."
