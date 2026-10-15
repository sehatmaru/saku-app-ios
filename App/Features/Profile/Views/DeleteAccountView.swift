import SwiftUI

/// Profil › Hapus akun (design "Hapus Akun", 1c): three steps, the button stays at the bottom and rises with the
/// keyboard. Info and the date → optional survey → typed confirmation. Nothing is deleted now; the account is
/// scheduled and can be cancelled by signing in again.
struct DeleteAccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var reason: AccountDeletion.Reason?
    @State private var note = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var failed = false
    @FocusState private var confirmFocused: Bool

    private var scheduledDate: Date {
        Calendar.current.date(byAdding: .day, value: AccountDeletion.graceDays, to: Date()) ?? Date()
    }
    private var scheduledDay: String { AccountDeletion.dayText(scheduledDate) }
    private var ready: Bool { AccountDeletion.phraseMatches(confirmation) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case 1: infoStep
                    case 2: surveyStep
                    default: confirmStep
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(Color.appBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .animation(.spring(duration: 0.42, bounce: 0.1), value: step)
    }

    // MARK: Header: back, three ticks, step

    private var header: some View {
        HStack(spacing: 14) {
            Button { goBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.appPrimary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel(L("Kembali"))
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(i <= step ? Color.appText : Color.appDivider).frame(height: 4)
                }
            }
            Text("\(step)/3").font(.app(13)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 6)
    }

    private func goBack() {
        confirmFocused = false
        if step > 1 { step -= 1 } else { dismiss() }
    }

    // MARK: Step 1

    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hapus akun").font(.app(34, weight: .bold)).tracking(-0.5).padding(.top, 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dihapus permanen pada").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Text(scheduledDay).font(.app(30, weight: .light)).tracking(-0.6)
                Text(L("%lld hari dari hari ini", AccountDeletion.graceDays)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(Color.appFill, in: RoundedRectangle(cornerRadius: 16)).padding(.top, 18)
            Text("Sampai tanggal itu kamu bisa membatalkannya dengan masuk lagi ke Saku.")
                .font(.app(16)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 14)
            Text("Yang ikut terhapus").font(.app(20, weight: .semibold)).padding(.top, 28)
            VStack(spacing: 0) {
                point("wallet.bifold", L("Semua dompet, transaksi, budget, dan kategorimu"))
                point("sparkle", L("Ingatan dan draf Smart Tracker"))
                point("person.crop.circle", L("Foto dan nama profilmu"))
                point("bell.slash", L("Pengingat di HP ini dimatikan sekarang"))
            }
            .padding(.top, 8)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            Text(text).font(.app(16)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    // MARK: Step 2

    private var surveyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kenapa kamu pergi?").font(.app(28, weight: .bold)).tracking(-0.4).padding(.top, 22)
            Text("Boleh dilewati. Jawabanmu membantu kami memperbaiki Saku.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(AccountDeletion.Reason.allCases) { item in
                    Button { withAnimation(.easeOut(duration: 0.2)) { reason = reason == item ? nil : item } } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().strokeBorder(reason == item ? Color.clear : Color.appBorder, lineWidth: 1.5)
                                    .background(Circle().fill(reason == item ? Color.appPrimary : Color.clear))
                                if reason == item {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 22, height: 22)
                            Text(item.title).font(.app(16))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 13).contentShape(Rectangle())
                        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == item ? .isSelected : [])
                }
            }
            .padding(.top, 18)
            if reason == .other {
                TextField(L("Ceritakan singkat (opsional)"), text: $note, axis: .vertical)
                    .font(.app(16)).lineLimit(3...5)
                    .padding(12).frame(minHeight: 84, alignment: .topLeading)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 6)
                    .onChange(of: note) { _, value in if value.count > AccountDeletion.noteLimit { note = String(value.prefix(AccountDeletion.noteLimit)) } }
                Text("\(note.count)/\(AccountDeletion.noteLimit)").font(.app(12)).foregroundStyle(Color.appTextTertiary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
            }
        }
    }

    // MARK: Step 3

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Konfirmasi").font(.app(28, weight: .bold)).tracking(-0.4).padding(.top, 22)
            (Text(L("Untuk melanjutkan, ketik ")) + Text(L("hapus akun saya")).fontWeight(.semibold))
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 8)
            ZStack(alignment: .trailing) {
                TextField(L("hapus akun saya"), text: $confirmation)
                    .font(.app(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($confirmFocused)
                    .padding(.leading, 14).padding(.trailing, 44).frame(height: 48)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                if ready {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appPrimary)
                        .padding(.trailing, 14).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.24), value: ready)
            .padding(.top, 14)
            Text(L("Bisa dibatalkan sampai %@.", scheduledDay)).font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 12)
        }
    }

    // MARK: Footer: the action sits at the bottom and rises with the keyboard

    private var footer: some View {
        VStack(spacing: 10) {
            if step == 3, failed {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 17)).foregroundStyle(Color.appError)
                    Text("Permintaan belum terkirim dan akunmu belum berubah. Coba lagi sebentar lagi.")
                        .font(.app(14)).lineSpacing(2).foregroundStyle(Color.appText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.appError.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if step < 3 {
                Button { step += 1 } label: {
                    Text(step == 1 ? L("Saya mengerti, lanjutkan") : (reason == nil ? L("Lewati") : L("Lanjut")))
                        .font(.app(17, weight: .semibold)).foregroundStyle(Color.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            } else {
                Button { delete() } label: {
                    HStack(spacing: 10) {
                        if isWorking { ProgressView().tint(.white) }
                        Text(isWorking ? L("Menghapus…") : L("Hapus akun")).font(.app(17, weight: .semibold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.appError, in: Capsule())
                    .opacity(ready ? 1 : 0.35)
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!ready || isWorking)
                .animation(.easeOut(duration: 0.3), value: ready)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
        )
        .animation(.spring(duration: 0.32), value: failed)
    }

    private func delete() {
        guard ready, !isWorking else { return }
        isWorking = true
        failed = false
        confirmFocused = false
        Task {
            let ok = await authViewModel.requestDeletion(reason: reason, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            isWorking = false
            failed = !ok
        }
    }
}
