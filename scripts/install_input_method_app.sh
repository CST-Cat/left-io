#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
INSTALL_DIR="$HOME/Library/Input Methods"
TARGET_APP="$INSTALL_DIR/LeftIO.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
pkill -x LeftIOInputMethod 2>/dev/null || true
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"

/usr/bin/mdls -name kMDItemCFBundleIdentifier "$TARGET_APP" || true
open "$TARGET_APP"

echo "$TARGET_APP"
