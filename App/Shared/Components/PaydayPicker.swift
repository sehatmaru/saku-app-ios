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
private func savePayday(_ day: Int, from: Date? = nil) async -> Bool {
    do {
        try await SupabaseSDK.updatePayday(day: day, from: from)
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
    /// Called just before a changed day is saved, so the screen behind can hold still until the sheet is gone.
    let onWillSave: () -> Void

    private enum Step { case day, choice }

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didFinish = false
    @State private var step = Step.day
    @State private var options: [PaydayOption] = []
    @State private var chosen: Date?
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    init(context: PaydayContext, onDone: @escaping (Int?) -> Void, onWillSave: @escaping () -> Void = {}) {
        self.context = context
        self.onDone = onDone
        self.onWillSave = onWillSave
        _selection = State(initialValue: context == .settings ? PaydaySetting.day : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step == .day { dayStep } else { choiceStep }

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
        }
        .disabled(isSaving)
        .filterSheet {
            if step == .day {
                SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, secondary: L("Nanti saja"), onPrimary: done, onSecondary: { dismiss() })
            } else {
                SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, secondary: L("Kembali"), onPrimary: saveChoice,
                                 onSecondary: { errorMessage = nil; step = .day })
            }
        }
        .onDisappear { if !didFinish { onDone(nil) } }
    }

    private var dayStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(WorkspaceStore.shared.paydayTitle).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
                Text(L("Periode budget dan ringkasan mulai di tanggal ini."))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L("Periode berjalan")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer(minLength: 8)
                Text(PaydayCycle.current.rangeLabel())
                    .font(.app(17, weight: .medium)).monospacedDigit().foregroundStyle(Color.appText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24).padding(.top, 14)

            PaydayDayPicker(selection: $selection)
                .padding(.top, 12)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(Color.appPrimary).frame(width: 24)
                Text(changeNote)
                    .font(.app(15)).lineSpacing(2).foregroundStyle(Color.appBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 16)
        }
    }

    private var choiceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Kapan tanggal baru mulai berlaku?")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
                Text(L("Gajian pindah ke tanggal %lld. Pilih hasilnya untuk periode berjalan.", selection ?? 0))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            VStack(spacing: 10) {
                ForEach(options) { optionRow($0) }
            }
            .padding(.horizontal, 24).padding(.top, 16)
        }
    }

    private func optionRow(_ option: PaydayOption) -> some View {
        let on = chosen == option.id
        return Button {
            chosen = option.id
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rangeText(option.next)).font(.app(17, weight: .medium)).monospacedDigit().foregroundStyle(Color.appText)
                        + Text(" · " + L("%lld hari", option.days(option.next))).font(.app(17)).foregroundStyle(Color.appTextSecondary)
                    Text(runningNote(option))
                        .font(.app(14)).monospacedDigit().foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.appPrimary : Color.appBorder)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.appFill : .clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? Color.appPrimary : Color.appBorder, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Options that end the running period the same day differ only in when it started, so then that is shown too.
    private func runningNote(_ option: PaydayOption) -> String {
        let end = PaydayCycle.dayMonth.string(from: Calendar.current.date(byAdding: .day, value: -1, to: option.running.end) ?? option.running.end)
        let twin = options.contains { $0.id != option.id && $0.running.end == option.running.end && $0.next == option.next }
        return twin ? L("Periode berjalan mulai %@, berakhir %@", PaydayCycle.dayMonth.string(from: option.running.start), end)
                    : L("Periode berjalan berakhir %@", end)
    }

    private func rangeText(_ period: DateInterval) -> String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        return PaydayCycle.dayMonth.string(from: period.start) + " – " + PaydayCycle.dayMonth.string(from: last)
    }

    /// Saving asks the server how the new day can start; with only one possible result there is nothing to ask.
    private var changeNote: String {
        let cycle = PaydayCycle.current
        guard let day = selection, day != PaydaySetting.day, !cycle.schedule.isEmpty,
              Date().timeIntervalSince1970 - memberSince > 7 * 86_400 else {
            return L("Periode budget dan ringkasan bulan ini langsung mengikuti tanggal baru.")
        }
        return WorkspaceStore.shared.activeIsPersonal
            ? L("Berikutnya kamu memilih kapan tanggal baru mulai berlaku, dengan rentang tanggal hasilnya.")
            : L("Berikutnya kamu memilih kapan tanggal baru mulai berlaku. Perubahan ini berlaku untuk semua anggota Workspace.")
    }

    private func done() {
        guard let day = selection, day != PaydaySetting.day else { dismiss(); return }
        isSaving = true
        errorMessage = nil
        Task {
            // no answer (offline, older server): save the way it always was, the server picks the date
            let choices = (try? await SupabaseSDK.paydayChoices(day: day)) ?? []
            let found = PaydayOption.options(for: choices, day: day)
            if found.count > 1 {
                options = found
                chosen = (found.first { $0.isDefault } ?? found[0]).id
                isSaving = false
                step = .choice
            } else {
                await save(day, from: found.first?.choice.from)
            }
        }
    }

    private func saveChoice() {
        guard let day = selection, let option = options.first(where: { $0.id == chosen }) else { return }
        isSaving = true
        errorMessage = nil
        Task { await save(day, from: option.choice.from) }
    }

    @MainActor private func save(_ day: Int, from: Date?) async {
        onWillSave()
        if await savePayday(day, from: from) {
            didFinish = true
            dismiss()
            onDone(day)
        } else {
            isSaving = false
            errorMessage = L("Gagal menyimpan tanggal gajian. Coba lagi.")
        }
    }
}
