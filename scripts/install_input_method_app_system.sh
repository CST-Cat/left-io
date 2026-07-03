#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
USER_INPUT_METHOD_APP="$HOME/Library/Input Methods/LeftIO.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

osascript <<APPLESCRIPT
do shell script "pkill -x LeftIOInputMethod 2>/dev/null || true; rm -rf '$USER_INPUT_METHOD_APP'; rm -rf /Library/Input\\\\ Methods/LeftIO.app; ditto '$SOURCE_APP' '/Library/Input Methods/LeftIO.app'; chown -R root:wheel '/Library/Input Methods/LeftIO.app'; xattr -dr com.apple.quarantine '/Library/Input Methods/LeftIO.app' 2>/dev/null || true" with administrator privileges
APPLESCRIPT

pkill -x TextInputMenuAgent 2>/dev/null || true
pkill -x TextInputSwitcher 2>/dev/null || true
pkill -x imklaunchagent 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
"$LSREGISTER" -u "$HOME/Library/Input Methods/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -u "/Library/Input Methods/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -f "/Library/Input Methods/LeftIO.app" 2>/dev/null || true

open -g "/Library/Input Methods/LeftIO.app"
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" || true

echo "/Library/Input Methods/LeftIO.app"
