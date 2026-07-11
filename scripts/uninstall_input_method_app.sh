#!/usr/bin/env bash
set -euo pipefail

USER_INPUT_METHOD_APP="${LEFTIO_USER_INPUT_METHOD_APP:-$HOME/Library/Input Methods/LeftIO.app}"
USER_APPLICATION_APP="${LEFTIO_USER_APPLICATION_APP:-$HOME/Applications/LeftIO.app}"
SYSTEM_INPUT_METHOD_APP="${LEFTIO_SYSTEM_INPUT_METHOD_APP:-/Library/Input Methods/LeftIO.app}"
OLD_SYSTEM_CONTAINER="${LEFTIO_OLD_SYSTEM_CONTAINER:-/Applications/LeftIO.app}"
APP_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"
LSREGISTER="${LEFTIO_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

shell_quote() {
  printf '%q' "$1"
}

disable_tis_sources() {
  if [[ -n "${LEFTIO_DISABLE_SOURCES_HELPER:-}" ]] &&
     [[ "$SYSTEM_INPUT_METHOD_APP" != "/Library/Input Methods/LeftIO.app" ]]; then
    "$LEFTIO_DISABLE_SOURCES_HELPER"
    return
  fi

  /usr/bin/swift - "$APP_BUNDLE_ID" "$MODE_ID" <<'SWIFT'
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
var disableFailed = false
for anySource in allSources {
    let source = unsafeBitCast(anySource, to: TISInputSource.self)
    let sourceID = stringValue(source, kTISPropertyInputSourceID)
    let inputModeID = stringValue(source, kTISPropertyInputModeID)
    let sourceBundleID = stringValue(source, kTISPropertyBundleID)
    if sourceBundleID == bundleID || sourceID == modeID || inputModeID == modeID {
        let status = TISDisableInputSource(source)
        print("disabled \(sourceID ?? inputModeID ?? sourceBundleID ?? "-") status=\(status)")
        disableFailed = disableFailed || status != noErr
    }
}
if disableFailed {
    exit(1)
}
SWIFT
}

run_as_administrator() {
  local command="$1"
  if [[ "${LEFTIO_TEST_ADMIN_FAIL:-0}" == "1" ]] &&
     [[ "$SYSTEM_INPUT_METHOD_APP" != "/Library/Input Methods/LeftIO.app" ]]; then
    return 1
  fi
  if [[ "${LEFTIO_TEST_NO_ADMIN:-0}" == "1" ]] &&
     [[ "$SYSTEM_INPUT_METHOD_APP" != "/Library/Input Methods/LeftIO.app" ]]; then
    /bin/bash -c "$command"
    return
  fi
  if [[ "${LEFTIO_INSTALL_WITH_SUDO:-0}" == "1" ]]; then
    sudo /bin/bash -c "$command"
    return
  fi

  local applescript_command="${command//\\/\\\\}"
  applescript_command="${applescript_command//\"/\\\"}"
  osascript <<APPLESCRIPT
do shell script "$applescript_command" with administrator privileges
APPLESCRIPT
}

if [[ "${LEFTIO_UNINSTALL_SYSTEM:-0}" == "1" ]] &&
   { [[ -d "$SYSTEM_INPUT_METHOD_APP" ]] || [[ -d "$OLD_SYSTEM_CONTAINER" ]]; }; then
  ROOT_UNINSTALL_COMMAND="rm -rf $(shell_quote "$SYSTEM_INPUT_METHOD_APP") $(shell_quote "$OLD_SYSTEM_CONTAINER")"
  if ! run_as_administrator "$ROOT_UNINSTALL_COMMAND"; then
    echo "System uninstall was not authorized; no LeftIO bundle was removed or disabled." >&2
    exit 1
  fi
fi

pkill -x LeftIO 2>/dev/null || true
pkill -x LeftIOInputMethod 2>/dev/null || true
pkill -x LeftIOLauncher 2>/dev/null || true

"$LSREGISTER" -u "$USER_INPUT_METHOD_APP" 2>/dev/null || true
"$LSREGISTER" -u "$USER_APPLICATION_APP" 2>/dev/null || true
if ! rm -rf "$USER_INPUT_METHOD_APP" "$USER_APPLICATION_APP"; then
  echo "Failed to remove one or more user LeftIO bundles." >&2
  exit 2
fi

if [[ "${LEFTIO_UNINSTALL_SYSTEM:-0}" == "1" ]]; then
  "$LSREGISTER" -u "$SYSTEM_INPUT_METHOD_APP" 2>/dev/null || true
  "$LSREGISTER" -u "$OLD_SYSTEM_CONTAINER" 2>/dev/null || true
fi

if [[ ! -d "$SYSTEM_INPUT_METHOD_APP" ]]; then
  if ! disable_tis_sources; then
    echo "LeftIO bundles were removed, but one or more cached TIS sources could not be disabled." >&2
    exit 2
  fi
else
  echo "preserving enabled TIS source because the system-level LeftIO copy remains installed"
fi

cat >&2 <<'MSG'
LeftIO was removed from the requested install locations.

If System Settings still shows LeftIO, log out of macOS and log back in.
MSG
