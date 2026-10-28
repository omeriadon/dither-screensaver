#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_DIR="$ROOT/build"
BUNDLE="$BUILD_DIR/GeometryClock.saver"
export MACOSX_DEPLOYMENT_TARGET=13.0

rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE/Contents/MacOS"

swiftc \
    -parse-as-library \
    -emit-object \
    -whole-module-optimization \
    -target "$(uname -m)-apple-macos13.0" \
    -module-name BauhausClock \
    "$ROOT/Sources/DitherConfiguration.swift" \
    "$ROOT/Sources/AnimationTiming.swift" \
    "$ROOT/Sources/ClockMath.swift" \
    "$ROOT/Sources/BauhausClockView.swift" \
    "$ROOT/Sources/DitherPreviewView.swift" \
    -o "$BUILD_DIR/Clock.o"

SWIFT_LIB_DIR="$(dirname "$(xcrun --find swiftc)")/../lib/swift/macosx"
clang -bundle "$BUILD_DIR/Clock.o" \
    -framework AppKit -framework ScreenSaver \
    -L "$SWIFT_LIB_DIR" -Wl,-rpath,/usr/lib/swift \
    -o "$BUNDLE/Contents/MacOS/BauhausClock"
rm "$BUILD_DIR/Clock.o"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>BauhausClock</string>
    <key>CFBundleIdentifier</key>
    <string>local.geometry-clock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Geometry Clock</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>BauhausClockView</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$BUNDLE"
echo "Built $BUNDLE"
