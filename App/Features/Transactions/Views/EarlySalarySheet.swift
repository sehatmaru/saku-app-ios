import SwiftUI

/// "Gaji masuk lebih awal": asked when a salary is recorded before payday. The user has to answer; nothing is saved
/// until they do, and "Batal" goes back to editing. Same sheet for the add form, the quick result and Konfirmasi transaksi.
struct EarlySalarySheet: View {
    let date: Date
    /// true = start the new period on this date, false = keep the usual period.
    let onChoose: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 24)).foregroundStyle(Color.stGreen)
                .frame(width: 48, height: 48).background(Color.stGreen.opacity(0.14), in: Circle()).padding(.top, 14)
            Text("Gaji masuk lebih awal").font(.app(24, weight: .bold)).padding(.top, 16)
            Text(L("Mulai periode baru di tanggal ini? Gaji kamu masuk %@, sebelum tanggal gajian.", dateText))
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
            VStack(alignment: .leading, spacing: 14) {
                point("arrow.right.circle", "Ya", "Periode berjalan berakhir sehari sebelumnya. Periode baru mulai di tanggal ini.")
                point("equal.circle", "Tidak", "Periode tetap seperti biasa.")
                point("trash", "Untuk membatalkan", "Hapus transaksi gaji ini.")
            }
            .padding(.top, 22)
            Spacer(minLength: 16)
            PrimaryButton(title: L("Ya, mulai periode baru")) { choose(true) }
            Button { choose(false) } label: {
                Text("Tidak, pakai periode biasa").font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            Button("Batal") { dismiss() }.font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity).frame(height: 44).padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    private func choose(_ value: Bool) {
        dismiss()
        onChoose(value)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.app(15, weight: .semibold))
                Text(L(detail)).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}
