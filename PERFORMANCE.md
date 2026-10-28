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
