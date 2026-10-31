import SwiftUI

/// "Gaji masuk lebih awal" (design "Gaji masuk lebih awal", direction A): asked when a salary is recorded before payday.
/// Two equal choices, each showing what it does to the period dates; nothing is saved until one is picked and
/// "Simpan" is pressed, and "Batal" goes back to editing. Same sheet for the add form, the quick result and Konfirmasi transaksi.
struct EarlySalarySheet: View {
    let date: Date
    /// true = start the new period on this date, false = keep the usual period.
    let onChoose: (Bool) -> Void
    var cycle: PaydayCycle = .current
    @State private var choice: Bool?
    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    /// What each choice does to the dates, worked out with the same period math the rest of the app uses.
    private var preview: Preview {
        let usual = cycle.period(containing: date)
        let moved = PaydayCycle(day: cycle.day, schedule: cycle.schedule, shifts: cycle.shifts + [date]).period(containing: date)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        return Preview(usual: usual, moved: moved, runningEnds: dayBefore)
    }

    private struct Preview {
        let usual: DateInterval
        let moved: DateInterval
        let runningEnds: Date
    }

    private func short(_ date: Date) -> String { PaydayCycle.dayMonth.string(from: date) }
    private func lastDay(_ interval: DateInterval) -> String {
        short(calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end)
    }
    private func days(_ from: Date, _ to: Date) -> Double { max(to.timeIntervalSince(from) / 86_400, 1) }

    private var contextText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "d MMMM yyyy"
        return L("Gaji dicatat %@. Biasanya gajian tanggal %lld.", formatter.string(from: date), cycle.day)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gaji masuk lebih awal").font(.app(22, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("Mulai periode baru di tanggal ini?").font(.app(16)).foregroundStyle(Color.appTextSecondary)
                    Text(contextText).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
                VStack(spacing: 10) {
                    option(true, title: "Ya, mulai periode baru",
                           bars: [(days(preview.usual.start, preview.runningEnds), Color.appBorder),
                                  (days(date, preview.moved.end), Color.appPrimary)],
                           lines: [(L("Periode berjalan berakhir"), short(preview.runningEnds)),
                                   (L("Periode baru"), short(preview.moved.start) + " – " + lastDay(preview.moved))],
                           foot: L("Setelah itu, %@ kembali normal.", short(preview.moved.end)))
                    option(false, title: "Tidak, pakai periode biasa",
                           bars: [(1, Color.appBorder)],
                           lines: [(L("Periode tetap"), short(preview.usual.start) + " – " + lastDay(preview.usual))],
                           foot: nil)
                }
                Text("Untuk membatalkan, hapus transaksi gaji ini.").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
        .filterSheet {
            SmartSheetFooter(primary: L("Simpan"), isEnabled: choice != nil, secondary: L("Batal"), onPrimary: {
                guard let choice else { return }
                dismiss()
                onChoose(choice)
            }) { dismiss() }
        }
        .background(Color.appBackground)
    }

    private func option(_ value: Bool, title: String, bars: [(Double, Color)], lines: [(String, String)], foot: String?) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(L(title)).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    ZStack {
                        Circle().strokeBorder(selected ? Color.appPrimary : Color.appBorder, lineWidth: 1.5)
                        if selected { Circle().fill(Color.appPrimary).frame(width: 8, height: 8) }
                    }
                    .frame(width: 22, height: 22)
                }
                GeometryReader { proxy in
                    let total = bars.reduce(0) { $0 + $1.0 }
                    HStack(spacing: 2) {
                        ForEach(bars.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(bars[i].1)
                                .frame(width: max((proxy.size.width - CGFloat(bars.count - 1) * 2) * bars[i].0 / total, 2))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                VStack(spacing: 6) {
                    ForEach(lines.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(lines[i].0).foregroundStyle(Color.appTextSecondary)
                            Spacer(minLength: 8)
                            Text(lines[i].1).fontWeight(.semibold).monospacedDigit().foregroundStyle(Color.appText)
                        }
                        .font(.app(14))
                    }
                    if let foot {
                        Text(foot).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Color.appPrimary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.appPrimary : Color.appBorder, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
