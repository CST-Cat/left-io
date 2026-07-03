#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
SOURCE_LAUNCHER_APP="$ROOT_DIR/.build/input-method/launcher/LeftIO.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

if [[ ! -d "$SOURCE_LAUNCHER_APP" ]]; then
  echo "Missing $SOURCE_LAUNCHER_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

osascript <<APPLESCRIPT
do shell script "pkill -x LeftIOInputMethod 2>/dev/null || true; rm -rf /Library/Input\\\\ Methods/LeftIO.app; rm -rf /Applications/LeftIO.app; rm -rf '$HOME/Library/Input Methods/LeftIO.app'; ditto '$SOURCE_APP' '/Library/Input Methods/LeftIO.app'; ditto '$SOURCE_LAUNCHER_APP' '/Applications/LeftIO.app'; chown -R root:wheel '/Library/Input Methods/LeftIO.app' '/Applications/LeftIO.app'; xattr -dr com.apple.quarantine '/Library/Input Methods/LeftIO.app' '/Applications/LeftIO.app' 2>/dev/null || true" with administrator privileges
APPLESCRIPT

pkill -x TextInputMenuAgent 2>/dev/null || true
pkill -x TextInputSwitcher 2>/dev/null || true
pkill -x imklaunchagent 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$HOME/Library/Input Methods/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -u "/Library/Input Methods/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -u "/Applications/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -f "/Library/Input Methods/LeftIO.app" 2>/dev/null || true
"$LSREGISTER" -f "/Applications/LeftIO.app" 2>/dev/null || true
open -g "/Library/Input Methods/LeftIO.app"

echo "/Library/Input Methods/LeftIO.app"
echo "/Applications/LeftIO.app"
