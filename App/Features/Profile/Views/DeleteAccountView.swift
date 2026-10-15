import SwiftUI

/// Profil › Hapus akun: what goes, the 30 days to change your mind, an optional one-question survey, and a typed
/// confirmation. Nothing is deleted now; the account is scheduled and can be cancelled by signing in again.
struct DeleteAccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var reason: AccountDeletion.Reason?
    @State private var note = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var failure: String?
    @FocusState private var confirmFocused: Bool

    private var scheduledDay: String {
        AccountDeletion.dayText(Calendar.current.date(byAdding: .day, value: AccountDeletion.graceDays, to: Date()) ?? Date())
    }
    private var canDelete: Bool { AccountDeletion.phraseMatches(confirmation) && !isWorking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hapus akun").font(.app(28, weight: .bold)).padding(.top, 8)
                Text(L("Akunmu dijadwalkan dihapus permanen pada %@. Sampai tanggal itu kamu bisa membatalkannya dengan masuk lagi ke Saku.", scheduledDay))
                    .font(.app(16)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 8)

                caption(L("Yang ikut terhapus")).padding(.top, 24)
                VStack(alignment: .leading, spacing: 10) {
                    point("wallet.bifold", L("Semua dompet, transaksi, budget, dan kategorimu"))
                    point("brain", L("Ingatan dan draf Smart Tracker"))
                    point("person.crop.circle", L("Foto dan nama profilmu"))
                    point("bell.slash", L("Pengingat di HP ini dimatikan sekarang"))
                }

                caption(L("Kenapa kamu pergi? (boleh dilewati)")).padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(AccountDeletion.Reason.allCases) { item in
                        Button { reason = reason == item ? nil : item } label: {
                            HStack(spacing: 12) {
                                Text(item.title).font(.app(16))
                                Spacer(minLength: 8)
                                Image(systemName: reason == item ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(reason == item ? Color.appPrimary : Color.appTextTertiary)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == item ? .isSelected : [])
                        Divider()
                    }
                }
                if reason == .other {
                    TextField(L("Ceritakan singkat (opsional)"), text: $note, axis: .vertical)
                        .font(.app(15)).lineLimit(3...5)
                        .padding(12).background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 10)
                        .onChange(of: note) { _, value in if value.count > AccountDeletion.noteLimit { note = String(value.prefix(AccountDeletion.noteLimit)) } }
                    Text("\(note.count)/\(AccountDeletion.noteLimit)").font(.app(12)).foregroundStyle(Color.appTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 4)
                }

                caption(L("Untuk melanjutkan, ketik %@", L("hapus akun saya"))).padding(.top, 28)
                TextField(L("hapus akun saya"), text: $confirmation)
                    .font(.app(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($confirmFocused)
                    .padding(.horizontal, 14).frame(height: 50)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))

                Button { delete() } label: {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().tint(.white) }
                        Text("Hapus akun").font(.app(16, weight: .semibold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.appError.opacity(canDelete ? 1 : 0.35), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canDelete)
                .padding(.top, 20).padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground)
        .navigationTitle(L("Hapus akun"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("Gagal menghapus akun", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func delete() {
        guard canDelete else { return }
        isWorking = true
        confirmFocused = false
        Task {
            let ok = await authViewModel.requestDeletion(reason: reason, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            isWorking = false
            if !ok { failure = authViewModel.errorMessage ?? L("Coba lagi.") }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.bottom, 10)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            Text(text).font(.app(15)).foregroundStyle(Color.appBody)
        }
    }
}
