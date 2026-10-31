import SwiftUI

/// Shown once when a trial ends without a subscription (Epic 11 US5, US6): what stays active, what is paused (design "Trial Ended Sheet", C).
struct TrialEndedSheet: View {
    let wallets: Int
    let categories: Int
    let budgets: Int
    let onOffer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ticksShown = false

    /// Darker sheet in dark mode: the card must be lighter than the sheet to show.
    private static let card = Color(light: 0xF2F2F4, dark: 0x2C2C2E)
    private static let tickShades: [Double] = [1, 0.6, 0.3]
    private static let tickCount = 30

    private var total: Int { wallets + categories + budgets }
    private var counts: [(label: String, n: Int)] { [(L("Dompet"), wallets), (L("Kategori"), categories), (L("Budget"), budgets)] }

    /// 30 ticks shared by the three groups in proportion, the last group takes what is left.
    private var ticks: [Double] {
        guard total > 0 else { return [] }
        var share = [wallets, categories].map { Int((Double($0) / Double(total) * Double(Self.tickCount)).rounded()) }
        share.append(max(Self.tickCount - share[0] - share[1], 0))
        return share.enumerated().flatMap { Array(repeating: Self.tickShades[$0.offset], count: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.app(22, weight: .bold)).tracking(-0.3).fixedSize(horizontal: false, vertical: true)
                Text("Terima kasih sudah mencoba.")
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }

            summaryCard

            list(title: L("Tetap aman"), tint: .appPrimary, titleTint: .appPrimary, rows: [
                ("wallet.bifold", L("Dompet, kategori, dan budget kamu tetap ada dan berfungsi.")),
                ("scalemass", L("Saldo tetap dihitung di Total saldo.")),
                ("doc.richtext", L("PDF yang sudah kamu unduh tetap milikmu.")),
            ])
            list(title: L("Dijeda"), tint: .appTextSecondary, titleTint: .appTextSecondary, rows: [
                ("plus.circle", L("Tambah dompet, kategori, atau budget di atas batas gratis.")),
                ("bell", L("Catat dari notifikasi, foto struk, dan email terusan. Draf yang sudah ada tetap bisa disimpan.")),
                ("sparkle", L("Laporan PDF baru. Bantuan AI kembali 10 kali per bulan.")),
            ])
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filterSheet {
            SmartSheetFooter(primary: L("Lihat Saku Plus"), secondary: L("Nanti saja"), onPrimary: { dismiss(); onOffer() }) { dismiss() }
        }
        .onDisappear { PlusStore.shared.markTrialEndedSeen() }
        .task { ticksShown = true }
    }

    /// "Trial Saku Plus sudah berakhir" with the product name in green.
    private var title: AttributedString {
        let name = "Saku Plus"
        var text = AttributedString(L("Trial %@ sudah berakhir", name))
        if let range = text.range(of: name) { text[range].foregroundColor = Color.appPrimary }
        return text
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(total)").font(.app(40, weight: .light)).tracking(-1.5).monospacedDigit()
                Text(L("item tetap aktif")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            HStack(spacing: 2) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { index, shade in
                    RoundedRectangle(cornerRadius: 1).fill(Color.appPrimary.opacity(shade))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(y: ticksShown ? 1 : 0.15, anchor: .bottom)
                        .opacity(ticksShown ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.15 + Double(index) * 0.014), value: ticksShown)
                }
            }
            .frame(height: 28).padding(.top, 14).padding(.bottom, 12)
            VStack(spacing: 6) {
                ForEach(Array(counts.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.appPrimary.opacity(Self.tickShades[index])).frame(width: 10, height: 10)
                        Text(item.label).font(.app(15))
                        Spacer()
                        Text("\(item.n)").font(.app(15, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func list(title: String, tint: Color, titleTint: Color, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.app(13, weight: .semibold)).foregroundStyle(titleTint).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: row.0).font(.system(size: 18)).foregroundStyle(tint).frame(width: 24).padding(.top, 1)
                    Text(row.1).font(.app(15)).foregroundStyle(tint == .appPrimary ? Color.appText : Color.appBody)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.appBorder.opacity(0.5)).frame(height: 0.5) }
            }
        }
    }
}
