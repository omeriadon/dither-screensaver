# Dither performance parity audit

The screen saver now uses the current DesktopDither renderer in `Sources/DitherMetalRenderer.swift`. The port includes the fused field/cell compute path with original quantization, shared packed gradients and pipelines, private intermediate textures, cached coverage atlases, join masks with two-dimensional dispatch, reusable pass descriptors, and palette-buffer caching. Top blur remains available but is disabled by default for the saver so the existing appearance is preserved.

The settings preview uses adaptive scheduling from `DitherRenderSchedulingPolicy`. The saver uses the original fixed 30 Hz host timer; its interval is never changed while rendering. Zero-speed, disabled, and non-finite configurations skip GPU submissions after intro completion. The settings preview stops its timer entirely for static configurations. Lifecycle timing is reset or seeded at attachment, start, and stop boundaries, and redraws are guarded for hidden views, invalid sizes, missing drawables, and backing-scale changes.

Verification includes the existing `Tools/DitherRender.swift` rendering self-checks, the animation timing and scheduling assertions in `Tests/AnimationTimingCheck.swift`, source inclusion checks in `build.sh`, `render.sh`, and `experimental/appex/build.sh`, and the settings checks. The render self-check also requires byte equality for 120 reference/optimized comparisons across eight modes, three geometries and five cell sizes, with palette variants and odd target dimensions.

Build scripts pass `-O` and full LLVM LTO (without debug information) in addition to whole-module optimization and link Metal Performance Shaders where the renderer requires it.

The checks are source/build/render-entry-point verification. No screen saver activation, installation, Xcode build, long-running compositor test, multi-display test, or new numeric performance claim was made.

## Extension lifecycle correction

The remote screen saver view service can attach and resize the view without calling `startAnimation`. Nonadvancing layout redraws then preserve the intro's blank first frame. The extension controller now explicitly starts animation in `viewDidAppear` and stops it in `viewDidDisappear`; the saver ignores duplicate starts to preserve its timing boundary. GPU optimizations and cadence remain intact.

Temporary live probes reproduced attached, nonadvancing frames with no start callback in the failing host. With lifecycle forwarding, the installed extension started on appearance and progressed to completed intro frames. The probes were removed. `Tests/ScreenSaverLifecycleCheck.swift` also exercises the real superclass timer in a hidden standalone window, verifies intro completion, and calls start twice. A standalone instance of Apple's private view-service controller cannot be tested outside its service process. Fullscreen activation was not used for final verification.

## Intermittent display stalls investigation

The user reported continued intermittent stalls, including one display freezing while the other continued, after the lifecycle correction. The optimization port had also changed the saver from a fixed host timer to assigning its interval both before and after every rendered frame. The saver now restores its pre-port fixed 30 Hz timer. Static configurations still skip GPU submissions. Shader optimizations and adaptive settings-preview scheduling are retained.

This is a conservative rollback of a scheduling change, not a confirmed root-cause fix. The standalone harness did not reproduce the intermittent remote-host stall. A source-count assertion from the initial investigation was removed because it checked implementation text rather than animation behavior. The expanded lifecycle check now measures actual renderer time for two independently timed saver views after intro completion, static-to-moving settings changes, hide/unhide, stop/start, and detach/reattach. Pausing or hiding one instance must not stop the other. All checks passed without activating the screen saver. A separate offscreen check produced 120 distinct matching frames from each of two renderer instances; the existing 120 image-parity comparisons also passed. These checks do not exercise the remote compositor or physical displays.

## Historical measurements before this port

The following records the older renderer and does not measure the port above.

# Dither performance investigation

Measured on this Mac's Apple M2 GPU, with the default effect and pixel size, on 27 October 2026. `./benchmark.sh` compiles a command-line tool and renders 120 warmed frames per size to offscreen Metal textures. It waits for each GPU command buffer to finish, so this is a serialized microbenchmark, not a simulation of two simultaneous screens or the actual macOS screen saver host. Submission is elapsed wall time through command-buffer submission, not process CPU time. GPU time uses Metal command-buffer timestamps.

| Texture size | Cell size in device pixels | Mean submission | Mean GPU time | GPU 95th percentile |
| --- | ---: | ---: | ---: | ---: |
| 640 × 360 | 2 | 0.020 ms | 0.431 ms | 0.350 ms |
| 1920 × 1080 | 2 | 0.026 ms | 1.328 ms | 2.301 ms |
| 2560 × 1664 | 4 | 0.040 ms | 0.886 ms | 1.375 ms |

Mean can exceed the 95th percentile when a few outliers are much slower. These are single runs, not power, temperature, compositor, sustained-load, or multi-display measurements; actual frame delivery also depends on macOS and other GPU work. The results show that the shader can render within a 16.7 ms frame budget in this test, but cannot establish whether the user's observed pauses were caused by GPU load.

The previous renderer used the system wall time and discarded elapsed time above 50 ms on any frame. The new renderer uses monotonic timing and retains elapsed time for active frames; it resets its timing state when stopped or detached so a later resume does not include idle time. `Tests/AnimationTimingCheck.swift` checks delayed-frame continuity and reset behavior. This fixes an identified timing weakness, but the intermittent pause itself has not been reproduced in the offscreen harness or verified as resolved in System Settings.

Cursor tracking, trail and ripple shaders, interaction buffers, and their controls were removed. Configuration is cached rather than parsed every frame, and the palette buffer is recreated only when its colors change. The default offscreen image checksum remains `7692264141583559136`, matching the prior default frame. This checks one static frame, not visual equivalence across every setting.

The screen saver was not activated during testing. Real preview cadence, idle activation, both displays running together, long-duration performance and battery/energy use remain unmeasured.
