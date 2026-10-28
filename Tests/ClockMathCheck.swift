import Foundation

@main
enum ClockMathCheck {
    static func main() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 3, minute: 30, second: 15))!
        let angles = ClockAngles.from(date: date, calendar: calendar)

        assert(abs(angles.second - (Double.pi / 2)) < 0.0001)
        assert(abs(angles.minute - (Double.pi * 1.0083333333)) < 0.0001)
        assert(abs(angles.hour - (Double.pi * 0.5840277778)) < 0.0001)
        print("ClockMathCheck passed")
    }
}
