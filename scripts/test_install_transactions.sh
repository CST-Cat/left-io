#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/input-method/LeftIO.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Build the input method first." >&2
  exit 1
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leftio-install-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
MACL_REGISTRATION_HELPER="$TEST_ROOT/register-with-macl.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'xattr -w com.apple.macl runtime-added "$1"'
} > "$MACL_REGISTRATION_HELPER"
chmod +x "$MACL_REGISTRATION_HELPER"
FAKE_HOME="$TEST_ROOT/home"
USER_TARGET_DIR="$FAKE_HOME/Library/Input Methods"
USER_TARGET_APP="$USER_TARGET_DIR/LeftIO.app"
SYSTEM_TARGET_DIR="$TEST_ROOT/system/Input Methods"
SYSTEM_TARGET_APP="$SYSTEM_TARGET_DIR/LeftIO.app"
ROOT_TRANSACTION_DIR="$TEST_ROOT/system/transactions"
USER_SYSTEM_APP="$FAKE_HOME/Library/Input Methods/LeftIO.app"
OLD_SYSTEM_CONTAINER="$TEST_ROOT/system/old-container.app"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_APP/Contents/Info.plist")"
QUARANTINED_SOURCE_APP="$TEST_ROOT/quarantined/LeftIO.app"
mkdir -p "$(dirname "$QUARANTINED_SOURCE_APP")"
ditto "$SOURCE_APP" "$QUARANTINED_SOURCE_APP"
xattr -w com.apple.quarantine '0081;LeftIOInstallTest;Codex;' \
  "$QUARANTINED_SOURCE_APP/Contents/MacOS/LeftIO"

copy_app_with_version() {
  local destination="$1"
  local version="$2"
  rm -rf "$destination"
  mkdir -p "$(dirname "$destination")"
  ditto "$SOURCE_APP" "$destination"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$destination/Contents/Info.plist"
}

assert_version() {
  local app="$1"
  local expected="$2"
  [[ -d "$app" ]] || {
    echo "Expected app to exist: $app" >&2
    exit 1
  }
  local actual
  actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [[ "$actual" == "$expected" ]] || {
    echo "Expected $app version $expected, got $actual." >&2
    exit 1
  }
}

common_user_environment=(
  HOME="$FAKE_HOME"
  LEFTIO_SOURCE_APP="$QUARANTINED_SOURCE_APP"
  LEFTIO_TARGET_DIR="$USER_TARGET_DIR"
  LEFTIO_OLD_USER_APP="$FAKE_HOME/Applications/LeftIO.app"
  LEFTIO_LSREGISTER=/usr/bin/true
  LEFTIO_SKIP_PROCESS_STOP=1
  LEFTIO_VERIFY_HELPER=/usr/bin/true
)

env "${common_user_environment[@]}" \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/true \
  "$ROOT_DIR/scripts/install_input_method_app.sh" >/dev/null
assert_version "$USER_TARGET_APP" "$SOURCE_VERSION"
if xattr -lr "$USER_TARGET_APP" 2>/dev/null | grep -q 'com.apple.quarantine'; then
  echo "User installer propagated quarantine metadata from its source." >&2
  exit 1
fi

env "${common_user_environment[@]}" \
  LEFTIO_REGISTRATION_HELPER="$MACL_REGISTRATION_HELPER" \
  "$ROOT_DIR/scripts/install_input_method_app.sh" >/dev/null
if xattr -lr "$USER_TARGET_APP" 2>/dev/null | grep -q 'com.apple.macl'; then
  echo "User installer retained macl metadata added by the registration helper." >&2
  exit 1
fi

copy_app_with_version "$USER_TARGET_APP" 9001
if env "${common_user_environment[@]}" \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/false \
  "$ROOT_DIR/scripts/install_input_method_app.sh" >/dev/null 2>&1; then
  echo "User installer unexpectedly succeeded with a failing registration helper." >&2
  exit 1
fi
assert_version "$USER_TARGET_APP" 9001

common_system_environment=(
  HOME="$FAKE_HOME"
  LEFTIO_SOURCE_APP="$SOURCE_APP"
  LEFTIO_SYSTEM_TARGET_DIR="$SYSTEM_TARGET_DIR"
  LEFTIO_ROOT_TRANSACTION_DIR="$ROOT_TRANSACTION_DIR"
  LEFTIO_USER_INPUT_METHOD_APP="$USER_SYSTEM_APP"
  LEFTIO_OLD_SYSTEM_CONTAINER="$OLD_SYSTEM_CONTAINER"
  LEFTIO_LSREGISTER=/usr/bin/true
  LEFTIO_SKIP_PROCESS_STOP=1
  LEFTIO_VERIFY_HELPER=/usr/bin/true
)

rm -rf "$SYSTEM_TARGET_APP"
copy_app_with_version "$USER_SYSTEM_APP" 9101
if env "${common_system_environment[@]}" \
  LEFTIO_TEST_ADMIN_FAIL=1 \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/true \
  "$ROOT_DIR/scripts/install_input_method_app_system.sh" >/dev/null 2>&1; then
  echo "System installer unexpectedly succeeded when authorization was denied." >&2
  exit 1
fi
assert_version "$USER_SYSTEM_APP" 9101
[[ ! -e "$SYSTEM_TARGET_APP" ]] || {
  echo "System target changed before administrator authorization succeeded." >&2
  exit 1
}

copy_app_with_version "$SYSTEM_TARGET_APP" 9151
copy_app_with_version "$USER_SYSTEM_APP" 9152
if env "${common_system_environment[@]}" \
  LEFTIO_TEST_NO_ADMIN=1 \
  LEFTIO_TEST_USER_BACKUP_FAIL=1 \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/true \
  "$ROOT_DIR/scripts/install_input_method_app_system.sh" >/dev/null 2>&1; then
  echo "System installer unexpectedly succeeded when the user backup could not be staged." >&2
  exit 1
fi
assert_version "$SYSTEM_TARGET_APP" 9151
assert_version "$USER_SYSTEM_APP" 9152

copy_app_with_version "$SYSTEM_TARGET_APP" 9201
copy_app_with_version "$USER_SYSTEM_APP" 9301
if env "${common_system_environment[@]}" \
  LEFTIO_TEST_NO_ADMIN=1 \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/false \
  "$ROOT_DIR/scripts/install_input_method_app_system.sh" >/dev/null 2>&1; then
  echo "System installer unexpectedly succeeded with a failing registration helper." >&2
  exit 1
fi
assert_version "$SYSTEM_TARGET_APP" 9201
assert_version "$USER_SYSTEM_APP" 9301

env "${common_system_environment[@]}" \
  LEFTIO_TEST_NO_ADMIN=1 \
  LEFTIO_REGISTRATION_HELPER=/usr/bin/true \
  "$ROOT_DIR/scripts/install_input_method_app_system.sh" >/dev/null
assert_version "$SYSTEM_TARGET_APP" "$SOURCE_VERSION"
[[ ! -e "$USER_SYSTEM_APP" ]] || {
  echo "Successful system install did not remove the duplicate user bundle." >&2
  exit 1
}
[[ ! -e "$ROOT_TRANSACTION_DIR" ]] || {
  echo "Successful system install left its root transaction backup behind." >&2
  exit 1
}

env "${common_system_environment[@]}" \
  LEFTIO_TEST_NO_ADMIN=1 \
  LEFTIO_REGISTRATION_HELPER="$MACL_REGISTRATION_HELPER" \
  "$ROOT_DIR/scripts/install_input_method_app_system.sh" >/dev/null
if xattr -lr "$SYSTEM_TARGET_APP" 2>/dev/null | grep -q 'com.apple.macl'; then
  echo "System installer retained macl metadata added by the registration helper." >&2
  exit 1
fi

copy_app_with_version "$SYSTEM_TARGET_APP" 9401
copy_app_with_version "$USER_SYSTEM_APP" 9402
if env \
  HOME="$FAKE_HOME" \
  LEFTIO_UNINSTALL_SYSTEM=1 \
  LEFTIO_SYSTEM_INPUT_METHOD_APP="$SYSTEM_TARGET_APP" \
  LEFTIO_USER_INPUT_METHOD_APP="$USER_SYSTEM_APP" \
  LEFTIO_USER_APPLICATION_APP="$FAKE_HOME/Applications/LeftIO.app" \
  LEFTIO_OLD_SYSTEM_CONTAINER="$OLD_SYSTEM_CONTAINER" \
  LEFTIO_LSREGISTER=/usr/bin/true \
  LEFTIO_DISABLE_SOURCES_HELPER=/usr/bin/true \
  LEFTIO_TEST_ADMIN_FAIL=1 \
  "$ROOT_DIR/scripts/uninstall_input_method_app.sh" >/dev/null 2>&1; then
  echo "System uninstaller unexpectedly succeeded when authorization was denied." >&2
  exit 1
fi
assert_version "$SYSTEM_TARGET_APP" 9401
assert_version "$USER_SYSTEM_APP" 9402

echo "Install transaction tests passed."
