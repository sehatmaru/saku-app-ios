import SwiftUI

/// Shown once when a trial ends without a subscription (Epic 11 US5, US6): what was used and what stays safe.
struct TrialEndedSheet: View {
    let wallets: Int
    let categories: Int
    let budgets: Int
    let onOffer: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trial Saku Plus sudah berakhir").font(.app(24, weight: .semibold)).foregroundStyle(Color.appText)
            Text("Terima kasih sudah mencoba. Ini yang terjadi sekarang.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)

            section(title: L("Tetap aman"), systemImage: "checkmark.shield", lines: [
                L("%lld dompet, %lld kategori, dan %lld budget tetap ada dan tetap dipakai.", wallets, categories, budgets),
                L("Saldomu tetap masuk Total saldo."),
                L("PDF yang sudah kamu unduh tetap milikmu."),
            ]).padding(.top, 20)
            section(title: L("Berhenti dulu"), systemImage: "pause.circle", lines: [
                L("Menambah dompet, kategori, atau budget di atas batas gratis."),
                L("Catat dari notifikasi, foto struk, dan penerusan email. Draf yang sudah ada tetap bisa disimpan."),
                L("Laporan PDF baru. Bantuan AI kembali 10 per bulan."),
            ]).padding(.top, 16)

            Spacer(minLength: 16)
            PrimaryButton(title: L("Lihat Saku Plus")) { dismiss(); onOffer() }
            Button { dismiss() } label: {
                Text("Nanti saja").font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.plain).padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
        .background(Color.appBackground)
        .presentationDetents([.large])
        .onDisappear { PlusStore.shared.markTrialEndedSeen() }
    }

    private func section(title: String, systemImage: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
