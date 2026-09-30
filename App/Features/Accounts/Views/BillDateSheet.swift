import SwiftUI

/// Picks the day a card bill was paid (Catat tagihan): only days from the statement's cut-off up to
/// today can be chosen, and the due date carries an orange dot.
struct BillDateSheet: View {
    let range: ClosedRange<Date>
    let dueDate: Date
    let color: Color
    let selected: Date
    let onPick: (Date) -> Void

    @State private var month: Date
    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current
    private static let dueDot = Color(hex: "C2410C")

    init(range: ClosedRange<Date>, dueDate: Date, color: Color, selected: Date, onPick: @escaping (Date) -> Void) {
        self.range = range
        self.dueDate = dueDate
        self.color = color
        self.selected = selected
        self.onPick = onPick
        let comps = Calendar.current.dateComponents([.year, .month], from: selected)
        _month = State(initialValue: Calendar.current.date(from: comps) ?? selected)
    }

    private var firstMonth: Date { monthStart(range.lowerBound) }
    private var lastMonth: Date { monthStart(range.upperBound) }
    private var hasPrevious: Bool { month > firstMonth }
    private var hasNext: Bool { month < lastMonth }

    private func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Leading blanks so the 1st lands under its weekday (weeks start on Monday), then every day.
    private var cells: [Date?] {
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (calendar.component(.weekday, from: month) + 5) % 7
        return Array(repeating: nil, count: lead)
            + (0..<length).map { calendar.date(byAdding: .day, value: $0, to: month) }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month).capitalized
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
                Spacer()
            }
            .overlay {
                Text("Tanggal bayar")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 13)

            HStack(spacing: 4) {
                if hasPrevious || hasNext {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(!hasPrevious)
                        .accessibilityLabel("Bulan sebelumnya")
                }
                Text(monthTitle + " · titik oranye = jatuh tempo")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                if hasPrevious || hasNext {
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(!hasNext)
                        .accessibilityLabel("Bulan berikutnya")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 10)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["S", "S", "R", "K", "J", "S", "M"].enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.app(12, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(height: 22)
                }
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 48) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            Spacer(minLength: 0)
        }
        .background(Color.appBackground)
        .presentationDetents([.height(CGFloat((cells.count + 6) / 7) * 48 + 150)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    private func shift(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isOn = calendar.isDate(day, inSameDayAs: selected)
        let isEnabled = day >= calendar.startOfDay(for: range.lowerBound) && day <= range.upperBound
        let isToday = calendar.isDateInToday(day)
        let isDue = calendar.isDate(day, inSameDayAs: dueDate)
        return Button { onPick(day) } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.app(16, weight: isOn || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? .white : !isEnabled ? Color.appBorder : isToday ? Color.appPrimary : Color.appText)
                    .frame(width: 38, height: 38)
                    .background(isOn ? color : .clear, in: Circle())
                Circle()
                    .fill(Self.dueDot)
                    .frame(width: 4, height: 4)
                    .opacity(isDue && !isOn ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide)) + (isDue ? ", jatuh tempo" : ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
