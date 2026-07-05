#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
TARGET_DIR="/Library/Input Methods"
TARGET_APP="$TARGET_DIR/LeftIO.app"
USER_INPUT_METHOD_APP="$HOME/Library/Input Methods/LeftIO.app"
OLD_SYSTEM_CONTAINER="/Applications/LeftIO.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

shell_quote() {
  printf '%q' "$1"
}

pkill -x LeftIO 2>/dev/null || true
pkill -x LeftIOInputMethod 2>/dev/null || true
pkill -x LeftIOLauncher 2>/dev/null || true

"$LSREGISTER" -u "$USER_INPUT_METHOD_APP" 2>/dev/null || true
"$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -u "$OLD_SYSTEM_CONTAINER" 2>/dev/null || true

rm -rf "$USER_INPUT_METHOD_APP"

ROOT_INSTALL_COMMAND="mkdir -p $(shell_quote "$TARGET_DIR"); rm -rf $(shell_quote "$TARGET_APP") $(shell_quote "$OLD_SYSTEM_CONTAINER"); ditto $(shell_quote "$SOURCE_APP") $(shell_quote "$TARGET_APP"); chown -R root:wheel $(shell_quote "$TARGET_APP"); xattr -cr $(shell_quote "$TARGET_APP") 2>/dev/null || true; xattr -dr com.apple.quarantine $(shell_quote "$TARGET_APP") 2>/dev/null || true; xattr -dr com.apple.provenance $(shell_quote "$TARGET_APP") 2>/dev/null || true; xattr -dr com.apple.macl $(shell_quote "$TARGET_APP") 2>/dev/null || true"

if [[ "${LEFTIO_INSTALL_WITH_SUDO:-0}" == "1" ]]; then
  sudo /bin/bash -c "$ROOT_INSTALL_COMMAND"
else
  APPLESCRIPT_INSTALL_COMMAND="${ROOT_INSTALL_COMMAND//\\/\\\\}"
  APPLESCRIPT_INSTALL_COMMAND="${APPLESCRIPT_INSTALL_COMMAND//\"/\\\"}"
osascript <<APPLESCRIPT
do shell script "$APPLESCRIPT_INSTALL_COMMAND" with administrator privileges
APPLESCRIPT
fi

"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
"$TARGET_APP/Contents/MacOS/LeftIO" --register-installed-input-source || {
  echo "warning: TIS registration helper did not complete; log out and log back in, then add LeftIO from System Settings." >&2
}

cat >&2 <<'MSG'
LeftIO was installed system-wide.

Next steps:
  1. Log out of macOS and log back in if this is the first install or the input source list looks stale.
  2. Open System Settings -> Keyboard -> Text Input -> Edit...
  3. Add "LeftIO 单手九宫格" manually.

This installer does not write com.apple.HIToolbox and does not switch the current input source.
MSG

echo "$TARGET_APP"
