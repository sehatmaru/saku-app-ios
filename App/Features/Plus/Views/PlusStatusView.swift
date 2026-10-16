import SwiftUI

/// Profil › Saku Plus (design "Plus B Status" 4f, states 4g-4k): what plan the account is on, a preview of the
/// other side, and where to manage it. Debug and TestFlight builds also get a picker for every state (US8).
struct PlusStatusView: View {
    @ObservedObject private var plus = PlusStore.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL
    @StateObject private var categories = CategoriesModel()
    @State private var walletCount = 0
    @State private var budgetCount = 0
    @State private var previews = false
    @State private var paywall: PlusReason?
    @State private var showsSoon = false
    @State private var isSwitching = false
    @State private var failure: String?

    private var phase: PlusPhase { plus.entitlement.phase() }
    private var onPlus: Bool { [.trial, .active, .grace].contains(phase) }
    /// What the screen shows: the opposite side while previewing.
    private var showsPlus: Bool { onPlus != previews }
    private var until: String { plus.entitlement.until.map(AccountDeletion.dayText) ?? "" }
    private var userId: String { authViewModel.currentUser?.id ?? "" }
    private let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    private struct Row: Identifiable {
        let id: String, icon: String, label: String
        var value = "", used = 0, of = 0, plusOnly = false
    }

    private var rows: [Row] {
        let expense = FreeLimits.activeCount(categories.arranged(.expense).shown, type: .expense)
        var list = [
            Row(id: "wallet", icon: "wallet.pass", label: L("Dompet uang aktif"), value: L("%lld dari %lld", walletCount, FreeLimits.moneyWallets), used: walletCount, of: FreeLimits.moneyWallets),
            Row(id: "category", icon: "tag", label: L("Kategori pengeluaran"), value: L("%lld dari %lld", expense, FreeLimits.expenseCategories), used: expense, of: FreeLimits.expenseCategories),
            Row(id: "budget", icon: "target", label: L("Budget"), value: L("%lld dari %lld", budgetCount, FreeLimits.budgets), used: budgetCount, of: FreeLimits.budgets),
        ]
        // AI help is counted on the server, which is not built yet: sample numbers, for test builds only
        if PlusStore.isInternalBuild { list.append(Row(id: "ai", icon: "sparkles", label: L("Bantuan AI bulan ini"), value: L("Sisa %lld dari %lld", AIQuota.sample.left, AIQuota.sample.total), used: AIQuota.sample.total - AIQuota.sample.left, of: AIQuota.sample.total)) }
        list += [
            Row(id: "notif", icon: "bell.badge", label: L("Catat dari notifikasi"), plusOnly: true),
            Row(id: "photo", icon: "camera", label: L("Foto struk dan screenshot"), plusOnly: true),
            Row(id: "email", icon: "envelope", label: L("Penerusan email"), plusOnly: true),
            Row(id: "pdf", icon: "doc.richtext", label: L("Laporan PDF"), plusOnly: true),
        ]
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.stEnter(0)
                switcher.padding(.top, 18).stEnter(1)
                Text(previews ? L("Ketuk \"Sekarang\" untuk kembali") : L("Ketuk untuk membandingkan"))
                    .font(.app(12)).foregroundStyle(Color.appTextTertiary).padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id == "ai" {
                            NavigationLink(destination: AIQuotaView().detailPage()) { rowView(row) }.buttonStyle(.plain)
                        } else {
                            rowView(row)
                        }
                    }
                }
                .padding(.top, 14)
                .id(showsPlus)
                .transition(.opacity)
                if PlusStore.isInternalBuild {
                    Text("Bantuan AI memakai angka contoh sampai server siap.")
                        .font(.app(12)).foregroundStyle(Color.appTextTertiary).padding(.top, 6)
                }
                Divider().overlay(Color.appDivider).padding(.vertical, 18)
                if let cta {
                    PrimaryButton(title: cta) { ctaTapped() }
                }
                Button { manageTapped() } label: {
                    HStack {
                        Text(onPlus ? L("Kelola langganan") : L("Pulihkan pembelian")).font(.app(16)).foregroundStyle(Color.appText)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                Text("Data yang melebihi batas tetap aman dan tetap dipakai. Hanya penambahan baru yang tertahan.")
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary).fixedSize(horizontal: false, vertical: true)
                if PlusStore.isInternalBuild { testPicker }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(L("Saku Plus"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .plusOffer($paywall)
        .task { await load() }
        .alert(L("Pembelian segera hadir"), isPresented: $showsSoon) { Button("OK", role: .cancel) {} } message: {
            Text("Saku Plus belum bisa dibeli. Kami kabari saat sudah dibuka.")
        }
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Tutup", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kamu sedang memakai").font(.app(14)).foregroundStyle(Color.appTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tier).font(.app(34, weight: .light)).tracking(-0.8)
                    .foregroundStyle(showsPlus ? Color.appPrimary : Color.appText)
                    .contentTransition(.opacity)
                if !previews, let pill { Text(pill.0).font(.app(12, weight: .semibold)).foregroundStyle(pill.1)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(pill.2, in: Capsule()) }
            }
            Text(subtitle).font(.app(14)).foregroundStyle(phase == .grace && !previews ? Color.appError : Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tier: String {
        if previews { return onPlus ? L("Tanpa Plus") : L("Dengan Plus") }
        return onPlus ? L("Saku Plus") : L("Saku Gratis")
    }

    private var subtitle: String {
        if previews { return onPlus ? L("Pratinjau bila langganan berhenti. Datamu tetap aman.") : L("Pratinjau. Begini Saku-mu setelah mencoba Plus.") }
        switch phase {
        case .free: return L("Mengetik selalu tanpa batas. Beberapa jumlah dibatasi.")
        case .trial: return L("Pada %@, %@ per tahun ditagih lewat App Store. Batalkan sebelum itu bila tidak ingin lanjut.", until, PlusPricing.yearly)
        case .active: return L("Diperpanjang %@ · %@ per tahun.", until, PlusPricing.yearly)
        case .grace: return L("Pembayaran belum berhasil. Plus tetap terbuka sampai %@.", until)
        case .ended: return L("Plus berakhir %@. Semua data tetap ada.", until)
        }
    }

    /// Label, text colour, background.
    private var pill: (String, Color, Color)? {
        switch phase {
        case .free: nil
        case .trial: (L("Trial · %lld hari lagi", plus.entitlement.daysLeft() ?? 0), Color.appPrimary, Color.appPrimary.opacity(0.12))
        case .active: (L("Tahunan"), Color.appPrimary, Color.appPrimary.opacity(0.12))
        case .grace: (L("Perlu tindakan"), Color.appError, Color.appError.opacity(0.12))
        case .ended: (L("Berakhir %@", until), Color.appTextSecondary, Color.stChip)
        }
    }

    // MARK: Preview switch

    private var switcher: some View {
        HStack(spacing: 0) {
            segment(L("Sekarang"), selected: !previews) { withAnimation(.easeInOut(duration: 0.25)) { previews = false } }
            segment(onPlus ? L("Tanpa Plus") : L("Dengan Plus"), selected: previews) { withAnimation(.easeInOut(duration: 0.25)) { previews = true } }
        }
        .padding(3)
        .background(Color.stChip, in: Capsule())
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(14, weight: .semibold))
                .foregroundStyle(selected && previews && !onPlus ? Color.white : Color.appText)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background { if selected { Capsule().fill(previews && !onPlus ? Color.appPrimary : Color.appBackground) } }
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func rowView(_ row: Row) -> some View {
        let unlocked = showsPlus
        let atLimit = row.of > 0 && row.used >= row.of
        let value: String = {
            guard unlocked else { return row.value }
            return row.of > 0 ? (row.id == "ai" ? L("Lebih banyak") : L("Tanpa batas")) : L("Terbuka")
        }()
        return HStack(spacing: 14) {
            Image(systemName: row.icon).font(.system(size: 18)).frame(width: 24)
                .foregroundStyle(unlocked ? Color.appPrimary : Color.appTextSecondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.label).font(.app(15)).foregroundStyle(Color.appText)
                if row.of > 0, !unlocked {
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { i in
                            Capsule().fill(i < Int((Double(row.used) / Double(row.of) * 10).rounded())
                                           ? (atLimit ? Color.appWarning : Color.appText) : Color.appBorder.opacity(0.5))
                                .frame(height: 3)
                        }
                    }
                    .frame(width: 110)
                }
            }
            Spacer(minLength: 8)
            if !unlocked, row.plusOnly {
                Text(verbatim: "Plus").font(.app(11, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Color.appPrimary.opacity(0.12), in: Capsule())
            }
            if unlocked, row.plusOnly { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appPrimary) }
            Text(value).font(.app(14)).monospacedDigit()
                .foregroundStyle(unlocked ? Color.appPrimary : (atLimit ? Color.appWarning : Color.appTextSecondary))
        }
        .padding(.vertical, 11)
    }

    // MARK: Actions

    private var cta: String? {
        if onPlus { return phase == .grace ? L("Perbarui pembayaran") : nil }
        return phase == .ended ? L("Lanjutkan dengan Plus") : L("Coba gratis 7 hari")
    }

    private func ctaTapped() {
        if phase == .grace, let subscriptionsURL { openURL(subscriptionsURL) } else { paywall = .general }
    }

    private func manageTapped() {
        if onPlus, let subscriptionsURL { openURL(subscriptionsURL) } else { showsSoon = true }
    }

    private func load() async {
        guard !userId.isEmpty else { return }
        await categories.load(userId: userId)
        if let accounts = try? await SupabaseRepository.shared.fetchAccounts(userId: userId) {
            walletCount = accounts.filter { $0.isActive && $0.type != .investment }.count
        }
        if let budgets = try? await SupabaseRepository.shared.fetchBudgets(userId: userId) { budgetCount = budgets.count }
    }

    // MARK: Internal test picker (US8)

    private var testPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uji internal").font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.top, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("free", L("Gratis")), ("trial", L("Trial")), ("active", L("Aktif")), ("grace", L("Tenggang")), ("ended", L("Berakhir"))], id: \.0) { key, title in
                        Button { switchTo(key) } label: {
                            Text(title).font(.app(14, weight: .semibold))
                                .foregroundStyle(isCurrent(key) ? Color.white : Color.appText)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(isCurrent(key) ? Color.appPrimary : Color.stChip, in: Capsule())
                        }
                        .buttonStyle(.plain).disabled(isSwitching)
                    }
                }
            }
            Text("Hanya di build uji. Dihapus sebelum rilis App Store.").font(.app(12)).foregroundStyle(Color.appTextTertiary)
        }
    }

    private func isCurrent(_ key: String) -> Bool {
        switch (key, phase) {
        case ("free", .free), ("trial", .trial), ("active", .active), ("grace", .grace), ("ended", .ended): true
        default: false
        }
    }

    /// Changes the server's value, then reads the profile back: the app never sets Plus on its own (US8).
    private func switchTo(_ key: String) {
        guard let authId = UUID(uuidString: authViewModel.currentUser?.authUserId ?? "") else { return }
        isSwitching = true
        Task {
            defer { isSwitching = false }
            do {
                try await SupabaseSDK.setTestPlusState(key)
                _ = try await SupabaseSDK.fetchProfile(authUserId: authId)
                previews = false
            } catch {
                failure = "\(error)".contains("test_plus_off") ? L("Tombol uji sedang dimatikan di server.") : L("Belum berhasil mengubah. Coba lagi sebentar lagi.")
            }
        }
    }
}
