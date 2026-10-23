import SwiftUI

/// One payday period as a calendar: a square per day, darker the more was spent, the amount inside. Monday first.
/// Used by the Kalender card on Statistik and by "Bulan ini" on Beranda; amounts follow the privacy switch.
struct SpendingCalendarGrid: View {
    let calendar: PeriodStatistics.SpendingCalendar
    let money: StatistikMoney

    private let heat: [Double] = [0.04, 0.12, 0.24, 0.38, 0.80]

    var body: some View {
        // Rows of seven: the leading blanks, then the days, padded to a full last row.
        let cells: [PeriodStatistics.CalendarDay?] = Array(repeating: nil, count: calendar.leadingBlanks) + calendar.days.map { Optional($0) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return VStack(alignment: .leading, spacing: 14) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(StatistikMoney.weekdays.indices, id: \.self) { index in
                        Text(StatistikMoney.weekdays[index].short).font(.app(11)).foregroundStyle(Color.appTextSecondary).padding(.bottom, 2)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            if column < rows[row].count, let day = rows[row][column] {
                                VStack(spacing: 1) {
                                    Text("\(day.day)").font(.app(10, weight: .semibold))
                                    Text(day.amount.flatMap { $0 > 0 ? money.cell($0) : nil } ?? " ").font(.app(9.5)).lineLimit(1).minimumScaleFactor(0.6)
                                }
                                .monospacedDigit()
                                .foregroundStyle(day.amount == nil ? Color.appTextTertiary : day.level >= 4 ? Color.appBackground : Color.appText)
                                .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                                .background(day.amount == nil ? Color.clear : Color.appText.opacity(heat[day.level]), in: RoundedRectangle(cornerRadius: 7))
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Rendah").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                ForEach(1..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(Color.appText.opacity(heat[level])).frame(width: 14, height: 8)
                }
                Text("Tinggi").font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}
