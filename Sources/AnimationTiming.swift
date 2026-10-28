import Foundation

struct DitherAnimationTiming {
    private var lastTime: TimeInterval?

    mutating func advance(now: TimeInterval, isAdvancing: Bool) -> TimeInterval {
        guard let previous = lastTime else {
            lastTime = now
            return 0
        }

        lastTime = now
        guard isAdvancing else {
            return 0
        }

        return max(0, now - previous)
    }

    mutating func reset() {
        lastTime = nil
    }
}
