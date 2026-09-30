import SwiftUI

/// Colour, label, icon and sign for each transaction type, shared by the add form and the detail page.
struct TransactionStyle {
    let type: Transaction.TransactionType
    let label: String
    let icon: String
    let color: Color
    let sign: String

    static let expense = TransactionStyle(type: .expense, label: "Pengeluaran", icon: "arrow.up.right", color: Color(hex: "D93636"), sign: "−")
    static let income = TransactionStyle(type: .income, label: "Pemasukan", icon: "arrow.down.left", color: Color(hex: "16875A"), sign: "+")
    static let transfer = TransactionStyle(type: .transfer, label: "Transfer", icon: "arrow.left.arrow.right", color: Color(hex: "143A73"), sign: "")
    static let adjustment = TransactionStyle(type: .adjustment, label: "Penyesuaian saldo", icon: "arrow.triangle.2.circlepath", color: Color(hex: "616161"), sign: "")

    /// The three types the add form's carousel offers, in order.
    static let entryTypes = [expense, income, transfer]

    static func of(_ type: Transaction.TransactionType) -> TransactionStyle {
        switch type {
        case .expense: expense
        case .income: income
        case .transfer: transfer
        case .adjustment: adjustment
        }
    }
}

/// Wallet colour from its icon, falling back to the brand green.
func walletColor(_ account: Account?) -> Color {
    account.flatMap { WalletIcon.resolve($0.icon)?.color } ?? .appPrimary
}

// MARK: - Picker sheet

/// Bottom sheet with a title, a Selesai button and scrolling content.
struct PickerSheet<Content: View>: View {
    let title: String
    var actionTitle = "Selesai"
    let onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.app(17, weight: .semibold))
                Spacer()
                Button(actionTitle, action: onDone)
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            ScrollView { content }
                .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }
}

/// Four-column grid of round category icons; the picked one fills with `color`.
struct CategoryPickerGrid: View {
    let categories: [Category]
    let selectedId: String?
    let color: Color
    let onPick: (Category) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
            ForEach(categories) { cat in
                let isOn = cat.id == selectedId
                Button { onPick(cat) } label: {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(isOn ? color : Color.appFill)
                            .frame(width: 54, height: 54)
                            .overlay {
                                Image(systemName: cat.icon ?? "tag")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isOn ? Color.white : Color.appText)
                            }
                            .scaleEffect(isOn ? 1.08 : 1)
                            .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: isOn)
                        Text(cat.name)
                            .font(.app(12))
                            .foregroundStyle(isOn ? Color.appText : Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }
}

/// Two-column grid of wallet cards with balance; the picked one gets a ring.
struct WalletPickerGrid: View {
    let accounts: [Account]
    let selectedId: String?
    let onPick: (Account) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(accounts) { acc in
                let isOn = acc.id == selectedId
                let color = walletColor(acc)
                Button { onPick(acc) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(WalletIcon.resolve(acc.icon)?.shortName ?? String(acc.name.prefix(4)).uppercased())
                                .font(.app(10, weight: .heavy))
                                .tracking(0.5)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(isOn ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                        Text(acc.name)
                            .font(.app(14, weight: .semibold))
                            .lineLimit(1)
                        Text(acc.isCreditCard
                             ? "Sisa limit Rp" + (acc.availableCredit ?? 0).formattedAsDigits()
                             : "Rp" + acc.balance.formattedAsDigits())
                            .font(.app(12))
                            .opacity(0.82)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(height: 76)
                    .background(color, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if isOn {
                            RoundedRectangle(cornerRadius: 16).inset(by: -2).stroke(Color.appBackground, lineWidth: 2)
                            RoundedRectangle(cornerRadius: 18).inset(by: -4).stroke(color, lineWidth: 2)
                        }
                    }
                    .scaleEffect(isOn ? 1.03 : 1)
                    .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }
}

/// Hari ini / Kemarin chips over a Monday-first month grid; future days are disabled.
struct DayPicker: View {
    let selected: Date
    let color: Color
    let onPick: (Date) -> Void
    @State private var shownMonth: Date

    private var calendar: Calendar { .current }

    init(selected: Date, color: Color, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.color = color
        self.onPick = onPick
        let calendar = Calendar.current
        _shownMonth = State(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: selected)) ?? selected)
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let isCurrentMonth = calendar.isDate(shownMonth, equalTo: today, toGranularity: .month)
        let grid = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                quickDay("Hari ini", today)
                quickDay("Kemarin", yesterday)
            }

            HStack {
                Text(Self.monthYear.string(from: shownMonth))
                    .font(.app(15, weight: .semibold))
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Bulan sebelumnya")
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Bulan berikutnya")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.appText)
            .padding(.top, 16)

            LazyVGrid(columns: grid, spacing: 0) {
                ForEach(["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"], id: \.self) {
                    Text($0).font(.app(12)).foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
                }
            }
            .padding(.top, 10)

            LazyVGrid(columns: grid, spacing: 0) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    dayCell(day, today: today)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func quickDay(_ label: String, _ day: Date) -> some View {
        let isOn = calendar.isDate(selected, inSameDayAs: day)
        return Button { onPick(day) } label: {
            Text(label)
                .font(.app(15, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.appText)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(isOn ? color : Color.appBackground, in: Capsule())
                .overlay(Capsule().stroke(isOn ? color : Color.appBorder, lineWidth: 1))
                .animation(.easeInOut(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
    }

    /// Days of `shownMonth`, padded with nils so the 1st lands under its weekday.
    private var monthCells: [Date?] {
        let count = calendar.range(of: .day, in: .month, for: shownMonth)?.count ?? 30
        let lead = (calendar.component(.weekday, from: shownMonth) + 5) % 7
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: shownMonth) }
        return Array(repeating: nil, count: lead) + days
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, today: Date) -> some View {
        if let day {
            let isOn = calendar.isDate(day, inSameDayAs: selected)
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let isFuture = day > today
            Button { onPick(day) } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.app(16, weight: isOn || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? Color.white : isFuture ? Color(light: 0xC7C7CC, dark: 0x48484A) : Color.appText)
                    .frame(width: 38, height: 38)
                    .background(isOn ? color : .clear, in: Circle())
                    .overlay {
                        if isToday && !isOn { Circle().inset(by: 0.75).stroke(color, lineWidth: 1.5) }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isOn)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private func moveMonth(_ delta: Int) {
        shownMonth = calendar.date(byAdding: .month, value: delta, to: shownMonth) ?? shownMonth
    }

    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f
    }()
}

// MARK: - Number pad

/// Integer amount entry shared by the add form and the detail page's amount editor.
enum NumberPad {
    static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "del"]

    /// New amount after pressing `key`, or nil when it would exceed 11 digits.
    static func apply(_ key: String, to amount: Int) -> Int? {
        let next: Int
        switch key {
        case "del": next = amount / 10
        case "000": next = amount * 1000
        default: next = amount * 10 + (Int(key) ?? 0)
        }
        return next <= 99_999_999_999 ? next : nil
    }
}

/// 3×4 grid of number keys.
struct NumberPadKeys: View {
    let onPress: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(NumberPad.keys, id: \.self) { key in
                Button { onPress(key) } label: {
                    Group {
                        if key == "del" {
                            Image(systemName: "delete.left").font(.system(size: 22))
                        } else {
                            Text(key).font(.app(24))
                        }
                    }
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(KeyStyle())
                .accessibilityLabel(key == "del" ? "Hapus" : key)
            }
        }
    }
}

/// Tall Simpan button next to the number pad, in the type colour once there's an amount.
struct SaveKey: View {
    let color: Color
    let isEnabled: Bool
    var isSaving = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                }
                Text("Simpan").font(.app(14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isEnabled ? color : Color(light: 0xC7C7CC, dark: 0x48484A), in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.4), value: isEnabled)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Number keys and Simpan in the design's 3:1 split.
struct AmountPad: View {
    let color: Color
    let isEnabled: Bool
    var isSaving = false
    let onPress: (String) -> Void
    let onSave: () -> Void

    var body: some View {
        GeometryReader { geo in
            let saveWidth = (geo.size.width - 6) / 4
            HStack(spacing: 6) {
                NumberPadKeys(onPress: onPress)
                    .frame(width: geo.size.width - saveWidth - 6)
                SaveKey(color: color, isEnabled: isEnabled, isSaving: isSaving, action: onSave)
                    .frame(width: saveWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 52 * 4 + 6 * 3)
    }
}

/// Numpad key: light fill that darkens while pressed.
struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Dark fill is a step lighter than sheets (#1C1C1E) so keys stay visible there too.
            .background(configuration.isPressed ? Color(light: 0xE5E5EA, dark: 0x48484A) : Color(light: 0xF7F7F8, dark: 0x2C2C2E),
                        in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Transaction dates in the revamp's wording.
enum TransactionDates {
    private static var calendar: Calendar { .current }

    /// "Hari ini", "Kemarin" or e.g. "Sel, 15 Sep".
    static func dayName(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hari ini" }
        if calendar.isDateInYesterday(date) { return "Kemarin" }
        return weekdayDayMonth.string(from: date)
    }

    /// "hari ini", "kemarin" or e.g. "15 Sep".
    static func dayShort(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "hari ini" }
        if calendar.isDateInYesterday(date) { return "kemarin" }
        return dayMonth.string(from: date)
    }

    /// e.g. "Senin, 28 Sep 2026 · 12.34"; the time is left out when none was recorded.
    static func long(_ date: Date, withYear: Bool = true) -> String {
        let day = (withYear ? fullWithYear : full).string(from: date)
        return hasTime(date) ? day + " · " + time.string(from: date) : day
    }

    private static func hasTime(_ date: Date) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour != 0 || parts.minute != 0
    }

    static let dayMonth = formatter("d MMM")
    static let weekdayDayMonth = formatter("EEE, d MMM")
    private static let full = formatter("EEEE, d MMM")
    private static let fullWithYear = formatter("EEEE, d MMM yyyy")
    private static let time = formatter("HH.mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "id_ID")
        return f
    }
}
