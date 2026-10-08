import SwiftUI

/// Profil › Catat cepat: what Saku remembered, deleting it, and the guide for noticing bank notifications.
struct SmartTrackerSettingsView: View {
    @ObservedObject private var store = DraftStore.shared
    @State private var confirmsDeleteAll = false

    private func name(_ id: String?, in list: [(String, String)]) -> String? { list.first { $0.0 == id }?.1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(destination: SmartTrackerPrivacyView().detailPage()) {
                    row(icon: "lock.shield", title: L("Data yang diproses"), subtitle: L("Apa yang dibaca dan ke mana dikirim"))
                }
                .buttonStyle(RowPressStyle())

                NavigationLink(destination: NotificationSetupGuideView().detailPage()) {
                    row(icon: "bell.badge", title: L("Catat dari notifikasi"), subtitle: L("Panduan memasang di Shortcuts"))
                }
                .buttonStyle(RowPressStyle())

                Text(L("Yang diingat Saku"))
                    .font(.app(20, weight: .semibold))
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 4)
                if store.memory.isEmpty {
                    Text(L("Belum ada. Setelah kamu menyimpan draf, Saku mengingat kategori dan dompet pilihanmu untuk kata yang sama."))
                        .font(.app(14)).foregroundStyle(Color.appTextSecondary).padding(.horizontal, 24).padding(.top, 4)
                } else {
                    ForEach(store.memory) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.keyword.capitalized).font(.app(16, weight: .medium))
                                Text([store.categories.first { $0.id == entry.categoryId }?.name,
                                      store.accounts.first { $0.id == entry.accountId }?.name].compactMap { $0 }.joined(separator: " · "))
                                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer()
                            Button { store.forget(entry) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appTextTertiary)
                            }
                            .accessibilityLabel(L("Hapus"))
                        }
                        .padding(.horizontal, 24).padding(.vertical, 12).rowSeparator()
                    }
                }

                Button(role: .destructive) { confirmsDeleteAll = true } label: {
                    Text(L("Hapus semua draf dan ingatan"))
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color(light: 0xFDECEC, dark: 0x3A1D1F), in: Capsule())
                }
                .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 40)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(L("Catat cepat"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmDialog(isPresented: $confirmsDeleteAll, icon: "trash", destructive: true,
                       title: L("Hapus semua draf dan ingatan?"),
                       message: L("Draf yang belum disimpan dan semua pilihan yang diingat dihapus dari perangkat ini."),
                       confirmTitle: L("Hapus")) {
            store.forgetEverything()
            confirmsDeleteAll = false
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
        }
        .padding(.horizontal, 24).padding(.vertical, 14).contentShape(Rectangle())
    }
}

/// Step by step: an iOS personal automation with the "Notification" trigger that sends the text to Saku.
/// Automations cannot be shared as a link, so each user builds one per app.
struct NotificationSetupGuideView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Saku tidak bisa membaca notifikasi aplikasi lain. Tapi iOS punya otomatisasi di Shortcuts yang bisa meneruskan notifikasi ke Saku. Pasang satu kali untuk tiap aplikasi."))
                    .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                Button { openURL(URL(string: "shortcuts://create-automation")!) } label: {
                    Label(L("Buka Shortcuts"), systemImage: "arrow.up.forward.app")
                        .font(.app(16, weight: .semibold)).foregroundStyle(Color.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 50).background(Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.app(13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(Color.appPrimary, in: Circle())
                        Text(step).font(.app(15)).lineSpacing(3)
                    }
                }
                Text(L("Aplikasi yang didukung: %@. Draf dari notifikasi selalu masuk ke Perlu dicek; teks notifikasi tidak disimpan.",
                       NotificationParser.supportedApps.joined(separator: ", ")))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Catat dari notifikasi"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var steps: [String] {
        [L("Di Shortcuts, buka tab Otomatisasi lalu ketuk + dan pilih Notifikasi."),
         L("Pilih aplikasinya (misalnya GoPay atau BCA), lalu pilih Jalankan Segera."),
         L("Ketuk Berikutnya, tambahkan aksi \"Catat dari notifikasi\" dari Saku."),
         L("Isi Aplikasi sumber dengan nama aplikasinya, lalu Judul, Subjudul, dan Isi dengan variabel dari notifikasi."),
         L("Matikan \"Tanya Sebelum Menjalankan\" jika iOS menawarkannya, lalu ketuk Selesai.")]
    }
}

/// What Smart Tracker reads and where it goes, any time, with the state of the user's agreement.
struct SmartTrackerPrivacyView: View {
    @AppStorage(SmartTrackerConsent.key) private var isGranted = false
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showsConsent = false
    @State private var showsRevoke = false
    @State private var isRevoking = false
    @State private var revokeFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(isGranted ? L("Kamu sudah menyetujui") : L("Belum disetujui"),
                      systemImage: isGranted ? "checkmark.seal.fill" : "exclamationmark.circle")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(isGranted ? Color.appPrimary : Color.appWarning)
                SmartTrackerPrivacyText()
                if !isGranted {
                    Button { showsConsent = true } label: {
                        Text(L("Baca dan setujui"))
                            .font(.app(16, weight: .semibold)).foregroundStyle(Color.appBackground)
                            .frame(maxWidth: .infinity).frame(height: 50).background(Color.appText, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                } else {
                    Button { showsRevoke = true } label: {
                        Text(L("Cabut persetujuan"))
                            .font(.app(16, weight: .semibold))
                            .foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(light: 0xFDECEC, dark: 0x3A1D1F), in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(24)
        }
        .background(Color.appBackground)
        .confirmDialog(isPresented: $showsRevoke, icon: "hand.raised", destructive: true,
                       title: L("Cabut persetujuan?"),
                       message: L("Catat cepat, Siri/Shortcuts, notifikasi, dan Bagikan berhenti membuat draf. Draf yang belum disimpan dan semua yang diingat Saku dihapus dari perangkat ini. Transaksi yang sudah tersimpan tidak berubah. Kamu bisa menyetujui lagi kapan saja."),
                       confirmTitle: L("Cabut persetujuan"), isBusy: isRevoking) { revoke() }
        .confirmDialog(isPresented: $revokeFailed, icon: "exclamationmark.triangle", title: L("Gagal mencabut persetujuan"),
                       message: L("Periksa koneksi internetmu lalu coba lagi. Persetujuanmu belum berubah."),
                       confirmTitle: nil, cancelTitle: L("Tutup"))
        .navigationTitle(L("Data yang diproses"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) }) { showsConsent = false }
        }
    }

    private func revoke() {
        guard let profileId = authViewModel.currentUser.flatMap({ UUID(uuidString: $0.id) }) else { return }
        isRevoking = true
        Task {
            do {
                try await SupabaseSDK.revokeSmartTrackerConsent(profileId: profileId)
                // nothing read under the old agreement stays: drafts, what was learned, text waiting from Bagikan
                DraftStore.shared.forgetEverything()
                _ = ShareInbox.drain()
                showsRevoke = false
            } catch {
                showsRevoke = false
                revokeFailed = true
            }
            isRevoking = false
        }
    }
}
