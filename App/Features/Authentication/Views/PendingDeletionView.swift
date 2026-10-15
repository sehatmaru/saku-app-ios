import SwiftUI

/// Shown after signing in (or opening the app) on an account that is waiting to be deleted:
/// "Batalkan" brings it back with its data, "Tetap hapus" signs out and leaves the date as it was.
struct PendingDeletionView: View {
    let date: Date
    @ObservedObject var authViewModel: AuthViewModel
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "trash.circle.fill").font(.system(size: 56)).foregroundStyle(Color.appError)
            Text("Akunmu dijadwalkan dihapus").font(.app(28, weight: .bold)).padding(.top, 20)
            Text(L("Dihapus permanen pada %@. Setelah itu datamu tidak bisa dipulihkan.", AccountDeletion.dayText(date)))
                .font(.app(16)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 10)
            Text("Batalkan sekarang kalau kamu berubah pikiran: akun aktif kembali dan semua datamu utuh.")
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 8)
            Spacer()
            Button {
                isWorking = true
                Task { _ = await authViewModel.cancelPendingDeletion(); isWorking = false }
            } label: {
                HStack(spacing: 8) {
                    if isWorking { ProgressView().tint(.white) }
                    Text("Batalkan penghapusan").font(.app(17, weight: .semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.appPrimary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(isWorking)
            Button("Tetap hapus") { authViewModel.logout() }
                .font(.app(16)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .disabled(isWorking)
            if let error = authViewModel.errorMessage {
                Text(error).font(.app(13)).foregroundStyle(Color.appError).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .background(Color.appBackground)
    }
}
