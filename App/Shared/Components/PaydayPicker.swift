import SwiftUI

// "Kapan kamu gajian?" (Budget design 2a card sheet, 2e onboarding, 2f Pengaturan).
//
// - `PaydaySheet(context:onDone:)`: bottom sheet "Tanggal gajian". Present it with `.sheet { … }`;
//   it sets its own detent. "Selesai" saves via `SupabaseSDK.updatePayday`, posts `.dataDidChange`
//   and calls `onDone(day)`; closing without a new day calls `onDone(nil)`. `.settings`
//   preselects the saved day and shows a note that the change applies right away — the
//   caller shows the toast.
// - `PaydayDayPicker` / `PaydayPreview`: the day grid and what it changes, also used by
//   step 5 of SetupOnboardingView.

enum PaydayContext {
    /// From the one-time card on Budget.
    case card
    /// From Profil › Pengaturan.
    case settings
}

extension PaydayCycle {
    /// "1 Sep – 30 Sep" / "25 Sep – 24 Okt", also for payday 1 (unlike `label(for:)`).
    func rangeLabel(for date: Date = Date()) -> String {
        let period = period(containing: date)
        return Self.dayMonth.string(from: period.start) + " – " + lastDayLabel(for: date)
    }

    /// Last day of the period, e.g. "24 Okt".
    func lastDayLabel(for date: Date = Date()) -> String {
        let end = period(containing: date).end
        return Self.dayMonth.string(from: Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    static var dayMonth: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "d MMM"
        return f
    }
}

/// Saves the payday on the signed-in user's profile and reloads everything period-based.
@MainActor
private func savePayday(_ day: Int) async -> Bool {
    do {
        try await SupabaseSDK.updatePayday(day: day)
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        return true
    } catch {
        return false
    }
}

// MARK: - Picker

/// "Akhir bulan" / "Tidak tentu" chips over a 7-column grid of days 1–31.
struct PaydayDayPicker: View {
    @Binding var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                chip(L("Akhir bulan"), 31)
                chip(L("Tidak tentu / tanggal 1"), 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(1...31, id: \.self) { day in
                    let isOn = selection == day
                    Button { pick(day) } label: {
                        Text("\(day)")
                            .font(.app(16, weight: isOn ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(isOn ? Color.appText : .clear))
                            .scaleEffect(isOn ? 1.06 : 1)
                            .animation(.spring(duration: 0.38, bounce: 0.5), value: isOn)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tanggal \(day)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func chip(_ title: String, _ day: Int) -> some View {
        let isOn = selection == day
        return Button { pick(day) } label: {
            Text(title)
                .font(.app(14, weight: .medium))
                .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isOn ? Color.appText : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func pick(_ day: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { selection = day }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// What the payday changes, for `day`.
struct PaydayPreview: View {
    let day: Int

    var body: some View {
        let cycle = PaydayCycle(day: day)
        VStack(alignment: .leading, spacing: 8) {
            row("chart.pie", L("Periode budget & ringkasan"), cycle.rangeLabel())
            row("bell", L("Pengingat menjelang gajian"), cycle.lastDayLabel())
            if day >= 29 {
                row("info.circle", L("Di bulan yang lebih pendek, dipakai"), L("tanggal terakhir"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.22), value: day)
    }

    private func row(_ icon: String, _ text: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 18)
            (Text(text + " ") + Text(value).fontWeight(.semibold).foregroundStyle(Color.appText))
                .font(.app(14))
                .foregroundStyle(Color.appBody)
                .monospacedDigit()
                .lineSpacing(2)
                .contentTransition(.numericText())
        }
        .transition(.opacity)
    }
}

// MARK: - Sheet

struct PaydaySheet: View {
    let context: PaydayContext
    /// The saved day, or nil when closed without a change.
    let onDone: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didFinish = false
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    init(context: PaydayContext, onDone: @escaping (Int?) -> Void) {
        self.context = context
        self.onDone = onDone
        _selection = State(initialValue: context == .settings ? PaydaySetting.day : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // header: X on the left, title centered (design "Tanggal gajian")
            ZStack {
                Text(L("Tanggal gajian")).font(.app(17, weight: .semibold))
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appFill, in: Circle())
                    }
                    .accessibilityLabel(L("Tutup"))
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)

            // the running period stays as is; the next one follows the picked day (design)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Periode berjalan")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                        Text(PaydayCycle.current.rangeLabel())
                            .font(.app(17, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color.appText)
                    }
                    Spacer(minLength: 8)
                    Text(L("Tidak berubah")).font(.app(12, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Color.appBackground, in: Capsule())
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))

                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appTextTertiary)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Periode berikutnya")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                        Text(nextPeriodLabel)
                            .font(.app(19, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Color.appPrimary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 8)
                    if isChanged {
                        Text(L("Tanggal baru")).font(.app(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 22)
                            .background(Color.appPrimary, in: Capsule())
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.appPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .animation(.easeOut(duration: 0.3), value: isChanged)
            }
            .padding(.horizontal, 24)

            PaydayDayPicker(selection: $selection)
                .padding(.top, 16)

            // the info box and the save button (design)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(Color.appPrimary)
                Text(changeNote)
                    .font(.app(14)).lineSpacing(2).foregroundStyle(Color.appBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            Spacer(minLength: 12)

            PrimaryButton(title: L("Simpan"), isLoading: isSaving, action: done)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .disabled(isSaving)
        .presentationDetents([.height(context == .settings ? 680 : 660)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
        .onDisappear { if !didFinish { onDone(nil) } }
    }

    private var isChanged: Bool {
        (selection ?? PaydaySetting.day) != PaydaySetting.day
    }

    /// "25 Okt – 24 Nov": what the next period looks like once the picked day takes over.
    private var nextPeriodLabel: String {
        let day = selection ?? PaydaySetting.day ?? 1
        let current = PaydayCycle.current.period(containing: Date())
        let next = PaydayCycle(day: day).period(containing: current.end)
        let end = Calendar.current.date(byAdding: .day, value: -1, to: next.end) ?? next.end
        return PaydayCycle.dayMonth.string(from: next.start) + " – " + PaydayCycle.dayMonth.string(from: end)
    }

    /// What saving does. The server decides the real date; this mirrors its rule for the copy
    /// (a correction applies now for a new account, else at the end of the running period).
    private var changeNote: String {
        let cycle = PaydayCycle.current
        guard let day = selection, day != PaydaySetting.day, !cycle.schedule.isEmpty,
              Date().timeIntervalSince1970 - memberSince > 7 * 86_400 else {
            return L("Periode budget dan ringkasan bulan ini langsung mengikuti tanggal baru.")
        }
        let period = cycle.period(containing: Date())
        return L("Perubahan ini berlaku mulai %@. Periode berjalan (%@ - %@) tetap memakai tanggal gajian lama supaya angka bulan ini dan bulan-bulan lalu tidak berubah.",
                 PaydayCycle.dayMonth.string(from: period.end), PaydayCycle.dayMonth.string(from: period.start),
                 cycle.lastDayLabel())
    }

    private func done() {
        guard let day = selection, day != PaydaySetting.day else { dismiss(); return }
        isSaving = true
        errorMessage = nil
        Task {
            if await savePayday(day) {
                didFinish = true
                dismiss()
                onDone(day)
            } else {
                isSaving = false
                errorMessage = L("Gagal menyimpan tanggal gajian. Coba lagi.")
            }
        }
    }
}
