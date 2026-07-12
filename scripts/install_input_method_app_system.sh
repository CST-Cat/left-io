#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${LEFTIO_SOURCE_APP:-$ROOT_DIR/.build/input-method/LeftIO.app}"
TARGET_DIR="${LEFTIO_SYSTEM_TARGET_DIR:-/Library/Input Methods}"
TARGET_APP="$TARGET_DIR/LeftIO.app"
ROOT_TRANSACTION_DIR="${LEFTIO_ROOT_TRANSACTION_DIR:-/Library/Application Support/LeftIO/InstallTransactions/system-$$}"
STAGING_APP="$ROOT_TRANSACTION_DIR/staged.app"
BACKUP_APP="$ROOT_TRANSACTION_DIR/previous.app"
USER_INPUT_METHOD_APP="${LEFTIO_USER_INPUT_METHOD_APP:-$HOME/Library/Input Methods/LeftIO.app}"
USER_TRANSACTION_DIR="$HOME/Library/Application Support/LeftIO/InstallTransactions/system-$$"
USER_BACKUP_APP="$USER_TRANSACTION_DIR/previous-user.app"
OLD_SYSTEM_CONTAINER="${LEFTIO_OLD_SYSTEM_CONTAINER:-/Applications/LeftIO.app}"
LSREGISTER="${LEFTIO_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

shell_quote() {
  printf '%q' "$1"
}

run_as_administrator() {
  local command="$1"
  if [[ "${LEFTIO_TEST_ADMIN_FAIL:-0}" == "1" ]] && [[ "$TARGET_DIR" != "/Library/Input Methods" ]]; then
    return 1
  fi
  if [[ "${LEFTIO_TEST_NO_ADMIN:-0}" == "1" ]] && [[ "$TARGET_DIR" != "/Library/Input Methods" ]]; then
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

register_bundle() {
  local app="$1"
  if [[ "$TARGET_DIR" != "/Library/Input Methods" ]] && [[ -n "${LEFTIO_REGISTRATION_HELPER:-}" ]]; then
    "$LEFTIO_REGISTRATION_HELPER" "$app"
  else
    "$app/Contents/MacOS/LeftIO" --register-installed-input-source
  fi
}

verify_bundle() {
  local app="$1"
  if [[ "$TARGET_DIR" != "/Library/Input Methods" ]] && [[ -n "${LEFTIO_VERIFY_HELPER:-}" ]]; then
    "$LEFTIO_VERIFY_HELPER" "$app"
  else
    LEFTIO_VERIFY_APP="$app" "$ROOT_DIR/scripts/verify_input_method_install.sh"
  fi
}

clear_runtime_added_attributes() {
  local app="$1"
  local quoted_app
  local cleanup_command
  quoted_app="$(shell_quote "$app")"
  cleanup_command="set -euo pipefail
for attempt in 1 2 3 4; do
  xattr -dr com.apple.quarantine $quoted_app 2>/dev/null || true
  xattr -dr com.apple.macl $quoted_app 2>/dev/null || true
  attributes=\$(xattr -lr $quoted_app 2>&1)
  if ! grep -Eq 'com\\.apple\\.(quarantine|macl)' <<<\"\$attributes\"; then
    exit 0
  fi
  sleep 0.2
done
echo 'Unable to clear quarantine or macl metadata from $app.' >&2
exit 1"

  if [[ "$app" == "$TARGET_APP" ]]; then
    run_as_administrator "$cleanup_command"
  else
    /bin/bash -c "$cleanup_command"
  fi
}

register_and_normalize_bundle() {
  local app="$1"
  register_bundle "$app" || return 1
  clear_runtime_added_attributes "$app"
}

ROOT_CHOWN_COMMAND="chown -R root:wheel $(shell_quote "$TARGET_APP")"
if [[ "$TARGET_DIR" != "/Library/Input Methods" ]]; then
  ROOT_CHOWN_COMMAND=":"
fi

ROOT_INSTALL_COMMAND="set -euo pipefail; mkdir -p $(shell_quote "$TARGET_DIR") $(shell_quote "$ROOT_TRANSACTION_DIR"); rm -rf $(shell_quote "$STAGING_APP") $(shell_quote "$BACKUP_APP"); ditto $(shell_quote "$SOURCE_APP") $(shell_quote "$STAGING_APP"); xattr -cr $(shell_quote "$STAGING_APP") 2>/dev/null || true; if ! xattr -lr $(shell_quote "$STAGING_APP") >/dev/null 2>&1; then echo 'Unable to inspect staged LeftIO extended attributes.' >&2; exit 2; fi; if xattr -lr $(shell_quote "$STAGING_APP") 2>/dev/null | grep -Eq 'com\\.apple\\.(quarantine|macl)'; then echo 'Staged LeftIO contains unsafe extended attributes.' >&2; exit 2; fi; codesign -vvv --deep --strict $(shell_quote "$STAGING_APP") >/dev/null 2>&1; if [[ -d $(shell_quote "$TARGET_APP") ]]; then mv $(shell_quote "$TARGET_APP") $(shell_quote "$BACKUP_APP"); fi; if ! mv $(shell_quote "$STAGING_APP") $(shell_quote "$TARGET_APP"); then if [[ -d $(shell_quote "$BACKUP_APP") ]]; then mv $(shell_quote "$BACKUP_APP") $(shell_quote "$TARGET_APP"); fi; exit 1; fi; $ROOT_CHOWN_COMMAND"
ROOT_ROLLBACK_COMMAND="set -euo pipefail; rm -rf $(shell_quote "$TARGET_APP"); if [[ -d $(shell_quote "$BACKUP_APP") ]]; then mv $(shell_quote "$BACKUP_APP") $(shell_quote "$TARGET_APP"); $ROOT_CHOWN_COMMAND; fi; rm -rf $(shell_quote "$ROOT_TRANSACTION_DIR")"

rollback_system_bundle() {
  run_as_administrator "$ROOT_ROLLBACK_COMMAND"
}

restore_user_bundle() {
  if [[ -d "$USER_BACKUP_APP" ]]; then
    if [[ -e "$USER_INPUT_METHOD_APP" ]]; then
      echo "Cannot restore the user LeftIO backup because $USER_INPUT_METHOD_APP already exists." >&2
      return 1
    fi
    if ! mv "$USER_BACKUP_APP" "$USER_INPUT_METHOD_APP"; then
      echo "Unable to restore the user LeftIO backup at $USER_BACKUP_APP." >&2
      return 1
    fi
  fi

  if [[ -d "$USER_INPUT_METHOD_APP" ]]; then
    "$LSREGISTER" -f "$USER_INPUT_METHOD_APP" 2>/dev/null || true
    if ! register_and_normalize_bundle "$USER_INPUT_METHOD_APP" || ! verify_bundle "$USER_INPUT_METHOD_APP"; then
      echo "The user LeftIO bundle was restored, but its TIS registration could not be verified." >&2
      return 2
    fi
  fi
  return 0
}

run_as_administrator "$ROOT_INSTALL_COMMAND"

if [[ "${LEFTIO_SKIP_PROCESS_STOP:-0}" != "1" ]]; then
  pkill -x LeftIO 2>/dev/null || true
  pkill -x LeftIOInputMethod 2>/dev/null || true
  pkill -x LeftIOLauncher 2>/dev/null || true
fi

"$LSREGISTER" -u "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -u "$OLD_SYSTEM_CONTAINER" 2>/dev/null || true

if ! rm -rf "$USER_TRANSACTION_DIR" || ! mkdir -p "$USER_TRANSACTION_DIR"; then
  if rollback_system_bundle; then
    echo "Unable to prepare the user migration transaction; the previous system installation was restored." >&2
    exit 1
  fi
  echo "Critical: unable to prepare the user migration transaction, and administrator rollback failed. The previous system bundle remains at $BACKUP_APP." >&2
  exit 2
fi
if [[ -d "$USER_INPUT_METHOD_APP" ]]; then
  "$LSREGISTER" -u "$USER_INPUT_METHOD_APP" 2>/dev/null || true
  if { [[ "${LEFTIO_TEST_USER_BACKUP_FAIL:-0}" == "1" ]] && [[ "$TARGET_DIR" != "/Library/Input Methods" ]]; } ||
     ! mv "$USER_INPUT_METHOD_APP" "$USER_BACKUP_APP"; then
    rollback_succeeded=1
    if ! rollback_system_bundle; then
      rollback_succeeded=0
    fi
    restore_status=0
    if restore_user_bundle; then
      :
    else
      restore_status=$?
    fi
    if [[ "$restore_status" == "0" ]]; then
      rm -rf "$USER_TRANSACTION_DIR"
    fi
    if [[ "$rollback_succeeded" != "1" || "$restore_status" != "0" ]]; then
      echo "Critical: user migration failed and the previous installation state could not be fully restored. System backup: $BACKUP_APP; user backup: $USER_BACKUP_APP." >&2
      exit 2
    fi
    echo "Unable to stage the user LeftIO copy; the previous user and system installations were restored." >&2
    exit 1
  fi
fi

"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
if ! register_and_normalize_bundle "$TARGET_APP" || ! verify_bundle "$TARGET_APP"; then
  ROLLBACK_SUCCEEDED=1
  if ! rollback_system_bundle; then
    ROLLBACK_SUCCEEDED=0
  fi
  RESTORE_STATUS=0
  if restore_user_bundle; then
    :
  else
    RESTORE_STATUS=$?
  fi
  if [[ ! -d "$USER_INPUT_METHOD_APP" ]] && [[ -d "$TARGET_APP" ]]; then
    "$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true
    if ! register_and_normalize_bundle "$TARGET_APP" || ! verify_bundle "$TARGET_APP"; then
      RESTORE_STATUS=2
      echo "The previous system LeftIO bundle was restored, but its TIS registration could not be verified." >&2
    fi
  fi
  if [[ "$RESTORE_STATUS" == "0" ]]; then
    rm -rf "$USER_TRANSACTION_DIR"
  fi
  if [[ "$ROLLBACK_SUCCEEDED" != "1" || "$RESTORE_STATUS" != "0" ]]; then
    echo "Critical: system registration failed and the previous installation state could not be fully verified. System backup: $BACKUP_APP; user backup: $USER_BACKUP_APP." >&2
    exit 2
  fi
  echo "System registration or verification failed; the previous installation was restored." >&2
  exit 1
fi

rm -rf "$USER_TRANSACTION_DIR"
ROOT_CLEANUP_COMMAND="rm -rf $(shell_quote "$ROOT_TRANSACTION_DIR") $(shell_quote "$OLD_SYSTEM_CONTAINER")"
if ! run_as_administrator "$ROOT_CLEANUP_COMMAND"; then
  echo "Warning: installation succeeded, but the administrator did not authorize cleanup of $ROOT_TRANSACTION_DIR." >&2
fi

cat >&2 <<'MSG'
LeftIO was installed system-wide.

Next steps:
  1. Log out of macOS and log back in if this is the first install or the input source list looks stale.
  2. Open System Settings -> Keyboard -> Text Input -> Edit...
  3. Add "LeftIO 单手九宫格" manually.

This installer does not write com.apple.HIToolbox and does not switch the current input source.
If LeftIO appears twice, run: make repair-input-method-sources
MSG

echo "$TARGET_APP"
