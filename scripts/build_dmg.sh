#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_APP="$ROOT_DIR/.build/input-method/launcher/LeftIO.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
STAGE_DIR="$DMG_DIR/LeftIO"
OUTPUT_DMG="$DMG_DIR/LeftIO.dmg"

if [[ ! -d "$LAUNCHER_APP" ]]; then
  echo "Missing launcher app. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

rm -rf "$STAGE_DIR" "$OUTPUT_DMG"
mkdir -p "$STAGE_DIR"

ditto "$LAUNCHER_APP" "$STAGE_DIR/LeftIO.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "LeftIO" \
  -srcfolder "$STAGE_DIR" \
  -fs HFS+ \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

echo "$OUTPUT_DMG"
