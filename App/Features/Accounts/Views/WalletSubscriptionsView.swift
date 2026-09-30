import SwiftUI

/// Recurring bills on one wallet as a month calendar (design 1b), pushed from the card detail.
struct WalletSubscriptionsView: View {
    let account: Account
    let subscriptions: [CardSubscription]
    let categories: [Category]
    /// Transactions this wallet's recurring bills have posted on their own.
    var recorded: [Transaction] = []

    private struct Editing: Identifiable {
        let existing: CardSubscription?
        let day: Int
        var id: String { existing?.id ?? "new-\(day)" }
    }

    @State private var form: Editing?
    @State private var monthOffset = 0
    @State private var selectedDay = Calendar.current.component(.day, from: Date())
    @State private var toastText = ""
    @State private var isToastShown = false
    @State private var showsAllRecorded = false
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    static let dueColor = Color(light: 0xC2410C, dark: 0xF07A45)
    private static let dueFill = Color(light: 0xFFF1E8, dark: 0x3A2418)

    init(account: Account, subscriptions: [CardSubscription], categories: [Category], recorded: [Transaction] = []) {
        self.account = account
        self.subscriptions = subscriptions
        self.categories = categories
        self.recorded = recorded
    }

    // MARK: Month maths

    private var calendar: Calendar { .current }

    private var monthStart: Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private var monthLength: Int { calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30 }
    /// Empty cells before the 1st in a Monday-first week.
    private var leadingBlanks: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    private var today: Int { calendar.component(.day, from: Date()) }
    private var selected: Int { min(selectedDay, monthLength) }

    private var isCardDueShown: Bool { account.isCreditCard && account.dueDay != nil }
    private func isDueDay(_ day: Int) -> Bool {
        guard account.isCreditCard, let due = account.dueDay else { return false }
        return min(due, monthLength) == day
    }

    /// Subscriptions billed on `day` of the shown month: monthly ones every month, yearly ones in their month.
    private func subscriptions(on day: Int) -> [CardSubscription] {
        let month = calendar.component(.month, from: monthStart)
        return subscriptions.filter { sub in
            guard let date = sub.nextBillingDateAsDate else { return false }
            if sub.frequency == .yearly, calendar.component(.month, from: date) != month { return false }
            return min(calendar.component(.day, from: date), monthLength) == day
        }
    }

    private var monthlyTotal: Double {
        subscriptions.filter(\.isActive).reduce(0) { $0 + $1.monthlyAmount }
    }

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private static let monthTitle: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "id_ID"); f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let dayTitle: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "id_ID"); f.dateFormat = "EEEE, d MMMM"; return f
    }()

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                totalBox
                autoNote
                monthHeader
                calendarGrid
                legend
                EmptyStateButton(title: "Tambah di tanggal \(selected)", isFullWidth: true) {
                    form = Editing(existing: nil, day: selected)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                dayList
                    .padding(.top, 18)
                recordedList
                    .padding(.top, 24)
            }
            .padding(.bottom, 60)
        }
        .background(Color.appBackground)
        .navigationTitle("Tagihan berulang")
        .navigationBarTitleDisplayMode(.inline)
        .toast(toastText, isShown: $isToastShown)
        .fullScreenCover(item: $form) { form in
            AddSubscriptionView(categories: categories, account: account, subscriptions: subscriptions,
                                existing: form.existing, day: form.day) {
                toastText = form.existing == nil ? "Tagihan berulang ditambahkan" : "Perubahan disimpan"
                if form.existing == nil { selectedDay = form.day }
                Task {
                    // After the cover has slid away.
                    try? await Task.sleep(for: .milliseconds(400))
                    isToastShown = true
                }
            }
        }
    }

    private var totalBox: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Total per bulan")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                Text(money(monthlyTotal))
                    .font(.app(20, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.appText)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Text("\(subscriptions.count) tagihan")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .animation(.settle(0.4), value: monthlyTotal)
        .accessibilityElement(children: .combine)
    }

    /// Says up front that bills post themselves, so nobody adds them by hand as well.
    private var autoNote: some View {
        Label("Tagihan dicatat otomatis sebagai pengeluaran saat kamu membuka Saku di tanggal tagih. Kalau baru dibuka setelahnya, tetap dicatat dengan tanggal tagihnya.",
              systemImage: "info.circle")
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }

    private var monthHeader: some View {
        HStack {
            Text(Self.monthTitle.string(from: monthStart))
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
                .contentTransition(.opacity)
            Spacer()
            HStack(spacing: 4) {
                monthButton("chevron.left", label: "Bulan sebelumnya", step: -1)
                monthButton("chevron.right", label: "Bulan berikutnya", step: 1)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func monthButton(_ symbol: String, label: String, step: Int) -> some View {
        Button {
            withAnimation(.settle(0.4)) { monthOffset += step }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(CircleHighlightStyle())
        .accessibilityLabel(label)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["S", "S", "R", "K", "J", "S", "M"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.app(12, weight: .semibold))
                        .foregroundStyle(Color(light: 0xA1A1A6, dark: 0x8E8E93))
                        .frame(height: 24)
                }
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<(leadingBlanks + monthLength), id: \.self) { index in
                    let day = index - leadingBlanks + 1
                    if day < 1 {
                        Color.clear.frame(height: 50)
                    } else {
                        dayCell(day)
                    }
                }
            }
            .id(monthOffset)
            .transition(.opacity)
        }
        .padding(.horizontal, 12)
    }

    private func dayCell(_ day: Int) -> some View {
        let isOn = day == selected
        let isToday = monthOffset == 0 && day == today
        let isPast = monthOffset == 0 && day < today
        let dots: [Color] = ((isDueDay(day) ? [Self.dueColor] : []) + subscriptions(on: day).map { _ in Color.appPrimary })
        let text: Color = isOn ? .appBackground : isToday ? .appPrimary : isPast ? Color(light: 0xA1A1A6, dark: 0x636366) : .appText
        return Button {
            withAnimation(.settle(0.35)) { selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.app(16, weight: isOn || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isOn ? Color.appText : Color.clear))
                    .scaleEffect(isOn ? 1.06 : 1)
                    .animation(.spring(duration: 0.38, bounce: 0.45), value: isOn)
                HStack(spacing: 3) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tanggal \(day)" + (dots.isEmpty ? "" : ", \(dots.count) tagihan"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(.appPrimary, "Tagihan berulang")
            if isCardDueShown { legendItem(Self.dueColor, "Jatuh tempo kartu") }
            Spacer(minLength: 0)
        }
        .font(.app(12))
        .foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    // MARK: Selected day

    private var selectedDate: Date {
        calendar.date(byAdding: .day, value: selected - 1, to: monthStart) ?? monthStart
    }

    private var dayList: some View {
        let subs = subscriptions(on: selected)
        let total = subs.filter(\.isActive).reduce(0) { $0 + $1.amount }
        let hasDue = isDueDay(selected)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayTitle.string(from: selectedDate))
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                if total > 0 {
                    Text(money(total))
                        .font(.app(13))
                        .monospacedDigit()
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if hasDue { dueRow }
            ForEach(subs) { sub in
                row(sub)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !hasDue && subs.isEmpty {
                Text("Tidak ada tagihan di tanggal ini")
                    .font(.app(15))
                    .foregroundStyle(Color(light: 0xA1A1A6, dark: 0x8E8E93))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
        .animation(.settle(0.35), value: subscriptions.map(\.id))
    }

    // MARK: Recorded

    private static let recordedDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "id_ID"); f.dateFormat = "d MMM yyyy"; return f
    }()

    /// What the recurring bills already posted, newest first.
    private var recordedList: some View {
        let sorted = recorded.sorted { $0.date > $1.date }
        let shown = showsAllRecorded ? sorted : Array(sorted.prefix(8))
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sudah dicatat otomatis")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                if !sorted.isEmpty {
                    Text("\(sorted.count) transaksi")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if sorted.isEmpty {
                Text("Belum ada. Tagihan yang jatuh tempo muncul di sini setelah dicatat.")
                    .font(.app(15))
                    .foregroundStyle(Color(light: 0xA1A1A6, dark: 0x8E8E93))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
            ForEach(shown) { txn in
                HStack(spacing: 14) {
                    iconCircle("checkmark", fill: Color.appPrimary.opacity(0.12), tint: .appPrimary)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.recurringName ?? "Tagihan berulang")
                                .font(.app(16))
                                .foregroundStyle(Color.appText)
                                .lineLimit(1)
                            Text(Self.recordedDate.string(from: txn.date))
                                .font(.app(13))
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer(minLength: 0)
                        Text("−" + money(txn.amount))
                            .font(.app(16))
                            .monospacedDigit()
                            .foregroundStyle(Color.appText)
                    }
                    .frame(height: 64)
                    .rowSeparator()
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)
            }
            if sorted.count > shown.count {
                Button("Lihat semua (\(sorted.count))") {
                    withAnimation(.settle(0.35)) { showsAllRecorded = true }
                }
                .font(.app(15, weight: .medium))
                .foregroundStyle(Color.appPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    private func iconCircle(_ symbol: String, fill: Color, tint: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
            }
    }

    private var dueRow: some View {
        HStack(spacing: 14) {
            iconCircle("calendar", fill: Self.dueFill, tint: Self.dueColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Jatuh tempo \(account.name)")
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Text("Bayar sebelum tanggal ini")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .rowSeparator()
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private func row(_ sub: CardSubscription) -> some View {
        let category = categories.first { $0.id == sub.categoryId }
        return Button { form = Editing(existing: sub, day: selected) } label: {
            HStack(spacing: 14) {
                iconCircle(category?.icon ?? "repeat", fill: .appFill, tint: .appBody)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text(sub.name)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(money(sub.amount))
                            .font(.app(16))
                            .monospacedDigit()
                            .foregroundStyle(sub.isActive ? Color.appText : Color.appTextSecondary)
                    }
                    HStack(spacing: 6) {
                        Text(category?.name ?? "Lainnya")
                        if sub.frequency == .yearly { Text("· tiap tahun") }
                        if !sub.isActive {
                            Text("Dijeda")
                                .font(.app(12, weight: .medium))
                                .foregroundStyle(Color.appWarning)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(Color.appWarning.opacity(0.12), in: Capsule())
                        }
                    }
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                }
                .frame(height: 64)
                .rowSeparator()
            }
            .padding(.horizontal, 24)
            .opacity(sub.isActive ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// Grey circle behind an icon button while it's pressed.
private struct CircleHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Color.appFill : .clear))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
