#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PRODUCT_NAME="LeftIOInputMethod"
LAUNCHER_PRODUCT_NAME="LeftIOLauncher"
APP_NAME="LeftIO"
BUNDLE_ID="io.github.cstcat.leftio"
LAUNCHER_BUNDLE_ID="io.github.cstcat.leftio.launcher"
MODE_ID="io.github.cstcat.leftio.onehandt9"
CONNECTION_NAME="LeftIO_1_Connection"
BUILD_DIR="$ROOT_DIR/.build/input-method"
INPUT_APP_DIR="$BUILD_DIR/$APP_NAME.app"
LAUNCHER_APP_DIR="$BUILD_DIR/launcher/$APP_NAME.app"

cd "$ROOT_DIR"

swift build -c release --product "$INPUT_PRODUCT_NAME"
swift build -c release --product "$LAUNCHER_PRODUCT_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$INPUT_APP_DIR" "$LAUNCHER_APP_DIR"
mkdir -p "$INPUT_APP_DIR/Contents/MacOS" "$INPUT_APP_DIR/Contents/Resources"
mkdir -p "$LAUNCHER_APP_DIR/Contents/MacOS" "$LAUNCHER_APP_DIR/Contents/Resources"

cp "$BIN_DIR/$INPUT_PRODUCT_NAME" "$INPUT_APP_DIR/Contents/MacOS/$INPUT_PRODUCT_NAME"
cp "$BIN_DIR/$LAUNCHER_PRODUCT_NAME" "$LAUNCHER_APP_DIR/Contents/MacOS/$LAUNCHER_PRODUCT_NAME"

APP_ICON_PPM="$BUILD_DIR/app_icon.ppm"
MENU_ICON_PPM="$BUILD_DIR/menu_icon.ppm"
python3 - "$APP_ICON_PPM" "$MENU_ICON_PPM" <<'PY'
import sys

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

    # L
    if 210 <= x <= 305 and 238 <= y <= 760:
        return (242, 248, 255)
    if 210 <= x <= 505 and 665 <= y <= 760:
        return (242, 248, 255)

    # 9, drawn as block segments so it survives Launchpad scaling.
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

    # Small left-hand key hint.
    if 154 <= x <= 870 and 824 <= y <= 858:
        return (95, 220, 190)
    if 154 <= x <= 188 and 790 <= y <= 858:
        return (95, 220, 190)

    return (r, g, b)

def menu_pixel(x, y):
    value = 255
    border = x in (4, 5, 58, 59) or y in (4, 5, 58, 59)
    l_glyph = (14 <= x <= 19 and 14 <= y <= 47) or (14 <= x <= 33 and 42 <= y <= 47)
    nine_glyph = (
        (38 <= x <= 52 and 14 <= y <= 19) or
        (38 <= x <= 43 and 14 <= y <= 32) or
        (48 <= x <= 52 and 14 <= y <= 47) or
        (38 <= x <= 52 and 28 <= y <= 33) or
        (38 <= x <= 52 and 42 <= y <= 47)
    )
    if border or l_glyph or nine_glyph:
        value = 0
    return (value, value, value)

write_ppm(app_path, 1024, 1024, app_pixel)
write_ppm(menu_path, 64, 64, menu_pixel)
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
iconutil -c icns "$ICONSET_DIR" -o "$INPUT_APP_DIR/Contents/Resources/AppIcon.icns"
cp "$INPUT_APP_DIR/Contents/Resources/AppIcon.icns" "$LAUNCHER_APP_DIR/Contents/Resources/AppIcon.icns"
sips -s format tiff "$MENU_ICON_PPM" --out "$INPUT_APP_DIR/Contents/Resources/menu_icon.tiff" >/dev/null

cat > "$INPUT_APP_DIR/Contents/Info.plist" <<PLIST
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
  <string>$INPUT_PRODUCT_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
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
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>$MODE_ID</key>
      <dict>
        <key>TISIconLabels</key>
        <dict>
          <key>Primary</key>
          <string>L9</string>
        </dict>
        <key>TISInputSourceID</key>
        <string>$MODE_ID</string>
        <key>TISIntendedLanguage</key>
        <string>zh-Hans</string>
        <key>tsInputModeAlternateMenuIconFileKey</key>
        <string>menu_icon.tiff</string>
        <key>tsInputModeDefaultStateKey</key>
        <true/>
        <key>tsInputModeKeyEquivalentKey</key>
        <string></string>
        <key>tsInputModeKeyEquivalentModifiersKey</key>
        <integer>4608</integer>
        <key>tsInputModeMenuIconFileKey</key>
        <string>menu_icon.tiff</string>
        <key>tsInputModePaletteIconFileKey</key>
        <string>menu_icon.tiff</string>
        <key>tsInputModeCharacterRepertoireKey</key>
        <array>
          <string>Hans</string>
          <string>Latn</string>
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
  <string>LeftIOInputMethod.LeftIOInputController</string>
  <key>InputMethodServerDelegateClass</key>
  <string>LeftIOInputMethod.LeftIOInputController</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 LeftIO contributors.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsSuddenTermination</key>
  <true/>
  <key>TICapsLockLanguageSwitchCapable</key>
  <true/>
  <key>TISIconIsTemplate</key>
  <true/>
  <key>TISIntendedLanguage</key>
  <string>zh-Hans</string>
  <key>tsInputMethodCharacterRepertoireKey</key>
  <array>
    <string>Hans</string>
    <string>Latn</string>
  </array>
  <key>tsInputMethodIconFileKey</key>
  <string>menu_icon.tiff</string>
</dict>
</plist>
PLIST

cat > "$LAUNCHER_APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>LeftIO</string>
  <key>CFBundleExecutable</key>
  <string>$LAUNCHER_PRODUCT_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$LAUNCHER_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LeftIO</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$INPUT_APP_DIR/Contents/PkgInfo"
printf 'APPL????' > "$LAUNCHER_APP_DIR/Contents/PkgInfo"

plutil -lint "$INPUT_APP_DIR/Contents/Info.plist"
plutil -lint "$LAUNCHER_APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$INPUT_APP_DIR"
codesign --force --deep --sign - "$LAUNCHER_APP_DIR"

echo "$INPUT_APP_DIR"
echo "$LAUNCHER_APP_DIR"
