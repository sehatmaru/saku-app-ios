import Foundation

/// One way to apply a payday change made in the middle of a period (PRD Ganti Tanggal Periode, P2/P3). The server works
/// out which ones are valid today; `PaydayOption` shows what each one does to the periods.
struct PaydayChoice: Equatable {
    enum Kind: String {
        case startOn = "start_on", after, extend, today
    }

    let kind: Kind
    let from: Date
    let extendsFrom: Date?
    let isDefault: Bool
}

/// What saving a choice gives: the running period and the one after it, worked out with the same period model the app
/// uses once the change is saved (shifts included), so the screen never promises dates the periods do not follow.
/// Choices with the same result are one option.
struct PaydayOption: Identifiable, Equatable {
    let choice: PaydayChoice
    let running: DateInterval
    let next: DateInterval
    let isDefault: Bool
    var id: Date { choice.from }

    static func options(for choices: [PaydayChoice], day: Int, today: Date = Date(), calendar: Calendar = .current) -> [PaydayOption] {
        let today = calendar.startOfDay(for: today)
        var base = PaydaySetting.schedule.filter { $0.from <= today }
        if base.isEmpty { base = [PaydayEntry(day: PaydayCycle.current.day, from: .distantPast)] }
        var options: [PaydayOption] = []
        for choice in choices {
            let entry = PaydayEntry(day: day, from: choice.from, extendsFrom: choice.extendsFrom)
            let cycle = PaydayCycle(day: day, schedule: base + [entry], shifts: PaydaySetting.shifts)
            let running = cycle.period(containing: today, calendar: calendar)
            let next = cycle.period(containing: running.end, calendar: calendar)
            if let index = options.firstIndex(where: { $0.running == running && $0.next == next }) {
                // the merged option keeps the default's choice, so the default stays selected
                if choice.isDefault { options[index] = PaydayOption(choice: choice, running: running, next: next, isDefault: true) }
            } else {
                options.append(PaydayOption(choice: choice, running: running, next: next, isDefault: choice.isDefault))
            }
        }
        return options
    }

    func days(_ period: DateInterval, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 0
    }
}
