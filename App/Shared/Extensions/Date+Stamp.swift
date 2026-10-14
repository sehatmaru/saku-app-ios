import Foundation

extension Date {
    /// The day of this date with the time it is right now: what a transaction created now is stamped with, so the
    /// list orders it by when it was actually recorded, whatever day the user picked. Today stays exactly now.
    func atCurrentTime(now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(self, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: self) ?? self
    }
}
