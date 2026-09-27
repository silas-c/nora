#!/bin/sh
set -eu

helper_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper_path=${1:-"$helper_dir/.build/debug/mac-helper"}
bundle="$helper_dir/.build/NoraMacHelper.app"
contents="$bundle/Contents"

if [ ! -x "$helper_path" ]; then
  echo "Helper executable not found: $helper_path" >&2
  echo "Build mac-helper first, then rerun this script." >&2
  exit 1
fi

mkdir -p "$contents/MacOS"
cp "$helper_dir/NoraMacHelper-Info.plist" "$contents/Info.plist"
cp "$helper_path" "$contents/MacOS/mac-helper"
chmod 755 "$contents/MacOS/mac-helper"
codesign --force --sign - --identifier ai.nora.mac-helper "$bundle"
echo "$bundle"
