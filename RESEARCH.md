# macOS screen saver research

Research date: 27 October 2026. This is a source review, not a claim that the specific failures on this Mac have been reproduced. Local static artifact inspection is recorded below; runtime verification remains separate work.

## Bauhaus Clock

Bauhaus Clock is a commercial analog clock screen saver. Its maker describes multiple dial colors, subtle dial details, and a pixel-shift feature added in version 1.1. Its own troubleshooting page says that on macOS Tahoe the Options button may fail to open, and advises quitting and reopening System Settings. That is the maker's diagnosis and workaround, not proof that every unresponsive Options button has the same cause. A limited static inventory of the installed binary appears below; source was not examined. [Bauhaus Clock](https://bauhausclock.com/)

## Apple's documented contract

Apple documents `.saver` bundles containing a `ScreenSaverView` subclass, installed in a Library/Screen Savers directory. The bundle's machine architecture must match its host; Apple recommends both arm64 and x86_64 for full compatibility. Apple describes initial drawing followed by animation startup, repeated frame callbacks, and eventual animation stop. [Screen Saver framework](https://developer.apple.com/documentation/screensaver)

The initializer receives a frame and an `isPreview` flag, which the documented API defines as true for a System Settings preview. The screen saver view is installed in a window before animation begins. [ScreenSaverView initializer](https://developer.apple.com/documentation/screensaver/screensaverview/init%28frame%3Aispreview%3A%29)

`animateOneFrame()` is called by a system timer with at least the configured interval between calls; it is not a precise clock. Drawing directly there or invalidating the view for `draw(_:)` are documented options. A clock should derive its displayed time from the current date rather than count frames. [Apple: animateOneFrame](https://developer.apple.com/documentation/screensaver/screensaverview/animateoneframe%28%29)

A legacy saver reports whether it has a configuration sheet, and returns an `NSWindow` for it. Apple says the sheet controller must end the sheet via `NSApplication.endSheet(_:)`. Apple directs savers to `ScreenSaverDefaults` with their bundle identifier because multiple applications can load a saver. [Apple: configureSheet](https://developer.apple.com/documentation/screensaver/screensaverview/configuresheet), [Apple: ScreenSaverDefaults](https://developer.apple.com/documentation/screensaver/screensaverdefaults)

## Reported host failures

These are first-hand developer and vendor reports, not guarantees that the reported bugs remain in every release or explain an individual black screen.

- During Tahoe betas, developers reported duplicate legacy saver instances, unexpected preview values, instances accumulating without proper stops, unresponsive Options, and secondary-display failures. Feedback IDs in the public discussion include FB19201567, FB19204084 and FB19206021. Apple Developer Technical Support acknowledged the reports and requested bug reports; that is not a published determination that every issue is fixed or unfixed in current releases. [Apple Developer Forums](https://developer.apple.com/forums/thread/787444)
- Aerial's legacy sample attributes retained instances and excess resource use on Sonoma and later to the compatibility host and describes force-exiting the host as a heavy-handed workaround. Do not assume the workaround is necessary or safe for another saver. Its Tahoe notes also report preview and multi-monitor regressions. [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal)
- Aerial's maintainers reported black-screen and Settings issues improved in their move to an undocumented extension API, but this is a project-specific claim, not a controlled comparison across all configurations. [Aerial issue 1396](https://github.com/JohnCoates/Aerial/issues/1396)

## Extension architecture and tradeoff

Apple documents the public legacy `.saver` route. Aerial's authors describe an alternative Apple screen saver extension point, `com.apple.screensaver`, but explicitly identify it and its supporting classes as private and undocumented. Their newer wallpaper-continuity implementation uses a different private `WallpaperExtensionKit` API. These may change without notice; their use also has distribution and review implications that require independent validation. Do not present either as a supported Apple API. [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal), [Aerial](https://github.com/AerialScreensaver/Aerial)

In an instrumented sample on macOS 27.2 build 26B5112a, Aerial's authors observed separate Settings and WallpaperAgent-hosted extension instances; multiple views over repeated activations; and some released views receiving no `stopAnimation`. They observed configuration and rendering in separate processes and recommend handling window attachment and detachment, idempotent starts, and rereading settings. These are valuable test hypotheses for other OS builds and for the legacy host, not verified behavior on this Mac. [AppexSaverMinimal technical background](https://github.com/AerialScreensaver/AppexSaverMinimal/blob/main/BACKGROUND.md)

The same report warns duplicate registered extension copies can cause an unexpected build to be loaded. If an extension approach is evaluated, log the loaded bundle path and test with only one registered copy. This finding does not establish why any particular `.saver` displays black. [AppexSaverMinimal technical background](https://github.com/AerialScreensaver/AppexSaverMinimal/blob/main/BACKGROUND.md)

## Practical starting criteria

- Produce an initial frame without network access or external assets; use current time for animation. Validate both a small preview and a full-size display.
- Treat start, stop, window attachment, and destruction as separate observable events; avoid independent background timers that continue after the view disappears. Test repeated activation and resource use rather than assuming the documented lifecycle always occurs.
- Settings must work across separate hosts and processes. A separate application can offer an independent configuration path, but does not by itself repair macOS's Options button.
- Test real System Settings preview, actual idle activation and unlock, repeated activation, restart, display attachment, and two monitors, on each supported macOS release. A standalone test harness alone cannot establish host reliability.
- Verify signing, notarization, installation, and both CPU architectures before distribution. Apple's architecture requirement is documented; notarization and a developer identity are distribution concerns. [Apple Screen Saver framework](https://developer.apple.com/documentation/screensaver), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Unresolved

The installed Bauhaus build received a limited static inventory; its settings implementation and failure mode remain unverified. No claim is made that every Apple screen saver shares an architecture, that any private API is stable, that an Options workaround cures black frames, or that a particular release fixes the reported host bugs. Local binary inspection, visual evaluation, and controlled real-host tests are necessary to establish those facts.

## Local artifact inventory

On this Mac, macOS 27.2 build 26B5112a, the installed `/Library/Screen Savers/Bauhaus Clock 2.1.saver` identifies itself as version 2.1, bundle `com.atilla.bauhausclock`, with principal class `Bauhaus_Clock_ScreensaverView`. Its binary is signed and includes arm64 and x86_64 slices. Static strings include `configureSheet`, `hasConfigureSheet`, `animateOneFrame`, `startAnimation`, and `stopAnimation`. These names establish only that they occur in the binary; they do not establish call paths or identify the cause of a failure. SHA-256 of the universal executable: `ab72fec39b57a45923b1b97717977c7fca60ec4cf5c8c8c07c7a00e49ae4375f`.

The system includes legacy `FloatingMessage.saver` and `Random.saver`, as well as separate Wallpaper Legacy, Aerials, Macintosh, Dynamic, and other extension bundles under `/System/Library/ExtensionKit/Extensions`. Their installed manifests identify `com.apple.wallpaper` as the extension point. Binary dependency inspection shows the Legacy extension links the public ScreenSaver framework and private WallpaperExtensionKit; Aerials and Macintosh also link private WallpaperExtensionKit. The Aerials extension carries private Apple entitlements. These are static observations, not evidence that all built-in savers follow one execution path or that a third-party app can use the same privileges.

The native REA analysis was opened against an arm64 slice of Bauhaus. Automatic analysis of the original universal binary could not select a provider; deeper analysis of the slice timed out after 300 seconds; no REA function-level result was obtained. The separately recorded disassembly below used Apple command-line tools and is not runtime evidence. No user settings or installed bundles were changed.

## Follow-up static analysis: macOS 27.2 build 26B5112a

This is a version-specific inventory, not a complete decompilation or a live trace. Paths are the installed system files; dependencies identify linked frameworks, not necessarily everything used at runtime. `otool -L`, `otool -ov`, and `llvm-objdump --macho --disassemble` were used. The OS ships more assets and components than this table captures.

| Installed component | Bundle metadata or selected direct dependencies | What this establishes |
| --- | --- | --- |
| `Random.saver` | `RandomView`, subclass of `ScreenSaverView` | A legacy bundle; Objective-C metadata lists initialization, drawing, and `_randomModule` methods. |
| `FloatingMessage.saver` | `FloatingMessageView`, subclass of `ScreenSaverView` | Another legacy bundle; metadata lists initialization, frame animation, and drawing methods. |
| `WallpaperLegacyExtension.appex` | `com.apple.wallpaper`; links `ScreenSaver`, `WallpaperExtensionKit`, and `WallpaperFoundation` | Apple has a wallpaper extension with direct dependencies on both the legacy and private wallpaper frameworks. Strings name `legacyScreenSaver` and `legacyScreenSaver-x86_64`; these strings alone do not prove a particular invocation path. |
| `WallpaperAerialsExtension.appex` | `com.apple.wallpaper`; links `WallpaperExtensionKit` and `WallpaperFoundation` | A separate extension; strings include asset loading and networking names. |
| `WallpaperMacintoshExtension.appex` | `com.apple.wallpaper`; links `WallpaperExtensionKit`, `WallpaperFoundation`, and Metal | A separate extension with a direct Metal dependency; strings include `PixelsRenderer`. |
| `WallpaperSonomaExtension.appex` | `com.apple.wallpaper`; links `WallpaperExtensionKit`, `WallpaperFoundation`, and AVFoundation | A separate extension with an AVFoundation dependency; strings contain paths to landscape and portrait `.mov` assets. |
| `WallpaperMontereyExtension.appex` and `WallpaperVenturaExtension.appex` | `com.apple.wallpaper`; link `WallpaperExtensionKit`, `WallpaperFoundation`, Metal, and SceneKit | Separate extensions with direct graphics framework dependencies. |
| `WallpaperDynamicExtension.appex`, `WallpaperGradientExtension.appex`, `WallpaperImageExtension.appex`, `WallpaperSequoiaExtension.appex` | `com.apple.wallpaper`; link `WallpaperExtensionKit` and `WallpaperFoundation` | Additional extensions whose internal rendering and runtime behavior remain untraced. |

`NeptuneOneWallpaper.appex` was present, but its plist could not be parsed by Python's `plistlib`; its architecture is not characterized here. `Wallpaper.appex` declares the Settings UI extension point; `WallpaperSettingsIntents.appex` is another related component. These inventories do not cover every screen saver asset, OS version, or host process.

For Bauhaus Clock 2.1's arm64 slice, Objective-C method metadata identifies `-[Bauhaus_Clock_ScreensaverView configureSheet]` at `0x4394`. Disassembly of that method shows a conditional window construction path, `initWithContentRect:styleMask:backing:defer:`, and calls to `defaultsForModuleWithName:` using `com.atilla.bauhausclock`, followed by lookups for saved theme, color, dial, movement, and size and creation of a theme-selection view. It also logs `configureSheet called` and `Configure sheet created successfully`. This supports a programmatic options window with module preferences; it does not show whether macOS calls that method or displays the window when Options is clicked. The binary identifies its log subsystem as `com.atilla.bauhausclock` and category as `screensaver`; logs may help distinguish a missing host callback from failure after the callback, but no logs were examined here.

## Prototype verification

The prototype compiled into an ad-hoc signed arm64 Mach-O bundle, loaded and instantiated through `Bundle`, and rendered a nonblack frame to an offscreen bitmap at 320×180 and 800×600. `Tests/BundleRenderCheck.swift` repeats that narrow check. This is not an actual System Settings preview or an idle, lock, wake, or multi-display test. It does not demonstrate that the legacy host will launch reliably.

### Dedicated Apple screen saver extensions

A follow-up search of all installed ExtensionKit manifests, not just names containing “Wallpaper”, found 11 bundles declaring the separate `com.apple.screensaver` extension point. This distinction corrects the earlier, incomplete inventory. These are observed plist declarations on this build. The timer and configuration fields express declared metadata, not proof of callback behavior.

| Apple extension | `SSENeedsAnimationTimer` | `SSEHasConfigureSheet` | Selected direct linked frameworks |
| --- | --- | --- | --- |
| Album Artwork | false | true | ScreenSaver, QuartzCore |
| Arabesque | true | false | ScreenSaver, Metal, QuartzCore, OpenGL |
| Computer Name | true | true | ScreenSaver |
| Drift | false | true | ScreenSaver, Metal, MetalKit, QuartzCore |
| Flurry | true | true | ScreenSaver, OpenGL |
| Hello | false | true | ScreenSaver, Metal, SceneKit, QuartzCore |
| Monterey | false | false | ScreenSaver, Metal, MetalKit, SceneKit, QuartzCore |
| Shell | true | false | ScreenSaver, Metal, QuartzCore, OpenGL |
| Ventura | false | false | ScreenSaver, SceneKit, QuartzCore |
| Word of the Day | true | true | ScreenSaver, QuartzCore |
| iLifeSlideshows | false | true | ScreenSaver |

All eleven have an `NSExtensionPrincipalClass` and `ScreenSaverViewControllerClass`. Each of the six that declares a configuration sheet also names a configuration view controller. Those declarations match the separate extension architecture described by the [Aerial project](https://github.com/AerialScreensaver/AppexSaverMinimal/blob/main/BACKGROUND.md). A linked graphics framework does not establish the exact rendering algorithm. Apple's use does not establish that its extension point is public, supported for third parties, or stable.

This changes the engineering assessment: the simple legacy prototype exercises the documented interface but also the compatibility path associated with the reported host failures. It is a useful baseline, not the final answer to the reliability goal. A controlled comparison against an extension-based prototype is needed before deciding whether the private API's demonstrated behavior justifies its compatibility and distribution risks.

The same disassembly shows a separate `showConfigureSheet` method logging its call, obtaining `NSApplication.sharedApplication.windows.firstObject`, and sending `beginSheet:completionHandler:`. Its `closeConfigureSheet:` path commits the selection, writes the module defaults, calls `synchronize`, invokes `applySettings`, then sends `endSheet:` and `orderOut:`. Choosing the first application window is a potential fragility if this method runs in a process containing multiple windows; the static code does not establish that macOS invokes this separate method, which window is first, or that it causes the reported Options failures. The observed `endSheet:` call follows Apple's documented dismissal requirement.

Codesign metadata on the installed Flurry, Drift, Hello, and Arabesque extensions includes the app sandbox plus private Apple entitlements and temporary exceptions. This confirms Apple's own signing profile has privileges a third-party developer cannot assume; it does not establish which privileges any one screen saver actually requires. The installed public SDK's ScreenSaver link stub lists `ScreenSaverExtension`, `ScreenSaverViewController`, and `ScreenSaverConfigurationViewController`, but their presence as linkable symbols alone is not a public API or compatibility guarantee.

A read-only query for Bauhaus's log subsystem over the preceding 24 hours yielded no matching event entries. That absence cannot determine whether the Options callback was called: logging may not have been retained or the relevant interaction may have occurred outside the query window.

`pluginkit -m -v -p com.apple.screensaver` reports 13 registrations on this Mac: the 11 dedicated Apple extensions in the table and `com.apple.ScreenSaver.Engine.legacyScreenSaver` plus its x86-64 variant, both located in `ScreenSaver.framework/PlugIns`. This is direct registry evidence that Apple's compatibility adapters and the dedicated savers share the screen saver extension point. It does not by itself trace a specific `.saver` launch through either adapter.

## Extension registration investigation

On macOS 27.2 build 26B5112a, PlugInKit rejected the first experimental app extension with the explicit log message `plug-ins must be sandboxed`. After signing it with `com.apple.security.app-sandbox`, PlugInKit rejected it as being outside a containing app. Registering the containing app with Launch Services before adding the extension resolved that second rejection: `pluginkit -m -v -D -A -i local.geometry-clock.appex` then reported exactly one registration at the expected build path. `experimental/appex/check-registration.sh` repeats the registration check and removes its temporary registration; it refuses to disturb an existing registration with the same identifier.

The existing System Settings screen saver sheet was reopened and its Other collection inspected around the alphabetical G entries. Geometry Clock did not appear there in that inspection even while PlugInKit reported it registered. This was an already-running Settings session, and its caching or gallery ordering was not established; this is a bounded observation, not proof that discovery fails after a fresh host launch. The existing Battered Planet selection remained unchanged. No extension launch, animation, lock-screen, or multi-display behavior was observed. The temporary PlugInKit and Launch Services registrations were removed after the check.

After a full quit and relaunch of System Settings while the extension was registered, `Geometry Clock Extension` appeared in the Other gallery between Geodesic Gears and GFlux. The previous missing-entry observation was therefore specific to the already-running Settings session. The gallery reported Battered Planet as the selected screen saver; Geometry Clock was not selected, so its preview and real activation remain untested. The experimental extension was left registered for the next controlled test; it can be removed using `pluginkit -r` on its bundle followed by `lsregister -u` on its containing app.

### First host activation and fallback

During a real selection and preview attempt, System Settings listed and started `GeometryClockExtension`, but WallpaperAgent logged that it could not find the screen saver module and failed to translate the choice. Its module lookup reported 306 modules, while Settings reported 307. No matching Geometry Clock crash report was found. This shows a host discovery failure at that time, not proof that an extension crash caused the fallback.

After restarting WallpaperAgent and selecting Geometry Clock again, Settings displayed the clock in its preview. A brief `ScreenSaverEngine` activation produced WallpaperAgent logs identifying `GeometryClockExtension`, starting animation, and receiving two remote view sizes, 1920×1080 and 1710×1112. The user confirmed seeing a screen saver during the activation, and the module path in the logs identifies the selected extension. The original visible selection, Battered Planet, was restored afterward. The extension remains registered for further experiments.

This is one successful activation after a host restart, not evidence of reliable operation across sleep, wake, idle, many repetitions, OS versions, or changes in display configuration. The system's older module count before restarting and successful lookup afterward support stale host discovery as the explanation for this observed failure; they do not establish that all black-screen or Options failures share that cause.
