#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_APP="$TARGET_DIR/LeftIO.app"
OLD_USER_APPLICATION_APP="$HOME/Applications/LeftIO.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

pkill -x LeftIO 2>/dev/null || true
pkill -x LeftIOInputMethod 2>/dev/null || true
pkill -x LeftIOLauncher 2>/dev/null || true

"$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -u "$OLD_USER_APPLICATION_APP" 2>/dev/null || true

rm -rf "$TARGET_APP"
rm -rf "$OLD_USER_APPLICATION_APP"

ditto "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
xattr -dr com.apple.provenance "$TARGET_APP" 2>/dev/null || true
xattr -dr com.apple.macl "$TARGET_APP" 2>/dev/null || true

"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
"$TARGET_APP/Contents/MacOS/LeftIO" --register-installed-input-source || {
  echo "warning: TIS registration helper did not complete; log out and log back in, then add LeftIO from System Settings." >&2
}

cat >&2 <<'MSG'
LeftIO was installed for the current user.

Next steps:
  1. Log out of macOS and log back in if this is the first install or the input source list looks stale.
  2. Open System Settings -> Keyboard -> Text Input -> Edit...
  3. Add "LeftIO 单手九宫格" manually.

This installer does not write com.apple.HIToolbox and does not switch the current input source.
If LeftIO appears twice, run: make repair-input-method-sources
MSG

echo "$TARGET_APP"
