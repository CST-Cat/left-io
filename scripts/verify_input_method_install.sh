#!/usr/bin/env bash
set -euo pipefail

USER_INPUT_METHOD_APP="$HOME/Library/Input Methods/LeftIO.app"
SYSTEM_INPUT_METHOD_APP="/Library/Input Methods/LeftIO.app"
APP_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"

if [[ -n "${LEFTIO_VERIFY_APP:-}" ]]; then
  INSTALLED_APP="$LEFTIO_VERIFY_APP"
elif [[ -d "$USER_INPUT_METHOD_APP" ]]; then
  INSTALLED_APP="$USER_INPUT_METHOD_APP"
elif [[ -d "$SYSTEM_INPUT_METHOD_APP" ]]; then
  INSTALLED_APP="$SYSTEM_INPUT_METHOD_APP"
else
  echo "missing: $USER_INPUT_METHOD_APP"
  echo "missing: $SYSTEM_INPUT_METHOD_APP"
  exit 1
fi

echo "== Installed bundle =="
echo "$INSTALLED_APP"
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  -c 'Print :CFBundleExecutable' \
  -c 'Print :InputMethodConnectionName' \
  -c 'Print :InputMethodServerControllerClass' \
  "$INSTALLED_APP/Contents/Info.plist"

echo
echo "== Code signature =="
codesign -vvv --deep --strict "$INSTALLED_APP" 2>&1

echo
echo "== Extended attributes =="
if xattr -lr "$INSTALLED_APP" 2>/dev/null | rg 'quarantine|provenance'; then
  echo "warning: quarantine/provenance attributes are still present"
else
  echo "ok: no quarantine/provenance attributes found"
fi

echo
echo "== TIS sources =="
swift -e '
import Carbon
import Foundation

let appBundleID = "'"$APP_BUNDLE_ID"'"
let modeID = "'"$MODE_ID"'"

func value(_ source: TISInputSource, _ property: CFString?) -> String {
    guard let property,
          let rawValue = TISGetInputSourceProperty(source, property) else {
        return "-"
    }
    return String(describing: unsafeBitCast(rawValue, to: CFTypeRef.self))
}

let allSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [AnyObject] ?? []
print("all", allSources.count)

var foundBundle = false
var foundMode = false
var selectedMode = false
var enabledBundle = false
var enabledMode = false
var selectCapableMode = false

for anySource in allSources {
    let source = unsafeBitCast(anySource, to: TISInputSource.self)
    let sourceID = value(source, kTISPropertyInputSourceID)
    let inputModeID = value(source, kTISPropertyInputModeID)
    let bundleID = value(source, kTISPropertyBundleID)
    let line = [
        sourceID,
        inputModeID,
        bundleID,
        value(source, kTISPropertyInputSourceType),
        value(source, kTISPropertyLocalizedName),
        value(source, kTISPropertyInputSourceIsEnabled),
        value(source, kTISPropertyInputSourceIsSelectCapable),
        value(source, kTISPropertyInputSourceIsSelected)
    ].joined(separator: " | ")

    if bundleID == appBundleID || sourceID == modeID || inputModeID == modeID {
        print(line)
    }

    if bundleID == appBundleID {
        foundBundle = true
        if sourceID == appBundleID {
            enabledBundle = value(source, kTISPropertyInputSourceIsEnabled) == "1"
        }
    }
    if sourceID == modeID || inputModeID == modeID {
        foundMode = true
        enabledMode = value(source, kTISPropertyInputSourceIsEnabled) == "1"
        selectCapableMode = value(source, kTISPropertyInputSourceIsSelectCapable) == "1"
        selectedMode = value(source, kTISPropertyInputSourceIsSelected) == "1"
    }
}

if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
    print("current", value(current, kTISPropertyInputSourceID), value(current, kTISPropertyLocalizedName), value(current, kTISPropertyBundleID))
}

print("bundle=\(foundBundle)")
print("mode=\(foundMode)")
print("bundleEnabled=\(enabledBundle)")
print("modeEnabled=\(enabledMode)")
print("modeSelectCapable=\(selectCapableMode)")
print("selected=\(selectedMode)")

if !foundBundle || !foundMode {
    exit(2)
}
if !enabledBundle || !enabledMode || !selectCapableMode {
    exit(3)
}
'
