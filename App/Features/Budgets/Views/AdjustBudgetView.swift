import SwiftUI

/// Sesuaikan budget (design 1b): the Tambah budget pattern, green panel plus keypad. Choose how
/// long the new amount applies; Simpan stays off until something changed. Present full screen.
struct AdjustBudgetView: View {
    let budget: Budget
    let category: Category
    @ObservedObject var viewModel: BudgetListViewModel
    var onSaved: () -> Void

    private enum Duration: CaseIterable { case forever, once, several }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var amount: Int
    @State private var duration: Duration = .forever
    @State private var periodCount = 3
    @State private var bump = false
    @State private var isSaving = false
    @State private var showOverspend = false
    @State private var showReplace = false
    @State private var failed = false

    init(budget: Budget, category: Category, viewModel: BudgetListViewModel, onSaved: @escaping () -> Void) {
        self.budget = budget
        self.category = category
        self.viewModel = viewModel
        self.onSaved = onSaved
        _amount = State(initialValue: Int(budget.amount))
    }

    private var cycle: PaydayCycle { .current }
    private var period: DateInterval { cycle.period(containing: Date()) }
    private var daysLeft: Int { budget.daysRemaining + 1 }
    private var baseAmount: Double { budget.baseAmount ?? budget.amount }
    private var average: Double { viewModel.threeMonthAverage(categoryId: category.id) }
    private var count: Int { duration == .forever ? 0 : duration == .once ? 1 : periodCount }
    private var changed: Bool { amount > 0 && (Double(amount) != budget.amount || duration != .forever) }

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func dayMonth(_ date: Date) -> String { PaydayCycle.dayMonth.string(from: date) }

    private func lastDay(ofPeriods n: Int) -> String {
        let end = cycle.period(offset: n - 1).end
        return dayMonth(Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    private func title(_ d: Duration) -> String {
        switch d {
        case .forever: return L("Selamanya")
        case .once: return L("Periode ini")
        case .several: return L("Beberapa")
        }
    }

    private var durationNote: String {
        switch duration {
        case .forever:
            return L("Nominal baru dipakai terus mulai periode ini. Periode lama tidak berubah.")
        case .once:
            return L("Hanya %@ – %@. Setelah itu kembali ke %@.", dayMonth(period.start), lastDay(ofPeriods: 1),
                     baseAmount.formattedAsCurrency())
        case .several:
            return L("Sampai %@, lalu otomatis kembali ke %@.", lastDay(ofPeriods: periodCount), baseAmount.formattedAsCurrency())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            panel
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Berlaku untuk"))
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                durationPicker.padding(.top, 10)
                Text(durationNote)
                    .font(.app(14))
                    .lineSpacing(2)
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                    .padding(.top, 10)
                if duration == .several { stepper.padding(.top, 10) }
                HStack {
                    Text(L("Bisa dipakai · %lld hari lagi", daysLeft)).foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text(perDay).fontWeight(.semibold)
                }
                .font(.app(13))
                .monospacedDigit()
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            Spacer(minLength: 8)
            AmountPad(color: .appPrimary, isEnabled: changed, isSaving: isSaving, onPress: press, onSave: save)
                .disabled(isSaving)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .background(Color.appBackground)
        .confirmDialog(isPresented: $showOverspend, icon: "exclamationmark.triangle",
                       title: L("Budget langsung lewat batas"),
                       message: L("Pengeluaranmu periode ini sudah %@, lebih besar dari %@. Budget akan langsung berstatus lewat batas. Lanjutkan?",
                                  budget.spent.formattedAsCurrency(), Double(amount).formattedAsCurrency()),
                       confirmTitle: L("Lanjutkan")) {
            showOverspend = false
            proceedAfterOverspend()
        }
        .confirmDialog(isPresented: $showReplace, icon: "arrow.triangle.2.circlepath",
                       title: L("Ganti perubahan sementara?"),
                       message: budget.temporary.map {
                           L("Kamu sudah punya budget sementara %@ sampai %@. Yang baru akan menggantikannya.",
                             $0.amount.formattedAsCurrency(), lastDay(of: $0))
                       } ?? "",
                       confirmTitle: L("Ganti"), cancelTitle: L("Tidak jadi")) {
            showReplace = false
            commit()
        }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: L("Perubahan budget belum tersimpan. Coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private var perDay: String {
        let room = Double(amount) - budget.spent
        return room > 0 ? L("≈ %@ per hari", money(room / Double(max(daysLeft, 1)))) : money(0) + "/" + L("hari")
    }

    private func lastDay(of change: BudgetAmountChange) -> String {
        let end = change.effectiveTo ?? Date()
        return dayMonth(Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button { if !isSaving { dismiss() } } label: { Text(L("Batal")).font(.app(17)) }
                Spacer()
            }
            .overlay { Text(L("Sesuaikan budget")).font(.app(17, weight: .semibold)) }
            .frame(height: 44)
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: category.icon ?? "tag")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                    }
                Text(category.name).font(.app(14, weight: .semibold)).lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 30)
            .background(.white.opacity(0.16), in: Capsule())
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 4) {
                Text("Rp").font(.app(22)).opacity(0.75).padding(.top, 8)
                Text(Double(amount).formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(amount > 0 ? 1 : 0.55)
            .scaleEffect(bump ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: bump)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Group {
                if average > 0 {
                    let isOn = Double(amount) == average
                    Button(action: useAverage) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                            Text(L("Rata-rata 3 bulan %@", money(average)))
                        }
                        .font(.app(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Color.appPrimary : .white)
                        .padding(.leading, 10)
                        .padding(.trailing, 14)
                        .frame(height: 32)
                        .background(isOn ? Color.white : Color.white.opacity(0.16), in: Capsule())
                        .animation(.easeInOut(duration: 0.22), value: isOn)
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .frame(height: 32)
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(height: 276)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(Color.appPrimary)
                .overlay {
                    LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: category.icon ?? "tag")
                        .font(.system(size: 170, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.07))
                        .offset(x: 30, y: 50)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
                .ignoresSafeArea(edges: .top)
        }
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            ForEach(Duration.allCases, id: \.self) { d in
                let on = duration == d
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { duration = d }
                } label: {
                    Text(title(d))
                        .font(.app(14, weight: on ? .semibold : .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(on ? Color.appBackground : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private var stepper: some View {
        HStack {
            Text(L("%lld periode", periodCount)).font(.app(16)).monospacedDigit()
            Spacer()
            HStack(spacing: 6) {
                stepButton("minus", enabled: periodCount > 2) { periodCount -= 1 }
                stepButton("plus", enabled: periodCount < 12) { periodCount += 1 }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.appText)
                .frame(width: 36, height: 36)
                .background(Color.appBackground, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(PressScaleStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    // MARK: Logic

    private func pulse() {
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            bump = false
        }
    }

    private func press(_ key: String) {
        guard !isSaving, let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        pulse()
    }

    private func useAverage() {
        guard !isSaving else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = Int(average) }
        pulse()
    }

    private func save() {
        guard changed, !isSaving else { return }
        if Double(amount) < budget.spent {
            showOverspend = true
        } else {
            proceedAfterOverspend()
        }
    }

    private func proceedAfterOverspend() {
        if budget.temporary != nil && duration != .forever {
            showReplace = true
        } else {
            commit()
        }
    }

    private func commit() {
        isSaving = true
        let how: BudgetAmountDuration = duration == .forever ? .forever : .periods(count)
        Task {
            let ok = await viewModel.saveAmount(budget: budget, amount: Double(amount), duration: how)
            isSaving = false
            if ok {
                dismiss()
                onSaved()
            } else {
                failed = true
            }
        }
    }
}
