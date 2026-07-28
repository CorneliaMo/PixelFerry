#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/PixelFerry.app"
CONTENTS="$APP/Contents"
ICON_MASTER="$ROOT/Branding/PixelFerryIcon-master.png"
STREAMER="$ROOT/PixelFerryStreamer"

command -v swift >/dev/null
command -v npm >/dev/null
command -v xcode-select >/dev/null
command -v lipo >/dev/null
command -v sips >/dev/null
command -v iconutil >/dev/null
command -v codesign >/dev/null
command -v otool >/dev/null
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
  echo "PixelFerry requires the full Xcode toolchain. Select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
test -f "$ICON_MASTER"
ICON_WIDTH="$(sips -g pixelWidth "$ICON_MASTER" | awk '/pixelWidth/{print $2}')"
ICON_HEIGHT="$(sips -g pixelHeight "$ICON_MASTER" | awk '/pixelHeight/{print $2}')"
test "$ICON_WIDTH" -ge 1024
test "$ICON_HEIGHT" -ge 1024

rm -rf "$DIST"
mkdir -p "$DIST" "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" "$CONTENTS/PlugIns"

ICONSET="$DIST/PixelFerry.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DIST/PixelFerry.icns"
rm -rf "$ICONSET"

(cd "$STREAMER" && npm ci && npm run check)
(cd "$STREAMER" && PIXELFERRY_ICON="$DIST/PixelFerry.icns" npm run package:mac)
cp -R "$STREAMER/out/universal/PixelFerry Streamer.app" "$CONTENTS/PlugIns/"

swift build --package-path "$ROOT" -c release --arch arm64 --build-path "$ROOT/.build/release-arm64"
swift build --package-path "$ROOT" -c release --arch x86_64 --build-path "$ROOT/.build/release-x86_64"

lipo -create \
  "$ROOT/.build/release-arm64/arm64-apple-macosx/release/PixelFerry" \
  "$ROOT/.build/release-x86_64/x86_64-apple-macosx/release/PixelFerry" \
  -output "$CONTENTS/MacOS/PixelFerry"
chmod 755 "$CONTENTS/MacOS/PixelFerry"

ARM_RELEASE="$ROOT/.build/release-arm64/arm64-apple-macosx/release"
for bundle in "$ARM_RELEASE"/*.bundle; do
  test -e "$bundle" || continue
  cp -R "$bundle" "$CONTENTS/Resources/"
  # SwiftPM's Bundle.module accessor resolves executable resources next to
  # Bundle.main.bundleURL. Retain the conventional Resources copy as well.
  cp -R "$bundle" "$APP/"
done

ARM_WEBRTC="$(find "$ROOT/.build/release-arm64" -type d -name WebRTC.framework -print -quit)"
INTEL_WEBRTC="$(find "$ROOT/.build/release-x86_64" -type d -name WebRTC.framework -print -quit)"
if [[ -n "$ARM_WEBRTC" ]]; then
  cp -R "$ARM_WEBRTC" "$CONTENTS/Frameworks/WebRTC.framework"
  WEBRTC_BINARY="$CONTENTS/Frameworks/WebRTC.framework/WebRTC"
  if ! lipo -archs "$WEBRTC_BINARY" | grep -qw arm64 ||
     ! lipo -archs "$WEBRTC_BINARY" | grep -qw x86_64; then
    test -n "$INTEL_WEBRTC"
    lipo -create \
      "$ARM_WEBRTC/WebRTC" \
      "$INTEL_WEBRTC/WebRTC" \
      -output "$WEBRTC_BINARY"
  fi
fi

mv "$DIST/PixelFerry.icns" "$CONTENTS/Resources/PixelFerry.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>PixelFerry</string>
  <key>CFBundleExecutable</key><string>PixelFerry</string>
  <key>CFBundleIconFile</key><string>PixelFerry</string>
  <key>CFBundleIdentifier</key><string>cn.corneliamo.PixelFerry</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>PixelFerry</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>PixelFerry shares a virtual display with browsers on your local network.</string>
  <key>NSScreenCaptureUsageDescription</key><string>PixelFerry captures its virtual display for streaming.</string>
</dict></plist>
PLIST

codesign --force --deep --sign - --identifier cn.corneliamo.PixelFerry.Streamer "$CONTENTS/PlugIns/PixelFerry Streamer.app"
if [[ -d "$CONTENTS/Frameworks/WebRTC.framework" ]]; then
  codesign --force --sign - "$CONTENTS/Frameworks/WebRTC.framework"
fi
codesign --force --sign - --identifier cn.corneliamo.PixelFerry "$APP"

plutil -lint "$CONTENTS/Info.plist"
test "$(lipo -archs "$CONTENTS/MacOS/PixelFerry")" = "x86_64 arm64" || test "$(lipo -archs "$CONTENTS/MacOS/PixelFerry")" = "arm64 x86_64"
test -x "$CONTENTS/PlugIns/PixelFerry Streamer.app/Contents/MacOS/PixelFerry Streamer"
test -s "$CONTENTS/Resources/PixelFerry.icns"
test -d "$APP/PixelFerry_PixelFerryApp.bundle"
otool -l "$CONTENTS/MacOS/PixelFerry" | grep -q '@executable_path/../Frameworks'
if otool -L "$CONTENTS/MacOS/PixelFerry" | grep -q 'WebRTC.framework'; then
  test -d "$CONTENTS/Frameworks/WebRTC.framework"
  lipo -archs "$CONTENTS/Frameworks/WebRTC.framework/WebRTC" | grep -qw arm64
  lipo -archs "$CONTENTS/Frameworks/WebRTC.framework/WebRTC" | grep -qw x86_64
fi
codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/PixelFerry-0.1.0-macOS-universal.zip"
echo "Built $APP and PixelFerry-0.1.0-macOS-universal.zip"
