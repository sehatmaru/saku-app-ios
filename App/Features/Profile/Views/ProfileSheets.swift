import SwiftUI
import UIKit

// The Profil settings sheets, design "Sheet Pengaturan":
// Tema, Bahasa and Total saldo are choice cards with a live preview, and Ekspor data
// offers CSV files and a PDF report. The sheets have no title or close button: the grabber
// and a swipe down close them, and the content starts right below it (radius 28).

// MARK: - Chrome

/// The green check that pops in on a selected card (design: pop .35s).
private struct PickedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.appPrimary, in: Circle())
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }
}

// MARK: - Tema

/// Three live previews; tapping one switches the app at once (no done button).
struct ThemeSheet: View {
    let selection: String
    let onPick: (String) -> Void

    private struct Option {
        let key: String
        let title: String
        let sub: String
    }

    private var options: [Option] {
        [Option(key: "Terang", title: L("Terang"), sub: L("Selalu terang")),
         Option(key: "Gelap", title: L("Gelap"), sub: L("Selalu gelap")),
         Option(key: "Sistem", title: L("Sistem"), sub: L("Ikuti pengaturan iPhone"))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 24)

            HStack(alignment: .top, spacing: 12) {
                ForEach(options, id: \.key) { option in
                    let on = option.key == selection
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { onPick(option.key) }
                    } label: {
                        VStack(spacing: 10) {
                            preview(option.key)
                                .frame(height: 124)
                                .background(on ? Color.appPrimary.opacity(0.10) : Color.appFill)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(on ? Color.appPrimary : .clear, lineWidth: 2)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(alignment: .topTrailing) {
                                    if on { PickedBadge().padding(8) }
                                }
                            Text(option.title)
                                .font(.app(15, weight: on ? .semibold : .regular))
                                .foregroundStyle(Color.appText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("\(option.title): \(option.sub)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Text(L("Sistem mengikuti pengaturan tampilan iPhone-mu."))
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .filterSheet()

        .background(Color.appBackground)
    }

    /// A mini screen: header line, big line, second line and a green button (design mock).
    @ViewBuilder
    private func preview(_ key: String) -> some View {
        switch key {
        case "Gelap":
            mock(dark: true)
        case "Sistem":
            ZStack {
                mock(dark: false)
                // the bottom-right half shows the dark version (design "system" split)
                mock(dark: true)
                    .clipShape(SystemSplit())
            }
        default:
            mock(dark: false)
        }
    }

    private func mock(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(dark ? Color(light: 0x3A3A3C, dark: 0x3A3A3C) : Color(light: 0xE5E5EA, dark: 0x3A3A3C))
                .frame(width: 40, height: 5)
            RoundedRectangle(cornerRadius: 4).fill(dark ? .white : Color(light: 0x111111, dark: 0xF5F5F7))
                .frame(width: 78, height: 14)
            RoundedRectangle(cornerRadius: 3).fill(dark ? Color(light: 0x3A3A3C, dark: 0x3A3A3C) : Color(light: 0xE5E5EA, dark: 0x3A3A3C))
                .frame(width: 54, height: 5)
            Spacer(minLength: 0)
            Capsule().fill(dark ? Color(light: 0x2FB57C, dark: 0x2FB57C) : Color(light: 0x16875A, dark: 0x16875A))
                .frame(height: 16)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dark ? Color(light: 0x000000, dark: 0x000000) : Color(light: 0xFFFFFF, dark: 0xFFFFFF))
    }

    /// The triangle that reveals the dark mockup at the bottom-right.
    private struct SystemSplit: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Bahasa

/// Two big cards with a sample line; tapping switches the language at once.
struct LanguageSheet: View {
    let selection: String
    let onPick: (String) -> Void

    private struct Option {
        let key: String
        let tile: String
        let title: String
        let sub: String
    }

    private var options: [Option] {
        // The samples stay in their own language on purpose: they preview the pick.
        [Option(key: "id", tile: "ID", title: L("Bahasa Indonesia"), sub: "Halo, selamat pagi"),
         Option(key: "en", tile: "EN", title: "English", sub: "Good morning")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 24)

            HStack(alignment: .top, spacing: 12) {
                ForEach(options, id: \.key) { option in
                    let on = option.key == selection
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { onPick(option.key) }
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(option.tile)
                                .font(.app(44, weight: .ultraLight))
                                .tracking(-1)
                                .foregroundStyle(on ? Color.appPrimary : Color.appText)
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.app(16, weight: on ? .semibold : .regular))
                                    .foregroundStyle(Color.appText)
                                Text(option.sub).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
                        .background(on ? Color.appPrimary.opacity(0.10) : Color.appFill, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(on ? Color.appPrimary : .clear, lineWidth: 2)
                        }
                        .overlay(alignment: .topTrailing) {
                            if on { PickedBadge().padding(12) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Text(L("Seluruh teks di Saku memakai bahasa yang dipilih."))
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .filterSheet()

        .background(Color.appBackground)
    }
}

// MARK: - Total saldo

/// The Beranda number previews the choice, live; tapping a card saves it.
struct BalanceSheet: View {
    let selection: String
    let cash: Double
    let assets: Double
    let onPick: (HomeBalanceMode) -> Void

    @State private var on: Bool

    init(selection: String, cash: Double, assets: Double, onPick: @escaping (HomeBalanceMode) -> Void) {
        self.selection = selection
        self.cash = cash
        self.assets = assets
        self.onPick = onPick
        _on = State(initialValue: selection == HomeBalanceMode.all.rawValue)
    }

    private struct Option {
        let mode: HomeBalanceMode
        let icon: String
        let title: String
        let sub: String
    }

    private var options: [Option] {
        [Option(mode: .cash, icon: "wallet.bifold", title: L("Kas saja"), sub: L("Tunai dan rekening bank")),
         Option(mode: .all, icon: "square.stack.3d.up", title: L("Semua dompet"), sub: L("Termasuk e-wallet dan kartu"))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 24)

            // Preview: exactly what Beranda will show.
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Total saldo")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                HStack(alignment: .top, spacing: 4) {
                    Text(verbatim: "Rp").font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
                    Text((on ? cash + assets : cash).formattedAsDigits())
                        .font(.app(42, weight: .ultraLight))
                        .tracking(-1.2)
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(on ? L("Dihitung dari semua dompet · tampil di Beranda") : L("Dihitung dari kas saja · tampil di Beranda"))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .contentTransition(.opacity)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .animation(.easeOut(duration: 0.25), value: on)

            HStack(alignment: .top, spacing: 12) {
                ForEach(options, id: \.mode) { option in
                    let isOn = (option.mode == .all) == on
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { on = option.mode == .all }
                        onPick(option.mode)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(isOn ? Color.appPrimary : Color.appTextSecondary)
                                .frame(width: 40, height: 40)
                                .background(Color.appBackground, in: Circle())
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.app(16, weight: isOn ? .semibold : .regular))
                                    .foregroundStyle(Color.appText)
                                Text(option.sub).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .background(isOn ? Color.appPrimary.opacity(0.10) : Color.appFill, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(isOn ? Color.appPrimary : .clear, lineWidth: 2)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isOn { PickedBadge().padding(12) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .filterSheet()

        .background(Color.appBackground)
    }
}

// MARK: - Ekspor data

/// Ekspor data (Enhancement 2, design "Ekspor Data" option B): one sheet, a CSV | PDF segment, defaults already chosen,
/// and a period list that opens in place so the two formats never share a choice.
struct ExportSheet: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ExportViewModel()
    @ObservedObject private var plus = PlusStore.shared
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    /// The sheet is dark grey in dark mode, so the usual fill would vanish into it: a lighter grey there.
    private static let fill = Color(light: 0xF2F2F4, dark: 0x2C2C2E)

    enum Format: Identifiable { case csv, pdf; var id: Self { self } }

    @State private var format: Format = .csv
    /// The period list that is open in place of the sheet's body, if any.
    @State private var picking: Format?
    /// CSV: everything, the periods picked by hand (indices into `periods`), or a date range. Only the transactions use it.
    @State private var selectsAll = false
    @State private var selectedPeriods: Set<Int> = [0]
    @State private var usesCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    /// PDF: the one payday period of the report (index into `periods`), and "Sembunyikan saldo dan nama dompet" (off unless asked).
    @State private var pdfPeriodIndex = 0
    @State private var hidesBalances = false
    @State private var sharing: ExportFile?
    @State private var isBuilding = false
    @State private var showsFailure = false
    /// Free accounts get a preview of the PDF instead of the file (Fitur 8, US4).
    @State private var showsPdfPreview = false

    private var cycle: PaydayCycle { PaydayCycle.current }

    /// The current payday period back to the month the account started, recent first.
    private var periods: [(interval: DateInterval, label: String)] {
        let since = Date(timeIntervalSince1970: memberSince)
        var list: [(DateInterval, String)] = []
        for offset in 0..<12 {
            let interval = cycle.period(offset: -offset)
            list.append((interval, cycle.label(for: interval.start)))
            if interval.start <= since { break }
        }
        return list
    }

    /// The range of the transactions CSV; nil = all data.
    private var selectedIntervals: [DateInterval]? {
        if usesCustomRange {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.startOfDay(for: max(customStart, customEnd))
            return [DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end)]
        }
        return selectsAll ? nil : selectedPeriods.sorted().compactMap { periods.indices.contains($0) ? periods[$0].interval : nil }
    }

    private var rangeText: String {
        if selectsAll { return L("Semua data") }
        if usesCustomRange { return L("Tanggal sendiri") }
        let labels = selectedPeriods.sorted().compactMap { periods.indices.contains($0) ? periods[$0].label : nil }
        if labels.count == 1 { return labels[0] }
        return labels.isEmpty ? L("Pilih periode") : L("%lld periode", labels.count)
    }

    private var pickCount: String {
        if selectsAll { return L("Semua data") }
        if usesCustomRange { return L("Tanggal sendiri") }
        return selectedPeriods.isEmpty ? L("Pilih periode") : L("%lld periode dipilih", selectedPeriods.count)
    }

    /// The transactions file would hold no row (Enhancement 2 US2): the sheet says so before sharing.
    private var rangeIsEmpty: Bool {
        guard viewModel.isReady else { return false }
        return !viewModel.transactions.contains { txn in
            selectedIntervals.map { $0.contains { txn.date >= $0.start && txn.date < $0.end } } ?? true
        }
    }

    private var reportPeriod: DateInterval { periods.indices.contains(pdfPeriodIndex) ? periods[pdfPeriodIndex].interval : cycle.period(offset: 0) }
    private var periodLabel: String { periods.indices.contains(pdfPeriodIndex) ? periods[pdfPeriodIndex].label : cycle.label(for: Date()) }
    private var canExport: Bool { viewModel.isReady && !isBuilding && (format == .pdf || !(selectedIntervals?.isEmpty ?? false)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainBody
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .filterSheet { exportFooter }
        .task { await viewModel.load(userId: authViewModel.currentUser?.id) }
        .sheet(item: $sharing) { ExportShareSheet(urls: $0.urls) }
        .sheet(item: $picking) { list in
            pickerBody(list).filterSheet { pickerFooter(list) }
        }
        .sheet(isPresented: $showsPdfPreview) {
            PdfPreviewView(summary: PdfReport.summary(transactions: viewModel.transactions, categories: viewModel.categories,
                                                      intervals: [reportPeriod]), periodLabel: periodLabel,
                           result: viewModel.reportModel(interval: reportPeriod, cycle: cycle, userName: "", isPrivate: false, isPreview: true).analysis)
        }
        .alert(L("Ekspor gagal"), isPresented: $showsFailure) {
            Button(L("Batal"), role: .cancel) {}
            Button(L("Coba lagi")) { export() }
        } message: { Text(L("Datamu tidak berubah. Coba lagi.")) }
    }

    // MARK: Main

    private var mainBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Ekspor data")).font(.app(20, weight: .semibold))
                Spacer()
            }
            .frame(minHeight: 44)

            segment

            if viewModel.loadFailed { notLoaded }
            if format == .csv { csvBody } else { pdfBody }
        }
    }

    private var exportFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if format == .csv, rangeIsEmpty {
                Label {
                    Text(L("Tidak ada transaksi di rentang ini. File Transaksi hanya berisi judul kolom."))
                        .font(.app(13)).fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: "exclamationmark.circle.fill") }
                .foregroundStyle(Color.appError)
            }
            exportButton
        }
    }

    private var segment: some View {
        HStack(spacing: 4) {
            segmentItem("CSV", plusBadge: false, isOn: format == .csv) { format = .csv }
            segmentItem("PDF", plusBadge: true, isOn: format == .pdf) { format = .pdf }
        }
        .padding(4)
        .background(Self.fill, in: Capsule())
    }

    private func segmentItem(_ title: String, plusBadge: Bool, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.app(15, weight: .semibold))
                if plusBadge { plusPill }
            }
            .foregroundStyle(isOn ? Color.appText : Color.appTextSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isOn ? Color.appBackground : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var plusPill: some View {
        Text("Plus").font(.app(11, weight: .bold)).foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.appPrimary.opacity(0.10), in: Capsule())
    }

    private var notLoaded: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Data belum dimuat")).font(.app(15, weight: .semibold))
                Text(L("Tunggu data selesai dimuat, lalu ekspor.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Button(L("Muat ulang")) { Task { await viewModel.load(userId: authViewModel.currentUser?.id) } }
                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary).frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.fill, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: CSV

    private var csvBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Transaksi dari")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                changeRow(rangeText) { picking = .csv }
                Text(L("Dompet dan budget selalu disertakan lengkap.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }

        }
    }

    private func changeRow(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(text).font(.app(15)).foregroundStyle(Color.appText).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(L("Ubah"))
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(Self.fill, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: PDF

    private var pdfBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Periode laporan")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                changeRow(periodLabel) { picking = .pdf }
            }
            Toggle(isOn: $hidesBalances) {
                Text(L("Sembunyikan saldo dan nama dompet")).font(.app(15))
            }
            .tint(Color.appPrimary)
            .frame(minHeight: 44)

            if !plus.isPlus {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        plusPill
                        Text(L("Laporan PDF khusus Saku Plus")).font(.app(15, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.appBorder).frame(height: 8).frame(maxWidth: 140, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4).fill(Color.appBorder.opacity(0.5)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(Color.appBorder.opacity(0.5)).frame(height: 8).padding(.trailing, 50)
                    }
                    .padding(14)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
                    Text(L("Lihat pratinjau dulu, lalu putuskan.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                .padding(16)
                .background(Self.fill, in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    // MARK: Period list

    private func pickerBody(_ list: Format) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(list == .csv ? L("Transaksi dari") : L("Pilih periode")).font(.app(20, weight: .semibold))
                .frame(minHeight: 44).padding(.top, 20)

            Text(list == .csv ? L("Pilih semua data, tanggal sendiri, atau satu periode atau lebih. Daftar bisa digulir.")
                              : L("Pilih satu periode. Daftar bisa digulir."))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)

            ScrollView {
                VStack(spacing: 0) {
                    if list == .csv {
                        pickRow(L("Semua data"), detail: L("Seluruh riwayat transaksi"), isOn: selectsAll) {
                            selectsAll = true; usesCustomRange = false; selectedPeriods = []
                        }
                        pickRow(L("Tanggal sendiri"), detail: L("Pilih tanggal awal dan akhir"), isOn: usesCustomRange) {
                            usesCustomRange = true; selectsAll = false; selectedPeriods = []
                        }
                        if usesCustomRange {
                            HStack(spacing: 12) {
                                DatePicker(L("Dari"), selection: $customStart, displayedComponents: .date)
                                DatePicker(L("Sampai"), selection: $customEnd, displayedComponents: .date)
                            }
                            .datePickerStyle(.compact).font(.app(14)).padding(.vertical, 8)
                        }
                    }
                    ForEach(periods.indices, id: \.self) { index in
                        let count = viewModel.transactions.filter { $0.date >= periods[index].interval.start && $0.date < periods[index].interval.end }.count
                        pickRow(periods[index].label, detail: L("%lld transaksi", count),
                                isOn: list == .pdf ? pdfPeriodIndex == index : (!selectsAll && !usesCustomRange && selectedPeriods.contains(index))) {
                            if list == .pdf { pdfPeriodIndex = index; return }
                            if selectsAll || usesCustomRange { selectsAll = false; usesCustomRange = false; selectedPeriods = [index] }
                            else if selectedPeriods.contains(index) { selectedPeriods.remove(index) }
                            else { selectedPeriods.insert(index) }
                        }
                    }
                }
            }
            .frame(height: 380)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
    }

    private func pickerFooter(_ list: Format) -> some View {
        VStack(spacing: 12) {
            Text(list == .csv ? pickCount : periodLabel).font(.app(15))
            PrimaryButton(title: L("Selesai"), isEnabled: list == .pdf || !(selectedIntervals?.isEmpty ?? false)) {
                picking = nil
            }
        }
    }

    private func pickRow(_ title: String, detail: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.app(17)).foregroundStyle(Color.appText).monospacedDigit()
                    Text(detail).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.appPrimary).opacity(isOn ? 1 : 0)
            }
            .frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.appBorder).frame(height: 0.5) }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Building

    private var exportButton: some View {
        Button { export() } label: {
            HStack(spacing: 10) {
                if isBuilding { ProgressView().tint(.white) }
                Text(isBuilding ? L("Menyiapkan…")
                     : format == .csv ? L("Ekspor CSV")
                     : plus.isPlus ? L("Buat laporan PDF") : L("Lihat pratinjau PDF"))
                    .font(.app(17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.appPrimary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!canExport)
        .opacity(canExport || isBuilding ? (isBuilding ? 0.6 : 1) : 0.4)
    }

    private func export() {
        guard viewModel.isReady else { return }
        if format == .csv { exportCsv() } else { exportPdf() }
    }

    /// One CSV per part, packed in a single ZIP made on the device (Enhancement 2 K2, K6).
    private func exportCsv() {
        isBuilding = true
        defer { isBuilding = false }
        let stamp = CsvExport.date(Date())
        let files: [(name: String, csv: String)] = [
            ("saku-transaksi-\(stamp).csv", CsvExport.transactions(viewModel.transactions, accounts: viewModel.accounts,
                                                                    categories: viewModel.categories,
                                                                    intervals: selectedIntervals, delimiter: .pipe)),
            ("saku-dompet-\(stamp).csv", CsvExport.wallets(viewModel.accounts, delimiter: .pipe)),
            ("saku-budget-\(stamp).csv", CsvExport.budgets(viewModel.budgets, categories: viewModel.categories, delimiter: .pipe))
        ]
        if let url = viewModel.zip(files, name: "saku-ekspor-\(stamp).zip") { sharing = ExportFile(urls: [url]) } else { showsFailure = true }
    }

    private func exportPdf() {
        guard plus.isPlus else { showsPdfPreview = true; return }
        isBuilding = true
        defer { isBuilding = false }
        let model = viewModel.reportModel(interval: reportPeriod, cycle: cycle,
                                          userName: authViewModel.currentUser?.displayName ?? "", isPrivate: hidesBalances)
        if let url = PdfReport.write(model) { sharing = ExportFile(urls: [url]) } else { showsFailure = true }
    }
}

/// The file waiting to be shared.
struct ExportFile: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// The system share sheet for a file made on the device.
struct ExportShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
