import Foundation

/// The one banner Beranda may show about Saku Plus (design "Plus B Status" 5a). Priority: grace period, then the
/// last two days of a trial. AI-help and referral banners come with their servers.
struct PlusBanner: Equatable {
    enum Kind: Equatable { case grace, trialEnding(days: Int) }

    let kind: Kind
    /// Closing a banner hides it for the same situation only; a new day or state shows it again.
    let key: String
    let title: String
    let body: String
    let action: String

    static func pick(for entitlement: Entitlement, now: Date = Date(), dismissed: Set<String>) -> PlusBanner? {
        let until = entitlement.until.map(AccountDeletion.dayText) ?? ""
        let banner: PlusBanner?
        switch entitlement.phase(at: now) {
        case .grace:
            banner = PlusBanner(kind: .grace, key: "grace-\(until)", title: L("Pembayaran belum berhasil"),
                                body: L("Plus tetap terbuka sampai %@. Perbarui metode pembayaran di App Store.", until),
                                action: L("Perbarui pembayaran"))
        case .trial:
            switch entitlement.daysLeft(at: now) ?? 99 {
            case 2:
                banner = PlusBanner(kind: .trialEnding(days: 2), key: "trial-2-\(until)", title: L("Trial berakhir 2 hari lagi"),
                                    body: L("Setelah %@, %@ per tahun ditagih lewat App Store. Batalkan kapan saja sebelumnya.", until, PlusPricing.yearly),
                                    action: L("Lihat detail"))
            case 1:
                banner = PlusBanner(kind: .trialEnding(days: 1), key: "trial-1-\(until)", title: L("Trial berakhir besok"),
                                    body: L("Besok, %@, %@ ditagih untuk 1 tahun Saku Plus.", until, PlusPricing.yearly),
                                    action: L("Kelola di App Store"))
            default: banner = nil
            }
        default: banner = nil
        }
        guard let banner, !dismissed.contains(banner.key) else { return nil }
        return banner
    }
}
