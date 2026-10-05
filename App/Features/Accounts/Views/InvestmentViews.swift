import SwiftUI

private enum InvestmentUI {
    static let box = Color(light: 0xF7F7F8, dark: 0x1C1C1E)
    static let line = Color(light: 0xEDEDF0, dark: 0x2C2C2E)
    static let errFill = Color(light: 0xFDECEA, dark: 0x3A1C1A)
    static let warnFill = Color(light: 0xFFF1E8, dark: 0x3A2316)
    static let warnInk = Color(light: 0xC2410C, dark: 0xFFB340)

    static func money(_ value: Double, visible: Bool) -> String { visible ? value.formattedAsCurrency() : "Rp" + hiddenAmount }

    static func signed(_ value: Double) -> String { (value > 0 ? "+" : value < 0 ? "−" : "") }

    static func shortDate(_ date: Date) -> String { TransactionDates.dayMonth.string(from: date) }

    static func daysAgo(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ...0: return L("hari ini")
        case 1: return L("kemarin")
        default: return L("%lld hari lalu", days)
        }
    }
}

// MARK: - Detail (design 4)

/// Under an open investment card: gain, capital, last update, and Setor, Tarik, Perbarui nilai, Riwayat.
struct InvestmentDetailContent: View {
    let account: Account
    let transactions: [Transaction]
    let isBalanceVisible: Bool
    let onDeposit: () -> Void
    let onWithdraw: () -> Void
    let onUpdateValue: () -> Void
    let onHistory: () -> Void

    var body: some View {
        let summary = InvestmentSummary(account: account, transactions: transactions)
        let gainColor: Color = summary.gain > 0 ? .appPrimary : summary.gain < 0 ? .appError : .appTextSecondary
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                row(L("Untung/rugi")) {
                    Text(gainText(summary))
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(gainColor)
                }
                row(L("Modal disetor")) {
                    Text(InvestmentUI.money(summary.capital, visible: isBalanceVisible)).font(.app(15))
                }
                row(L("Terakhir diperbarui")) {
                    Text(summary.lastUpdated.map { InvestmentUI.shortDate($0) + " · " + InvestmentUI.daysAgo($0) } ?? "—")
                        .font(.app(15))
                }
            }
            .padding(16)
            .background(InvestmentUI.box, in: RoundedRectangle(cornerRadius: 18))

            if let note = note(summary) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 14)).padding(.top, 1)
                    Text(note).font(.app(13)).lineSpacing(2)
                }
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 10)
            }

            HStack(spacing: 0) {
                action(L("Setor"), "tray.and.arrow.down", onDeposit)
                action(L("Tarik"), "tray.and.arrow.up", onWithdraw)
                action(L("Perbarui nilai"), "arrow.triangle.2.circlepath", onUpdateValue, tinted: true)
                action(L("Riwayat"), "clock.arrow.circlepath", onHistory)
            }
            .padding(.top, 18)
        }
    }

    private func gainText(_ s: InvestmentSummary) -> String {
        guard isBalanceVisible else { return "••••" }
        let sign = InvestmentUI.signed(s.gain)
        let rupiah = sign + abs(s.gain).formattedAsCurrency()
        return s.percent.map { rupiah + " · " + InvestmentSummary.percentText($0, signed: true) } ?? rupiah
    }

    private func note(_ s: InvestmentSummary) -> String? {
        if s.capital <= 0 { return L("Modal Rp0, jadi persen untung/rugi tidak ditampilkan.") }
        if s.value <= 0 { return L("Nilai Rp0 berarti rugi 100% dari modal. Perbarui nilai jika ini keliru.") }
        return nil
    }

    private func row<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Spacer(minLength: 8)
            value().monospacedDigit()
        }
    }

    private func action(_ title: String, _ icon: String, _ perform: @escaping () -> Void, tinted: Bool = false) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tinted ? Color.appInvestment : Color.appText)
                    .frame(width: 44, height: 44)
                    .background(tinted ? Color.appInvestmentTint : Color.appFill, in: Circle())
                Text(title).font(.app(12)).foregroundStyle(Color.appText).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Perbarui nilai (design 5)

/// The investment's new worth, typed on the number pad. Applies straight away: the difference is logged as an
/// adjustment, which is neither income nor expense.
struct UpdateValueView: View {
    let account: Account
    /// Capital put in, for the "rugi 100%" note.
    let capital: Double
    let onApply: (_ newValue: Double, _ date: Date, _ note: String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var digits: String
    @State private var negative = false
    @State private var fresh = true
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var note = ""
    @State private var showsDate = false
    @State private var shake: CGFloat = 0
    @State private var bump = false
    @State private var isSaving = false
    @State private var done: (value: Double, delta: Double)?
    @State private var failed = false
    @FocusState private var noteFocused: Bool

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "neg", "0", "del"]

    init(account: Account, capital: Double, onApply: @escaping (Double, Date, String) async -> Bool) {
        self.account = account
        self.capital = capital
        self.onApply = onApply
        _digits = State(initialValue: String(Int(account.balance.rounded())))
    }

    private var magnitude: Double { Double(digits) ?? 0 }
    private var isError: Bool { negative && magnitude > 0 }
    private var newValue: Double { negative ? -magnitude : magnitude }
    private var delta: Double { newValue - account.balance }
    private func money(_ v: Double) -> String { v.formattedAsCurrency() }

    var body: some View {
        VStack(spacing: 0) {
            panel
            hint
                .padding(.horizontal, 24)
                .padding(.top, 12)
            rows
                .padding(.top, 10)
            Spacer(minLength: 0)
            if !noteFocused {
                keypad
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.appBackground)
        .foregroundStyle(Color.appText)
        .sheet(isPresented: $showsDate) {
            PickerSheet(title: L("Tanggal"), onDone: { showsDate = false }) {
                DayPicker(selected: date, color: .appInvestmentPanel) { day in date = day; showsDate = false }
            }
        }
        .alert(L("Gagal memperbarui nilai"), isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }.font(.app(17)).disabled(isSaving)
                Spacer()
            }
            .overlay { Text("Perbarui nilai").font(.app(17, weight: .semibold)) }
            .frame(height: 44)
            .padding(.horizontal, 20)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Label(L("%@ · Investasi", account.name), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.app(13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(.white.opacity(0.18), in: Capsule())
                        .padding(.top, 10)

                    HStack(alignment: .top, spacing: 4) {
                        Text(negative ? "−Rp" : "Rp").font(.app(22)).opacity(0.8).padding(.top, 8)
                        Text(Double(magnitude).formattedAsDigits())
                            .font(.app(56, weight: .light))
                            .tracking(-2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                    }
                    .monospacedDigit()
                    .opacity(fresh ? 0.7 : 1)
                    .scaleEffect(bump ? 1.04 : 1)
                    .offset(x: shake)
                    .animation(.easeOut(duration: 0.12), value: bump)
                    .padding(.top, 14)

                    HStack(alignment: .top, spacing: 8) {
                        stat(L("Nilai sebelumnya"), money(account.balance))
                        stat(L("Nilai baru"), (isError ? "−" : "") + money(magnitude))
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Selisih").font(.app(12)).opacity(0.85)
                            Label(isError ? "—" : InvestmentUI.signed(delta) + money(abs(delta)),
                                  systemImage: isError ? "xmark" : delta > 0 ? "chart.line.uptrend.xyaxis" : delta < 0 ? "chart.line.downtrend.xyaxis" : "equal")
                                .font(.app(14, weight: .bold))
                                .foregroundStyle(Color.appInvestmentPanel)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(.white, in: Capsule())
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .monospacedDigit()
                    .padding(14)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                }
                .opacity(done == nil ? 1 : 0)
                .scaleEffect(done == nil ? 1 : 0.97)
                .offset(y: done == nil ? 0 : -14)

                if let done {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.appInvestmentPanel)
                            .frame(width: 64, height: 64)
                            .background(.white, in: Circle())
                        Text("Nilai diperbarui").font(.app(20, weight: .semibold)).padding(.top, 6)
                        Text("\(account.name) \(money(done.value)) · selisih \(InvestmentUI.signed(done.delta))\(money(abs(done.delta)))")
                            .font(.app(14)).opacity(0.9).monospacedDigit()
                        Text("Dicatat sebagai penyesuaian nilai").font(.app(13)).opacity(0.85)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(height: 232, alignment: .top)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(height: 282)
        .frame(maxWidth: .infinity)
        .background { UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32).fill(Color.appInvestmentPanel).ignoresSafeArea(edges: .top) }
        .animation(.settle(0.4), value: done == nil)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(12)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.app(15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hint and rows

    @ViewBuilder private var hint: some View {
        if isError {
            banner("exclamationmark.circle.fill", L("Nilai tidak bisa negatif. Isi 0 jika asetmu sudah habis."), ink: .appError, fill: InvestmentUI.errFill)
        } else if magnitude == 0 {
            banner("info.circle.fill", L("Nilai Rp0 diterima. Ini berarti rugi 100%% dari modal %@.", money(capital)), ink: InvestmentUI.warnInk, fill: InvestmentUI.warnFill)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 17)).padding(.top, 1)
                Text("Ketik nilai terbaru dari aplikasi investasimu. Selisih bukan pemasukan atau pengeluaran.")
                    .font(.app(14)).lineSpacing(2)
            }
            .foregroundStyle(Color.appTextSecondary)
            .padding(.vertical, 10)
        }
    }

    private func banner(_ icon: String, _ text: String, ink: Color, fill: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 17)).padding(.top, 1)
            Text(text).font(.app(14, weight: .medium)).lineSpacing(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(fill, in: RoundedRectangle(cornerRadius: 14))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            formRow(L("Dompet")) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.appInvestmentPanel).frame(width: 20, height: 14)
                    Text(account.name)
                }
            } trailing: { Image(systemName: "lock").font(.system(size: 14)).foregroundStyle(Color.appTextTertiary) }
            Button { noteFocused = false; showsDate = true } label: {
                formRow(L("Tanggal")) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 17)).foregroundStyle(Color.appTextSecondary)
                        Text(Calendar.current.isDateInToday(date) ? L("Hari ini") + " · " + InvestmentUI.shortDate(date) : InvestmentUI.shortDate(date))
                    }
                } trailing: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary) }
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                Text("Catatan").font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
                TextField("Opsional", text: $note)
                    .font(.app(16, weight: .medium))
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit { noteFocused = false }
            }
            .frame(height: 52)
            .padding(.horizontal, 24)
        }
    }

    private func formRow<V: View, T: View>(_ title: String, @ViewBuilder value: () -> V, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
            value().font(.app(16, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(InvestmentUI.line).frame(height: 1) }
    }

    // MARK: Keypad

    private var keypad: some View {
        GeometryReader { geo in
            let side = (geo.size.width - 6) / 4
            HStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Self.keys, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "del" { Image(systemName: "delete.left").font(.system(size: 22)) }
                                else if key == "neg" { Image(systemName: "plusminus").font(.system(size: 20)) }
                                else { Text(key).font(.app(24)) }
                            }
                            .foregroundStyle(Color.appText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(KeyStyle())
                    }
                }
                .frame(width: geo.size.width - side - 6)
                SaveKey(color: Color.appInvestmentPanel, isEnabled: !isError && !isSaving, isSaving: isSaving, title: "Terapkan", action: apply)
                    .frame(width: side)
                    .offset(x: shake == 0 ? 0 : 0)
            }
        }
        .frame(height: 52 * 4 + 6 * 3)
    }

    private func press(_ key: String) {
        guard done == nil, !isSaving else { return }
        switch key {
        case "neg": negative.toggle(); fresh = false
        case "del": digits = fresh ? "" : String(digits.dropLast()); fresh = false
        default:
            let base = fresh ? "" : digits
            digits = String((base + key).drop { $0 == "0" }.prefix(11))
            if digits.isEmpty { digits = "0" }
            fresh = false
        }
        if digits.isEmpty { digits = "0" }
        bump = true
        Task { try? await Task.sleep(for: .milliseconds(90)); bump = false }
    }

    private func apply() {
        guard done == nil, !isSaving else { return }
        if isError {
            Task {
                for x in [-10, 9, -6, 4, 0] as [CGFloat] { withAnimation(.default) { shake = x }; try? await Task.sleep(for: .milliseconds(60)) }
            }
            return
        }
        isSaving = true
        let value = newValue, change = delta
        Task {
            // Today keeps its time so the update sorts after a deposit made earlier the same day.
            let when = Calendar.current.isDateInToday(date) ? Date() : date
            let ok = await onApply(value, when, note)
            isSaving = false
            guard ok else { failed = true; return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.settle(0.4)) { done = (value, change) }
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
    }
}

// MARK: - Riwayat (design 7)

/// One wallet's history, a box per month: the month's closing value, the capital and what the updates added.
struct InvestmentHistoryView: View {
    let account: Account
    let transactions: [Transaction]
    let accounts: [Account]
    let isBalanceVisible: Bool

    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var seeded = false

    private var months: [InvestmentHistory.Month] {
        InvestmentHistory.months(account: account, transactions: transactions, accounts: accounts)
    }

    private func title(_ row: InvestmentHistory.Row) -> String {
        switch row.kind {
        case .value: L("Perbarui nilai")
        case .deposit: L("Setor ke aset")
        case .withdrawal: L("Tarik dari aset")
        case .opening: L("Nilai awal")
        }
    }

    private func sub(_ row: InvestmentHistory.Row) -> String {
        let date = InvestmentUI.shortDate(row.date)
        let text: String
        switch row.kind {
        case .value: text = date + " · " + InvestmentUI.money(row.from, visible: isBalanceVisible) + " → " + InvestmentUI.money(row.to, visible: isBalanceVisible)
        case .deposit: text = date + " · " + (row.otherName.map { L("dari %@", $0) } ?? "")
        case .withdrawal: text = date + " · " + (row.otherName.map { L("ke %@", $0) } ?? "")
        case .opening: text = date + " · " + L("saat dompet dibuat")
        }
        return row.note.map { text + " · " + $0 } ?? text
    }

    var body: some View {
        let all = months
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shown: [(InvestmentHistory.Month, [InvestmentHistory.Row])] = all.compactMap { month in
            let rows = q.isEmpty ? month.rows : month.rows.filter { (title($0) + " " + sub($0)).lowercased().contains(q) }
            return rows.isEmpty ? nil : (month, rows)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Color.appTextTertiary)
                    TextField("Cari setor, tarik, atau perbarui nilai", text: $query).font(.app(16))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appTextTertiary) }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 4)

                if shown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(Color.appBorder)
                        Text("Tidak ada hasil").font(.app(17, weight: .semibold))
                        Text("Coba kata lain seperti “setor”, “tarik”, atau nama dompet.")
                            .font(.app(14)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)
                    .padding(.horizontal, 16)
                } else {
                    ForEach(shown, id: \.0.id) { month, rows in monthBox(month, rows: rows, open: !q.isEmpty || !collapsed.contains(month.id)) }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 14)).padding(.top, 1)
                        Text("Setor, tarik, dan perbarui nilai tidak dihitung sebagai pemasukan atau pengeluaran.").font(.app(13)).lineSpacing(2)
                    }
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Color.appBackground)
        .navigationTitle("Riwayat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The newest month opens; older ones start closed.
            guard !seeded else { return }
            seeded = true
            collapsed = Set(months.dropFirst().map(\.id))
        }
    }

    private func monthBox(_ month: InvestmentHistory.Month, rows: [InvestmentHistory.Row], open: Bool) -> some View {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "LLLL yyyy"
        let title = f.string(from: month.start).capitalized(with: AppLanguage.locale)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.settle(0.35)) { if collapsed.contains(month.id) { collapsed.remove(month.id) } else { collapsed.insert(month.id) } }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.app(16, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(InvestmentUI.money(month.endValue, visible: isBalanceVisible)).font(.app(16, weight: .semibold)).monospacedDigit()
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appBorder)
                    }
                    HStack {
                        Text(L("Modal %@", InvestmentUI.money(month.capital, visible: isBalanceVisible)))
                        Spacer(minLength: 8)
                        if let change = month.change, change != 0 {
                            Text((change > 0 ? L("Untung") : L("Rugi")) + " " + InvestmentUI.signed(change) + InvestmentUI.money(abs(change), visible: isBalanceVisible))
                                .fontWeight(.semibold)
                                .foregroundStyle(change > 0 ? Color.appPrimary : Color.appError)
                        }
                    }
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(InvestmentUI.box)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { ForEach(rows) { row in rowView(row) } }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(InvestmentUI.line, lineWidth: 1))
        .padding(.top, 14)
    }

    private func rowView(_ row: InvestmentHistory.Row) -> some View {
        let icon: String = switch row.kind {
        case .value: "arrow.triangle.2.circlepath"
        case .deposit: "tray.and.arrow.down"
        case .withdrawal: "tray.and.arrow.up"
        case .opening: "flag"
        }
        let amountColor: Color = row.kind == .value ? (row.amount > 0 ? .appPrimary : row.amount < 0 ? .appError : .appTextSecondary) : .appTextSecondary
        let amount = (row.kind == .value ? InvestmentUI.signed(row.amount) : "") + InvestmentUI.money(abs(row.amount), visible: isBalanceVisible)
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.appInvestment)
                .frame(width: 40, height: 40)
                .background(Color.appInvestmentTint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(title(row)).font(.app(16)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(amount).font(.app(16)).monospacedDigit().foregroundStyle(amountColor)
                }
                Text(sub(row)).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .foregroundStyle(Color.appText)
    }
}
