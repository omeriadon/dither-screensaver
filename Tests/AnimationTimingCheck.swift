import Foundation

@main
enum AnimationTimingCheck {
    static func main() {
        var clock = DitherAnimationClock()

        assert(clock.advance(now: 10, isAdvancing: true) == 0)
        assert(clock.advance(now: 10.016, isAdvancing: true) > 0.015)
        assert(clock.advance(now: 9, isAdvancing: true) == 0)
        assert(clock.advance(now: 10, isAdvancing: true) == 1)
        assert(clock.advance(now: 10.016, isAdvancing: false) == 0)
        assert(clock.advance(now: 10.032, isAdvancing: true) > 0.015)
        clock.reset()
        assert(clock.advance(now: 100, isAdvancing: true) == 0)
        assert(clock.advance(now: 100.1, isAdvancing: true) > 0.099)

        print("AnimationTimingCheck passed")
    }
}
