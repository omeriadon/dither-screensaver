import Foundation

@main
enum AnimationTimingCheck {
    static func main() {
        var timing = DitherAnimationTiming()

        assert(timing.advance(now: 10, isAdvancing: true) == 0)
        assert(timing.advance(now: 10.016, isAdvancing: true) > 0.015)
        assert(timing.advance(now: 9, isAdvancing: true) == 0)
        assert(timing.advance(now: 10, isAdvancing: true) == 1)
        assert(timing.advance(now: 10.016, isAdvancing: false) == 0)
        assert(timing.advance(now: 10.032, isAdvancing: true) > 0.015)
        timing.reset()
        assert(timing.advance(now: 100, isAdvancing: true) == 0)
        assert(timing.advance(now: 100.1, isAdvancing: true) > 0.099)

        var staticConfiguration = DitherConfiguration()
        staticConfiguration.waveSpeed = 0
        assert(DitherRenderSchedulingPolicy.interval(for: staticConfiguration, introComplete: true) == nil)
        staticConfiguration.disableAnimation = true
        assert(DitherRenderSchedulingPolicy.interval(for: staticConfiguration, introComplete: true) == nil)

        var introConfiguration = DitherConfiguration()
        introConfiguration.intro = true
        assert(DitherRenderSchedulingPolicy.interval(for: introConfiguration, introComplete: false) == 1.0 / 30.0)

        var movingConfiguration = DitherConfiguration()
        movingConfiguration.waveSpeed = DitherRenderSchedulingPolicy.referenceSpeed
        let movingInterval = DitherRenderSchedulingPolicy.interval(for: movingConfiguration, introComplete: true)
        assert(movingInterval != nil)
        assert(movingInterval! <= 1.0 / DitherRenderSchedulingPolicy.minimumFramesPerSecond)

        movingConfiguration.waveSpeed = 0.01
        assert(abs(DitherRenderSchedulingPolicy.interval(for: movingConfiguration, introComplete: true)! - 1.0 / 6.0) < 0.000001)
        movingConfiguration.disableAnimation = true
        assert(DitherRenderSchedulingPolicy.interval(for: movingConfiguration, introComplete: true) == nil)
        assert(DitherRenderSchedulingPolicy.interval(for: staticConfiguration, introComplete: false) == 1.0 / 30.0)
        timing.seed(now: 200)
        assert(abs(timing.advance(now: 200.1, isAdvancing: true) - 0.1) < 0.000001)

        print("AnimationTimingCheck passed")
    }
}
