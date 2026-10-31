import SwiftUI

/// Profil › Paket Saku (design "Saku Gratis": 1a free, 2b trial, 3a active, 3b grace, 3c ended): the plan the account is on and where to manage it. The picker for every state lives in Profil › Menu uji.
struct PlusStatusView: View {
    @ObservedObject private var plus = PlusStore.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL
    @State private var paywall: PlusReason?
    @State private var failure: String?

    private var phase: PlusPhase { plus.entitlement.phase() }
    private var onPlus: Bool { [.trial, .active, .grace].contains(phase) }
    private var until: String { plus.entitlement.until.map(AccountDeletion.dayText) ?? "" }
    private var userId: String { authViewModel.currentUser?.id ?? "" }
    private let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")
    /// The dark card of the design (ink-950).
    private static let ink = Color(light: 0x111113, dark: 0x2A2A2E)

    private var showsAI: Bool { PlusStore.isInternalBuild }

    /// What the free plan allows: Dompet, Kategori, Budget (and Bantuan AI while it uses sample numbers).
    private var limits: [(String, String)] {
        var list = [(L("Dompet uang aktif"), "\(FreeLimits.moneyWallets)"), (L("Kategori pengeluaran"), "\(FreeLimits.expenseCategories)"), (L("Budget"), "\(FreeLimits.budgets)")]
        // AI help is counted on the server, which is not built yet: sample numbers, for test builds only
        if showsAI { list.append((L("Bantuan AI per bulan"), "\(AIQuota.sample.total)")) }
        return list
    }

    private var features: [String] {
        [L("Catat dari notifikasi"), L("Foto struk dan screenshot"), L("Penerusan email"), L("Laporan PDF")]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if onPlus || phase == .ended { statusHero.motion(.fup); tiles.padding(.top, 14) } else { freeHero.motion(.fup); table.padding(.top, 16) }
                if onPlus || phase == .ended { Divider().overlay(Color.appDivider).padding(.top, 20).padding(.bottom, 6) } else { Spacer().frame(height: 8) }
                manageRow
                if !onPlus {
                    Text("Data yang melebihi batas tetap aman dan tetap dipakai. Hanya penambahan baru yang tertahan.")
                        .font(.app(13)).foregroundStyle(Color.appTextTertiary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                }
                if showsAI && !onPlus {
                    Text("Bantuan AI memakai angka contoh sampai server siap.")
                        .font(.app(12)).foregroundStyle(Color.appTextTertiary).padding(.top, 6)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
            .id(phase)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(L("Paket Saku"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .plusOffer($paywall)
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Tutup", role: .cancel) {}
        }
    }

    // MARK: Free (design 1a): dark card, then the Gratis vs Plus table

    private var freeHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Kamu sedang memakai").font(.app(14)).foregroundStyle(.white.opacity(0.7))
                Text("Saku Gratis").font(.app(30, weight: .semibold)).tracking(-0.3).foregroundStyle(.white)
            }
            PrimaryButton(title: L("Join Saku Plus")) { paywall = .general }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.ink, in: RoundedRectangle(cornerRadius: 28))
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Yang kamu dapat").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gratis").frame(width: 64, alignment: .trailing)
                Text(verbatim: "Plus").fontWeight(.semibold).foregroundStyle(Color.appPrimary).frame(width: 72, alignment: .trailing)
            }
            .font(.app(13, weight: .medium)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 16).padding(.vertical, 12).background(Color.appFill)
            ForEach(Array(limits.enumerated()), id: \.offset) { index, row in
                tableRow(row.0, index: index) {
                    Text(row.1).font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 64, alignment: .trailing)
                    Image(systemName: "infinity").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.appPrimary).frame(width: 72, alignment: .trailing)
                }
            }
            ForEach(Array(features.enumerated()), id: \.offset) { index, title in
                tableRow(title, index: limits.count + index) {
                    Text(verbatim: "–").font(.app(15)).foregroundStyle(Color.appTextTertiary).frame(width: 64, alignment: .trailing)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.appPrimary).frame(width: 72, alignment: .trailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.appDivider))
    }

    private func tableRow<T: View>(_ title: String, index: Int, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.app(16)).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
        .motion(.fleft, delay: Double(index) * 0.07)
    }

    // MARK: Plus states (design 2b trial, 3a active, 3b grace, 3c ended)

    private var heroColor: Color {
        switch phase {
        case .grace: Color.appWarning
        case .ended: Self.ink
        default: Color.appPrimary
        }
    }

    private var statusHero: some View {
        let left = plus.entitlement.daysLeft() ?? 0
        let big: String, unit: String, tag: String?, caption: String
        switch phase {
        case .trial:
            big = "\(left)"; unit = L("hari lagi"); tag = nil
            let trialPlan = plus.entitlement.plan
            caption = L("Ditagih %@ · %@ per %@", until, PlusPricing.price(trialPlan), trialPlan == .monthly ? L("bulan") : L("tahun"))
        case .active:
            let monthly = plus.entitlement.plan == .monthly
            big = PlusPricing.price(monthly ? .monthly : .yearly); unit = monthly ? L("per bulan") : L("per tahun"); tag = L("Aktif")

            caption = L("Ditagih berikutnya %@", until)
        case .grace:
            big = "\(left)"; unit = L("hari lagi"); tag = L("Masa tenggang")
            caption = L("Pembayaran belum berhasil. Plus berakhir %@ bila tidak diperbarui.", until)
        default:
            big = L("Plus berakhir"); unit = ""; tag = L("Berakhir")
            caption = L("Berakhir %@. Datamu tetap aman.", until)
        }
        let (bars, filled) = plus.entitlement.bars() ?? (14, 0)
        let button = phase == .grace ? L("Perbarui pembayaran") : (phase == .ended ? L("Perpanjang Saku Plus") : nil)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label { Text("Saku Plus").font(.app(15, weight: .semibold)) } icon: { Image(systemName: "sparkles").font(.system(size: 15)) }
                Spacer()
                if let tag {
                    Text(tag).font(.app(12, weight: .semibold)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 24).background(.white.opacity(0.2), in: Capsule())
                } else {
                    Text("Trial").font(.app(13)).foregroundStyle(.white.opacity(0.8))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(big).font(.app(big.count > 4 ? (phase == .ended ? 34 : 44) : 56, weight: .ultraLight)).tracking(-1.5).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.app(17)) }
            }
            .padding(.top, 8)
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule().fill(i < filled ? Color.white : Color.white.opacity(0.3)).frame(height: 6)
                        .motion(.tick, delay: 0.25 + Double(i) * 0.045)
                }
            }
            .padding(.top, 14)
            Text(caption).font(.app(13)).lineSpacing(2).foregroundStyle(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            if let button {
                Button { ctaTapped() } label: {
                    Text(button).font(.app(15, weight: .semibold)).foregroundStyle(phase == .grace ? Color.appWarning : Self.ink)
                        .frame(maxWidth: .infinity).frame(height: 44).background(.white, in: Capsule())
                }
                .buttonStyle(PressScaleStyle()).padding(.top, 16)
                .motion(.pop, delay: 0.3)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
        .background(heroColor, in: RoundedRectangle(cornerRadius: 28))
    }

    private var tiles: some View {
        let locked = phase == .ended
        let items = [("infinity", L("Tanpa batas")), ("bell", L("Notifikasi bank")), ("camera", L("Foto struk")),
                     ("envelope", L("Email tagihan")), ("doc.richtext", L("Laporan PDF")), ("sparkles", L("AI tanpa batas"))]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: item.0).font(.system(size: 18)).foregroundStyle(locked ? Color.appTextTertiary : Color.appPrimary).frame(height: 22, alignment: .leading)
                    Text(item.1).font(.app(12, weight: .medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: locked ? "lock.fill" : "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(locked ? Color.appTextTertiary : Color.appPrimary, in: Circle())
                        .motion(.chk, delay: Double(index) * 0.08 + 0.5).padding(10)
                }
                .motion(.tile, delay: Double(index) * 0.08 + 0.15)
            }
        }
    }

    private var manageRow: some View {
        Button { manageTapped() } label: {
            HStack(spacing: 14) {
                Image(systemName: onPlus || phase == .ended ? "creditcard" : "arrow.clockwise").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                Text(onPlus || phase == .ended ? L("Kelola langganan") : L("Pulihkan pembelian")).font(.app(16)).foregroundStyle(Color.appText)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func ctaTapped() {
        if phase == .grace, let subscriptionsURL { openURL(subscriptionsURL) } else { paywall = .general }
    }

    private func manageTapped() {
        if onPlus, let subscriptionsURL { openURL(subscriptionsURL); return }
        Task {
            if await PlusPurchases.shared.restore() { return }
            failure = L("Tidak ada langganan Saku Plus di Apple ID ini.")
        }
    }
}

/// The page's motion from the design: rise, slide in, grow, pop and bob, each with its own delay (seconds).
private extension View {
    func motion(_ kind: PlanMotion.Kind, delay: Double = 0) -> some View { modifier(PlanMotion(kind: kind, delay: delay)) }
}

private struct PlanMotion: ViewModifier {
    enum Kind { case fup, fleft, tile, tick, chk, pop }
    let kind: Kind
    let delay: Double
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var curve: Animation {
        switch kind {
        case .fup, .fleft: .easeOut(duration: 0.5).delay(delay)
        case .tile: .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.7).delay(delay)
        case .tick: .easeOut(duration: 0.4).delay(delay)
        case .chk: .timingCurve(0.3, 1.5, 0.5, 1, duration: 0.5).delay(delay)
        case .pop: .spring(duration: 0.5, bounce: 0.3).delay(delay)
        }
    }

    func body(content: Content) -> some View {
        let shown = on || reduceMotion
        return content
            .opacity(kind == .tick || shown ? 1 : 0)
            .offset(x: kind == .fleft && !shown ? -16 : 0,
                    y: kind == .fup && !shown ? 14 : kind == .tile && !shown ? 18 : 0)
            .scaleEffect(x: kind == .tick && !shown ? 0 : 1, y: 1, anchor: .leading)
            .scaleEffect(kind == .chk && !shown ? 0 : kind == .tile && !shown ? 0.94 : kind == .pop && !shown ? 0.88 : 1)
            .animation(curve, value: on)
            .onAppear { on = true }
    }
}
