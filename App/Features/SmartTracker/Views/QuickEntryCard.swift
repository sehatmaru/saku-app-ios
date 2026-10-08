import SwiftUI

/// "Catat cepat" on Beranda: one sentence (typed or spoken) becomes drafts in "Perlu dicek".
struct QuickEntryCard: View {
    let userId: String
    @ObservedObject private var store = DraftStore.shared
    @StateObject private var voice = SpeechDictation()
    @AppStorage(SmartTrackerConsent.key) private var hasConsented = false
    @State private var text = ""
    @State private var showsConsent = false
    @State private var showsQueue = false
    @State private var lastAdded = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appPrimary)
                TextField(L("Catat cepat: kopi 25rb gopay"), text: $text)
                    .font(.app(16))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { toggleVoice() } label: {
                    Image(systemName: voice.isListening ? "stop.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(voice.isListening ? Color.appError : Color.appTextSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(voice.isListening ? L("Berhenti merekam") : L("Catat dengan suara"))
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.appPrimary)
                    }
                    .accessibilityLabel(L("Buat draf"))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.appFill, in: Capsule())

            if let message = voice.message {
                Text(message).font(.app(13)).foregroundStyle(Color.appError)
            }
            if lastAdded > 0 {
                Text(L("%lld draf ditambahkan. Cek dulu sebelum disimpan.", lastAdded))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .transition(.opacity)
            }
            if !store.drafts.isEmpty {
                Button { showsQueue = true } label: {
                    HStack(spacing: 8) {
                        Text("\(store.drafts.count)")
                            .font(.app(13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.appPrimary, in: Capsule())
                        Text(L("Perlu dicek"))
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(Color.appText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.2), value: lastAdded)
        .onChange(of: voice.transcript) { _, spoken in if !spoken.isEmpty { text = spoken } }
        .sheet(isPresented: $showsConsent) { SmartTrackerConsentSheet(profileId: UUID(uuidString: userId)) { showsConsent = false; submit() } }
        .sheet(isPresented: $showsQueue) { DraftQueueView(userId: userId) }
        .task {
            await NotificationManager.shared.requestPermissionIfNeeded()
            await store.refreshReferenceData(userId: userId)
        }
    }

    private func toggleVoice() {
        guard hasConsented else { showsConsent = true; return }
        focused = false
        voice.toggle()
    }

    private func submit() {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        guard hasConsented else { showsConsent = true; return }
        if voice.isListening { voice.stop() }
        let source: Draft.Source = voice.transcript == sentence ? .voice : .typed
        text = ""
        focused = false
        Haptics.add()
        showsQueue = true
        Task {
            let added = await store.addRefined(text: sentence, source: source)
            lastAdded = added.count
            try? await Task.sleep(for: .seconds(4))
            lastAdded = 0
        }
    }
}

/// What Smart Tracker reads and where it goes, shown before first use.
struct SmartTrackerConsentSheet: View {
    /// Whose agreement this is; it is saved on the profile so it follows the account to every device.
    let profileId: UUID?
    var onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Color.appPrimary)
            Text(L("Catat cepat")).font(.app(24, weight: .bold))
            SmartTrackerPrivacyText()
            Spacer()
            Button {
                // agree now (works offline); the profile is updated in the background and retried at next launch
                SmartTrackerConsent.isGranted = true
                if let profileId { Task { try? await SupabaseSDK.recordSmartTrackerConsent(profileId: profileId) } }
                onAgree()
            } label: {
                Text(L("Mengerti, lanjutkan"))
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appText, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            Button(L("Nanti saja")) { dismiss() }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.appTextSecondary)
        }
        .font(.app(15))
        .lineSpacing(3)
        .padding(24)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
    }
}

/// The three paragraphs of the agreement: what is read, where it goes, how long it is kept.
/// Shown in the consent sheet and, any time, from Profil › Catat cepat › Data yang diproses.
struct SmartTrackerPrivacyText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Saku membaca kalimat yang kamu ketik atau ucapkan, lalu membuat draf transaksi. Draf disimpan di perangkat ini dan baru jadi transaksi setelah kamu menyetujuinya."))
            Text(L("Kalimatnya diproses di perangkatmu. Hanya jika kalimat sulit dipahami, teksnya (tanpa saldo atau nomor rekening) dikirim ke server Saku untuk dibantu model bahasa. Penyedia model tidak menyimpan dan tidak melatih model dari teks itu."))
            Text(L("Teks asli dihapus setelah draf dibuat. Draf yang tidak diproses dihapus otomatis setelah 30 hari. Kamu bisa menghapus semuanya di Profil."))
                .foregroundStyle(Color.appTextSecondary)
        }
        .font(.app(15))
        .lineSpacing(3)
    }
}
