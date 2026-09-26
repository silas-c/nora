#!/usr/bin/env bash
# Runs the desktop-ui tests. Extra arguments are passed to `swift test`.
# With only the Command Line Tools installed (no Xcode), SwiftPM does not add Swift Testing's
# search paths, and some installs ship a _Testing_Foundation overlay without its module files.
set -euo pipefail
cd "$(dirname "$0")/.."

flags=()
developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  flags+=(
    -Xswiftc -F -Xswiftc "$frameworks"
    -Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing"
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
    -Xlinker -F -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$frameworks"
  )
fi

swift test ${flags[@]+"${flags[@]}"} "$@"
