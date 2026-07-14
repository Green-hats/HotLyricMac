#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="${1:-$ROOT/dist}"
APP="$OUTPUT/HotLyric.app"
ICON_SOURCE="$ROOT/../HotLyric/HotLyric.Win32/Assets/HotLyricIcon.png"

cd "$ROOT"
swift build -c release --product HotLyricMac
swift build -c release --product HotLyricMac \
    --triple x86_64-apple-macosx13.0 \
    --build-path "$ROOT/.build-x86"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
lipo -create \
    "$ROOT/.build/release/HotLyricMac" \
    "$ROOT/.build-x86/x86_64-apple-macosx/release/HotLyricMac" \
    -output "$APP/Contents/MacOS/HotLyricMac"

for bundle in "$ROOT"/.build/release/*.bundle; do
    [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

if [[ -f "$ICON_SOURCE" ]]; then
    ICONSET="$ROOT/.build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - --entitlements "$ROOT/HotLyricMac.entitlements" "$APP"
echo "$APP"
