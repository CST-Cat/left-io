#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"
OLD_BUNDLE_ID="io.github.cstcat.leftio"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

backup_preference_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp "$path" "$path.leftio-repair-bak-$TIMESTAMP"
  fi
}

preference_file_for_domain() {
  case "$1" in
    com.apple.HIToolbox)
      printf '%s\n' "$HOME/Library/Preferences/com.apple.HIToolbox.plist"
      ;;
    com.apple.inputsources)
      printf '%s\n' "$HOME/Library/Preferences/com.apple.inputsources.plist"
      ;;
    *)
      return 1
      ;;
  esac
}

repair_domain() {
  local domain="$1"
  local tmp_dir
  local exported
  tmp_dir="$(mktemp -d)"
  exported="$tmp_dir/$domain.plist"

  if ! defaults export "$domain" "$exported" 2>/dev/null; then
    rm -rf "$tmp_dir"
    return 0
  fi

  local repair_result
  repair_result="$(python3 - "$exported" "$domain" "$APP_BUNDLE_ID" "$MODE_ID" "$OLD_BUNDLE_ID" <<'PY'
import plistlib
import sys

path, domain, app_bundle_id, mode_id, old_bundle_id = sys.argv[1:6]

with open(path, "rb") as handle:
    plist = plistlib.load(handle)

changed = False

def is_old_leftio(entry):
    values = [
        entry.get("Bundle ID"),
        entry.get("Input Mode"),
        entry.get("InputSourceID"),
    ]
    return any(isinstance(value, str) and value.startswith(old_bundle_id) for value in values)

def is_leftio_mode(entry):
    return (
        entry.get("Bundle ID") == app_bundle_id
        and entry.get("Input Mode") == mode_id
    )

def is_leftio_parent(entry):
    return (
        entry.get("Bundle ID") == app_bundle_id
        and "Input Mode" not in entry
        and entry.get("InputSourceKind") == "Keyboard Input Method"
    )

def repair_array(name, entries):
    global changed
    if not isinstance(entries, list):
        return entries

    repaired = []
    kept_leftio_mode = False
    kept_leftio_parent = False

    for entry in entries:
        if not isinstance(entry, dict):
            repaired.append(entry)
            continue

        if is_old_leftio(entry):
            changed = True
            continue

        if domain == "com.apple.inputsources" and name == "AppleEnabledThirdPartyInputSources":
            if is_leftio_mode(entry):
                # HIToolbox already owns the selectable mode; keeping it here makes TIS show two LeftIO modes.
                changed = True
                continue
            if is_leftio_parent(entry):
                if kept_leftio_parent:
                    changed = True
                    continue
                kept_leftio_parent = True

        if domain == "com.apple.HIToolbox" and name == "AppleEnabledInputSources":
            if is_leftio_mode(entry):
                if kept_leftio_mode:
                    changed = True
                    continue
                kept_leftio_mode = True
            elif is_leftio_parent(entry):
                if kept_leftio_parent:
                    changed = True
                    continue
                kept_leftio_parent = True

        repaired.append(entry)

    if len(repaired) != len(entries):
        changed = True
    return repaired

for key, value in list(plist.items()):
    plist[key] = repair_array(key, value)

if changed:
    with open(path, "wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)

print("changed" if changed else "unchanged")
PY
)"
  echo "$domain: $repair_result"

  if [[ "$repair_result" != "changed" ]]; then
    rm -rf "$tmp_dir"
    return 0
  fi

  local result
  result="$(python3 - "$exported" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    plistlib.load(handle)
print("ok")
PY
)"

  if [[ "$result" == "ok" ]]; then
    local preference_file
    preference_file="$(preference_file_for_domain "$domain")"
    backup_preference_file "$preference_file"
    defaults import "$domain" "$exported"
  fi

  rm -rf "$tmp_dir"
}

repair_domain com.apple.HIToolbox
repair_domain com.apple.inputsources

killall cfprefsd 2>/dev/null || true
pkill -x LeftIO 2>/dev/null || true

cat >&2 <<MSG
LeftIO input-source preferences were repaired.

Only LeftIO entries were normalized:
  - removed old $OLD_BUNDLE_ID entries
  - kept one $MODE_ID entry in com.apple.HIToolbox
  - kept only the parent $APP_BUNDLE_ID entry in com.apple.inputsources

If System Settings still shows a stale duplicate, log out of macOS and log back in.
MSG
