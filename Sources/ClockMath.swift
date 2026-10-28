import Foundation

struct ClockAngles {
    let hour: Double
    let minute: Double
    let second: Double

    static func from(date: Date, calendar: Calendar = .current) -> ClockAngles {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hour = Double(components.hour ?? 0).truncatingRemainder(dividingBy: 12)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)
        let fraction = Double(components.nanosecond ?? 0) / 1_000_000_000

        return ClockAngles(
            hour: 2 * Double.pi * ((hour + minute / 60 + second / 3600 + fraction / 3600) / 12),
            minute: 2 * Double.pi * ((minute + second / 60 + fraction / 60) / 60),
            second: 2 * Double.pi * ((second + fraction) / 60)
        )
    }
}
