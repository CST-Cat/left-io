#!/usr/bin/env bash
set -euo pipefail

USER_INPUT_METHOD_APP="$HOME/Library/Input Methods/LeftIO.app"
USER_APPLICATION_APP="$HOME/Applications/LeftIO.app"
SYSTEM_INPUT_METHOD_APP="/Library/Input Methods/LeftIO.app"
OLD_SYSTEM_CONTAINER="/Applications/LeftIO.app"
APP_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

shell_quote() {
  printf '%q' "$1"
}

/usr/bin/swift - "$APP_BUNDLE_ID" "$MODE_ID" <<'SWIFT' || true
import Carbon
import Foundation

let bundleID = CommandLine.arguments[1]
let modeID = CommandLine.arguments[2]

func stringValue(_ source: TISInputSource, _ property: CFString?) -> String? {
    guard let property,
          let rawValue = TISGetInputSourceProperty(source, property) else {
        return nil
    }
    let value = unsafeBitCast(rawValue, to: CFTypeRef.self)
    guard CFGetTypeID(value) == CFStringGetTypeID() else {
        return nil
    }
    return value as? String
}

let allSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [AnyObject] ?? []
for anySource in allSources {
    let source = unsafeBitCast(anySource, to: TISInputSource.self)
    let sourceID = stringValue(source, kTISPropertyInputSourceID)
    let inputModeID = stringValue(source, kTISPropertyInputModeID)
    let sourceBundleID = stringValue(source, kTISPropertyBundleID)
    if sourceBundleID == bundleID || sourceID == modeID || inputModeID == modeID {
        let status = TISDisableInputSource(source)
        print("disabled \(sourceID ?? inputModeID ?? sourceBundleID ?? "-") status=\(status)")
    }
}
SWIFT

pkill -x LeftIO 2>/dev/null || true
pkill -x LeftIOInputMethod 2>/dev/null || true
pkill -x LeftIOLauncher 2>/dev/null || true

"$LSREGISTER" -u "$USER_INPUT_METHOD_APP" 2>/dev/null || true
"$LSREGISTER" -u "$USER_APPLICATION_APP" 2>/dev/null || true
rm -rf "$USER_INPUT_METHOD_APP"
rm -rf "$USER_APPLICATION_APP"

if [[ "${LEFTIO_UNINSTALL_SYSTEM:-0}" == "1" ]]; then
  ROOT_UNINSTALL_COMMAND="rm -rf $(shell_quote "$SYSTEM_INPUT_METHOD_APP") $(shell_quote "$OLD_SYSTEM_CONTAINER")"
  if [[ "${LEFTIO_INSTALL_WITH_SUDO:-0}" == "1" ]]; then
    sudo /bin/bash -c "$ROOT_UNINSTALL_COMMAND"
  else
    APPLESCRIPT_UNINSTALL_COMMAND="${ROOT_UNINSTALL_COMMAND//\\/\\\\}"
    APPLESCRIPT_UNINSTALL_COMMAND="${APPLESCRIPT_UNINSTALL_COMMAND//\"/\\\"}"
osascript <<APPLESCRIPT
do shell script "$APPLESCRIPT_UNINSTALL_COMMAND" with administrator privileges
APPLESCRIPT
  fi
  "$LSREGISTER" -u "$SYSTEM_INPUT_METHOD_APP" 2>/dev/null || true
  "$LSREGISTER" -u "$OLD_SYSTEM_CONTAINER" 2>/dev/null || true
fi

cat >&2 <<'MSG'
LeftIO was removed from the requested install locations.

If System Settings still shows LeftIO, log out of macOS and log back in.
MSG
