import SwiftUI
import UIKit

/// Profil › Ekspor data: raw data as CSV, made on the device and shared (Fitur 8, US1 & US2).
struct ExportView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ExportViewModel()

    /// Which transactions go in the file (US1).
    enum Range: Hashable {
        case period(Int)
        case custom
        case all
    }

    @State private var range: Range = .period(0)
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var delimiter: CsvExport.Delimiter = .comma
    @State private var sharing: ShareItem?
    @State private var showsFailure = false
    @State private var showsLoadFailure = false

    private var cycle: PaydayCycle { PaydayCycle.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionCaption(L("Transaksi"))
                transactionsCard.stEnter(0)

                sectionCaption(L("Dompet"))
                plainCard(icon: "wallet.bifold", detail: L("Nama, jenis, saldo saat ini, dan saldo awal."),
                          title: L("Bagikan CSV dompet")) { shareWallets() }
                    .stEnter(1)

                sectionCaption(L("Budget"))
                plainCard(icon: "chart.pie", detail: L("Kategori, nominal, periode, dan terpakai."),
                          title: L("Bagikan CSV budget")) { shareBudgets() }
                    .stEnter(2)
            }
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Ekspor data"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollIndicators(.hidden)
        .hidesSmartButton()
        .task { await viewModel.load(userId: authViewModel.currentUser?.id) }
        .sheet(item: $sharing) { ShareSheet(url: $0.url) }
        .alert(L("Gagal membuat file CSV."), isPresented: $showsFailure) {
            Button("Tutup", role: .cancel) {}
        }
        .alert(L("Data belum lengkap dimuat. Periksa koneksi lalu coba lagi."), isPresented: $showsLoadFailure) {
            Button("Tutup", role: .cancel) {}
        }
    }

    // MARK: Transactions (US1)

    private var transactionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Rentang")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { offset in
                        chip(cycle.label(for: cycle.period(offset: -offset).start), isSelected: range == .period(offset)) {
                            range = .period(offset)
                        }
                    }
                    chip(L("Rentang tanggal"), isSelected: range == .custom) { range = .custom }
                    chip(L("Semua data"), isSelected: range == .all) { range = .all }
                }
                .padding(.vertical, 1)
            }

            if range == .custom {
                HStack(spacing: 12) {
                    DatePicker(L("Dari"), selection: $customStart, displayedComponents: .date)
                    DatePicker(L("Sampai"), selection: $customEnd, displayedComponents: .date)
                }
                .datePickerStyle(.compact)
                .font(.app(14))
            }

            Text(L("Pemisah kolom")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            HStack(spacing: 8) {
                chip(L("Koma"), isSelected: delimiter == .comma) { delimiter = .comma }
                chip(L("Titik koma"), isSelected: delimiter == .semicolon) { delimiter = .semicolon }
            }
            Text(L("Excel dengan pengaturan Indonesia: pilih titik koma supaya kolom terpisah."))
                .font(.app(12)).foregroundStyle(Color.appTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: L("Bagikan CSV transaksi")) { shareTransactions() }
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    private func plainCard(icon: String, detail: String, title: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Color.appTextSecondary)
                Text(detail).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: title, action: action)
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.appText)
                .padding(.horizontal, 12).frame(height: 34)
                .background(isSelected ? Color.stGreen : Color.appBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
    }

    // MARK: Sharing

    private func shareTransactions() {
        let interval: DateInterval?
        switch range {
        case .period(let offset):
            interval = cycle.period(offset: -offset)
        case .custom:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.startOfDay(for: max(customStart, customEnd))
            interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        case .all:
            interval = nil
        }
        let csv = viewModel.transactionsCsv(interval: interval, delimiter: delimiter)
        share(csv, name: fileName("transaksi", interval: interval))
    }

    private func shareWallets() {
        share(viewModel.walletsCsv(delimiter: delimiter), name: "saku-dompet-\(CsvExport.date(Date())).csv")
    }

    private func shareBudgets() {
        share(viewModel.budgetsCsv(delimiter: delimiter), name: "saku-budget-\(CsvExport.date(Date())).csv")
    }

    private func share(_ csv: String, name: String) {
        if viewModel.loadFailed {
            showsLoadFailure = true
            Task { await viewModel.load(userId: authViewModel.currentUser?.id) }
            return
        }
        if let url = viewModel.write(csv, name: name) {
            sharing = ShareItem(url: url)
        } else {
            showsFailure = true
        }
    }

    private func fileName(_ kind: String, interval: DateInterval?) -> String {
        guard let interval else { return "saku-\(kind)-semua-\(CsvExport.date(Date())).csv" }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "saku-\(kind)-\(CsvExport.date(interval.start))_\(CsvExport.date(end)).csv"
    }
}

/// The file waiting to be shared.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet for a file made on the device.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
