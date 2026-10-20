import SwiftUI

/// "Bagikan laporan" from a period's detail in Riwayat Budget (Fitur 8 US5): the privacy choice, then the PDF of that
/// period. A free account sees the same preview as in Ekspor data instead of the file.
struct ShareReportSheet: View {
    let interval: DateInterval
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ExportViewModel()
    @ObservedObject private var plus = PlusStore.shared
    /// Off unless asked, like in Ekspor data.
    @State private var hidesBalances = false
    @State private var sharing: ExportFile?
    @State private var showsPreview = false
    @State private var failed = false

    private var cycle: PaydayCycle { PaydayCycle.current }
    private var periodLabel: String { ReportModel.title(for: interval) }
    private var userId: String? { authViewModel.currentUser?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 24)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bagikan laporan").font(.app(22, weight: .bold)).tracking(-0.3)
                    Text(L("Laporan PDF periode %@", periodLabel)).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                }

                Toggle(isOn: $hidesBalances) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sembunyikan saldo dan nama dompet").font(.app(16, weight: .medium))
                        Text("Semua nominal rupiah jadi titik-titik. Persentase dan status tetap terlihat.")
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                }
                .tint(Color.appPrimary)
                .padding(16)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 18))

                if viewModel.loadFailed {
                    Text("Datamu belum bisa dimuat. Periksa koneksi lalu coba lagi.")
                        .font(.app(14)).foregroundStyle(Color.appError)
                }
                PrimaryButton(title: viewModel.loadFailed ? L("Coba lagi") : L("Buat laporan PDF"),
                              isLoading: !viewModel.isReady && !viewModel.loadFailed, isEnabled: true) { create() }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
        .task { await viewModel.load(userId: userId) }
        .sheet(item: $sharing) { ExportShareSheet(urls: $0.urls) }
        .sheet(isPresented: $showsPreview) {
            PdfPreviewView(summary: PdfReport.summary(transactions: viewModel.transactions, categories: viewModel.categories,
                                                      intervals: [interval]), periodLabel: periodLabel)
        }
        .alert(L("Laporan belum bisa dibuat"), isPresented: $failed) { Button(L("Tutup"), role: .cancel) {} }
    }

    private func create() {
        guard viewModel.isReady else { Task { await viewModel.load(userId: userId) }; return }
        guard plus.isPlus else { showsPreview = true; return }
        let model = viewModel.reportModel(interval: interval, cycle: cycle, userName: authViewModel.currentUser?.displayName ?? "",
                                          isPrivate: hidesBalances)
        if let url = PdfReport.write(model) { sharing = ExportFile(urls: [url]) } else { failed = true }
    }
}
