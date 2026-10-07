import SwiftUI

struct BudgetListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: BudgetListViewModel

    init(viewModel: BudgetListViewModel = BudgetListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    /// Same key as `PaydaySetting`, so the header follows a payday saved anywhere.
    @AppStorage("paydayDay") private var paydayRaw = 0
    /// "Nanti saja" on the "Kapan kamu gajian?" card, per device.
    @AppStorage("paydayCardDismissed") private var isPaydayCardDismissed = false
    /// Tambah budget is showing: for `category` when a row was tapped, else from the pick step.
    @State private var addTarget: AddTarget?

    private struct AddTarget: Identifiable {
        let id = UUID()
        let category: Category?
    }
    @State private var showPaydaySheet = false
    /// Payday the header keeps showing while it fades out to the new period.
    @State private var frozenPayday: Int?
    @State private var isPeriodHidden = false
    /// Row that just got a budget, tinted for a moment.
    @State private var flashId: String?
    @State private var toastText = ""
    @State private var isToastShown = false
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private var setItems: [BudgetListItem] {
        viewModel.budgetItems.filter { $0.budget != nil }
    }

    private var unsetItems: [BudgetListItem] {
        viewModel.budgetItems.filter { $0.budget == nil }
    }

    private var headerPayday: Int? {
        let day = frozenPayday ?? paydayRaw
        return day == 0 ? nil : day
    }

    private var showsPaydayCard: Bool {
        viewModel.hasLoadedOnce && paydayRaw == 0 && !isPaydayCardDismissed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: L("Budget")) {}

                    periodHeader

                    if showsPaydayCard {
                        paydayCard
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }

                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .padding(24)
                    } else if !viewModel.hasLoadedOnce {
                        budgetSkeleton
                    } else {
                        if let error = viewModel.errorMessage {
                            ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                        }
                        if viewModel.budgetItems.isEmpty {
                            emptyState
                        } else {
                            budgetList
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
                .animation(.settle(0.42), value: showsPaydayCard)
            }
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $addTarget) { target in
                if let userId = authViewModel.currentUser?.id {
                    AddBudgetView(viewModel: viewModel, userId: userId, category: target.category) { category in
                        budgetAdded(category)
                    }
                }
            }
            .sheet(isPresented: $showPaydaySheet) {
                PaydaySheet(context: .card) { day in paydayPicked(day) }
            }
            .toast(toastText, isShown: $isToastShown)
            .task {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadBudgets(userId: userId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                guard let userId = authViewModel.currentUser?.id else { return }
                Task {
                    await viewModel.loadBudgets(userId: userId, forceRefresh: true)
                }
            }
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadBudgets(userId: userId, forceRefresh: true)
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            guard let userId = authViewModel.currentUser?.id else { return }
            Task {
                await viewModel.loadBudgets(userId: userId, forceRefresh: true)
            }
        }
    }

    private func showToast(_ text: String) {
        toastText = text
        isToastShown = true
    }

    // MARK: Period

    /// "25 Sep – 24 Okt", days left, and one tick per day of the period.
    private var periodHeader: some View {
        let cycle = PaydayCycle(day: headerPayday ?? 1)
        let days = cycle.days()
        let dayNumber = days.total - days.left
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(cycle.rangeLabel())
                    .font(.app(20, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.appText)
                Spacer()
                Text("\(days.left + 1) hari lagi")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .monospacedDigit()
            // Fills like the category bars below (same tick-by-tick sweep, just ahead of the first row) and only on first open.
            SegmentBar(value: Double(dayNumber) / Double(max(days.total, 1)), count: days.total,
                       delay: 0.3, isActive: !isPeriodHidden, replays: false)
                .id(days.total)
                .padding(.top, 10)
            (Text(headerPayday.map { L("Gajian tiap tanggal %lld", $0) } ?? L("Mengikuti tanggal 1"))
                + Text(" · hari ke-\(dayNumber) dari \(days.total)"))
                .padding(.top, 12)
        }
        .font(.app(13))
        .foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isPeriodHidden ? 0 : 1)
        .offset(y: isPeriodHidden ? 8 : 0)
        .animation(.easeInOut(duration: 0.22), value: isPeriodHidden)
        .accessibilityElement(children: .combine)
    }

    private var paydayCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 19))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 40, height: 40)
                .background(Color.appBackground, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Kapan kamu gajian?")
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text("Kami pakai tanggal ini supaya budget dan ringkasan bulananmu dimulai saat gaji masuk, bukan tanggal 1.")
                    .font(.app(14))
                    .lineSpacing(2)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button {
                        frozenPayday = paydayRaw
                        showPaydaySheet = true
                    } label: {
                        Text("Atur")
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 34)
                            .background(Color.appPrimary, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    Button("Nanti saja") { isPaydayCardDismissed = true }
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Card sheet closed: fade the header out, bring it back on the new period, then say so.
    private func paydayPicked(_ day: Int?) {
        guard day != nil else { frozenPayday = nil; return }
        isPeriodHidden = true
        Task {
            try? await Task.sleep(for: .milliseconds(360))
            frozenPayday = nil
            isPeriodHidden = false
            try? await Task.sleep(for: .milliseconds(140))
            showToast(L("Periode budget diperbarui"))
        }
    }

    // MARK: Budgets

    private var budgetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !setItems.isEmpty {
                SectionHeader(title: L("Per kategori"), trailing: L("%lld aktif", setItems.count))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }
            ForEach(Array(setItems.enumerated()), id: \.element.id) { i, item in
                NavigationLink(destination: budgetDetailDestination(for: item).detailPage()) {
                    BudgetCardView(budget: item.budget, category: item.category,
                                   fillDelay: 0.37 + Double(i) * 0.07, isFillActive: !isPeriodHidden)
                        .padding(.horizontal, 24)
                        .background(flashId == item.category.id ? Color.appPrimary.opacity(0.1) : .clear)
                        .animation(.easeInOut(duration: 0.7), value: flashId)
                }
                .buttonStyle(RowPressStyle())
            }
            if !unsetItems.isEmpty {
                SectionHeader(title: L("Belum diatur"), trailing: "\(unsetItems.count)")
                    .padding(.horizontal, 24)
                    .padding(.top, setItems.isEmpty ? 14 : 22)
                    .padding(.bottom, 4)
                ForEach(unsetItems) { item in
                    Button { addTarget = AddTarget(category: item.category) } label: {
                        unsetRow(item.category)
                            .padding(.horizontal, 24)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            Text("Budget dihitung per kategori. Tiap periode mulai dari nol, sisa tidak terbawa ke periode berikutnya.")
                .font(.app(13))
                .lineSpacing(2)
                .foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 36)
        }
        .padding(.top, 12)
    }

    /// A category without a budget: tap to set one, starting on the amount.
    private func unsetRow(_ category: Category) -> some View {
        let average = viewModel.threeMonthAverage(categoryId: category.id)
        return HStack(spacing: 14) {
            Image(systemName: category.icon ?? "tag")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Text(average > 0
                     ? L("Rata-rata 3 bulan %@", isBalanceVisible ? average.formattedAsCurrency() : "Rp" + hiddenAmount)
                     : L("Belum dipakai"))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Atur")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.appPrimary.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Atur budget")
    }

    private var emptyState: some View {
        EmptyMessage(icon: "chart.pie",
                     title: L("Belum ada budget"),
                     message: L("Atur batas pengeluaran per kategori. Tiap periode mulai dari nol, sisa tidak terbawa."))
            .padding(.horizontal, 40)
            .padding(.top, 70)
    }

    private func budgetAdded(_ category: Category) {
        flashId = category.id
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showToast(L("Budget %@ aktif", category.name))
            try? await Task.sleep(for: .milliseconds(1100))
            flashId = nil
        }
    }

    /// Placeholder rows while budgets load.
    private var budgetSkeleton: some View {
        VStack(spacing: 0) {
            ForEach([0.46, 0.58, 0.40, 0.62, 0.50], id: \.self) { share in
                HStack(spacing: 14) {
                    Circle().fill(Color.appFill).frame(width: 40, height: 40)
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SkeletonBlock(width: geo.size.width * share, height: 14, radius: 7)
                                Spacer()
                                SkeletonBlock(width: geo.size.width * 0.22, height: 14, radius: 7)
                            }
                            SkeletonBlock(height: 4, radius: 2)
                            SkeletonBlock(width: geo.size.width * 0.55, height: 11, radius: 6)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: 80)
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 14)
        .accessibilityLabel("Memuat")
    }

    private func budgetDetailDestination(for item: BudgetListItem) -> BudgetDetailView {
        BudgetDetailView(
            budget: item.budget!,
            category: item.category,
            allTransactions: viewModel.allExpenseTransactions.filter { $0.categoryId == item.category.id },
            accounts: viewModel.accounts,
            onAdjustBudget: { updated in
                Task {
                    let name = updated.name
                    let amount = updated.amount
                    let periodUnit = updated.periodUnit
                    let periodInterval = updated.periodInterval
                    let startDate = updated.startDate
                    let endDate = updated.endDate
                    let isActive = updated.isActive
                    await viewModel.updateBudget(id: updated.id, name: name, amount: amount, periodUnit: periodUnit, periodInterval: periodInterval, startDate: startDate, endDate: endDate, isActive: isActive)
                }
            },
            onUnsetBudget: {
                Task {
                    await viewModel.removeBudget(id: item.budget!.id)
                }
            }
        )
    }
}

/// Budget row: name and status, 30 ticks green / orange from 80% / red from 100%, spent of amount.
struct BudgetCardView: View {
    let budget: Budget?
    let category: Category
    /// Stagger for the segment bar's fill-in, so rows fill one after another.
    var fillDelay: Double = 0
    /// Empties the bar while false, e.g. while the period changes.
    var isFillActive = true

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    var body: some View {
        if let budget {
            row(budget)
        }
    }

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func row(_ budget: Budget) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category.icon ?? "tag")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(category.name)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(statusText(budget))
                        .font(.app(14))
                        .foregroundStyle(budget.progress >= 0.8 ? color(budget) : Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                SegmentBar(value: budget.progress, color: color(budget), delay: fillDelay, isActive: isFillActive, replays: false)
                Text(L("%@ dari %@", money(budget.spent), money(budget.amount)))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func statusText(_ budget: Budget) -> String {
        if budget.remaining < 0 {
            // Big overruns shortened ("Lewat Rp6 M") so the status fits beside the name.
            let over = -budget.remaining
            return L("Lewat %@", over >= 10_000_000 && isBalanceVisible ? "Rp" + over.abbreviatedRupiah() : money(over))
        }
        if budget.remaining == 0 { return L("Habis") }
        // Today still counts as a day to spend in.
        return L("%@/hari", money(budget.remaining / Double(budget.daysRemaining + 1)))
    }

    private func color(_ budget: Budget) -> Color {
        budget.progress >= 1 ? .appError : budget.progress >= 0.8 ? .appWarning : .appPrimary
    }
}
