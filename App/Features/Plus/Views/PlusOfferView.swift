import SwiftUI

/// Why the offer is shown: a limit reached or a Plus feature tapped (US1, TC 1, 23, 24).
enum PlusReason: Identifiable, Equatable {
    case moneyWallets, investmentWallets, categories(CategoryType), budgets, notifications, receiptPhoto, general

    var id: String {
        switch self {
        case .categories(let type): "categories-\(type.rawValue)"
        default: "\(self)"
        }
    }

    var title: String {
        switch self {
        case .moneyWallets: L("Batas dompet tercapai")
        case .investmentWallets: L("Batas Dompet Investasi tercapai")
        case .categories: L("Batas kategori tercapai")
        case .budgets: L("Batas budget tercapai")
        case .notifications: L("Catat dari notifikasi butuh Saku Plus")
        case .receiptPhoto: L("Foto struk butuh Saku Plus")
        case .general: L("Saku Plus")
        }
    }

    /// What the free plan allows and what stays safe.
    var message: String {
        switch self {
        case .moneyWallets: L("Paket gratis maksimal %lld dompet uang aktif. Arsipkan dompet yang tidak dipakai untuk memberi ruang, atau pakai Saku Plus tanpa batas.", FreeLimits.moneyWallets)
        case .investmentWallets: L("Paket gratis maksimal %lld Dompet Investasi aktif. Arsipkan yang tidak dipakai untuk memberi ruang, atau pakai Saku Plus tanpa batas.", FreeLimits.investmentWallets)
        case .categories(let type): L("Paket gratis maksimal %lld kategori %@ aktif. Sembunyikan kategori yang tidak kamu pakai untuk memberi ruang, atau pakai Saku Plus tanpa batas.", FreeLimits.categories(type), type == .income ? L("pemasukan") : L("pengeluaran"))
        case .budgets: L("Paket gratis maksimal %lld budget. Budget yang sudah ada tetap aman. Pakai Saku Plus tanpa batas.", FreeLimits.budgets)
        case .notifications: L("Saku Plus mencatat transaksi dari notifikasi bank dan e-wallet otomatis. Draf yang sudah ada tetap bisa diperiksa dan disimpan.")
        case .receiptPhoto: L("Saku Plus membaca foto struk dan screenshot jadi draf transaksi.")
        case .general: L("Tanpa batas dompet, kategori, dan budget, plus catat dari notifikasi dan foto struk.")
        }
    }

    /// The secondary action, shown only where the user can make room instead.
    var makeRoomTitle: String? {
        switch self {
        case .moneyWallets, .investmentWallets: L("Atur dompet dulu")
        case .categories: L("Atur kategori dulu")
        case .budgets: L("Atur budget dulu")
        default: nil
        }
    }
}

/// Placeholder offer until the paywall design and the App Store products exist (Epic 11, US2/US3):
/// it shows what Plus gives and that buying is not open yet. No price is shown because none is set.
struct PlusOfferView: View {
    let reason: PlusReason
    @Environment(\.dismiss) private var dismiss

    private var benefits: [(String, String)] { [
        ("infinity", L("Dompet, kategori, dan budget tanpa batas")),
        ("bell.badge", L("Catat dari notifikasi bank dan e-wallet")),
        ("doc.text.viewfinder", L("Foto struk dan screenshot jadi draf")),
        ("sparkles", L("Lebih banyak bantuan AI")),
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 22)).foregroundStyle(Color.appText)
                .frame(width: 52, height: 52).background(Color.stChip, in: Circle())
                .padding(.top, 28)
            Text(reason.title)
                .font(.app(22, weight: .bold)).foregroundStyle(Color.appText).padding(.top, 16)
            Text(reason.message)
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(benefits, id: \.0) { benefit in
                    HStack(spacing: 12) {
                        Image(systemName: benefit.0).font(.system(size: 17)).foregroundStyle(Color.stGreen).frame(width: 24)
                        Text(benefit.1).font(.app(15)).foregroundStyle(Color.appText)
                    }
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 24)

            Text("Pembelian Saku Plus segera hadir.")
                .font(.app(13)).foregroundStyle(Color.appTextTertiary)
                .frame(maxWidth: .infinity).padding(.bottom, 10)
            PrimaryButton(title: L("Coba gratis 7 hari"), isEnabled: false) {}
            Button { dismiss() } label: {
                Text(reason.makeRoomTitle ?? L("Nanti saja"))
                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Presents the Plus offer for `reason` (nil = closed).
    func plusOffer(_ reason: Binding<PlusReason?>) -> some View {
        sheet(item: reason) { PlusOfferView(reason: $0) }
    }
}
