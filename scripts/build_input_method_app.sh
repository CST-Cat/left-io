#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDORED_RIME_ROOT="$ROOT_DIR/vendor/librime"
LIBRIME_BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/build_vendored_librime.sh"
INPUT_PRODUCT_NAME="LeftIOInputMethod"
APP_NAME="LeftIO"
APP_EXECUTABLE_NAME="LeftIO"
APP_BUNDLE_ID="io.github.cstcat.inputmethod.leftio"
MODE_ID="io.github.cstcat.inputmethod.leftio.onehandt9"
CONNECTION_NAME="${APP_BUNDLE_ID}_Connection"
BUILD_DIR="$ROOT_DIR/.build/input-method"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MIN_SYSTEM_VERSION="15.0"
RIME_MINIMAL_DIR="${LEFTIO_RIME_MINIMAL_DIR:-$VENDORED_RIME_ROOT/data/minimal}"

preferred_input_method_sdkroot() {
  local sdk_dir
  for sdk_dir in \
    /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk \
    /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15*.sdk; do
    if [[ -d "$sdk_dir" ]]; then
      echo "$sdk_dir"
      return 0
    fi
  done
  return 1
}

detect_vendored_librime() {
  for candidate in \
    "$VENDORED_RIME_ROOT/build/lib/librime.1.dylib" \
    "$VENDORED_RIME_ROOT/build/lib/Release/librime.1.dylib" \
    "$VENDORED_RIME_ROOT/dist/lib/librime.1.dylib" \
    "$VENDORED_RIME_ROOT/build/lib/librime.dylib" \
    "$VENDORED_RIME_ROOT/build/lib/Release/librime.dylib" \
    "$VENDORED_RIME_ROOT/dist/lib/librime.dylib"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

should_auto_bootstrap_librime() {
  if [[ "${LEFTIO_SKIP_LIBRIME_BOOTSTRAP:-0}" == "1" ]]; then
    return 1
  fi

  if [[ -n "${LEFTIO_AUTO_BOOTSTRAP_LIBRIME:-}" ]]; then
    if [[ "${LEFTIO_AUTO_BOOTSTRAP_LIBRIME}" == "1" ]]; then
      return 0
    fi
    return 1
  fi

  [[ "${CI:-}" != "true" ]]
}

ensure_vendored_librime() {
  if [[ -d "$RIME_MINIMAL_DIR" ]] && detect_vendored_librime >/dev/null; then
    return 0
  fi

  if ! should_auto_bootstrap_librime; then
    return 0
  fi

  echo "Vendored librime is missing. Bootstrapping it now..." >&2
  "$LIBRIME_BOOTSTRAP_SCRIPT"
}

detect_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
    | head -n 1
}

SDKROOT_OVERRIDE="${LEFTIO_SDKROOT:-$(preferred_input_method_sdkroot || true)}"
MIN_SYSTEM_VERSION="${LEFTIO_MIN_SYSTEM_VERSION:-$MIN_SYSTEM_VERSION}"
SIGNING_IDENTITY="${LEFTIO_SIGNING_IDENTITY:-$(detect_signing_identity)}"

cd "$ROOT_DIR"

ensure_vendored_librime

SWIFT_BUILD_ENV=()
if [[ -n "$SDKROOT_OVERRIDE" ]]; then
  SWIFT_BUILD_ENV+=("SDKROOT=$SDKROOT_OVERRIDE")
fi
if [[ -n "$MIN_SYSTEM_VERSION" ]]; then
  SWIFT_BUILD_ENV+=("MACOSX_DEPLOYMENT_TARGET=$MIN_SYSTEM_VERSION")
fi

env "${SWIFT_BUILD_ENV[@]}" swift build -c release --product "$INPUT_PRODUCT_NAME"
BIN_DIR="$(env "${SWIFT_BUILD_ENV[@]}" swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$RESOURCES_DIR" \
  "$FRAMEWORKS_DIR" \
  "$RESOURCES_DIR/Rime"

cp "$BIN_DIR/$INPUT_PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
if [[ -d "$RIME_MINIMAL_DIR" ]]; then
  cp "$RIME_MINIMAL_DIR"/* "$RESOURCES_DIR/Rime/"
fi
cp "$ROOT_DIR"/data/*.yaml "$RESOURCES_DIR/Rime/"
cat > "$RESOURCES_DIR/InfoPlist.strings" <<STRINGS
"CFBundleDisplayName" = "LeftIO 单手九宫格";
"CFBundleName" = "LeftIO";
"$MODE_ID" = "LeftIO 单手九宫格";
STRINGS

VENDORED_LIBRIME_PATH="${LEFTIO_LIBRIME_DYLIB:-$(detect_vendored_librime || true)}"
if [[ -n "$VENDORED_LIBRIME_PATH" ]]; then
  cp "$VENDORED_LIBRIME_PATH" "$FRAMEWORKS_DIR/"
fi

APP_ICON_PPM="$BUILD_DIR/app_icon.ppm"
MENU_ICON_PNG="$RESOURCES_DIR/menu_icon.png"
python3 - "$APP_ICON_PPM" "$MENU_ICON_PNG" <<'PY'
import sys
from PIL import Image, ImageDraw

app_path, menu_path = sys.argv[1:3]

def write_ppm(path, width, height, pixel):
    with open(path, "w", encoding="ascii") as file:
        file.write(f"P3\n{width} {height}\n255\n")
        for y in range(height):
            row = []
            for x in range(width):
                row.append("%d %d %d" % pixel(x, y))
            file.write(" ".join(row))
            file.write("\n")

def app_pixel(x, y):
    r = 18 + int(26 * x / 1023)
    g = 34 + int(66 * y / 1023)
    b = 46 + int(36 * (x + y) / 2046)

    if 210 <= x <= 305 and 238 <= y <= 760:
        return (242, 248, 255)
    if 210 <= x <= 505 and 665 <= y <= 760:
        return (242, 248, 255)

    if 575 <= x <= 820 and 238 <= y <= 330:
        return (255, 213, 92)
    if 575 <= x <= 665 and 238 <= y <= 515:
        return (255, 213, 92)
    if 730 <= x <= 820 and 238 <= y <= 760:
        return (255, 213, 92)
    if 575 <= x <= 820 and 425 <= y <= 515:
        return (255, 213, 92)
    if 575 <= x <= 820 and 670 <= y <= 760:
        return (255, 213, 92)

    if 154 <= x <= 870 and 824 <= y <= 858:
        return (95, 220, 190)
    if 154 <= x <= 188 and 790 <= y <= 858:
        return (95, 220, 190)

    return (r, g, b)

write_ppm(app_path, 1024, 1024, app_pixel)

icon = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
draw = ImageDraw.Draw(icon)
ink = (0, 0, 0, 255)

# Use a single, small "L" with generous padding. This reads cleanly in
# the menu bar and avoids the oversized multi-letter look in Settings.
draw.rounded_rectangle((4, 3, 6, 12), radius=1, fill=ink)
draw.rounded_rectangle((4, 10, 10, 12), radius=1, fill=ink)

icon.save(menu_path)
PY

ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -s format png "$APP_ICON_PPM" --out "$BUILD_DIR/AppIcon-1024.png" >/dev/null
for spec in \
  "16 16 icon_16x16.png" \
  "32 32 icon_16x16@2x.png" \
  "32 32 icon_32x32.png" \
  "64 64 icon_32x32@2x.png" \
  "128 128 icon_128x128.png" \
  "256 256 icon_128x128@2x.png" \
  "256 256 icon_256x256.png" \
  "512 512 icon_256x256@2x.png" \
  "512 512 icon_512x512.png" \
  "1024 1024 icon_512x512@2x.png"; do
    set -- $spec
    sips -z "$1" "$2" "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/$3" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>LeftIO 单手九宫格</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LeftIO</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>LSHasLocalizedDisplayName</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>$MODE_ID</key>
      <dict>
        <key>TISInputSourceID</key>
        <string>$MODE_ID</string>
        <key>tsInputModeAlternateMenuIconFileKey</key>
        <string>menu_icon.png</string>
        <key>tsInputModeDefaultStateKey</key>
        <true/>
        <key>tsInputModeKeyEquivalentKey</key>
        <string></string>
        <key>tsInputModeKeyEquivalentModifiersKey</key>
        <integer>4608</integer>
        <key>tsInputModeMenuIconFileKey</key>
        <string>menu_icon.png</string>
        <key>tsInputModePaletteIconFileKey</key>
        <string>menu_icon.png</string>
        <key>tsInputModeCharacterRepertoireKey</key>
        <array>
          <string>Hans</string>
          <string>Hant</string>
        </array>
        <key>tsInputModeIsVisibleKey</key>
        <true/>
        <key>tsInputModePrimaryInScriptKey</key>
        <true/>
        <key>tsInputModeScriptKey</key>
        <string>smSimpChinese</string>
      </dict>
    </dict>
    <key>tsVisibleInputModeOrderedArrayKey</key>
    <array>
      <string>$MODE_ID</string>
    </array>
  </dict>
  <key>InputMethodConnectionName</key>
  <string>$CONNECTION_NAME</string>
  <key>InputMethodServerControllerClass</key>
  <string>LeftIOInputController</string>
  <key>InputMethodServerDelegateClass</key>
  <string>LeftIOInputController</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 LeftIO contributors.</string>
  <key>NSSupportsSuddenTermination</key>
  <true/>
  <key>TICapsLockLanguageSwitchCapable</key>
  <true/>
  <key>TISIconIsTemplate</key>
  <true/>
  <key>TISInputSourceID</key>
  <string>$APP_BUNDLE_ID</string>
  <key>TISIntendedLanguage</key>
  <string>zh-Hans</string>
  <key>tsInputMethodCharacterRepertoireKey</key>
  <array>
    <string>Hans</string>
    <string>Hant</string>
    <string>Latn</string>
  </array>
  <key>tsInputMethodIconFileKey</key>
  <string>menu_icon.png</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

plutil -lint "$APP_DIR/Contents/Info.plist"
if [[ -d "$FRAMEWORKS_DIR" ]]; then
  while IFS= read -r framework_binary; do
    if [[ -n "$SIGNING_IDENTITY" ]]; then
      codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$framework_binary"
    else
      codesign --force --sign - "$framework_binary"
    fi
  done < <(find "$FRAMEWORKS_DIR" -type f \( -name '*.dylib' -o -name '*.framework' \) -print)
fi
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.macl "$APP_DIR" 2>/dev/null || true

echo "$APP_DIR"
