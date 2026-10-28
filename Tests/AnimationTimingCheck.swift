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

        print("AnimationTimingCheck passed")
    }
}
