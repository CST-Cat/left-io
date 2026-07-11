#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_METHOD_APP="$ROOT_DIR/.build/input-method/LeftIO.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
STAGE_DIR="$DMG_DIR/LeftIO"
OUTPUT_DMG="${LEFTIO_DMG_OUTPUT:-$DMG_DIR/LeftIO.dmg}"
INSTALL_COMMAND="$STAGE_DIR/Install LeftIO.command"
README_FILE="$STAGE_DIR/README.txt"
DMG_SIGNING_IDENTITY="${LEFTIO_DMG_SIGNING_IDENTITY:-}"

if [[ ! -d "$INPUT_METHOD_APP" ]]; then
  echo "Missing input method app. Run scripts/build_input_method_app.sh first." >&2
  exit 1
fi

rm -rf "$STAGE_DIR"
rm -f "$OUTPUT_DMG"
mkdir -p "$STAGE_DIR" "$(dirname "$OUTPUT_DMG")"

ditto "$INPUT_METHOD_APP" "$STAGE_DIR/LeftIO.app"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGE_DIR/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT_DIR/LICENSES" "$STAGE_DIR/LICENSES"
cat > "$INSTALL_COMMAND" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
open "$SCRIPT_DIR/LeftIO.app"
SH
chmod +x "$INSTALL_COMMAND"

cat > "$README_FILE" <<'TXT'
LeftIO is a macOS input method. Do not drag it to /Applications.

Install:
1. Open "Install LeftIO.command" or "LeftIO.app" from this disk image.
2. LeftIO copies itself to ~/Library/Input Methods/LeftIO.app and registers with macOS.
3. Open System Settings -> Keyboard -> Text Input -> Edit... and add "LeftIO 单手九宫格".
4. If the input source list looks stale, log out and log back in.
TXT

hdiutil create \
  -volname "LeftIO" \
  -srcfolder "$STAGE_DIR" \
  -fs HFS+ \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

if [[ -n "$DMG_SIGNING_IDENTITY" ]]; then
  if [[ "$DMG_SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "LEFTIO_DMG_SIGNING_IDENTITY must be a Developer ID Application identity." >&2
    exit 1
  fi
  codesign --force --timestamp --sign "$DMG_SIGNING_IDENTITY" "$OUTPUT_DMG"
  codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

echo "$OUTPUT_DMG"
