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

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMM"
        return f
    }()
}

/// Saves the payday on the signed-in user's profile and reloads everything period-based.
@MainActor
private func savePayday(_ day: Int, auth: AuthViewModel) async -> Bool {
    guard let id = auth.currentUser.flatMap({ UUID(uuidString: $0.id) }) else { return false }
    do {
        try await SupabaseSDK.updatePayday(profileId: id, day: day)
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
                chip("Akhir bulan", 31)
                chip("Tidak tentu / tanggal 1", 1)
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
            row("chart.pie", "Budget & ringkasan berjalan", cycle.rangeLabel())
            row("bell", "Pengingat menjelang gajian", cycle.lastDayLabel())
            if day >= 29 {
                row("info.circle", "Di bulan yang lebih pendek, dipakai", "tanggal terakhir")
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

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didFinish = false

    init(context: PaydayContext, onDone: @escaping (Int?) -> Void) {
        self.context = context
        self.onDone = onDone
        _selection = State(initialValue: context == .settings ? PaydaySetting.day : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tanggal gajian")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                if isSaving {
                    ProgressView()
                } else {
                    Button("Selesai", action: done)
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 13)

            Text("Budget, “Aman dipakai” harian, dan ringkasan bulan ini di Beranda dimulai dari tanggal ini.")
                .font(.app(14))
                .lineSpacing(2)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            PaydayDayPicker(selection: $selection)

            PaydayPreview(day: selection ?? PaydaySetting.day ?? 1)
                .padding(.top, 12)

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else if context == .settings {
                Label("Periode budget dan ringkasan bulan ini langsung mengikuti tanggal baru.", systemImage: "info.circle")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .background(Color.appBackground)
        .disabled(isSaving)
        .presentationDetents([.height(context == .settings ? 640 : 610)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
        .onDisappear { if !didFinish { onDone(nil) } }
    }

    private func done() {
        guard let day = selection, day != PaydaySetting.day else { dismiss(); return }
        isSaving = true
        errorMessage = nil
        Task {
            if await savePayday(day, auth: authViewModel) {
                didFinish = true
                dismiss()
                onDone(day)
            } else {
                isSaving = false
                errorMessage = "Gagal menyimpan tanggal gajian. Coba lagi."
            }
        }
    }
}
