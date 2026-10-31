import SwiftUI

/// Profil › Menu uji (internal and TestFlight builds only): every test trigger in one place. Plus state, the Beranda
/// notices and the Smart Tracker sheets. Removed before the App Store release.
struct TestMenuView: View {
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var homePreview = HomePreview.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isSwitching = false
    @State private var failure: String?
    @State private var showsTrialEndedTest = false
    @State private var sheet: PreviewSheet?
    @State private var confirm: PreviewConfirm?

    private var phase: PlusPhase { plus.entitlement.phase() }

    enum PreviewSheet: String, Identifiable {
        case smart, image, imageNeedsTracker, memory, saveAll
        var id: String { rawValue }
    }

    enum PreviewConfirm: String, Identifiable {
        case off, offBusy, forget, deleteAll, failedOff, failed
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header("Saku Plus")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("free", "Gratis"), ("trial", "Trial"), ("active", "Aktif"), ("monthly", "Bulanan"), ("grace", "Tenggang"), ("ended", "Berakhir")], id: \.0) { key, title in
                            Button { switchTo(key) } label: {
                                Text(verbatim: title).font(.app(14, weight: .semibold))
                                    .foregroundStyle(isCurrent(key) ? Color.white : Color.appText)
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(isCurrent(key) ? Color.appPrimary : Color.stChip, in: Capsule())
                            }
                            .buttonStyle(.plain).disabled(isSwitching)
                        }
                    }
                }
                item("Lihat ringkasan trial berakhir", selected: false) { showsTrialEndedTest = true }

                header("Pratinjau Beranda")
                note("Ketuk satu, lalu buka tab Beranda. Ketuk lagi untuk mematikan. Kembali normal saat aplikasi dibuka ulang.")
                ForEach(HomePreview.Kind.allCases) { kind in
                    item(kind.title, selected: homePreview.kind == kind) { homePreview.toggle(kind) }
                }

                header("Smart Tracker · persetujuan")
                note("Setuju tidak menyimpan apa pun di sini.")
                item("Smart Tracker", selected: false) { sheet = .smart }
                item("Catat dari gambar", selected: false) { sheet = .image }
                item("Catat dari gambar + catatan Smart Tracker", selected: false) { sheet = .imageNeedsTracker }
                item("Sinkron Ingatan", selected: false) { sheet = .memory }

                header("Smart Tracker · konfirmasi")
                item("Simpan N transaksi", selected: false) { sheet = .saveAll }
                item("Matikan Smart Tracker?", selected: false) { confirm = .off }
                item("Matikan Smart Tracker? (sibuk)", selected: false) { confirm = .offBusy }
                item("Lupakan semua?", selected: false) { confirm = .forget }
                item("Abaikan semua draf?", selected: false) { confirm = .deleteAll }

                header("Smart Tracker · informasi")
                item("Gagal mematikan Smart Tracker", selected: false) { confirm = .failedOff }
                item("Gagal", selected: false) { confirm = .failed }

                note("Hanya di build uji. Dihapus sebelum rilis App Store.").padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(Text(verbatim: "Menu uji"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Tutup", role: .cancel) {}
        }
        .sheet(isPresented: $showsTrialEndedTest) { TrialEndedSheet(wallets: 6, categories: 9, budgets: 4) {} }
        .sheet(item: $sheet) { item in
            switch item {
            case .smart: SmartTrackerConsentSheet(profileId: nil, onAgree: { sheet = nil }, isPreview: true)
            case .image: ImageConsentSheet(profileId: nil, onAgree: {}, onDetails: nil, isPreview: true, previewNeedsTracker: false)
            case .imageNeedsTracker: ImageConsentSheet(profileId: nil, onAgree: {}, onDetails: nil, isPreview: true, previewNeedsTracker: true)
            case .memory: MemorySyncConsentSheet(profileId: nil, isPreview: true)
            case .saveAll:
                SmartSheet(tone: .consent, icon: "checkmark.circle", title: L("Simpan %lld transaksi yang lengkap?", 5),
                           message: L("%lld draf yang belum lengkap tetap di daftar supaya bisa kamu cek nanti.", 2)) {
                    SmartSheetFooter(primary: L("Simpan %lld transaksi", 5), secondary: L("Batal"), onPrimary: { sheet = nil }) { sheet = nil }
                }
            }
        }
        .confirmDialog(isPresented: flag(.off), icon: "power", destructive: true, title: L("Matikan Smart Tracker?"),
                       message: L("Semua cara mencatat berhenti. %lld draf dan %lld ingatan dihapus dari HP ini. Transaksi yang sudah tersimpan tetap aman.", 3, 12),
                       confirmTitle: L("Matikan dan hapus")) { confirm = nil }
        .confirmDialog(isPresented: flag(.offBusy), icon: "power", destructive: true, title: L("Matikan Smart Tracker?"),
                       message: L("Semua cara mencatat berhenti. %lld draf dan %lld ingatan dihapus dari HP ini. Transaksi yang sudah tersimpan tetap aman.", 3, 12),
                       confirmTitle: L("Matikan dan hapus"), isBusy: true) {}
        .confirmDialog(isPresented: flag(.forget), icon: "brain", destructive: true, title: L("Lupakan semua?"),
                       message: L("Semua pilihan yang diingat dihapus. Transaksi yang sudah tersimpan tidak berubah."),
                       confirmTitle: L("Lupakan semua")) { confirm = nil }
        .confirmDialog(isPresented: flag(.deleteAll), icon: "eye.slash", inkButton: true, title: L("Abaikan semua draf?"),
                       message: L("Semua %lld draf dari Smart Tracker akan dibuang. Transaksi yang sudah tersimpan tidak terpengaruh.", 3),
                       confirmTitle: L("Abaikan semua")) { confirm = nil }
        .confirmDialog(isPresented: flag(.failedOff), icon: "exclamationmark.triangle", title: L("Gagal mematikan Smart Tracker"),
                       message: L("Periksa koneksi internetmu lalu coba lagi. Pengaturanmu belum berubah."),
                       confirmTitle: nil, cancelTitle: L("Tutup"))
        .confirmDialog(isPresented: flag(.failed), icon: "exclamationmark.triangle", title: L("Gagal"),
                       message: L("Terjadi kesalahan. Coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private func flag(_ value: PreviewConfirm) -> Binding<Bool> {
        Binding(get: { confirm == value }, set: { if !$0 && confirm == value { confirm = nil } })
    }

    private func header(_ text: String) -> some View {
        Text(verbatim: text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.top, 18)
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).font(.app(12)).foregroundStyle(Color.appTextTertiary)
    }

    private func item(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).font(.app(14, weight: .semibold))
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .foregroundStyle(selected ? Color.white : Color.appText)
            .padding(.horizontal, 14).frame(height: 38)
            .background(selected ? Color.appPrimary : Color.stChip, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func isCurrent(_ key: String) -> Bool {
        switch (key, phase) {
        case ("free", .free), ("trial", .trial), ("grace", .grace), ("ended", .ended): true
        case ("active", .active): plus.entitlement.plan == .yearly
        case ("monthly", .active): plus.entitlement.plan == .monthly
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
                try await SupabaseSDK.setTestPlusState(key == "monthly" ? "active" : key)
                PlusStore.shared.useTestSwitch()
                PlusStore.shared.setPlan(key == "monthly" ? .monthly : .yearly)
                _ = try await SupabaseSDK.fetchProfile(authUserId: authId)
            } catch {
                failure = "\(error)".contains("test_plus_off") ? L("Tombol uji sedang dimatikan di server.") : L("Belum berhasil mengubah. Coba lagi sebentar lagi.")
            }
        }
    }
}
