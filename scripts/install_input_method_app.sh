#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
INSTALL_DIR="$HOME/Library/Input Methods"
TARGET_APP="$INSTALL_DIR/LeftIO.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
pkill -x LeftIOInputMethod 2>/dev/null || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
codesign --force --deep --sign - "$TARGET_APP"

pkill -x TextInputMenuAgent 2>/dev/null || true
pkill -x TextInputSwitcher 2>/dev/null || true
pkill -x imklaunchagent 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
"$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true

open -g "$TARGET_APP"
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" || true

echo "$TARGET_APP"
