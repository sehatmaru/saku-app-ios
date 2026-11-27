import SwiftUI

/// "Tagihan berulang": Tidak / Tiap bulan / Tiap tahun, each with the next date. One sheet for Tambah transaksi,
/// Detail transaksi, Ubah and Draf.
struct RepeatChoiceSheet: View {
    let selected: CardSubscription.Frequency?
    let amount: Double
    var accountName: String?
    /// The next bill date for a frequency.
    let date: (CardSubscription.Frequency) -> Date
    var isBusy = false
    let onSelect: (CardSubscription.Frequency?) -> Void
    let onDone: () -> Void

    private static let options: [(CardSubscription.Frequency?, String)] = [(nil, "Tidak"), (.monthly, "Tiap bulan"), (.yearly, "Tiap tahun")]

    private static var longDate: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "EEEE, d MMM yyyy"
        return f
    }

    private func menuDate(_ frequency: CardSubscription.Frequency) -> String {
        let d = date(frequency)
        return frequency == .yearly ? TransactionDates.dayMonth.string(from: d) + " " + String(Calendar.current.component(.year, from: d))
            : TransactionDates.dayMonth.string(from: d)
    }

    /// A period on from a start day, and never a day that is already past.
    static func nextDate(from start: Date, _ frequency: CardSubscription.Frequency) -> Date {
        let calendar = Calendar.current
        let component: Calendar.Component = frequency == .yearly ? .year : .month
        let today = calendar.startOfDay(for: Date())
        var next = calendar.startOfDay(for: start)
        repeat {
            next = calendar.date(byAdding: component, value: 1, to: next) ?? today.addingTimeInterval(86_400)
        } while next <= today
        return next
    }

    var body: some View {
        PickerSheet(title: L("Tagihan berulang"), actionTitle: L("Tutup"), onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Self.options, id: \.1) { option, title in
                        Button { if !isBusy { onSelect(option) } } label: {
                            HStack(spacing: 12) {
                                Text(L(title)).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                                Spacer()
                                if let option {
                                    Text(menuDate(option)).font(.app(14)).monospacedDigit().foregroundStyle(Color.appTextSecondary)
                                }
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appPrimary)
                                    .opacity(option == selected ? 1 : 0).frame(width: 16)
                            }
                            .padding(.horizontal, 16).frame(height: 52)
                            .rowSeparator()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityAddTraits(option == selected ? .isSelected : [])
                    }
                }
                .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let frequency = selected {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
                            .frame(width: 38, height: 38).background(Color.appBackground, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tagihan berikutnya").font(.app(12)).foregroundStyle(Color.appTextTertiary)
                            Text(Self.longDate.string(from: date(frequency))).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
                            Text("−Rp" + amount.formattedAsDigits() + (accountName.map { " · " + $0 } ?? ""))
                                .font(.app(13)).monospacedDigit().foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 14)
                    .transition(.opacity)
                }

                Text("Dicatat otomatis sebagai pengeluaran saat kamu membuka Saku di tanggal itu. Tidak bisa digabung dengan Cicilan 0%.")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }
    }
}
