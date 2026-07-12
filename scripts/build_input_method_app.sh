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
# Keep the published IMK connection name free of periods. On the supported
# macOS runtime, imklaunchagent rejects the bundle-id-derived variant as an
# unrecognized InputMethodConnectionName. This also matches Squirrel and
# WeType's established <product>_Connection convention.
CONNECTION_NAME="LeftIO_Connection"
BUILD_DIR="$ROOT_DIR/.build/input-method"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MIN_SYSTEM_VERSION="13.0"
RIME_MINIMAL_DIR="${LEFTIO_RIME_MINIMAL_DIR:-$VENDORED_RIME_ROOT/data/minimal}"
VERSION="${LEFTIO_VERSION:-0.1.0}"
BUILD_NUMBER="${LEFTIO_BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${LEFTIO_ARCHS:-arm64 x86_64}"

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

detect_rime_deployer() {
  local candidate
  for candidate in \
    "$VENDORED_RIME_ROOT/build/bin/rime_deployer" \
    "$VENDORED_RIME_ROOT/build/bin/Release/rime_deployer" \
    "$VENDORED_RIME_ROOT/dist/bin/rime_deployer"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

should_auto_bootstrap_librime() {
  [[ "${LEFTIO_AUTO_BOOTSTRAP_LIBRIME:-0}" == "1" ]]
}

ensure_vendored_librime() {
  if [[ -d "$RIME_MINIMAL_DIR" ]] && detect_vendored_librime >/dev/null; then
    return 0
  fi

  if ! should_auto_bootstrap_librime; then
    if [[ "${LEFTIO_ALLOW_LEXICON_ONLY:-0}" == "1" ]]; then
      echo "Warning: building without bundled librime; indexed lexicon fallback only." >&2
      return 0
    fi
    cat >&2 <<'MESSAGE'
Vendored librime or its data is missing.
Run `make build-vendored-librime`, or opt in to network bootstrap with
LEFTIO_AUTO_BOOTSTRAP_LIBRIME=1. Use LEFTIO_ALLOW_LEXICON_ONLY=1 only for an
explicit fallback-only development build.
MESSAGE
    exit 1
  fi

  echo "Vendored librime is missing. Bootstrapping it now..." >&2
  "$LIBRIME_BOOTSTRAP_SCRIPT"
}

detect_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
    | head -n 1
}

verify_architectures() {
  local binary="$1"
  local architectures
  architectures="$(lipo -archs "$binary")"
  local required
  for required in $ARCHS; do
    if [[ " $architectures " != *" $required "* ]]; then
      echo "$binary is missing $required (contains: $architectures)." >&2
      exit 1
    fi
  done
}

sign_binary() {
  local target="$1"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    codesign --force --sign - "$target"
    return 0
  fi

  local arguments=(--force --options runtime --sign "$SIGNING_IDENTITY")
  if [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
    arguments=(--force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
  fi
  codesign "${arguments[@]}" "$target"
}

SDKROOT_OVERRIDE="${LEFTIO_SDKROOT:-$(preferred_input_method_sdkroot || true)}"
MIN_SYSTEM_VERSION="${LEFTIO_MIN_SYSTEM_VERSION:-$MIN_SYSTEM_VERSION}"
SIGNING_IDENTITY="${LEFTIO_SIGNING_IDENTITY:-$(detect_signing_identity)}"

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  echo "LEFTIO_VERSION must contain exactly 3 dot-separated numeric components." >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "LEFTIO_BUILD_NUMBER must contain 1-3 dot-separated numeric components." >&2
  exit 1
fi
if [[ ! "$MIN_SYSTEM_VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "LEFTIO_MIN_SYSTEM_VERSION must contain 2-3 numeric components." >&2
  exit 1
fi
if [[ "${LEFTIO_REQUIRE_DEVELOPER_ID:-0}" == "1" ]] &&
   [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "A Developer ID Application identity is required for a release build." >&2
  exit 1
fi

cd "$ROOT_DIR"

ensure_vendored_librime

SWIFT_BUILD_ENV=()
if [[ -n "$SDKROOT_OVERRIDE" ]]; then
  SWIFT_BUILD_ENV+=("SDKROOT=$SDKROOT_OVERRIDE")
fi
if [[ -n "$MIN_SYSTEM_VERSION" ]]; then
  SWIFT_BUILD_ENV+=("MACOSX_DEPLOYMENT_TARGET=$MIN_SYSTEM_VERSION")
fi

SWIFT_ARCH_ARGUMENTS=()
for architecture in $ARCHS; do
  case "$architecture" in
    arm64|x86_64)
      SWIFT_ARCH_ARGUMENTS+=(--arch "$architecture")
      ;;
    *)
      echo "Unsupported LEFTIO_ARCHS entry: $architecture" >&2
      exit 1
      ;;
  esac
done
if [[ "${#SWIFT_ARCH_ARGUMENTS[@]}" -eq 0 ]]; then
  echo "LEFTIO_ARCHS must name at least one architecture." >&2
  exit 1
fi

env "${SWIFT_BUILD_ENV[@]}" swift build -c release --product "$INPUT_PRODUCT_NAME" "${SWIFT_ARCH_ARGUMENTS[@]}"
BIN_DIR="$(env "${SWIFT_BUILD_ENV[@]}" swift build -c release --show-bin-path "${SWIFT_ARCH_ARGUMENTS[@]}")"

rm -rf "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$RESOURCES_DIR" \
  "$FRAMEWORKS_DIR" \
  "$RESOURCES_DIR/Rime" \
  "$RESOURCES_DIR/Licenses"

cp "$BIN_DIR/$INPUT_PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
if [[ -d "$RIME_MINIMAL_DIR" ]]; then
  cp "$RIME_MINIMAL_DIR"/* "$RESOURCES_DIR/Rime/"
fi
cp "$ROOT_DIR"/data/*.yaml "$RESOURCES_DIR/Rime/"
if [[ -d "$VENDORED_RIME_ROOT/share/opencc" ]]; then
  ditto "$VENDORED_RIME_ROOT/share/opencc" "$RESOURCES_DIR/Rime/opencc"
fi
cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR"/LICENSES/* "$RESOURCES_DIR/Licenses/"
cat > "$RESOURCES_DIR/InfoPlist.strings" <<STRINGS
"CFBundleDisplayName" = "LeftIO 单手九宫格";
"CFBundleName" = "LeftIO";
"$MODE_ID" = "LeftIO 单手九宫格";
STRINGS

VENDORED_LIBRIME_PATH="${LEFTIO_LIBRIME_DYLIB:-$(detect_vendored_librime || true)}"
if [[ -n "$VENDORED_LIBRIME_PATH" ]]; then
  cp "$VENDORED_LIBRIME_PATH" "$FRAMEWORKS_DIR/"

  RIME_DEPLOYER="$(detect_rime_deployer || true)"
  if [[ -z "$RIME_DEPLOYER" ]]; then
    echo "Bundled librime is present, but rime_deployer is missing." >&2
    exit 1
  fi
  RIME_PREBUILT_DIR="$RESOURCES_DIR/Rime/build"
  RIME_PRECOMPILE_USER_DIR="$BUILD_DIR/rime-precompile-user"
  rm -rf "$RIME_PREBUILT_DIR" "$RIME_PRECOMPILE_USER_DIR"
  mkdir -p "$RIME_PREBUILT_DIR" "$RIME_PRECOMPILE_USER_DIR"
  cp \
    "$ROOT_DIR/data/prebuild/default.custom.yaml" \
    "$RIME_PRECOMPILE_USER_DIR/default.custom.yaml"
  "$RIME_DEPLOYER" --build \
    "$RIME_PRECOMPILE_USER_DIR" \
    "$RESOURCES_DIR/Rime" \
    "$RIME_PREBUILT_DIR"
  rm -f "$RIME_PREBUILT_DIR"/*.table.txt
  for artifact in \
    default.yaml \
    onehand_t9.schema.yaml \
    onehand_t9.prism.bin \
    onehand_t9.table.bin \
    onehand_t9.reverse.bin; do
    if [[ ! -f "$RIME_PREBUILT_DIR/$artifact" ]]; then
      echo "Rime precompile did not produce $artifact." >&2
      exit 1
    fi
  done
  for opencc_artifact in \
    opencc/t2s.json \
    opencc/STCharacters.ocd2 \
    opencc/STPhrases.ocd2; do
    if [[ ! -f "$RESOURCES_DIR/Rime/$opencc_artifact" ]]; then
      echo "Rime OpenCC resource is missing: $opencc_artifact." >&2
      exit 1
    fi
  done
  rm -rf "$RIME_PRECOMPILE_USER_DIR"
fi

verify_architectures "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
if [[ -n "$VENDORED_LIBRIME_PATH" ]]; then
  verify_architectures "$FRAMEWORKS_DIR/$(basename "$VENDORED_LIBRIME_PATH")"
fi

APP_ICON_PPM="$BUILD_DIR/app_icon.ppm"
MENU_ICON_PNG="$RESOURCES_DIR/menu_icon.png"
MENU_ICON_PNG_2X="$RESOURCES_DIR/menu_icon@2x.png"
MENU_ICON_PNG_4X="$BUILD_DIR/menu_icon@4x.png"
MENU_ICON_TIFF="$RESOURCES_DIR/menu_icon.tiff"
MENU_ICON_PDF="$RESOURCES_DIR/menu_icon@2x.pdf"
python3 - "$APP_ICON_PPM" "$MENU_ICON_PNG" "$MENU_ICON_PNG_2X" "$MENU_ICON_PNG_4X" "$MENU_ICON_PDF" <<'PY'
import sys
import struct
import zlib

app_path, menu_path, menu_2x_path, menu_4x_path, menu_pdf_path = sys.argv[1:6]

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

def write_png(path, width, height, pixel):
    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixel(x, y))
        rows.append(bytes(row))

    contents = b"\x89PNG\r\n\x1a\n"
    contents += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    contents += chunk(b"IDAT", zlib.compress(b"".join(rows), level=9))
    contents += chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(contents)

def menu_pixel(size, x, y):
    scale = size / 16
    # Template image: black alpha mask only. TIS recolors this for light,
    # dark, selected, and Fn-picker contexts when TISIconIsTemplate is set.
    vertical = (
        round(4 * scale) <= x <= round(6 * scale)
        and round(3 * scale) <= y <= round(12 * scale)
    )
    horizontal = (
        round(4 * scale) <= x <= round(10 * scale)
        and round(10 * scale) <= y <= round(12 * scale)
    )
    return (0, 0, 0, 255) if vertical or horizontal else (0, 0, 0, 0)

def write_menu_pdf(path):
    # Match the system input methods that feed the Fn picker through
    # TISIconLabels/CustomIcon: a valid PDF on a 28x36 canvas.
    stream = "\n".join([
        "0 0 0 rg",
        "9 8 5 20 re f",
        "9 8 12 5 re f",
    ]) + "\n"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 28 36] /Contents 4 0 R >>",
        f"<< /Length {len(stream.encode('ascii'))} >>\nstream\n{stream}endstream",
    ]
    chunks = ["%PDF-1.3\n"]
    offsets = [0]
    for index, body in enumerate(objects, start=1):
        offsets.append(sum(len(chunk.encode("ascii")) for chunk in chunks))
        chunks.append(f"{index} 0 obj\n{body}\nendobj\n")
    xref_offset = sum(len(chunk.encode("ascii")) for chunk in chunks)
    chunks.append("xref\n0 5\n0000000000 65535 f \n")
    for offset in offsets[1:]:
        chunks.append(f"{offset:010d} 00000 n \n")
    chunks.append("trailer\n<< /Size 5 /Root 1 0 R >>\n")
    chunks.append(f"startxref\n{xref_offset}\n%%EOF\n")
    with open(path, "w", encoding="ascii") as file:
        file.write("".join(chunks))

write_ppm(app_path, 1024, 1024, app_pixel)

write_png(menu_path, 16, 16, lambda x, y: menu_pixel(16, x, y))
write_png(menu_2x_path, 32, 32, lambda x, y: menu_pixel(32, x, y))
write_png(menu_4x_path, 64, 64, lambda x, y: menu_pixel(64, x, y))
write_menu_pdf(menu_pdf_path)
PY

MENU_ICON_TIFF_1X="$BUILD_DIR/menu_icon_1x.tiff"
MENU_ICON_TIFF_2X="$BUILD_DIR/menu_icon_2x.tiff"
MENU_ICON_TIFF_4X="$BUILD_DIR/menu_icon_4x.tiff"
sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 "$MENU_ICON_PNG" --out "$MENU_ICON_TIFF_1X" >/dev/null
sips -s format tiff -s dpiWidth 144 -s dpiHeight 144 "$MENU_ICON_PNG_2X" --out "$MENU_ICON_TIFF_2X" >/dev/null
sips -s format tiff -s dpiWidth 288 -s dpiHeight 288 "$MENU_ICON_PNG_4X" --out "$MENU_ICON_TIFF_4X" >/dev/null
tiffutil -cat "$MENU_ICON_TIFF_1X" "$MENU_ICON_TIFF_2X" "$MENU_ICON_TIFF_4X" -out "$MENU_ICON_TIFF" >/dev/null

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
  <string>$VERSION</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
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
        <string>menu_icon.tiff</string>
        <key>tsInputModeDefaultStateKey</key>
        <true/>
        <key>tsInputModeKeyEquivalentKey</key>
        <string></string>
        <key>tsInputModeKeyEquivalentModifiersKey</key>
        <integer>4608</integer>
        <key>TISIconIsTemplate</key>
        <true/>
        <key>TISIconLabels</key>
        <dict>
          <key>Primary</key>
          <string>L</string>
          <key>CustomIcon</key>
          <string>menu_icon@2x.pdf</string>
        </dict>
        <key>tsInputModeMenuIconFileKey</key>
        <string>menu_icon.tiff</string>
        <key>tsInputModePaletteIconFileKey</key>
        <string>menu_icon.tiff</string>
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
        <string>smUnicodeScript</string>
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
  </array>
  <key>tsInputMethodIconFileKey</key>
  <string>menu_icon.tiff</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

plutil -lint "$APP_DIR/Contents/Info.plist"
if [[ -d "$FRAMEWORKS_DIR" ]]; then
  while IFS= read -r framework_binary; do
    sign_binary "$framework_binary"
  done < <(find "$FRAMEWORKS_DIR" -type f \( -name '*.dylib' -o -name '*.framework' \) -print)
fi
sign_binary "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.provenance "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.macl "$APP_DIR" 2>/dev/null || true
if ! APP_ATTRIBUTES="$(xattr -lr "$APP_DIR" 2>&1)"; then
  echo "Unable to inspect built app extended attributes: $APP_ATTRIBUTES" >&2
  exit 1
fi
if grep -Eq 'com\.apple\.(quarantine|macl)' <<<"$APP_ATTRIBUTES"; then
  echo "Built app still contains quarantine or macl metadata." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
