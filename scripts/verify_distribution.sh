#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/input-method/LeftIO.app}"
DMG_PATH="${2:-}"
REQUIRED_ARCHS="${LEFTIO_REQUIRED_ARCHS:-arm64 x86_64}"
EXPECTED_MIN_SYSTEM_VERSION="${LEFTIO_EXPECTED_MIN_SYSTEM_VERSION:-13.0}"
EXPECTED_VERSION="${LEFTIO_EXPECTED_VERSION:-}"
EXPECTED_BUILD_NUMBER="${LEFTIO_EXPECTED_BUILD_NUMBER:-}"
EXPECTED_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
EXPECTED_MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"

fail() {
  echo "Distribution verification failed: $*" >&2
  exit 1
}

verify_architectures() {
  local binary="$1"
  [[ -f "$binary" ]] || fail "missing binary $binary"
  local architectures
  architectures="$(lipo -archs "$binary")"
  local required
  for required in $REQUIRED_ARCHS; do
    [[ " $architectures " == *" $required "* ]] ||
      fail "$binary is missing $required (contains: $architectures)"
  done
}

verify_no_download_metadata() {
  local path="$1"
  local attributes
  if ! attributes="$(xattr -lr "$path" 2>&1)"; then
    fail "unable to inspect extended attributes on $path: $attributes"
  fi
  if grep -Eq 'com\.apple\.(quarantine|macl)' <<<"$attributes"; then
    fail "$path contains quarantine or macl metadata"
  fi
  if grep -q 'com.apple.provenance' <<<"$attributes"; then
    echo "Warning: macOS retained protected provenance metadata on $path." >&2
  fi
}

verify_license_directory() {
  local directory="$1"
  local label="$2"
  local license_file
  for license_file in \
    GPL-3.0-only.txt \
    LGPL-3.0-only.txt \
    boost-BSL-1.0.txt \
    glog-BSD-3-Clause.txt \
    googletest-BSD-3-Clause.txt \
    leveldb-BSD-3-Clause.txt \
    librime-BSD-3-Clause.txt \
    marisa-trie-COPYING.md \
    opencc-Apache-2.0.txt \
    yaml-cpp-MIT.txt; do
    [[ -s "$directory/$license_file" ]] ||
      fail "$label is missing license file $license_file"
  done
}

verify_app() {
  local app="$1"
  [[ -d "$app" ]] || fail "missing app $app"
  [[ -f "$app/Contents/Info.plist" ]] || fail "missing Info.plist in $app"
  [[ -f "$app/Contents/Resources/LICENSE.txt" ]] || fail "missing project license in $app"
  [[ -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md" ]] ||
    fail "missing third-party notices in $app"
  verify_license_directory "$app/Contents/Resources/Licenses" "$app"
  for artifact in \
    default.yaml \
    onehand_t9.schema.yaml \
    onehand_t9.prism.bin \
    onehand_t9.table.bin \
    onehand_t9.reverse.bin; do
    [[ -f "$app/Contents/Resources/Rime/build/$artifact" ]] ||
      fail "missing prebuilt Rime artifact $artifact in $app"
  done

  local executable
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
  verify_architectures "$app/Contents/MacOS/$executable"

  local bundle_id mode_id connection_name minimum_version version build_number
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
  mode_id="$(/usr/libexec/PlistBuddy -c 'Print :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0' "$app/Contents/Info.plist")"
  connection_name="$(/usr/libexec/PlistBuddy -c 'Print :InputMethodConnectionName' "$app/Contents/Info.plist")"
  minimum_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] ||
    fail "expected bundle id $EXPECTED_BUNDLE_ID, got $bundle_id"
  [[ "$mode_id" == "$EXPECTED_MODE_ID" ]] ||
    fail "expected mode id $EXPECTED_MODE_ID, got $mode_id"
  [[ "$connection_name" == "${EXPECTED_BUNDLE_ID}_Connection" ]] ||
    fail "unexpected input method connection $connection_name"
  [[ "$minimum_version" == "$EXPECTED_MIN_SYSTEM_VERSION" ]] ||
    fail "expected macOS $EXPECTED_MIN_SYSTEM_VERSION minimum, got $minimum_version"
  [[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail "invalid app version $version"
  [[ "$build_number" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "invalid build number $build_number"
  if [[ -n "$EXPECTED_VERSION" ]] && [[ "$version" != "$EXPECTED_VERSION" ]]; then
    fail "expected app version $EXPECTED_VERSION, got $version"
  fi
  if [[ -n "$EXPECTED_BUILD_NUMBER" ]] && [[ "$build_number" != "$EXPECTED_BUILD_NUMBER" ]]; then
    fail "expected build number $EXPECTED_BUILD_NUMBER, got $build_number"
  fi

  local dylib
  dylib="$(find "$app/Contents/Frameworks" -maxdepth 1 -type f -name 'librime*.dylib' -print -quit)"
  [[ -n "$dylib" ]] || fail "bundled librime is missing"
  verify_architectures "$dylib"
  codesign --verify --deep --strict --verbose=2 "$app"
  verify_no_download_metadata "$app"
}

verify_app "$APP_PATH"

if [[ -n "$DMG_PATH" ]]; then
  [[ -f "$DMG_PATH" ]] || fail "missing disk image $DMG_PATH"
  verify_no_download_metadata "$DMG_PATH"
  hdiutil verify "$DMG_PATH" >/dev/null

  MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/leftio-dmg.XXXXXX")"
  cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  }
  trap cleanup EXIT
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null

  [[ -x "$MOUNT_POINT/Install LeftIO.command" ]] || fail "DMG installer command is missing"
  [[ -f "$MOUNT_POINT/LICENSE.txt" ]] || fail "DMG project license is missing"
  [[ -f "$MOUNT_POINT/THIRD_PARTY_NOTICES.md" ]] || fail "DMG notices are missing"
  verify_license_directory "$MOUNT_POINT/LICENSES" "DMG"
  verify_app "$MOUNT_POINT/LeftIO.app"

  if [[ "${LEFTIO_REQUIRE_GATEKEEPER:-0}" == "1" ]]; then
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
    spctl --assess --type execute --verbose=2 "$MOUNT_POINT/LeftIO.app"
  fi
fi

echo "Distribution verification passed."
