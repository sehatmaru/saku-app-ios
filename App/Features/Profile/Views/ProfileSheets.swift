import SwiftUI
import UIKit

// The Profil settings sheets, design "Sheet Pengaturan":
// Tema, Bahasa and Total saldo are choice cards with a live preview, and Ekspor data
// offers an XLS workbook and a PDF report. Every sheet keeps the app's bottom-sheet chrome:
// X button on the left, centered title, grabber, radius 28.

// MARK: - Chrome

/// The shared header: X on the left, title in the middle.
private struct SheetHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title).font(.app(17, weight: .semibold))
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appFill, in: Circle())
                }
                .accessibilityLabel(L("Tutup"))
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

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
            SheetHeader(title: L("Tema"))

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
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
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
            SheetHeader(title: L("Bahasa"))

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
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
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
            SheetHeader(title: L("Total saldo"))

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
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }
}

// MARK: - Ekspor data

/// Periode chips over the XLS and PDF cards (design "Sheet Pengaturan", section Data).
struct ExportSheet: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ExportViewModel()
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    /// Which files the XLS workbook holds.
    enum XlsPart: String, CaseIterable, Hashable {
        case transactions, wallets, budgets

        var label: String {
            switch self {
            case .transactions: L("Transaksi")
            case .wallets: L("Dompet")
            case .budgets: L("Budget")
            }
        }
    }

    /// Everything, or the periods picked by hand (indices into `periods`).
    @State private var selectsAll = false
    @State private var selectedPeriods: Set<Int> = [0]
    @State private var parts: Set<XlsPart> = [.transactions, .wallets]
    @State private var sharing: ExportFile?
    @State private var isBuilding = false
    @State private var showsFailure = false
    @State private var showsLoadFailure = false

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

    private var selectedIntervals: [DateInterval]? {
        selectsAll ? nil : selectedPeriods.sorted().compactMap { periods.indices.contains($0) ? periods[$0].interval : nil }
    }

    private var countLabel: String {
        if selectsAll { return L("Semua data") }
        if selectedPeriods.isEmpty { return L("Pilih periode") }
        return L("%lld periode dipilih", selectedPeriods.count)
    }

    private var periodLabel: String {
        if selectsAll { return L("Semua data") }
        let labels = selectedPeriods.sorted().compactMap { periods.indices.contains($0) ? periods[$0].label : nil }
        if labels.count == 1 { return labels[0] }
        return L("%lld periode", labels.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: L("Ekspor data"))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodSection
                    xlsCard
                    pdfCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.height(660)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
        .task { await viewModel.load(userId: authViewModel.currentUser?.id) }
        .sheet(item: $sharing) { ExportShareSheet(url: $0.url) }
        .alert(L("Gagal membuat file. Coba lagi."), isPresented: $showsFailure) {
            Button(L("Tutup"), role: .cancel) {}
        }
        .alert(L("Data belum lengkap dimuat. Periksa koneksi lalu coba lagi."), isPresented: $showsLoadFailure) {
            Button(L("Tutup"), role: .cancel) {}
        }
    }

    // MARK: Periode

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Periode")).font(.app(13, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text(countLabel).font(.app(13, weight: .medium)).foregroundStyle(Color.appPrimary)
                    .contentTransition(.opacity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    periodChip(L("Semua data"), isSelected: selectsAll) {
                        selectsAll.toggle()
                        if selectsAll { selectedPeriods = [] }
                    }
                    ForEach(periods.indices, id: \.self) { index in
                        let label = periods[index].label
                        periodChip(label, isSelected: selectsAll || selectedPeriods.contains(index)) {
                            if selectsAll {
                                selectsAll = false
                                selectedPeriods = [index]
                            } else if selectedPeriods.contains(index) {
                                selectedPeriods.remove(index)
                            } else {
                                selectedPeriods.insert(index)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            Text(L("Data tersedia sejak %@. Geser untuk periode lainnya.",
                   monthYear(Date(timeIntervalSince1970: memberSince))))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
    }

    private func periodChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                }
                Text(title).font(.app(14, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.appPrimary : Color.appText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isSelected ? Color.appPrimary.opacity(0.10) : Color.appBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.appPrimary : Color.appBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: XLS

    private var xlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Ekspor ke XLS")).font(.app(17, weight: .semibold))
                    Text(L("Data mentah untuk diolah sendiri")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(XlsPart.allCases, id: \.self) { part in
                    let on = parts.contains(part)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.18)) {
                            if on { parts.remove(part) } else { parts.insert(part) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                            Text(part.label).font(.app(14, weight: .medium))
                        }
                        .foregroundStyle(on ? .white : Color.appText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(on ? Color.appPrimary : Color.appBackground, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            exportButton(title: L("Ekspor XLS"), icon: "arrow.down", style: .primary, enabled: !parts.isEmpty && !isBuilding) {
                exportXls()
            }
        }
        .padding(16)
        .background(Color.appPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: PDF

    private var pdfCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Laporan PDF")).font(.app(17, weight: .semibold)).foregroundStyle(.white)
                    Text(L("Ringkasan dan analisis, siap dibagikan"))
                        .font(.app(13)).foregroundStyle(.white.opacity(0.7))
                }
            }

            exportButton(title: L("Buat laporan PDF"), icon: "chart.pie", style: .onDark, enabled: !isBuilding) {
                exportPdf()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(light: 0x111214, dark: 0x111214), in: RoundedRectangle(cornerRadius: 24))
    }

    private enum ExportButtonStyle { case primary, onDark }

    private func exportButton(title: String, icon: String, style: ExportButtonStyle, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if isBuilding {
                    ProgressView().tint(style == .onDark ? Color(light: 0x111214, dark: 0x111214) : .white)
                } else {
                    Image(systemName: icon).font(.system(size: 16, weight: .bold))
                }
                Text(title).font(.app(16, weight: .medium))
            }
            .foregroundStyle(style == .onDark ? Color(light: 0x111214, dark: 0x111214) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(style == .onDark ? Color(light: 0xFFFFFF, dark: 0xFFFFFF) : Color.appPrimary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: Building

    private func exportXls() {
        guard !viewModel.loadFailed else { retryLoad(); return }
        isBuilding = true
        defer { isBuilding = false }
        var sheets: [XlsxExport.Sheet] = []
        if parts.contains(.transactions) {
            sheets.append(XlsxExport.transactions(viewModel.transactions, accounts: viewModel.accounts,
                                                  categories: viewModel.categories, intervals: selectedIntervals))
        }
        if parts.contains(.wallets) {
            sheets.append(XlsxExport.wallets(viewModel.accounts))
        }
        if parts.contains(.budgets) {
            sheets.append(XlsxExport.budgets(viewModel.budgets, categories: viewModel.categories))
        }
        let name = parts.count == 1 ? "saku-\(parts.first!.rawValue).xlsx" : "saku-export.xlsx"
        if let url = XlsxExport.write(sheets, name: name) {
            sharing = ExportFile(url: url)
        } else {
            showsFailure = true
        }
    }

    private func exportPdf() {
        guard !viewModel.loadFailed else { retryLoad(); return }
        isBuilding = true
        defer { isBuilding = false }
        if let url = PdfReport.write(transactions: viewModel.transactions, accounts: viewModel.accounts,
                                     categories: viewModel.categories, budgets: viewModel.budgets,
                                     intervals: selectedIntervals, periodLabel: periodLabel,
                                     name: "saku-laporan-\(CsvExport.date(Date())).pdf") {
            sharing = ExportFile(url: url)
        } else {
            showsFailure = true
        }
    }

    private func retryLoad() {
        showsLoadFailure = true
        Task { await viewModel.load(userId: authViewModel.currentUser?.id) }
    }

    private func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

/// The file waiting to be shared.
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet for a file made on the device.
private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
