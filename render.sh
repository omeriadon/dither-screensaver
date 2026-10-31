#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT="${1:-$ROOT/build/dither-render.png}"
mkdir -p "${OUTPUT:h}" "$ROOT/build"
swiftc \
    -parse-as-library \
    -O \
    -lto=llvm-full \
    -target "$(uname -m)-apple-macos13.0" \
    "$ROOT/Sources/DitherConfiguration.swift" \
    "$ROOT/Sources/AnimationTiming.swift" \
    "$ROOT/Sources/DitherMetalRenderer.swift" \
    "$ROOT/Sources/DitherScreenSaverView.swift" \
    "$ROOT/Tools/DitherRender.swift" \
    -framework AppKit \
    -framework ScreenSaver \
    -framework Metal \
    -framework MetalPerformanceShaders \
    -framework CoreGraphics \
    -framework ImageIO \
    -o "$ROOT/build/DitherRender"
"$ROOT/build/DitherRender" "$OUTPUT"
