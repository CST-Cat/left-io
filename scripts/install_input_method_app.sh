#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${LEFTIO_SOURCE_APP:-$ROOT_DIR/.build/input-method/LeftIO.app}"
TARGET_DIR="${LEFTIO_TARGET_DIR:-$HOME/Library/Input Methods}"
TARGET_APP="$TARGET_DIR/LeftIO.app"
TRANSACTION_DIR="$HOME/Library/Application Support/LeftIO/InstallTransactions/cli-$$"
STAGING_APP="$TRANSACTION_DIR/staged.app"
BACKUP_APP="$TRANSACTION_DIR/previous.app"
OLD_USER_APPLICATION_APP="${LEFTIO_OLD_USER_APP:-$HOME/Applications/LeftIO.app}"
SYSTEM_INPUT_METHOD_APP="${LEFTIO_SYSTEM_INPUT_METHOD_APP:-/Library/Input Methods/LeftIO.app}"
LSREGISTER="${LEFTIO_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"
INPUT_SOURCE_SESSION_HELPER="${LEFTIO_INPUT_SOURCE_SESSION_HELPER:-$ROOT_DIR/scripts/manage_input_source_session.sh}"
PRESERVE_TRANSACTION=0
RESTORE_LEFTIO_SELECTION=0

register_bundle() {
  local app="$1"
  if [[ -n "${LEFTIO_REGISTRATION_HELPER:-}" ]]; then
    "$LEFTIO_REGISTRATION_HELPER" "$app"
  else
    "$app/Contents/MacOS/LeftIO" --register-installed-input-source
  fi
}

verify_bundle() {
  local app="$1"
  if [[ -n "${LEFTIO_VERIFY_HELPER:-}" ]]; then
    "$LEFTIO_VERIFY_HELPER" "$app"
  else
    LEFTIO_VERIFY_APP="$app" "$ROOT_DIR/scripts/verify_input_method_install.sh"
  fi
}

clear_runtime_added_attributes() {
  local app="$1"
  local attributes

  # Starting the signed registration helper can cause macOS to attach macl to
  # the containing bundle even though the staged copy was clean. Normalize
  # only the two attributes that are hard failures. The attachment can arrive
  # just after the helper exits, so recheck instead of assuming one removal won
  # the race.
  for _ in 1 2 3 4; do
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
    xattr -dr com.apple.macl "$app" 2>/dev/null || true
    attributes="$(xattr -lr "$app" 2>&1)" || return 1
    if ! grep -Eq 'com\.apple\.(quarantine|macl)' <<<"$attributes"; then
      return 0
    fi
    sleep 0.2
  done
  echo "Unable to clear quarantine or macl metadata from $app." >&2
  return 1
}

register_and_normalize_bundle() {
  local app="$1"
  register_bundle "$app" || return 1
  clear_runtime_added_attributes "$app"
}

restore_leftio_selection() {
  local app="$1"
  for _ in 1 2 3; do
    open -n -gj "$app" 2>/dev/null || true
    sleep 0.4
    if "$INPUT_SOURCE_SESSION_HELPER" select "$MODE_ID" >/dev/null 2>&1; then
      sleep 0.2
      if pgrep -x LeftIO >/dev/null 2>&1; then
        return 0
      fi
    fi
  done
  return 1
}

restore_previous_installation() {
  if [[ -e "$TARGET_APP" ]] && ! rm -rf "$TARGET_APP"; then
    PRESERVE_TRANSACTION=1
    echo "Unable to remove the failed LeftIO activation at $TARGET_APP." >&2
    return 1
  fi

  if [[ ! -d "$BACKUP_APP" ]]; then
    return 0
  fi
  if ! mv "$BACKUP_APP" "$TARGET_APP"; then
    PRESERVE_TRANSACTION=1
    echo "Unable to restore the previous LeftIO bundle; it remains at $BACKUP_APP." >&2
    return 1
  fi

  "$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
  if ! register_and_normalize_bundle "$TARGET_APP" || ! verify_bundle "$TARGET_APP"; then
    echo "The previous LeftIO bundle was restored, but its TIS registration could not be verified." >&2
    return 2
  fi
  return 0
}

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi
if [[ -z "${LEFTIO_TARGET_DIR:-}" ]] && [[ -d "$SYSTEM_INPUT_METHOD_APP" ]]; then
  echo "A system-level LeftIO is already installed at $SYSTEM_INPUT_METHOD_APP." >&2
  echo "Remove or update that copy instead of creating a duplicate user source." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TRANSACTION_DIR"
mkdir -p "$TRANSACTION_DIR"

cleanup() {
  if [[ "$PRESERVE_TRANSACTION" == "1" ]]; then
    echo "Preserving failed install transaction at $TRANSACTION_DIR." >&2
  else
    rm -rf "$TRANSACTION_DIR"
  fi
  if [[ "$RESTORE_LEFTIO_SELECTION" == "1" ]] && [[ -d "$TARGET_APP" ]]; then
    if ! restore_leftio_selection "$TARGET_APP"; then
      echo "Unable to restore LeftIO as the selected input source after installation." >&2
    fi
  fi
}
trap cleanup EXIT

ditto "$SOURCE_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP" 2>/dev/null || true
if ! STAGED_ATTRIBUTES="$(xattr -lr "$STAGING_APP" 2>&1)"; then
  echo "Unable to inspect extended attributes on staged LeftIO: $STAGED_ATTRIBUTES" >&2
  exit 1
fi
if grep -Eq 'com\.apple\.(quarantine|macl)' <<<"$STAGED_ATTRIBUTES"; then
  echo "Staged LeftIO still contains quarantine or macl metadata." >&2
  exit 1
fi
codesign -vvv --deep --strict "$STAGING_APP" >/dev/null 2>&1

if [[ -z "${LEFTIO_TARGET_DIR:-}" ]] && [[ "${LEFTIO_SKIP_INPUT_SOURCE_RESTORE:-0}" != "1" ]]; then
  CURRENT_INPUT_SOURCE="$($INPUT_SOURCE_SESSION_HELPER current)"
  if [[ "$CURRENT_INPUT_SOURCE" == "$MODE_ID" || "$CURRENT_INPUT_SOURCE" == "$BUNDLE_ID" ]]; then
    if ! "$INPUT_SOURCE_SESSION_HELPER" select-fallback "$MODE_ID" "$BUNDLE_ID" >/dev/null; then
      echo "LeftIO is selected, but no safe fallback input source could be selected before updating it." >&2
      exit 1
    fi
    RESTORE_LEFTIO_SELECTION=1
  fi
fi

if [[ "${LEFTIO_SKIP_PROCESS_STOP:-0}" != "1" ]]; then
  pkill -x LeftIO 2>/dev/null || true
  pkill -x LeftIOInputMethod 2>/dev/null || true
  pkill -x LeftIOLauncher 2>/dev/null || true
fi

"$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -u "$OLD_USER_APPLICATION_APP" 2>/dev/null || true

if [[ -d "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$BACKUP_APP"
fi

if ! mv "$STAGING_APP" "$TARGET_APP"; then
  if restore_previous_installation; then
    echo "Failed to activate the staged LeftIO bundle; the previous installation was restored." >&2
    exit 1
  else
    restore_status=$?
  fi
  if [[ "$restore_status" == "2" ]]; then
    exit 2
  fi
  exit 3
fi

"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
if ! register_and_normalize_bundle "$TARGET_APP" || ! verify_bundle "$TARGET_APP"; then
  if restore_previous_installation; then
    echo "LeftIO registration or verification failed; the previous installation state was restored." >&2
    exit 1
  else
    restore_status=$?
  fi
  if [[ "$restore_status" == "2" ]]; then
    exit 2
  fi
  exit 3
fi

rm -rf "$BACKUP_APP" "$OLD_USER_APPLICATION_APP"

if [[ "$RESTORE_LEFTIO_SELECTION" == "1" ]]; then
  if ! restore_leftio_selection "$TARGET_APP"; then
    echo "LeftIO was installed, but the installer could not restore it as the selected input source." >&2
    exit 5
  fi
  RESTORE_LEFTIO_SELECTION=0
fi

cat >&2 <<'MSG'
LeftIO was installed for the current user.

Next steps:
  1. Log out of macOS and log back in if this is the first install or the input source list looks stale.
  2. Open System Settings -> Keyboard -> Text Input -> Edit...
  3. Add "LeftIO 单手九宫格" manually.

This installer does not write com.apple.HIToolbox. When updating a currently
selected LeftIO, it temporarily selects the ASCII fallback and restores LeftIO
after the new endpoint is running; otherwise it leaves the current source alone.
If LeftIO appears twice, run: make repair-input-method-sources
MSG

echo "$TARGET_APP"
