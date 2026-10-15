import SwiftUI

/// Profil › Saku Plus: the plan's status, what it gives, and (tester accounts on internal builds only) the
/// switch (any account, debug and TestFlight builds only) that turns Plus on without buying (US8). Buying and restoring come with Epic 11 US3/US7.
struct PlusStatusView: View {
    @ObservedObject private var plus = PlusStore.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isSwitching = false
    @State private var failure: String?

    private var showsTestSwitch: Bool { PlusStore.isInternalBuild }

    private var limits: [(String, String)] { [
        (L("Dompet uang aktif"), String(FreeLimits.moneyWallets)),
        (L("Dompet Investasi aktif"), String(FreeLimits.investmentWallets)),
        (L("Kategori pengeluaran"), String(FreeLimits.expenseCategories)),
        (L("Kategori pemasukan"), String(FreeLimits.incomeCategories)),
        (L("Budget"), String(FreeLimits.budgets)),
    ] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard.stEnter(0)

                sectionCaption(plus.isPlus ? L("Yang terbuka") : L("Batas paket gratis"))
                VStack(spacing: 0) {
                    if plus.isPlus {
                        line(L("Dompet, kategori, dan budget"), L("Tanpa batas"))
                        line(L("Catat dari notifikasi"), L("Terbuka"))
                        line(L("Foto struk dan screenshot"), L("Terbuka"))
                    } else {
                        ForEach(limits, id: \.0) { line($0.0, $0.1) }
                        line(L("Catat dari notifikasi"), L("Butuh Plus"))
                        line(L("Foto struk dan screenshot"), L("Butuh Plus"))
                    }
                }
                .padding(.horizontal, 24).stEnter(1)

                Text("Data yang melebihi batas tetap aman dan tetap dipakai. Hanya penambahan baru yang tertahan.")
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary)
                    .padding(.horizontal, 24).padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)

                if showsTestSwitch {
                    sectionCaption(L("Uji internal"))
                    testSwitch.stEnter(2)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Saku Plus"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollIndicators(.hidden)
        .hidesSmartButton()
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Tutup", role: .cancel) {}
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(plus.entitlement.status.title).font(.app(22, weight: .bold)).foregroundStyle(Color.appText)
                if plus.isPlus {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.stGreen)
                }
            }
            Text(plus.isPlus ? L("Semua fitur Saku Plus terbuka.") : L("Kamu memakai paket gratis."))
                .font(.app(14)).foregroundStyle(Color.appTextSecondary)
            if let until = plus.entitlement.until, plus.isPlus {
                Text(L("Berlaku sampai %@", until.formatted(date: .long, time: .omitted)))
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary)
            }
            if !plus.isPlus {
                PrimaryButton(title: L("Coba gratis 7 hari"), isEnabled: false) {}.padding(.top, 8)
                Text("Pembelian Saku Plus segera hadir.")
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24).padding(.top, 8)
    }

    private var testSwitch: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saku Plus untuk uji").font(.app(16)).foregroundStyle(Color.appText)
                Text("Hanya di build uji. Dihapus sebelum rilis App Store.")
                    .font(.app(12)).foregroundStyle(Color.appTextTertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { plus.isPlus }, set: { toggle($0) }))
                .labelsHidden().tint(Color.stGreen).disabled(isSwitching)
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    /// Changes the server's value, then reads the profile back: the app never sets Plus on its own (US8).
    private func toggle(_ on: Bool) {
        guard let authId = UUID(uuidString: authViewModel.currentUser?.authUserId ?? "") else { return }
        isSwitching = true
        Task {
            defer { isSwitching = false }
            do {
                try await SupabaseSDK.setTestPlus(on)
                _ = try await SupabaseSDK.fetchProfile(authUserId: authId)
            } catch {
                failure = "\(error)".contains("test_plus_off") ? L("Tombol uji sedang dimatikan di server.") : L("Belum berhasil mengubah. Coba lagi sebentar lagi.")
            }
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.app(15)).foregroundStyle(Color.appText)
            Spacer()
            Text(value).font(.app(15)).foregroundStyle(Color.appTextSecondary)
        }
        .padding(.vertical, 12)
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
    }
}
