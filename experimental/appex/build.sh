#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
PROJECT_ROOT="${ROOT:h:h}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/DitherHost.app"
APPEX="$APP/Contents/PlugIns/DitherExtension.appex"
export MACOSX_DEPLOYMENT_TARGET=13.0

if [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -x "/Applications/Xcode 27.2 rc.app/Contents/Developer/usr/bin/actool" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode 27.2 rc.app/Contents/Developer"
fi

rm -rf "$BUILD_DIR"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources" "$APP/Contents/MacOS"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_LIB_DIR="$(dirname "$(xcrun --find swiftc)")/../lib/swift/macosx"
TARGET="$(uname -m)-apple-macos13.0"

swiftc \
    -parse-as-library \
    -target "$TARGET" \
    "$PROJECT_ROOT/Sources/DitherConfiguration.swift" \
    "$PROJECT_ROOT/Sources/AnimationTiming.swift" \
    "$PROJECT_ROOT/Sources/DitherScreenSaverView.swift" \
    "$PROJECT_ROOT/Tools/DitherRender.swift" \
    -framework AppKit \
    -framework ScreenSaver \
    -framework Metal \
    -framework CoreGraphics \
    -framework ImageIO \
    -o "$BUILD_DIR/DitherRender"
"$BUILD_DIR/DitherRender" "$BUILD_DIR/thumbnail-source.png"
CATALOG="$BUILD_DIR/Assets.xcassets"
mkdir -p "$CATALOG/thumbnail.imageset"
cp "$ROOT/Resources/Assets.xcassets/Contents.json" "$CATALOG/Contents.json"
cp "$ROOT/Resources/Assets.xcassets/thumbnail.imageset/Contents.json" "$CATALOG/thumbnail.imageset/Contents.json"
sips --resampleHeightWidth 65 107 "$BUILD_DIR/thumbnail-source.png" --out "$CATALOG/thumbnail.imageset/thumbnail.png" >/dev/null
sips --resampleHeightWidth 130 214 "$BUILD_DIR/thumbnail-source.png" --out "$CATALOG/thumbnail.imageset/thumbnail@2x.png" >/dev/null
cp "$CATALOG/thumbnail.imageset/thumbnail.png" "$APPEX/Contents/Resources/thumbnail.png"
cp "$CATALOG/thumbnail.imageset/thumbnail@2x.png" "$APPEX/Contents/Resources/thumbnail@2x.png"

ACTOOL="${DEVELOPER_DIR:-}/usr/bin/actool"
if [[ ! -x "$ACTOOL" ]]; then
    ACTOOL="$(xcrun --find actool)"
fi
mkdir -p "$BUILD_DIR/compiled-assets"
"$ACTOOL" \
    --compile "$BUILD_DIR/compiled-assets" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    "$CATALOG"
cp "$BUILD_DIR/compiled-assets/Assets.car" "$APPEX/Contents/Resources/Assets.car"

swiftc \
    -parse-as-library \
    -emit-object \
    -whole-module-optimization \
    -D DITHER_APPEX \
    -target "$TARGET" \
    -module-name DitherExtension \
    -import-objc-header "$ROOT/ScreenSaverPrivate.h" \
    "$PROJECT_ROOT/Sources/DitherConfiguration.swift" \
    "$PROJECT_ROOT/Sources/AnimationTiming.swift" \
    "$PROJECT_ROOT/Sources/DitherScreenSaverView.swift" \
    "$PROJECT_ROOT/Sources/DitherPreviewView.swift" \
    "$ROOT/Extension.swift" \
    "$ROOT/ViewController.swift" \
    "$ROOT/Settings.swift" \
    "$ROOT/DitherOptionsView.swift" \
    "$ROOT/ConfigurationViewController.swift" \
    -framework SwiftUI \
    -o "$BUILD_DIR/Extension.o"

clang -Wl,-e,_NSExtensionMain \
    -isysroot "$SDKROOT" \
    -target "$TARGET" \
    "$BUILD_DIR/Extension.o" \
    -framework AppKit \
    -framework ScreenSaver \
    -L "$SWIFT_LIB_DIR" \
    -Wl,-rpath,/usr/lib/swift \
    -o "$APPEX/Contents/MacOS/DitherExtension"

swiftc \
    -parse-as-library \
    -target "$TARGET" \
    "$ROOT/HostMain.swift" \
    -framework AppKit \
    -o "$APP/Contents/MacOS/DitherHost"

cp "$ROOT/Extension-Info.plist" "$APPEX/Contents/Info.plist"
cp "$ROOT/Host-Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --entitlements "$ROOT/Extension.entitlements" "$APPEX"
codesign --force --sign - "$APP"
echo "Built and ad-hoc signed $APP"
