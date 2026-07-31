#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STREAMER="$ROOT/PixelFerryStreamer"
ICON_MASTER="$ROOT/Branding/PixelFerryIcon-master.png"
OUTPUT_DIR="$ROOT/dist"
SIGN_IDENTITY="-"
RUN_TESTS=1
RUN_NPM_CI=1

usage() {
  cat <<'EOF'
Build a complete Universal 2 PixelFerry macOS application.

Usage:
  scripts/build-release.sh [options]

Options:
  --output <directory>       Artifact directory (default: ./dist)
  --sign-identity <identity> codesign identity (default: - for ad-hoc)
  --skip-tests               Skip Swift and Node test suites
  --skip-npm-ci              Reuse PixelFerryStreamer/node_modules
  -h, --help                 Show this help

Artifacts:
  PixelFerry.app
  PixelFerry-<version>-macOS-universal.zip
  build-manifest.txt

The default output is ad-hoc signed for local development. This script does
not notarize or publish the application.
EOF
}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
find_macos_framework() {
  local search_root="$1"
  local required_arch="$2"
  local framework binary arches
  while IFS= read -r framework; do
    binary="$framework/WebRTC"
    [[ -f "$binary" ]] || continue
    xcrun vtool -show-build "$binary" 2>/dev/null |
      grep -Eq '^[[:space:]]*platform[[:space:]]+MACOS$' || continue
    arches=" $(lipo -archs "$binary") "
    [[ "$arches" == *" $required_arch "* ]] || continue
    printf '%s\n' "$framework"
    return 0
  done < <(find "$search_root" -type d -name WebRTC.framework -print)
  return 1
}

while (($#)); do
  case "$1" in
    --output)
      (($# >= 2)) || die "--output requires a directory"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --sign-identity)
      (($# >= 2)) || die "--sign-identity requires a value"
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --skip-npm-ci)
      RUN_NPM_CI=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (use --help)"
      ;;
  esac
done

trap 'printf "\nerror: build failed at line %s\n" "$LINENO" >&2' ERR

for command in awk codesign curl ditto find iconutil lipo npm node otool plutil \
  security shasum sips swift sw_vers xcodebuild xcode-select xcrun; do
  require_command "$command"
done
[[ -x /usr/libexec/PlistBuddy ]] || die "PlistBuddy is unavailable"

DEVELOPER_DIR_PATH="$(xcode-select -p)"
[[ "$DEVELOPER_DIR_PATH" != */CommandLineTools ]] ||
  die "full Xcode is required; run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
xcrun --find swift >/dev/null ||
  die "the selected Xcode installation does not provide Swift"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
((MACOS_MAJOR >= 15)) || die "macOS 15 or newer is required"
XCODE_MAJOR="$(xcodebuild -version | awk 'NR == 1 { split($2, v, "[.]"); print v[1] }')"
((XCODE_MAJOR >= 16)) || die "Xcode 16 or newer is required"
read -r NODE_MAJOR NODE_MINOR < <(
  node -p "const [major, minor] = process.versions.node.split('.').map(Number); major + ' ' + minor"
)
if ((NODE_MAJOR < 22 || (NODE_MAJOR == 22 && NODE_MINOR < 12))); then
  die "Node.js 22.12 or newer is required"
fi

[[ -f "$ROOT/Package.swift" ]] || die "Package.swift is missing"
[[ -f "$STREAMER/package-lock.json" ]] || die "PixelFerryStreamer/package-lock.json is missing"
[[ -f "$ICON_MASTER" ]] || die "icon master is missing: $ICON_MASTER"

VERSION="$(cd "$STREAMER" && node -p "require('./package.json').version")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] ||
  die "invalid package version: $VERSION"
MARKETING_VERSION="${VERSION%%-*}"
BUILD_NUMBER="${PIXELFERRY_BUILD_NUMBER:-1}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
  die "PIXELFERRY_BUILD_NUMBER must be a positive integer"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning)"
  grep -Fq "\"$SIGN_IDENTITY\"" <<<"$AVAILABLE_IDENTITIES" ||
    die "codesign identity was not found: $SIGN_IDENTITY"
fi

[[ "$OUTPUT_DIR" != "/" && "$OUTPUT_DIR" != "//" ]] ||
  die "refusing unsafe output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
[[ "$OUTPUT_DIR" != "/" && "$OUTPUT_DIR" != "$ROOT" ]] ||
  die "refusing unsafe output directory: $OUTPUT_DIR"

APP="$OUTPUT_DIR/PixelFerry.app"
CONTENTS="$APP/Contents"
HELPER_APP="$CONTENTS/PlugIns/PixelFerry Streamer.app"
ZIP="$OUTPUT_DIR/PixelFerry-$VERSION-macOS-universal.zip"
MANIFEST="$OUTPUT_DIR/build-manifest.txt"
PACKAGING_ROOT="$ROOT/.build/pixelferry-packaging"
ICONSET="$PACKAGING_ROOT/PixelFerry.iconset"
ICNS="$PACKAGING_ROOT/PixelFerry.icns"

log "Environment"
printf 'Xcode:      %s\n' "$(xcodebuild -version | tr '\n' ' ')"
printf 'Swift:      %s\n' "$(swift --version | sed -n '1p')"
printf 'Node:       %s\n' "$(node --version)"
printf 'npm:        %s\n' "$(npm --version)"
printf 'Version:    %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'Signing:    %s\n' "$SIGN_IDENTITY"
printf 'Output:     %s\n' "$OUTPUT_DIR"

log "Preparing clean staging directories"
rm -rf "$APP" "$PACKAGING_ROOT"
rm -f "$ZIP" "$MANIFEST"
mkdir -p "$OUTPUT_DIR" "$PACKAGING_ROOT" \
  "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" \
  "$CONTENTS/PlugIns"

log "Generating application icon"
ICON_WIDTH="$(sips -g pixelWidth "$ICON_MASTER" | awk '/pixelWidth/{print $2}')"
ICON_HEIGHT="$(sips -g pixelHeight "$ICON_MASTER" | awk '/pixelHeight/{print $2}')"
[[ "$ICON_WIDTH" -ge 1024 && "$ICON_HEIGHT" -ge 1024 ]] ||
  die "icon master must be at least 1024x1024"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_MASTER" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_MASTER" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"
cp "$ICNS" "$CONTENTS/Resources/PixelFerry.icns"

log "Installing locked streamer dependencies"
if ((RUN_NPM_CI)); then
  (cd "$STREAMER" && npm ci)
else
  [[ -d "$STREAMER/node_modules" ]] ||
    die "--skip-npm-ci requires PixelFerryStreamer/node_modules"
  (cd "$STREAMER" && npm ls --depth=0 >/dev/null) ||
    die "existing streamer dependencies do not match package.json"
fi

if ((RUN_TESTS)); then
  log "Testing streamer"
  (cd "$STREAMER" && npm run check)
fi

log "Packaging Universal 2 PixelFerry Streamer"
(cd "$STREAMER" && \
  PIXELFERRY_ICON="$ICNS" \
  PIXELFERRY_BUILD_NUMBER="$BUILD_NUMBER" \
  npm run package:mac)
PACKAGED_HELPER="$STREAMER/out/universal/PixelFerry Streamer.app"
[[ -d "$PACKAGED_HELPER" ]] || die "streamer package was not produced"
cp -R "$PACKAGED_HELPER" "$CONTENTS/PlugIns/"

if ((RUN_TESTS)); then
  log "Testing Swift package"
  TEST_BIN_PATH="$(swift build --package-path "$ROOT" --show-bin-path)"
  STALE_TEST_FRAMEWORK="$TEST_BIN_PATH/PixelFerryCoreTests.xctest/Contents/Frameworks/WebRTC.framework"
  rm -rf "$STALE_TEST_FRAMEWORK"
  swift build --package-path "$ROOT" --build-tests
  TEST_ARCH="$(uname -m)"
  TEST_WEBRTC="$(find_macos_framework "$ROOT/.build" "$TEST_ARCH")" || true
  [[ -n "$TEST_WEBRTC" ]] ||
    die "a WebRTC.framework compatible with $TEST_ARCH was not found for Swift tests"
  TEST_BUNDLE="$TEST_BIN_PATH/PixelFerryCoreTests.xctest"
  [[ -d "$TEST_BUNDLE" ]] || die "PixelFerryCoreTests.xctest was not produced at $TEST_BUNDLE"
  TEST_FRAMEWORKS="$TEST_BUNDLE/Contents/Frameworks"
  mkdir -p "$TEST_FRAMEWORKS"
  rm -rf "$TEST_FRAMEWORKS/WebRTC.framework"
  ditto "$TEST_WEBRTC" "$TEST_FRAMEWORKS/WebRTC.framework"
  codesign --force --sign - "$TEST_FRAMEWORKS/WebRTC.framework"
  codesign --force --deep --sign - "$TEST_BUNDLE"
  swift test --package-path "$ROOT" --skip-build
fi

build_swift_arch() {
  local arch="$1"
  local build_path="$ROOT/.build/pixelferry-$arch"
  log "Building Swift release for $arch"
  swift build \
    --package-path "$ROOT" \
    --configuration release \
    --arch "$arch" \
    --build-path "$build_path"
}

swift_bin_path() {
  local arch="$1"
  local build_path="$ROOT/.build/pixelferry-$arch"
  swift build \
    --package-path "$ROOT" \
    --configuration release \
    --arch "$arch" \
    --build-path "$build_path" \
    --show-bin-path
}

build_swift_arch arm64
build_swift_arch x86_64
ARM_BIN="$(swift_bin_path arm64)"
INTEL_BIN="$(swift_bin_path x86_64)"
[[ -x "$ARM_BIN/PixelFerryApp" ]] || die "arm64 PixelFerryApp executable is missing"
[[ -x "$INTEL_BIN/PixelFerryApp" ]] || die "x86_64 PixelFerryApp executable is missing"

log "Creating Universal 2 application executable"
lipo -create "$ARM_BIN/PixelFerryApp" "$INTEL_BIN/PixelFerryApp" \
  -output "$CONTENTS/MacOS/PixelFerry"
chmod 755 "$CONTENTS/MacOS/PixelFerry"

log "Embedding SwiftPM resources"
RESOURCE_COUNT=0
while IFS= read -r bundle; do
  [[ -n "$bundle" ]] || continue
  name="$(basename "$bundle")"
  cp -R "$bundle" "$CONTENTS/Resources/$name"
  RESOURCE_COUNT=$((RESOURCE_COUNT + 1))
done < <(find "$ARM_BIN" -maxdepth 1 -type d -name '*.bundle' -print)
((RESOURCE_COUNT > 0)) || die "no SwiftPM resource bundles were produced"
[[ -d "$CONTENTS/Resources/PixelFerry_PixelFerryApp.bundle" ]] ||
  die "PixelFerryApp localization bundle is missing"
[[ -d "$CONTENTS/Resources/PixelFerry_PixelFerryCore.bundle" ]] ||
  die "PixelFerryCore web resource bundle is missing"

log "Embedding WebRTC framework when dynamically linked"
ARM_WEBRTC="$(find_macos_framework "$ROOT/.build/pixelferry-arm64" arm64)" || true
INTEL_WEBRTC="$(find_macos_framework "$ROOT/.build/pixelferry-x86_64" x86_64)" || true
if [[ -n "$ARM_WEBRTC" ]]; then
  cp -R "$ARM_WEBRTC" "$CONTENTS/Frameworks/WebRTC.framework"
  WEBRTC_BINARY="$CONTENTS/Frameworks/WebRTC.framework/WebRTC"
  [[ -f "$WEBRTC_BINARY" ]] || die "WebRTC framework binary is missing"
  WEBRTC_ARCHES="$(lipo -archs "$WEBRTC_BINARY")"
  if [[ " $WEBRTC_ARCHES " != *" arm64 "* ||
        " $WEBRTC_ARCHES " != *" x86_64 "* ]]; then
    [[ -n "$INTEL_WEBRTC" ]] || die "x86_64 WebRTC framework is missing"
    lipo -create "$ARM_WEBRTC/WebRTC" "$INTEL_WEBRTC/WebRTC" \
      -output "$WEBRTC_BINARY"
  fi
fi

log "Writing application metadata"
cat >"$CONTENTS/Info.plist" <<PLIST
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
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>PixelFerry shares a virtual display with browsers on your local network.</string>
  <key>NSScreenCaptureUsageDescription</key><string>PixelFerry Streamer captures the PixelFerry virtual display for browser streaming.</string>
</dict></plist>
PLIST

mkdir -p "$CONTENTS/Resources/en.lproj" "$CONTENTS/Resources/zh-Hans.lproj"
cat >"$CONTENTS/Resources/en.lproj/InfoPlist.strings" <<'EOF'
"NSLocalNetworkUsageDescription" = "PixelFerry shares a virtual display with browsers on your local network.";
"NSScreenCaptureUsageDescription" = "PixelFerry Streamer captures the PixelFerry virtual display for browser streaming.";
EOF
cat >"$CONTENTS/Resources/zh-Hans.lproj/InfoPlist.strings" <<'EOF'
"NSLocalNetworkUsageDescription" = "PixelFerry 将虚拟显示器画面共享给局域网中的浏览器。";
"NSScreenCaptureUsageDescription" = "PixelFerry Streamer 需要捕获 PixelFerry 虚拟显示器以进行浏览器串流。";
EOF
plutil -lint "$CONTENTS/Info.plist" >/dev/null

sign_code() {
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$@"
  else
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$@"
  fi
}

log "Signing nested code and application"
if [[ -d "$CONTENTS/Frameworks/WebRTC.framework" ]]; then
  sign_code "$CONTENTS/Frameworks/WebRTC.framework"
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$HELPER_APP"
else
  codesign --force --deep --timestamp --sign "$SIGN_IDENTITY" "$HELPER_APP"
fi
sign_code "$APP"

require_arches() {
  local binary="$1"
  local arches
  arches="$(lipo -archs "$binary")"
  [[ " $arches " == *" arm64 "* ]] || die "$binary is missing arm64"
  [[ " $arches " == *" x86_64 "* ]] || die "$binary is missing x86_64"
}

log "Validating application bundle"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == \
   "cn.corneliamo.PixelFerry" ]] || die "unexpected main bundle identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HELPER_APP/Contents/Info.plist")" == \
   "cn.corneliamo.PixelFerry.Streamer" ]] || die "unexpected helper bundle identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$CONTENTS/Info.plist")" == "true" ]] ||
  die "main application must be an agent application"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$HELPER_APP/Contents/Info.plist")" == "true" ]] ||
  die "streamer must be an agent application"
[[ -x "$HELPER_APP/Contents/MacOS/PixelFerry Streamer" ]] ||
  die "embedded streamer executable is missing"
[[ -s "$CONTENTS/Resources/PixelFerry.icns" ]] || die "application icon is missing"
[[ -f "$HELPER_APP/Contents/Resources/en.lproj/InfoPlist.strings" ]] ||
  die "streamer English permission localization is missing"
[[ -f "$HELPER_APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" ]] ||
  die "streamer Chinese permission localization is missing"
require_arches "$CONTENTS/MacOS/PixelFerry"
require_arches "$HELPER_APP/Contents/MacOS/PixelFerry Streamer"
APP_LOAD_COMMANDS="$(otool -l "$CONTENTS/MacOS/PixelFerry")"
grep -q '@executable_path/../Frameworks' <<<"$APP_LOAD_COMMANDS" ||
  die "application Frameworks rpath is missing"
APP_DEPENDENCIES="$(otool -L "$CONTENTS/MacOS/PixelFerry")"
if grep -q 'WebRTC.framework' <<<"$APP_DEPENDENCIES"; then
  [[ -d "$CONTENTS/Frameworks/WebRTC.framework" ]] ||
    die "dynamically linked WebRTC framework is missing"
  require_arches "$CONTENTS/Frameworks/WebRTC.framework/WebRTC"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

log "Creating archive and manifest"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
[[ -s "$ZIP" ]] || die "archive was not created"
ZIP_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
{
  printf 'product=PixelFerry\n'
  printf 'version=%s\n' "$VERSION"
  printf 'marketing_version=%s\n' "$MARKETING_VERSION"
  printf 'build=%s\n' "$BUILD_NUMBER"
  printf 'architectures=%s\n' "$(lipo -archs "$CONTENTS/MacOS/PixelFerry")"
  printf 'bundle_id=cn.corneliamo.PixelFerry\n'
  printf 'helper_bundle_id=cn.corneliamo.PixelFerry.Streamer\n'
  printf 'signing_identity=%s\n' "$SIGN_IDENTITY"
  printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ' ')"
  printf 'swift=%s\n' "$(swift --version | sed -n '1p')"
  printf 'node=%s\n' "$(node --version)"
  printf 'archive_sha256=%s\n' "$ZIP_SHA256"
} >"$MANIFEST"

trap - ERR
log "Build complete"
printf 'Application: %s\n' "$APP"
printf 'Archive:     %s\n' "$ZIP"
printf 'SHA-256:    %s\n' "$ZIP_SHA256"
printf 'Manifest:    %s\n' "$MANIFEST"
