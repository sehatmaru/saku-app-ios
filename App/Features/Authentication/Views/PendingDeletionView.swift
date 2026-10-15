import SwiftUI

/// Shown after signing in (or opening the app) on an account that is waiting to be deleted (design "Hapus Akun", 2b):
/// the date is the main number. "Batalkan penghapusan" brings the account back with its data, "Tetap hapus" signs out
/// and leaves the date as it was.
struct PendingDeletionView: View {
    let date: Date
    @ObservedObject var authViewModel: AuthViewModel
    @State private var isWorking = false
    @State private var failed = false

    private var daysLeft: Int {
        max(0, min(AccountDeletion.graceDays, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0))
    }
    private var dayNumber: String { Self.format(date, "d") }
    private var monthYear: String { Self.format(date, "MMMM yyyy") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = pattern
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Akunmu dijadwalkan dihapus").font(.app(34, weight: .bold)).tracking(-0.5).lineSpacing(2).padding(.top, 70)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dihapus permanen pada").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(dayNumber).font(.app(58, weight: .ultraLight)).tracking(-2).monospacedDigit()
                    Text(monthYear).font(.app(26, weight: .light)).tracking(-0.5)
                }
            }
            .padding(.top, 36)
            // one segment per day of the wait: the days gone by are dark, the days left stay light
            HStack(spacing: 2) {
                ForEach(0..<AccountDeletion.graceDays, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < AccountDeletion.graceDays - daysLeft ? Color.appText : Color.appDivider)
                        .frame(height: 8)
                }
            }
            .padding(.top, 14)
            Text(L("%lld hari lagi", daysLeft)).font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
            Text(L("Dihapus permanen pada %@. Setelah itu datamu tidak bisa dipulihkan.", AccountDeletion.dayText(date)))
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 24)
            Text("Batalkan sekarang kalau kamu berubah pikiran: akun aktif kembali dan semua datamu utuh.")
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 8)
            Spacer(minLength: 16)
            if failed {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color.appError)
                    Text("Belum berhasil dibatalkan dan akunmu belum berubah. Coba lagi sebentar lagi.")
                        .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appBody)
                }
                .padding(.bottom, 12).transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button {
                isWorking = true
                failed = false
                Task {
                    let ok = await authViewModel.cancelPendingDeletion()
                    isWorking = false
                    failed = !ok
                }
            } label: {
                HStack(spacing: 10) {
                    if isWorking { ProgressView().tint(.white) }
                    Text(isWorking ? L("Membatalkan…") : L("Batalkan penghapusan")).font(.app(17, weight: .semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.appPrimary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(isWorking)
            Button("Tetap hapus") { authViewModel.logout() }
                .font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .opacity(isWorking ? 0.35 : 1).disabled(isWorking)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appBackground)
        .animation(.spring(duration: 0.32), value: failed)
    }
}
