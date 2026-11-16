import SwiftUI
import Charts

enum InvestmentUI {
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

/// Under an open investment card: gain, capital, last update and the chart. The actions sit above, in the wallet's row.
struct InvestmentDetailContent: View {
    let account: Account
    let transactions: [Transaction]
    let isBalanceVisible: Bool

    var body: some View {
        let summary = InvestmentSummary(account: account, transactions: transactions)
        let gainColor: Color = summary.gain > 0 ? .appPrimary : summary.gain < 0 ? .appError : .appTextSecondary
        VStack(alignment: .leading, spacing: 0) {
            Text("Untung/rugi").font(.app(13)).foregroundStyle(Color.appTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(gainAmount(summary))
                    .font(.app(28, weight: .semibold)).tracking(-0.6).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(gainColor)
                if isBalanceVisible, let percent = summary.percent {
                    Text(InvestmentSummary.percentText(percent, signed: true))
                        .font(.app(13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(gainColor)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(gainColor.opacity(0.12), in: Capsule())
                }
            }
            .padding(.top, 3)

            if let note = note(summary) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 14)).padding(.top, 1)
                    Text(note).font(.app(13)).lineSpacing(2)
                }
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 10)
            }

            InvestmentChartView(account: account, transactions: transactions, isBalanceVisible: isBalanceVisible)
                .padding(.top, 18)
        }
    }

    private func gainAmount(_ s: InvestmentSummary) -> String {
        guard isBalanceVisible else { return "••••" }
        return InvestmentUI.signed(s.gain) + abs(s.gain).formattedAsCurrency()
    }

    private func note(_ s: InvestmentSummary) -> String? {
        if s.capital <= 0 { return L("Modal Rp0, jadi persen untung/rugi tidak ditampilkan.") }
        if s.value <= 0 { return L("Nilai Rp0 berarti rugi 100% dari modal. Perbarui nilai jika ini keliru.") }
        return nil
    }
}

// MARK: - Grafik performa (Fitur 7 US1)

/// Value (solid) and capital (dashed) over time, a dot at every change. Plain numbers only: no judgement words.
struct InvestmentChartView: View {
    let seriesFor: (InvestmentSeries.Range) -> InvestmentSeries
    let isBalanceVisible: Bool
    var valueLabel = L("Nilai")
    var capitalLabel = L("Modal disetor")
    var emptyText = L("Grafik muncul setelah ada 2 titik data. Isi lewat Perbarui nilai, setor, atau tarik.")
    /// A dot at every change; off for a long daily history.
    var showsDots = true
    /// The range tabs and the footnote under the chart; a single wallet shows the last 6 months without them.
    var showsRanges = true
    @State private var range = InvestmentSeries.Range.months6

    /// One investment wallet: its value and capital.
    init(account: Account, transactions: [Transaction], isBalanceVisible: Bool) {
        seriesFor = { InvestmentSeries(account: account, transactions: transactions, range: $0) }
        self.isBalanceVisible = isBalanceVisible
        showsRanges = false
    }

    init(seriesFor: @escaping (InvestmentSeries.Range) -> InvestmentSeries, isBalanceVisible: Bool,
         valueLabel: String, capitalLabel: String, emptyText: String, showsDots: Bool) {
        self.seriesFor = seriesFor
        self.isBalanceVisible = isBalanceVisible
        self.valueLabel = valueLabel
        self.capitalLabel = capitalLabel
        self.emptyText = emptyText
        self.showsDots = showsDots
    }

    var body: some View {
        let series = seriesFor(range)
        VStack(alignment: .leading, spacing: 0) {
            if !isBalanceVisible {
                placeholder(icon: "eye.slash", title: L("Grafik disembunyikan"), text: nil)
            } else if series.hasLine {
                chart(series)
            } else {
                placeholder(icon: "chart.line.uptrend.xyaxis", title: L("Grafik belum tersedia"), text: emptyText)
            }
            if showsRanges {
                ranges.padding(.top, 14).opacity(series.hasLine || !isBalanceVisible ? 1 : 0.4)
                Text("Angka berdasarkan pembaruanmu, bukan harga pasar")
                    .font(.app(12)).foregroundStyle(Color.appTextSecondary).padding(.top, 10)
            }
        }
    }

    /// The gap between capital (dashed) and value (solid) is the gain or loss: red under capital, green over it.
    /// Value and capital that stay equal draw no gap.
    private func chart(_ series: InvestmentSeries) -> some View {
        let points = series.points
        let first = points.first, last = points.last
        let gap = (last?.value ?? 0) - (last?.capital ?? 0)
        let isEven = abs(gap) < max(1, abs(last?.capital ?? 0) * 0.0005)
        let valueBelow = gap <= 0
        // when the lines coincide, the label goes on the side the line is not coming from
        let arrivesFromAbove = points.count > 1 && points[points.count - 2].value > (last?.value ?? 0)
        // headroom above and below, so the end labels sit inside the plot and clear of the date labels
        let bounds = series.valueBounds
        let pad = max((bounds.upperBound - bounds.lowerBound) * 0.2, abs(bounds.upperBound) * 0.04)
        let domain = (bounds.lowerBound - pad)...(bounds.upperBound + pad)
        let span = bounds.upperBound - bounds.lowerBound
        return Chart {
            ForEach(Array(points.enumerated().dropFirst()), id: \.offset) { index, point in
                let before = points[index - 1]
                let tint: Color = point.value < point.capital ? .appError : .appPrimary
                ForEach(Array([before, point].enumerated()), id: \.offset) { _, end in
                    AreaMark(x: .value("t", end.date), yStart: .value("modal", end.capital), yEnd: .value("nilai", end.value),
                             series: .value("s", "gap\(index)"))
                        .foregroundStyle(tint.opacity(abs(point.value - point.capital) < 1 ? 0 : 0.14))
                }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("t", point.date), y: .value("modal", point.capital), series: .value("s", "modal"))
                    .foregroundStyle(Color.appTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                LineMark(x: .value("t", point.date), y: .value("nilai", point.value), series: .value("s", "nilai"))
                    .foregroundStyle(Color.appText)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(points.enumerated()).filter { showsDots ? $0.element.isChange : $0.offset == points.count - 1 }, id: \.offset) { index, point in
                PointMark(x: .value("t", point.date), y: .value("nilai", point.value))
                    .symbolSize(index == points.count - 1 ? 60 : 24)
                    .foregroundStyle(Color.appText)
            }
            if let first, let last {
                if !isEven {
                    PointMark(x: .value("t", last.date), y: .value("modal", last.capital))
                        .symbolSize(0)
                        .annotation(position: valueBelow ? .top : .bottom, alignment: .trailing, spacing: 4) {
                            Text(capitalLabel + " " + Self.axisText(last.capital))
                                .font(.app(11)).foregroundStyle(Color.appTextSecondary).fixedSize()
                        }
                    if abs(gap) > span * 0.35 {
                        PointMark(x: .value("t", Date(timeIntervalSince1970: (first.date.timeIntervalSince1970 + last.date.timeIntervalSince1970) / 2)),
                                  y: .value("nilai", (last.value + last.capital) / 2))
                            .symbolSize(0)
                            .annotation(position: .overlay) {
                                Text((gap < 0 ? L("Rugi %@", Self.axisText(abs(gap))) : L("Untung %@", Self.axisText(gap))))
                                    .font(.app(12, weight: .semibold)).foregroundStyle(gap < 0 ? Color.appError : Color.appPrimary)
                                    .fixedSize()
                            }
                    }
                }
                PointMark(x: .value("t", last.date), y: .value("nilai", last.value))
                    .symbolSize(0)
                    .annotation(position: isEven ? (arrivesFromAbove ? .bottom : .top) : valueBelow ? .bottom : .top, alignment: .trailing, spacing: 6) {
                        Text(isEven ? L("Nilai = modal") + " " + Self.axisText(last.value) : valueLabel + " " + Self.axisText(last.value))
                            .font(.app(11, weight: .semibold)).foregroundStyle(Color.appText).fixedSize()
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(range: .plotDimension(padding: 6))
        .chartYAxis(.hidden)
        .chartXAxis {
            if let first, let last {
                AxisMarks(values: [first.date, last.date]) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                        if let date = value.as(Date.self) {
                            Text(Calendar.current.isDateInToday(date) ? L("Hari ini") : TransactionDates.dayMonth.string(from: date))
                                .font(.app(11)).foregroundStyle(Color.appTextTertiary)
                        }
                    }
                }
            }
        }
        .frame(height: 190)
        .accessibilityLabel(L("Grafik nilai dan modal"))
    }

    private func placeholder(icon: String, title: String, text: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Color.appTextTertiary)
            Text(title).font(.app(15, weight: .semibold))
            if let text {
                Text(text).font(.app(13)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 150).padding(.horizontal, 28)
        .background(InvestmentUI.box, in: RoundedRectangle(cornerRadius: 16))
    }

    private var ranges: some View {
        HStack(spacing: 22) {
            ForEach(InvestmentSeries.Range.allCases, id: \.self) { item in
                Button { withAnimation(.settle(0.3)) { range = item } } label: {
                    Text(item.title).font(.app(15, weight: range == item ? .semibold : .regular))
                        .foregroundStyle(range == item ? Color.appText : Color.appTextSecondary)
                        .frame(minHeight: 36)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(range == item ? Color.appText : Color.clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// "52 jt", "1,2 M": short, for the value axis.
    static func axisText(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.locale
        f.maximumFractionDigits = 1
        let size = abs(value)
        let (scaled, unit): (Double, String) = size >= 1e9 ? (value / 1e9, Lx("M", en: "B"))
            : size >= 1e6 ? (value / 1e6, Lx("jt", en: "M"))
            : size >= 1e3 ? (value / 1e3, Lx("rb", en: "K")) : (value, "")
        return (f.string(from: NSNumber(value: scaled)) ?? "0") + (unit.isEmpty ? "" : " " + unit)
    }
}

// MARK: - Alokasi (Fitur 7 US2)

/// One thin segmented bar under "Total aset" and each wallet's share. Colours are the app's own, none of them
/// red, so a share never reads as a verdict.
struct InvestmentAllocationView: View {
    let allocation: InvestmentAllocation
    let isBalanceVisible: Bool
    /// Each wallet's own card colour, so a share matches its card below.
    var colors: [String: Color] = [:]

    private static let palette: [Color] = [.appInvestment, .appPrimary, .appText, .appTextTertiary, .appSecondary, .appWarning]
    private func color(_ index: Int) -> Color {
        colors[allocation.slices[index].id] ?? Self.palette[index % Self.palette.count]
    }

    /// The two biggest shares and the rest: "Bibit 70% · Stockbit 26% · lainnya 4%".
    private var summary: String {
        let slices = allocation.slices
        func pct(_ f: Double) -> String { isBalanceVisible ? InvestmentSummary.percentText(f) : "••%" }
        let shown = slices.count > 3 ? Array(slices.prefix(2)) : slices
        var parts = shown.map { "\($0.name) \(pct($0.fraction))" }
        if slices.count > 3 { parts.append(L("lainnya") + " " + pct(slices.dropFirst(2).reduce(0) { $0 + $1.fraction })) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if isBalanceVisible {
                        ForEach(Array(allocation.slices.enumerated()), id: \.element.id) { index, slice in
                            RoundedRectangle(cornerRadius: 2).fill(color(index))
                                .frame(width: max(2, (geo.size.width - CGFloat(allocation.slices.count - 1) * 2) * slice.fraction))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(Color.appDivider)
                    }
                }
            }
            .frame(height: 8)
            Text(summary)
                .font(.app(13)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pengingat (Fitur 7 US3)

/// Pick how often to be reminded to update the value (Mati, Mingguan, Dua mingguan, Bulanan), or the one-time
/// "Mau diingatkan?" offer after the first investment wallet. Turning one on asks for notification permission;
/// when it is denied the reminder is still saved and the sheet says where to allow it.
struct InvestmentReminderSheet: View {
    let account: Account
    let transactions: [Transaction]
    let offer: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var chosen = InvestmentReminder.off
    @State private var denied = false
    @State private var height: CGFloat = 380

    private let store = InvestmentReminderStore()
    private var choices: [InvestmentReminder] { InvestmentReminder.allCases.filter { $0 != .off } }

    var body: some View {
        Group {
            if denied { deniedView } else if offer { offerView } else { optionsView }
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geo in
            Color.clear.onAppear { height = geo.size.height }.onChange(of: geo.size.height) { _, new in height = new }
        })
        .filterSheet { if !denied && !offer { SmartSheetFooter(primary: L("Tutup"), secondary: nil, onPrimary: { dismiss() }) } }
        .background(Color.appBackground)
        .onAppear {
            chosen = offer ? .monthly : store.interval(for: account.id)
            if offer { store.wasOffered = true }
        }
    }

    private func apply(_ interval: InvestmentReminder) {
        store.set(interval, for: account.id)
        Task {
            if interval != .off {
                await NotificationManager.shared.requestPermissionIfNeeded()
                if await NotificationManager.shared.notificationsDenied() {
                    withAnimation(.settle(0.3)) { denied = true }
                }
            }
            await NotificationManager.shared.scheduleInvestmentReminder(account: account, transactions: transactions)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52).background(Color.appPrimary, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity).frame(height: 48)
                .overlay(Capsule().stroke(Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pengingat").font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Diingatkan memperbarui nilai %@.", account.name)).font(.app(14)).foregroundStyle(Color.appTextSecondary).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(InvestmentReminder.allCases) { item in
                    Button { chosen = item; apply(item) } label: {
                        HStack {
                            Text(item.title).font(.app(17)).foregroundStyle(Color.appText)
                            Spacer()
                            if chosen == item { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appPrimary) }
                        }
                        .frame(height: 52).contentShape(Rectangle())
                        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            Label("Diingatkan pukul 09.00", systemImage: "clock").font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
        }
    }

    private var offerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "bell").font(.system(size: 30)).foregroundStyle(Color.appPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.appTextSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Tutup"))
            }
            Text("Mau diingatkan?").font(.app(22, weight: .semibold)).padding(.top, 4)
            Text(L("Nilai %@ hanya berubah saat kamu memperbaruinya. Kami bisa mengingatkanmu pukul 09.00.", account.name))
                .font(.app(15)).foregroundStyle(Color.appBody).lineSpacing(2).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(choices) { item in
                    Button { chosen = item } label: {
                        Text(item.title).font(.app(14, weight: chosen == item ? .medium : .regular))
                            .foregroundStyle(chosen == item ? Color.appBackground : Color.appText)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(chosen == item ? Color.appText : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(chosen == item ? Color.clear : Color.appBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
            primary(L("Ingatkan aku")) { apply(chosen); if !denied { Task { try? await Task.sleep(for: .milliseconds(350)); if !denied { dismiss() } } } }
                .padding(.top, 20)
            secondary(L("Tidak perlu")) { dismiss() }.padding(.top, 6)
            Text("Tidak akan ditanyakan lagi. Bisa diatur di detail dompet.")
                .font(.app(12)).foregroundStyle(Color.appTextSecondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 10)
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "bell.slash").font(.system(size: 30)).foregroundStyle(Color.appTextSecondary)
            Text("Notifikasi belum diizinkan").font(.app(20, weight: .semibold)).padding(.top, 12)
            Text(L("Pengingat %@ sudah kami simpan, tapi baru berjalan setelah kamu mengizinkan notifikasi Saku di Pengaturan iPhone.", chosen.title))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            primary(L("Buka Pengaturan")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .padding(.top, 22)
            Button { dismiss() } label: {
                Text("Nanti saja").font(.app(16)).foregroundStyle(Color.appTextSecondary).frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.plain).padding(.top, 6)
        }
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
            PickerSheet(title: L("Tanggal"), actionTitle: nil, onDone: { showsDate = false }) {
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

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nilai sebelumnya").font(.app(12)).opacity(0.85)
                            Text(money(account.balance)).font(.app(17, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Selisih").font(.app(12)).opacity(0.85)
                            HStack(spacing: 5) {
                                Image(systemName: isError ? "xmark" : delta > 0 ? "chart.line.uptrend.xyaxis" : delta < 0 ? "chart.line.downtrend.xyaxis" : "equal")
                                    .font(.system(size: 13, weight: .bold))
                                Text(isError ? "—" : InvestmentUI.signed(delta) + money(abs(delta)))
                                    .font(.app(17, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
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

    // MARK: Hint and rows

    @ViewBuilder private var hint: some View {
        if isError {
            banner("exclamationmark.circle.fill", L("Nilai tidak bisa negatif. Isi 0 jika asetmu sudah habis."), ink: .appError, fill: InvestmentUI.errFill)
        } else if magnitude == 0 {
            banner("info.circle.fill", L("Nilai Rp0 diterima. Ini berarti rugi 100%% dari modal %@.", money(capital)), ink: InvestmentUI.warnInk, fill: InvestmentUI.warnFill)
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
