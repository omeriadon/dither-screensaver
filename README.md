# React Bits Dither Screen Saver

An AppKit/Metal port of React Bits Dither. It uses the existing public
`ScreenSaverView` bundle and experimental extension entry points. Metal
shaders compile at runtime with `MTLDevice.makeLibrary(source:)`; no WebKit or
web content is used.

## Build

Open `Dither.xcodeproj` in Xcode. The Dither build target runs the extension
build script and produces `experimental/appex/build/DitherHost.app`.

```sh
./build.sh
```

The result is `build/Dither.saver`. The script builds for the current
architecture and ad-hoc signs locally. It does not install the saver, launch
ScreenSaverEngine, register it, or modify system settings.

The extension build is:

```sh
experimental/appex/build.sh
```

## Offscreen render and self-check

```sh
./render.sh "$PWD/build/dither-render.png"
```

This builds the real Metal renderer, renders 640×360 into an offscreen
texture, writes a PNG, and checks wave frequency, dither mode, palette, and
deterministic output. It performs no screen-saver activation or system-state
changes.

Settings persistence is checked without touching the real saver preference
domain:

```sh
swiftc Sources/DitherConfiguration.swift experimental/appex/Settings.swift experimental/appex/SettingsCheck.swift -framework ScreenSaver -o /tmp/DitherSettingsCheck
/tmp/DitherSettingsCheck
```

The renderer has no pointer, hover, trail, ripple, or cursor settings.

`./benchmark.sh` builds the same renderer and reports command submission and
Metal GPU times for 120 warmed frames at 640×360, 1920×1080, and 2560×1664.
It does not reproduce screen-saver scheduling or display-compositor behavior.
See `PERFORMANCE.md` for the measurements and their limits.

## Attribution

The requested source snapshot is preserved in
`ThirdParty/ReactBits/Dither.jsx`, with its MIT + Commons Clause license and native-port notes in
`ThirdParty/ReactBits/ATTRIBUTION.md` and `ThirdParty/ReactBits/LICENSE`.

## Verification limits

The PNG verifies offscreen Metal output only. Actual System Settings preview,
idle activation, fullscreen rendering, multi-display behavior, and host
lifecycle remain unverified. No screen saver was triggered during development.
