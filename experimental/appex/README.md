# Dither app-extension experiment

This is an experimental macOS screensaver app extension. It reuses the public
Metal Dither renderer and `DitherScreenSaverView` entry point from the repository, but the
extension entry points and manifest target Apple's private, undocumented
`com.apple.screensaver` extension point.

The private API is intentionally isolated in `ScreenSaverPrivate.h`. The
extension is not a supported Apple integration, has no reliability guarantee,
may stop loading after an OS update, and is not suitable for Mac App Store
distribution. The public `.saver` build remains the supported implementation.

## Build

From the repository root:

```sh
experimental/appex/build.sh
```

The output is `experimental/appex/build/DitherHost.app`. The script
only builds and ad-hoc signs it. It does not register, install, or change
system settings.

Rebuilding replaces the bundle and can remove its existing registration. To
register a development build again, register its containing app first and then
its extension:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/experimental/appex/build/DitherHost.app"
pluginkit -a "$PWD/experimental/appex/build/DitherHost.app/Contents/PlugIns/DitherExtension.appex"
```

The extension executable and manifests compile and pass code-signature
verification. The sandboxed extension registers successfully after its host
app is registered with Launch Services. Check registration and remove the
temporary registration afterwards with:

```sh
experimental/appex/check-registration.sh
```

The script refuses to run if the extension identifier is already registered.
On this Mac running macOS 27.2, System Settings showed Dither in its live
preview, and WallpaperAgent loaded the extension for two displays during a
brief full-screen activation. The initially running WallpaperAgent did not know
the newly registered module and fell back to the default saver; restarting it
made the module available. Registration alone does not establish reliability.
The extension has no extra ViewBridge entitlements, which may affect behavior
on other macOS versions.

The script uses `swiftc` and `clang`; it does not use `xcodebuild`. A local
development build requires the macOS SDK, AppKit, ScreenSaver, and an arm64 or
x86_64 macOS toolchain matching the host.

The extension exposes Dither controls in System Settings with a pinned live
preview. Gap and corner radius are fractions of a grid cell. Backgrounds can
be black, white, or tinted at 20% of the wave color; existing custom backgrounds
are preserved. Save writes the extension's `ScreenSaverDefaults` domain;
Cancel leaves saved values unchanged.

The settings check can be run without touching the extension's preference
domain:

```sh
swiftc Sources/DitherConfiguration.swift experimental/appex/Settings.swift experimental/appex/SettingsCheck.swift \
    -framework ScreenSaver -o /tmp/DitherSettingsCheck
/tmp/DitherSettingsCheck
```

## Signing and distribution

The build uses an ad-hoc signature for local inspection only. For a real
outside-the-store experiment, replace the `codesign --sign -` arguments with a
suitable Developer ID identity, sign the nested extension before the host, and verify
with `codesign --verify --deep --strict --verbose=2`. Notarization and runtime
behavior still require independent testing; signing does not make the private
API supported or reliable.

Do not copy this build into a system screensaver directory or register it as
part of the build step. Registration and host behavior are deliberately left
for a separate, controlled test.

Technical shape follows Apple's installed `ScreenSaver.framework` manifests
and the original minimal reference at
https://github.com/AerialScreensaver/AppexSaverMinimal. No reference source
implementation is copied here.
