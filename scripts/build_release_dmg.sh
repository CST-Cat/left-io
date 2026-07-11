#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${LEFTIO_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${LEFTIO_NOTARY_PROFILE:-}"
RELEASE_VERSION="${LEFTIO_VERSION:-}"
RELEASE_BUILD_NUMBER="${LEFTIO_BUILD_NUMBER:-}"
DMG_PATH="$ROOT_DIR/.build/dmg/LeftIO.notarizing.dmg"
FINAL_DMG_PATH="$ROOT_DIR/.build/dmg/LeftIO.dmg"
NOTARY_RESULT_PATH="$ROOT_DIR/.build/dmg/notary-result.json"
NOTARY_LOG_PATH="$ROOT_DIR/.build/dmg/notary-log.json"

if [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Set LEFTIO_SIGNING_IDENTITY to a Developer ID Application identity." >&2
  exit 1
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set LEFTIO_NOTARY_PROFILE to a notarytool keychain profile." >&2
  exit 1
fi
if [[ -z "$RELEASE_VERSION" || -z "$RELEASE_BUILD_NUMBER" ]]; then
  echo "Set explicit LEFTIO_VERSION and LEFTIO_BUILD_NUMBER values for a release." >&2
  exit 1
fi
for unsupported_override in \
  LEFTIO_LIBRIME_REVISION \
  LEFTIO_LIBRIME_REF \
  LEFTIO_LIBRIME_DYLIB \
  LEFTIO_RIME_MINIMAL_DIR \
  LEFTIO_ALLOW_LEXICON_ONLY \
  LEFTIO_AUTO_BOOTSTRAP_LIBRIME \
  LEFTIO_MIN_SYSTEM_VERSION \
  LEFTIO_SDKROOT; do
  if [[ -n "${!unsupported_override:-}" ]]; then
    echo "$unsupported_override is not allowed in the reproducible release path." >&2
    exit 1
  fi
done
if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Developer ID identity is not available in the current keychain." >&2
  exit 1
fi

LEFTIO_BUILD_UNIVERSAL=1 \
LEFTIO_FORCE_CLEAN_LIBRIME=1 \
LEFTIO_MIN_SYSTEM_VERSION=13.0 \
  "$ROOT_DIR/scripts/build_vendored_librime.sh"
LEFTIO_ARCHS="arm64 x86_64" \
LEFTIO_MIN_SYSTEM_VERSION=13.0 \
LEFTIO_REQUIRE_DEVELOPER_ID=1 \
LEFTIO_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
LEFTIO_VERSION="$RELEASE_VERSION" \
LEFTIO_BUILD_NUMBER="$RELEASE_BUILD_NUMBER" \
  "$ROOT_DIR/scripts/build_input_method_app.sh"
LEFTIO_DMG_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
LEFTIO_DMG_OUTPUT="$DMG_PATH" \
  "$ROOT_DIR/scripts/build_dmg.sh"
LEFTIO_REQUIRED_ARCHS="arm64 x86_64" \
LEFTIO_EXPECTED_VERSION="$RELEASE_VERSION" \
LEFTIO_EXPECTED_BUILD_NUMBER="$RELEASE_BUILD_NUMBER" \
  "$ROOT_DIR/scripts/verify_distribution.sh" \
  "$ROOT_DIR/.build/input-method/LeftIO.app" \
  "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT_PATH"
SUBMISSION_ID="$(python3 - "$NOTARY_RESULT_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as file:
    result = json.load(file)
if result.get("status") != "Accepted":
    print(
        f"Notarization was not accepted: status={result.get('status')} id={result.get('id')}",
        file=sys.stderr,
    )
    raise SystemExit(1)
submission_id = result.get("id")
if not isinstance(submission_id, str) or not submission_id:
    print("Accepted notarization result did not include a submission id.", file=sys.stderr)
    raise SystemExit(1)
print(submission_id)
PY
)"
rm -f "$NOTARY_LOG_PATH"
xcrun notarytool log \
  --keychain-profile "$NOTARY_PROFILE" \
  "$SUBMISSION_ID" \
  "$NOTARY_LOG_PATH"
python3 - "$NOTARY_LOG_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as file:
    result = json.load(file)
issues = result.get("issues") or []
if issues:
    for issue in issues:
        print(
            "Notarization issue: "
            f"severity={issue.get('severity')} path={issue.get('path')} "
            f"message={issue.get('message')}",
            file=sys.stderr,
        )
    raise SystemExit(1)
PY
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

LEFTIO_REQUIRED_ARCHS="arm64 x86_64" \
LEFTIO_REQUIRE_GATEKEEPER=1 \
LEFTIO_EXPECTED_VERSION="$RELEASE_VERSION" \
LEFTIO_EXPECTED_BUILD_NUMBER="$RELEASE_BUILD_NUMBER" \
  "$ROOT_DIR/scripts/verify_distribution.sh" \
  "$ROOT_DIR/.build/input-method/LeftIO.app" \
  "$DMG_PATH"

mv -f "$DMG_PATH" "$FINAL_DMG_PATH"
echo "$FINAL_DMG_PATH"
