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
INFO_PLIST="$INSTALLED_APP/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || {
  echo "missing Info.plist: $INFO_PLIST" >&2
  exit 2
}
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
CONNECTION_NAME="$(/usr/libexec/PlistBuddy -c 'Print :InputMethodConnectionName' "$INFO_PLIST")"
CONTROLLER_CLASS="$(/usr/libexec/PlistBuddy -c 'Print :InputMethodServerControllerClass' "$INFO_PLIST")"
printf '%s\n' "$BUNDLE_IDENTIFIER" "$BUNDLE_EXECUTABLE" "$CONNECTION_NAME" "$CONTROLLER_CLASS"
[[ "$BUNDLE_IDENTIFIER" == "$APP_BUNDLE_ID" ]] || {
  echo "unexpected bundle identifier: $BUNDLE_IDENTIFIER" >&2
  exit 2
}
[[ "$BUNDLE_EXECUTABLE" == "LeftIO" ]] || {
  echo "unexpected bundle executable: $BUNDLE_EXECUTABLE" >&2
  exit 2
}
[[ "$CONNECTION_NAME" == "${APP_BUNDLE_ID}_Connection" ]] || {
  echo "unexpected input method connection: $CONNECTION_NAME" >&2
  exit 2
}
[[ "$CONTROLLER_CLASS" == "LeftIOInputController" ]] || {
  echo "unexpected input method controller: $CONTROLLER_CLASS" >&2
  exit 2
}

echo
echo "== Code signature =="
codesign -vvv --deep --strict "$INSTALLED_APP" 2>&1

echo
echo "== Extended attributes =="
if ! ALL_ATTRIBUTES="$(xattr -lr "$INSTALLED_APP" 2>&1)"; then
  echo "unable to inspect extended attributes: $ALL_ATTRIBUTES" >&2
  exit 4
fi
UNSAFE_ATTRIBUTE_OUTPUT="$(grep -E 'com\.apple\.(quarantine|macl)' <<<"$ALL_ATTRIBUTES" || true)"
if [[ -n "$UNSAFE_ATTRIBUTE_OUTPUT" ]]; then
  printf '%s\n' "$UNSAFE_ATTRIBUTE_OUTPUT"
  echo "error: quarantine or macl attributes are still present" >&2
  exit 4
fi
PROVENANCE_OUTPUT="$(grep -F 'com.apple.provenance' <<<"$ALL_ATTRIBUTES" || true)"
if [[ -n "$PROVENANCE_OUTPUT" ]]; then
  printf '%s\n' "$PROVENANCE_OUTPUT"
  echo "warning: provenance attributes are present; TIS verification must still pass"
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

func boolValue(_ source: TISInputSource, _ property: CFString?) -> Bool? {
    guard let property,
          let rawValue = TISGetInputSourceProperty(source, property) else {
        return nil
    }
    let value = unsafeBitCast(rawValue, to: CFTypeRef.self)
    guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
        return nil
    }
    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
}

let allSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [AnyObject] ?? []
print("all", allSources.count)

var foundBundle = false
var foundMode = false
var selectedMode = false
var enabledBundle = false
var enabledMode = false
var selectCapableMode = false
var bundleParentCount = 0
var modeCount = 0

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
            bundleParentCount += 1
            enabledBundle = enabledBundle || boolValue(source, kTISPropertyInputSourceIsEnabled) == true
        }
    }
    if sourceID == modeID || inputModeID == modeID {
        foundMode = true
        modeCount += 1
        enabledMode = enabledMode || boolValue(source, kTISPropertyInputSourceIsEnabled) == true
        selectCapableMode = selectCapableMode || boolValue(source, kTISPropertyInputSourceIsSelectCapable) == true
        selectedMode = selectedMode || boolValue(source, kTISPropertyInputSourceIsSelected) == true
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
print("bundleParentCount=\(bundleParentCount)")
print("modeCount=\(modeCount)")

if !foundBundle || !foundMode {
    exit(2)
}
if !enabledBundle || !enabledMode || !selectCapableMode {
    exit(3)
}
if bundleParentCount != 1 || modeCount != 1 {
    exit(4)
}
'
