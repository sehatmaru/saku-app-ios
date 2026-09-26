import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget
    let category: Category
    let allTransactions: [Transaction]
    let accounts: [Account]
    var showHistoryButton: Bool = true
    var onAdjustBudget: ((Budget) -> Void)?
    var onUnsetBudget: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var showAllTransactions = false
    @State private var showHistory = false
    @State private var showAdjustBudget = false
    @State private var showUnsetAlert = false
    @State private var adjustAmountText = ""
    @State private var adjustAmountDigits = ""
    @State private var showAdjustConfirm = false
    @State private var pendingAmount: Double = 0

    private enum AdjustScope: String, CaseIterable {
        case thisMonth = "Hanya bulan ini"
        case ongoing = "Bulan ini dan seterusnya"
    }

    @State private var adjustScope: AdjustScope = .thisMonth
    @State private var detailTransaction: Transaction?

    private var transactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return allTransactions.filter { $0.date >= monthStart && $0.date < nextMonth }
    }

    private var displayedTransactions: [Transaction] {
        showAllTransactions ? transactions : Array(transactions.prefix(5))
    }

    private var monthlyHistory: [MonthlySpending] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let grouped = Dictionary(grouping: allTransactions) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))!
        }

        return grouped
            .filter { $0.key < currentMonth }
            .map { month, txs in
                MonthlySpending(month: month, spent: txs.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summaryCard
                    .padding(.horizontal)

                HStack {
                    Text("Transaksi Bulan Ini")
                        .font(.app(15, weight: .semibold))
                    Spacer()
                    Text("\(transactions.count) transaksi")
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal)
                .padding(.top, Spacing.md)

                transactionListContent
                    .padding([.horizontal, .top])

                Color.clear
                    .frame(height: Spacing.xl)
                    .padding(.bottom)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHistory) {
            BudgetHistoryView(budget: budget, category: category, monthlyHistory: monthlyHistory, allTransactions: allTransactions, accounts: accounts)
        }
        .sheet(isPresented: $showAdjustBudget) {
            adjustBudgetSheet
                .presentationDetents([.medium])
                .presentationBackground(Color.appCardBackground)
        }
        .alert("Konfirmasi Perubahan", isPresented: $showAdjustConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Simpan") {
                let updated = Budget(
                    id: budget.id,
                    categoryId: budget.categoryId,
                    name: budget.name,
                    amount: pendingAmount,
                    periodUnit: budget.periodUnit,
                    periodInterval: budget.periodInterval,
                    startDate: budget.startDate,
                    endDate: budget.endDate,
                    isActive: budget.isActive,
                    spent: budget.spent
                )
                onAdjustBudget?(updated)
                showAdjustBudget = false
                dismiss()
            }
        } message: {
            Text("Budget \(category.name) akan diubah menjadi \(String(Int(pendingAmount)).formattedWithThousandSeparator) untuk \"\(adjustScope.rawValue)\".")
        }
        .alert("Hapus Budget?", isPresented: $showUnsetAlert) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                onUnsetBudget?()
                dismiss()
            }
        } message: {
            Text("Budget untuk \(category.name) akan dihapus.")
        }
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(
                transaction: txn,
                categories: [category],
                accounts: accounts,
                isEditable: false
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: category.icon ?? "tag")
                        .font(.app(17, weight: .medium))
                        .foregroundColor(.appPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                    Text("Budget Bulanan")
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)
                }
                Spacer()
                Text(budget.progress >= 1 ? "0%" : "\(Int((1 - budget.progress) * 100))%")
                    .font(.app(15, weight: .semibold))
                    .foregroundColor(progressColor)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(spacing: 0) {
                Text("Rp")
                    .font(.app(28, weight: .bold))
                    .foregroundColor(.appText)
                Text(budget.progress >= 1 ? "0" : budget.remaining.formattedAsCurrency().replacingOccurrences(of: "Rp", with: ""))
                    .font(.app(28, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xs)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Total Budget")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                    Text(budget.amount.formattedAsCurrency())
                        .font(.app(14, weight: .semibold))
                        .foregroundColor(.appText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Terpakai")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                    Text(budget.spent.formattedAsCurrency())
                        .font(.app(14, weight: .semibold))
                        .foregroundColor(.appExpense)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)

            ProgressView(value: min(budget.progress, 1.0))
                .tint(progressColor)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)

            if showHistoryButton {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                Button {
                    showHistory = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.app(13))
                                .foregroundColor(.appPrimary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Riwayat Bulan Sebelumnya")
                                .font(.app(13, weight: .medium))
                                .foregroundColor(.appText)
                            Text("Lihat performa bulan lalu")
                                .font(.app(10))
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.app(10))
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if onAdjustBudget != nil || onUnsetBudget != nil {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                HStack(spacing: Spacing.md) {
                    if onAdjustBudget != nil {
                        Button {
                            adjustAmountText = ""
                            adjustAmountDigits = ""
                            showAdjustBudget = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.app(11))
                                Text("Sesuaikan Budget")
                                    .font(.app(11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appPrimary.opacity(0.1))
                            .foregroundColor(.appPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if onUnsetBudget != nil {
                        Button(role: .destructive) {
                            showUnsetAlert = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "xmark")
                                    .font(.app(11))
                                Text("Hapus Budget")
                                    .font(.app(11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appError.opacity(0.1))
                            .foregroundColor(.appError)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func miniStatCard(icon: String, label: String, amount: String, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.app(11, weight: .semibold))
                        .foregroundColor(color)
                }
            Text(label)
                .font(.app(10))
                .foregroundColor(.appTextSecondary)
            Text(amount)
                .font(.app(12, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var remainingPct: Double {
        budget.progress >= 1 ? 0 : (1 - budget.progress) * 100
    }

    private var progressColor: Color {
        remainingPct <= 0 ? .appError : remainingPct <= 20 ? .appWarning : .appPrimary
    }

    private var adjustBudgetSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                scopePicker
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)

                HStack {
                    Text("Rp")
                        .font(.app(17, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                    TextField("\(String(Int(budget.amount)).formattedWithThousandSeparator)", text: $adjustAmountText)
                        .font(.app(17, weight: .medium))
                        .keyboardType(.numberPad)
                }
                .padding()
                .background(Color.appGroupedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, Spacing.xl)

                Spacer()

                Button("Simpan") {
                    guard let amount = Double(adjustAmountDigits), amount > 0 else { return }
                    pendingAmount = amount
                    showAdjustConfirm = true
                }
                .frame(maxWidth: .infinity)
                .font(.app(17, weight: .semibold))
                .foregroundColor(.appPrimary)
                .disabled(adjustAmountDigits.isEmpty)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle("Sesuaikan Budget \(category.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showAdjustBudget = false
                    }
                }
            }
            .onChange(of: adjustAmountText) { _, newValue in
                let digits = String(newValue.filter { $0.isWholeNumber })
                let formatted = digits.formattedWithThousandSeparator
                if formatted != newValue {
                    adjustAmountText = formatted
                }
                adjustAmountDigits = digits
            }
        }
    }

    private var scopePicker: some View {
        VStack(spacing: Spacing.md) {
            ForEach(Array(AdjustScope.allCases), id: \.self) { scope in
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        adjustScope = scope
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(adjustScope == scope ? Color.appPrimary : Color.appGroupedBackground)
                                .frame(width: 44, height: 44)
                            Image(systemName: scope == .thisMonth ? "calendar.badge.clock" : "calendar.badge.plus")
                                .font(.app(16))
                                .foregroundColor(adjustScope == scope ? .white : .appTextSecondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope.rawValue)
                                .font(.app(14, weight: .semibold))
                                .foregroundColor(adjustScope == scope ? .appPrimary : .appText)
                            Text(scope == .thisMonth ? "Ubah budget hanya untuk bulan berjalan" : "Terapkan untuk bulan ini dan seterusnya")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if adjustScope == scope {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.app(18))
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .background(adjustScope == scope ? Color.appPrimary.opacity(0.06) : Color.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(adjustScope == scope ? Color.appPrimary.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var transactionListContent: some View {
        if transactions.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "tray")
                    .font(.app(32))
                    .foregroundColor(.appTextSecondary)
                Text("Belum ada transaksi")
                    .font(.app(15))
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxxl)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 0) {
                ForEach(displayedTransactions) { transaction in
                    transactionRow(transaction)
                        .contentShape(Rectangle())
                        .onTapGesture { detailTransaction = transaction }
                    if transaction.id != displayedTransactions.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                if transactions.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllTransactions.toggle()
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: showAllTransactions ? "chevron.up" : "chevron.down")
                                .font(.app(10))
                            Text(showAllTransactions ? "Sembunyikan" : "Lihat Semua (\(transactions.count))")
                                .font(.app(12, weight: .medium))
                        }
                        .foregroundColor(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        TransactionRowView(transaction: transaction, categories: [category], accounts: accounts, showAccount: true)
    }
}

// MARK: - Transaction

fileprivate struct MonthlySpending: Identifiable {
    let id = UUID()
    let month: Date
    let spent: Double

    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: month)
    }

    func progress(_ budgetAmount: Double) -> Double {
        budgetAmount > 0 ? spent / budgetAmount : 0
    }

    func remainingPct(_ budgetAmount: Double) -> Double {
        let p = progress(budgetAmount)
        return p >= 1 ? 0 : (1 - p) * 100
    }

    func statusColor(_ budgetAmount: Double) -> Color {
        let r = remainingPct(budgetAmount)
        return r <= 0 ? .appError : r <= 20 ? .appWarning : .appPrimary
    }

    func statusIcon(_ budgetAmount: Double) -> String {
        remainingPct(budgetAmount) <= 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }
}

fileprivate struct BudgetHistoryView: View {
    let budget: Budget
    let category: Category
    let monthlyHistory: [MonthlySpending]
    let allTransactions: [Transaction]
    let accounts: [Account]

    @Environment(\.dismiss) private var dismiss
    @State private var expandedYears: Set<Int> = []

    private var groupedByYear: [(year: Int, items: [MonthlySpending])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: monthlyHistory) { history in
            calendar.component(.year, from: history.month)
        }
        return grouped.map { (year: $0.key, items: $0.value.sorted { $0.month > $1.month }) }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(groupedByYear, id: \.year) { group in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation {
                                    if expandedYears.contains(group.year) {
                                        expandedYears.remove(group.year)
                                    } else {
                                        expandedYears.insert(group.year)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.app(12))
                                        .foregroundColor(.appTextSecondary)
                                    Text(String(group.year))
                                        .font(.app(13, weight: .medium))
                                        .foregroundColor(.appText)
                                    Spacer()
                                    Text("\(group.items.count)")
                                        .font(.app(12, weight: .semibold))
                                        .foregroundColor(.appTextSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.appTextSecondary.opacity(0.15))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.down")
                                        .font(.app(10))
                                        .foregroundColor(.appTextSecondary)
                                        .rotationEffect(.degrees(expandedYears.contains(group.year) ? 180 : 0))
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, Spacing.lg)
                            }
                            .buttonStyle(.plain)

                            if expandedYears.contains(group.year) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, history in
                                        NavigationLink(destination: BudgetMonthDetailView(budget: budget, category: category, month: history.month, allTransactions: allTransactions, accounts: accounts)) {
                                            historyRow(history)
                                        }
                                        .buttonStyle(.plain)
                                        if index < group.items.count - 1 {
                                            Divider()
                                                .padding(.leading, 48)
                                        }
                                    }
                                }
                                .padding(.top, Spacing.sm)
                                .padding(.bottom, Spacing.md)
                                .padding(.horizontal, Spacing.lg)
                            }
                        }
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Riwayat Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        dismiss()
                    }
                    .font(.app(15, weight: .medium))
                }
            }
            .onAppear {
                if expandedYears.isEmpty {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    expandedYears = [currentYear]
                }
            }
        }
    }

    private func historyRow(_ history: MonthlySpending) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(history.statusColor(budget.amount).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: history.statusIcon(budget.amount))
                        .font(.app(11, weight: .semibold))
                        .foregroundColor(history.statusColor(budget.amount))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(history.monthLabel)
                        .font(.app(14, weight: .medium))
                        .foregroundColor(.appText)
                    Text("Budget \(budget.amount.formattedAsCurrency())")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(history.spent.formattedAsCurrency())
                        .font(.app(14, weight: .semibold))
                        .foregroundColor(history.statusColor(budget.amount))
                    Text("\(Int(history.remainingPct(budget.amount)))%")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appCardBackground)
                    .frame(height: 6)
                Capsule()
                    .fill(history.statusColor(budget.amount))
                    .frame(width: nil, height: 6)
                    .scaleEffect(x: min(history.progress(budget.amount), 1), y: 1, anchor: .leading)
            }
        }
        .padding(.vertical, 10)
    }
}

fileprivate struct BudgetMonthDetailView: View {
    let budget: Budget
    let category: Category
    let month: Date
    let allTransactions: [Transaction]
    let accounts: [Account]

    @State private var detailTransaction: Transaction?

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: month)
    }

    private var transactions: [Transaction] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return allTransactions
            .filter { $0.date >= monthStart && $0.date < nextMonth }
            .sorted { $0.date > $1.date }
    }

    private var spent: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private var remaining: Double {
        budget.amount - spent
    }

    private var progress: Double {
        budget.amount > 0 ? spent / budget.amount : 0
    }

    private var remainingPct: Double {
        progress >= 1 ? 0 : (1 - progress) * 100
    }

    private var progressColor: Color {
        remainingPct <= 0 ? .appError : remainingPct <= 20 ? .appWarning : .appPrimary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: category.icon ?? "tag")
                                .font(.app(17, weight: .medium))
                                .foregroundColor(.appPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monthLabel)
                                .font(.app(17, weight: .semibold))
                                .foregroundColor(.appText)
                            Text("Budget \(budget.amount.formattedAsCurrency())")
                                .font(.app(12))
                                .foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                        Text(progress >= 1 ? "0%" : "\(Int((1 - progress) * 100))%")
                            .font(.app(15, weight: .semibold))
                            .foregroundColor(progressColor)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)

                    HStack(spacing: 0) {
                        Text("Rp")
                            .font(.app(28, weight: .bold))
                            .foregroundColor(.appText)
                        Text(progress >= 1 ? "0" : remaining.formattedAsCurrency().replacingOccurrences(of: "Rp", with: ""))
                            .font(.app(28, weight: .bold))
                            .foregroundColor(.appText)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xs)

                    Divider()
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.md)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total Budget")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(budget.amount.formattedAsCurrency())
                                .font(.app(14, weight: .semibold))
                                .foregroundColor(.appText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Terpakai")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(spent.formattedAsCurrency())
                                .font(.app(14, weight: .semibold))
                                .foregroundColor(.appExpense)
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.md)

                    ProgressView(value: min(progress, 1.0))
                        .tint(progressColor)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.lg)
                }
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                HStack {
                    Text("Transaksi")
                        .font(.app(15, weight: .semibold))
                    Spacer()
                    Text("\(transactions.count) transaksi")
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal)
                .padding(.top, Spacing.md)

                if transactions.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "tray")
                            .font(.app(32))
                            .foregroundColor(.appTextSecondary)
                        Text("Belum ada transaksi")
                            .font(.app(15))
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxxl)
                    .background(Color.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding([.horizontal, .top])
                } else {
                    VStack(spacing: 0) {
                        ForEach(transactions) { transaction in
                            transactionRow(transaction)
                                .contentShape(Rectangle())
                                .onTapGesture { detailTransaction = transaction }
                            if transaction.id != transactions.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding([.horizontal, .top])
                }

                Color.clear
                    .frame(height: Spacing.xl)
                    .padding(.bottom)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle(monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(
                transaction: txn,
                categories: [category],
                accounts: accounts,
                isEditable: false
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func miniStatCard(icon: String, label: String, amount: String, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.app(11, weight: .semibold))
                        .foregroundColor(color)
                }
            Text(label)
                .font(.app(10))
                .foregroundColor(.appTextSecondary)
            Text(amount)
                .font(.app(12, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        TransactionRowView(transaction: transaction, categories: [category], accounts: accounts, showAccount: true)
    }
}
