import SwiftUI

/// Tambah budget (Budget design 2c → 2d): pick an expense category without a budget, then the
/// amount on a green panel. Present full screen; `onAdded` runs after the done state, just
/// before it closes.
struct AddBudgetView: View {
    @ObservedObject var viewModel: BudgetListViewModel
    let userId: String
    var onAdded: (Category) -> Void

    /// With `category`, opens straight on the amount step for it (tapping a row without a budget).
    init(viewModel: BudgetListViewModel, userId: String, category: Category? = nil,
         onAdded: @escaping (Category) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.userId = userId
        self.onAdded = onAdded
        _category = State(initialValue: category)
        _step = State(initialValue: category == nil ? 1 : 2)
        _opensOnAmount = State(initialValue: category != nil)
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var step = 1
    /// Opened from a category row (Atur): there is no category step behind it, so back means cancel.
    @State private var opensOnAmount: Bool
    @State private var category: Category?
    @State private var amount = 0
    @State private var bump = false
    @State private var shake: CGFloat = 0
    @State private var isSaving = false
    @State private var isDone = false
    @State private var errorMessage: String?
    @State private var showsNewCategory = false

    private var cycle: PaydayCycle { .current }
    /// Days left in the period, today included.
    private var daysLeft: Int { cycle.days().left + 1 }
    private var average: Double { category.map { viewModel.threeMonthAverage(categoryId: $0.id) } ?? 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                pickStep
                    .offset(x: step == 2 ? -geo.size.width * 0.3 : 0)
                amountStep
                    // The edge shadow belongs to the page's background alone: on the whole page it
                    // also blurred every number key.
                    .background {
                        Color.appBackground
                            .ignoresSafeArea()
                            .shadow(color: .black.opacity(step == 2 ? 0.08 : 0), radius: 15, x: -10)
                    }
                    .offset(x: step == 2 ? 0 : geo.size.width + 20)
            }
            .animation(.settle(0.48), value: step)
        }
        .background(Color.appBackground)
        .fullScreenCover(isPresented: $showsNewCategory) {
            CategoryFormView(mode: .new(.expense), categories: viewModel.categories, hiddenIds: [],
                             userId: userId) { outcome in
                guard case .saved(let created) = outcome else { return }
                Task { await continueWith(created) }
            }
        }
    }

    /// A category made from here: if its form already set a budget we're done, otherwise go on
    /// to the amount step with it.
    private func continueWith(_ created: Category) async {
        let budgets = (try? await SupabaseRepository.shared.fetchBudgets(userId: userId)) ?? []
        if budgets.contains(where: { $0.categoryId == created.id && $0.isActive }) {
            onAdded(created)
            dismiss()
        } else {
            category = created
            amount = 0
            step = 2
        }
    }

    // MARK: Step 1

    private var pickStep: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
                Spacer()
            }
            .overlay {
                Text("Tambah budget").font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Langkah 1 dari 2")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Pilih kategori")
                            .font(.app(28, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.appText)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    Button { showsNewCategory = true } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .strokeBorder(Color.appBorder, lineWidth: 1.5)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.appPrimary)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kategori baru")
                                    .font(.app(16, weight: .medium))
                                    .foregroundStyle(Color.appPrimary)
                                Text("Buat kategori sekaligus atur budgetnya")
                                    .font(.app(13))
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer()
                            chevron
                        }
                        .frame(height: 64)
                        .padding(.leading, 24)
                        .padding(.trailing, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .padding(.top, 14)

                    Text("Belum punya budget")
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 4)

                    ForEach(viewModel.availableCategories) { item in
                        categoryRow(item)
                    }

                    if viewModel.availableCategories.isEmpty {
                        Text("Semua kategori sudah punya budget.")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }

                    let budgeted = viewModel.visibleBudgets.count
                    if budgeted > 0 {
                        Text("\(budgeted) kategori lain sudah punya budget.")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextTertiary)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .background(Color.appBackground)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    private func categoryRow(_ item: Category) -> some View {
        let avg = viewModel.threeMonthAverage(categoryId: item.id)
        return Button {
            category = item
            amount = 0
            isDone = false
            errorMessage = nil
            step = 2
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon ?? "tag")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 40)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                        Text(L("Rata-rata 3 bulan %@", money(avg)))
                            .font(.app(13))
                            .monospacedDigit()
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 8)
                    chevron
                }
                .frame(height: 64)
                .rowSeparator()
            }
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: Step 2

    private var amountStep: some View {
        VStack(spacing: 0) {
            panel
            if let errorMessage {
                Text(errorMessage)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            Spacer(minLength: 12)
            AmountPad(color: .appPrimary, isEnabled: amount > 0, isSaving: isSaving, onPress: press, onSave: save)
                .disabled(isSaving || isDone)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    guard !isSaving, !isDone else { return }
                    if opensOnAmount { dismiss() } else { step = 1 }
                } label: {
                    if opensOnAmount {
                        Text("Batal").font(.app(17))
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold))
                            Text("Kategori").font(.app(17))
                        }
                    }
                }
                .accessibilityLabel(opensOnAmount ? "Batal" : "Kembali ke kategori")
                Spacer()
            }
            .overlay {
                Text("Langkah 2 dari 2").font(.app(13)).opacity(0.8)
            }
            .frame(height: 44)
            .padding(.horizontal, 12)

            ZStack(alignment: .top) {
                panelContent
                    .opacity(isDone ? 0 : 1)
                    .offset(y: isDone ? -14 : 0)
                    .scaleEffect(isDone ? 0.97 : 1)
                    .animation(.settle(0.42), value: isDone)
                doneContent
            }
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
                    Image(systemName: category?.icon ?? "tag")
                        .font(.system(size: 170, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.07))
                        .offset(x: 30, y: 50)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
                .ignoresSafeArea(edges: .top)
        }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: category?.icon ?? "tag")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                    }
                Text(category?.name ?? "").font(.app(14, weight: .semibold)).lineLimit(1)
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
            .offset(x: shake)
            .animation(.easeOut(duration: 0.12), value: bump)
            .animation(.easeOut(duration: 0.2), value: amount > 0)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .accessibilityElement()
            .accessibilityLabel("Nominal Rp\(amount)")

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
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .frame(height: 32)
            .padding(.top, 14)

            VStack(spacing: 6) {
                infoRow(L("Periode"), L("%@ · %lld hari lagi", cycle.rangeLabel(), daysLeft))
                infoRow(L("Bisa dipakai"), amount > 0 ? L("≈ %@ per hari", money(Double(amount) / Double(daysLeft))) : "—")
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).opacity(0.85)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).lineLimit(1)
        }
        .font(.app(13))
        .monospacedDigit()
    }

    private var doneContent: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                }
                .scaleEffect(isDone ? 1 : 0.4)
                .animation(.spring(duration: 0.56, bounce: 0.5), value: isDone)
            Text("Budget tersimpan")
                .font(.app(20, weight: .semibold))
                .padding(.top, 6)
            Text("\(category?.name ?? "") · \(Double(amount).formattedAsCurrency()) per periode")
                .font(.app(14))
                .opacity(0.85)
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isDone ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isDone)
        .allowsHitTesting(false)
    }

    // MARK: Logic

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func pulse() {
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            bump = false
        }
    }

    private func press(_ key: String) {
        guard !isDone, !isSaving, let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        pulse()
    }

    private func useAverage() {
        guard !isDone, !isSaving else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = Int(average) }
        pulse()
    }

    private func save() {
        guard !isDone, !isSaving else { return }
        guard amount > 0, let category else {
            Task {
                for value: CGFloat in [-10, 9, -6, 4, 0] {
                    withAnimation(.easeInOut(duration: 0.06)) { shake = value }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
            return
        }
        isSaving = true
        errorMessage = nil
        let start = ISO8601DateFormatter().string(from: cycle.period(containing: Date()).start)
        Task {
            let ok = await viewModel.setBudget(categoryId: category.id, name: category.name, amount: Double(amount),
                                               periodUnit: "month", periodInterval: 1,
                                               startDate: start, endDate: nil, userId: userId)
            isSaving = false
            guard ok else {
                errorMessage = L("Gagal menyimpan budget. Coba lagi.")
                return
            }
            isDone = true
            try? await Task.sleep(for: .milliseconds(1400))
            onAdded(category)
            dismiss()
        }
    }
}
