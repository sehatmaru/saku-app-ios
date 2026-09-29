import SwiftUI

/// Transaction detail in the add form's style: a panel in the type colour, the details
/// below, then what the transaction did to the budget or balances. Delete asks first and
/// can be undone for a few seconds.
///
/// Edit reopens the add form prefilled with this transaction.
struct TransactionDetailView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    var isEditable = true
    let onUpdate: ((Transaction) -> Void)?

    @State private var txn: Transaction
    @State private var accounts: [Account]
    @State private var monthTransactions: [Transaction] = []
    @State private var monthlyBudget: Double = 0
    @State private var categoryBudget: Budget?
    /// The 0% plan this card purchase is split into, if any.
    @State private var installment: CardInstallment?
    @State private var isEntered = false

    @State private var showsForm = false

    @State private var isConfirmingDelete = false
    @State private var pendingDelete: Task<Void, Never>?
    @State private var toast: Toast?

    private struct Toast: Equatable {
        let message: String
        let icon: String
        var canUndo = false
    }

    init(transaction: Transaction, categories: [Category], accounts: [Account], isEditable: Bool = true, onUpdate: ((Transaction) -> Void)? = nil) {
        self.categories = categories
        self.isEditable = isEditable
        self.onUpdate = onUpdate
        _txn = State(initialValue: transaction)
        _accounts = State(initialValue: accounts)
    }

    private var style: TransactionStyle { .of(txn.type) }
    private var category: Category? { categories.first { $0.id == txn.categoryId } }
    private var account: Account? { accounts.first { $0.id == txn.accountId } }
    private var counterparty: Account? { accounts.first { $0.id == txn.counterpartyAccountId } }
    private var isTransfer: Bool { txn.type == .transfer }
    private var isAdjustment: Bool { txn.type == .adjustment }
    /// A transfer into a card pays its bill: debt goes down, not an expense.
    private var isBillPayment: Bool { isTransfer && counterparty?.isCreditCard == true }
    private var typeLabel: String { isBillPayment ? "Bayar tagihan" : style.label }
    private var typeIcon: String { isBillPayment ? "creditcard" : style.icon }
    private var signedAdjustment: Double { txn.delta ?? txn.amount }
    private var isDeleted: Bool { pendingDelete != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rows
                        impact
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .opacity(isDeleted ? 0.3 : 1)
            .allowsHitTesting(!isDeleted)
            .animation(.easeInOut(duration: 0.4), value: isDeleted)

            if isEditable {
                deleteButton
                    .opacity(isDeleted ? 0.3 : 1)
                    .allowsHitTesting(!isDeleted)
            }

            toastView
            confirmDelete
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Balance adjustments have no form to edit them in.
            if isEditable && !isDeleted && !isAdjustment {
                ToolbarItem(placement: .topBarTrailing) { editControl }
            }
        }
        .tint(.white)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            isEntered = true
        }
        .task { await loadContext() }
        .onDisappear {
            // Leaving during the undo window still deletes.
            if pendingDelete != nil { finishDelete(now: true) }
        }
        .fullScreenCover(isPresented: $showsForm) {
            if let userId = authViewModel.currentUser?.id {
                AddTransactionView(categories: categories, accounts: accounts, userId: userId, onSave: {},
                                   editing: txn, onUpdated: { applied($0) })
            }
        }
    }

    // MARK: - Data

    private func loadContext() async {
        guard let userId = authViewModel.currentUser?.id else { return }
        async let fetchedAccounts = SupabaseRepository.shared.fetchAccounts(userId: userId)
        async let transactions = SupabaseRepository.shared.fetchTransactions(userId: userId)
        async let budgets = SupabaseRepository.shared.fetchBudgets(userId: userId)
        if let fetched = try? await fetchedAccounts { accounts = fetched }
        let calendar = Calendar.current
        monthTransactions = ((try? await transactions) ?? []).filter {
            PaydayCycle.current.contains($0.date, periodOf: txn.date, calendar: calendar)
        }
        let active = ((try? await budgets) ?? []).filter(\.isActive)
        monthlyBudget = active.reduce(0) { $0 + $1.amount }
        if var budget = active.first(where: { $0.categoryId == txn.categoryId && txn.type == .expense }) {
            budget.spent = (try? await SupabaseRepository.shared.fetchBudgetSpent(
                categoryId: budget.categoryId, userId: userId,
                startDate: budget.currentPeriodStart(), endDate: budget.currentPeriodEnd()
            )) ?? 0
            categoryBudget = budget
        } else {
            categoryBudget = nil
        }
        if txn.type == .expense, let card = account, card.isCreditCard {
            installment = (try? await SupabaseRepository.shared.fetchInstallments(accountIds: [card.id]))?
                .first { $0.transactionId == txn.id }
        } else {
            installment = nil
        }
    }

    /// Takes the edited transaction back from the form and refreshes the context.
    private func applied(_ updated: Transaction) {
        txn = updated
        onUpdate?(updated)
        Task { await loadContext() }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            Label(typeLabel, systemImage: typeIcon)
                .font(.app(13, weight: .semibold))
                .labelStyle(PillLabelStyle())
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(.white.opacity(0.18), in: Capsule())

            HStack(alignment: .top, spacing: 4) {
                Text(amountSign + "Rp")
                    .font(.app(22))
                    .opacity(0.75)
                    .padding(.top, 8)
                Text((isAdjustment ? abs(signedAdjustment) : txn.amount).formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Text(title)
                .font(.app(17, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.top, 10)
            Text(TransactionDates.long(txn.date))
                .font(.app(13))
                .opacity(0.8)
                .padding(.top, 4)
        }
        .rise(isEntered, y: 14, fade: 0.5, move: 0.6)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(style.color)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var amountSign: String {
        isAdjustment ? (signedAdjustment < 0 ? "−" : "+") : style.sign
    }

    private var title: String {
        if let note = txn.note, !note.isEmpty { return note }
        if isTransfer { return "\(account?.name ?? "?") → \(counterparty?.name ?? "?")" }
        return category?.name ?? style.label
    }

    private var editControl: some View {
        Button("Edit") { showsForm = true }
            .font(.app(17, weight: .semibold))
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 0) {
            if isTransfer {
                row(label: "Dari", value: account?.name ?? "—", swatch: walletColor(account), index: 0)
                row(label: "Ke", value: counterparty?.name ?? "—", swatch: walletColor(counterparty), index: 1)
            } else if isAdjustment {
                row(label: "Dompet", value: account?.name ?? "—", swatch: walletColor(account), index: 0)
            } else {
                row(label: "Kategori", value: category?.name ?? "—", icon: category?.icon ?? "tag", index: 0)
                row(label: "Dompet", value: account?.name ?? "—", swatch: walletColor(account), index: 1)
                if let installment, let card = account {
                    installmentRow(installment, card: card)
                }
            }
            row(label: "Tanggal", value: TransactionDates.long(txn.date, withYear: false), icon: "calendar", index: 2)
            row(label: "Catatan", value: txn.description?.isEmpty == false ? txn.description! : "—", icon: "square.and.pencil", index: 3)
        }
    }

    private func row(label: String, value: String, swatch: Color? = nil, icon: String? = nil, index: Int) -> some View {
        DetailRow(label: label, value: value, swatch: swatch, icon: icon, height: 50)
            .rise(isEntered, y: 12, delay: 0.18 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    /// "Cicilan 6 bulan · Rp…/bulan" and how many parts the statements have billed so far.
    private func installmentRow(_ plan: CardInstallment, card: Account) -> some View {
        let billed = CreditStatement.billedParts(of: plan, purchaseDate: txn.date, card: card)
        let monthly = txn.amount / Double(max(1, plan.months))
        return VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Cicilan", value: "\(plan.months) bulan · Rp" + monthly.formattedAsDigits() + "/bulan",
                      icon: "calendar.badge.clock", height: 50)
            VStack(alignment: .leading, spacing: 8) {
                SegmentBar(value: Double(billed) / Double(max(1, plan.months)), count: plan.months, height: 6, spacing: 3)
                Text("\(billed) dari \(plan.months) sudah ditagih")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .rowSeparator()
        }
        .rise(isEntered, y: 12, delay: 0.3, fade: 0.4, move: 0.5)
    }

    // MARK: - Impact

    private struct ImpactItem: Identifiable {
        let label: String
        let value: String
        var valueColor: Color = .appText
        /// Segments already used before this transaction, and after it; nil hides the bar.
        var ticks: (before: Int, after: Int, color: Color)?
        let sub: String
        var id: String { label }
    }

    private var impact: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(txn.type == .expense ? "Dampak ke budget" : "Dampak ke saldo")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            ForEach(impactItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.label).font(.app(15, weight: .medium))
                        Spacer(minLength: 0)
                        Text(item.value)
                            .font(.app(15))
                            .foregroundStyle(item.valueColor)
                            .multilineTextAlignment(.trailing)
                    }
                    if let ticks = item.ticks {
                        HStack(spacing: 2) {
                            ForEach(0..<30, id: \.self) { i in
                                let filled = isEntered ? (i < ticks.before ? Color.appText : i < ticks.after ? ticks.color : Color.appDivider) : Color.appDivider
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(filled)
                                    .animation(.easeInOut(duration: 0.2).delay(0.3 + Double(i) * 0.014), value: isEntered)
                            }
                        }
                        .frame(height: 8)
                    }
                    Text(item.sub)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .padding(.vertical, 12)
                .rowSeparator()
            }
            if let note = impactNote {
                Label(note, systemImage: "info.circle")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 12)
            }
        }
        .rise(isEntered, y: 16, delay: 0.42, fade: 0.5, move: 0.6)
    }

    private var impactItems: [ImpactItem] {
        switch txn.type {
        case .expense: return budgetItems
        case .income:
            var items = account.map { [balanceItem($0, sub: "Transaksi ini +Rp" + txn.amount.formattedAsDigits())] } ?? []
            items.append(cashflowItem)
            return items
        case .transfer:
            return [account, counterparty].compactMap { $0 }.map { balanceItem($0, sub: transferSub(for: $0)) }
        case .adjustment:
            let change = (signedAdjustment < 0 ? "−Rp" : "+Rp") + abs(signedAdjustment).formattedAsDigits()
            return account.map { [balanceItem($0, sub: "Penyesuaian " + change)] } ?? []
        }
    }

    /// Wording follows what the transfer did to each side: a card's balance is debt, so money
    /// into it lowers the bill and cash out of it raises the bill.
    private func transferSub(for wallet: Account) -> String {
        let isCredit = Dictionary(accounts.map { ($0.id, $0.isCreditCard) }, uniquingKeysWith: { first, _ in first })
        let effect = SupabaseRepository.balanceEffects(of: txn, isCredit: isCredit)
            .filter { $0.0 == wallet.id }.reduce(0) { $0 + $1.1 }
        let amount = "Rp" + abs(effect).formattedAsDigits()
        if wallet.isCreditCard { return (effect < 0 ? "Tagihan turun " : "Tagihan naik ") + amount }
        return (effect < 0 ? "Keluar " : "Masuk ") + amount
    }

    private var impactNote: String? {
        switch txn.type {
        case .transfer where isBillPayment: "Bayar tagihan kartu kredit bukan pengeluaran, jadi tidak memengaruhi budget."
        case .transfer: "Transfer antar dompet tidak memengaruhi budget."
        case .expense where budgetItems.isEmpty: "Belum ada budget untuk transaksi ini."
        default: nil
        }
    }

    private func balanceItem(_ account: Account, sub: String) -> ImpactItem {
        ImpactItem(label: (account.isCreditCard ? "Tagihan " : "Saldo ") + account.name,
                   value: rupiah(account.balance) + " sekarang", sub: sub)
    }

    private var cashflowItem: ImpactItem {
        let income = monthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = monthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let net = income - expense
        return ImpactItem(label: "Net cashflow " + Self.monthName.string(from: txn.date),
                          value: (net < 0 ? "−Rp" : "+Rp") + abs(net).formattedAsDigits(),
                          valueColor: net < 0 ? .appError : .appPrimary,
                          sub: "Masuk Rp" + income.abbreviatedRupiah() + " · keluar Rp" + expense.abbreviatedRupiah())
    }

    /// Daily budget (this month's budgets ÷ days) and the category's own budget, each with
    /// what was used before this transaction and what it added.
    private var budgetItems: [ImpactItem] {
        var items: [ImpactItem] = []
        let calendar = Calendar.current
        let amount = txn.amount
        if monthlyBudget > 0 {
            let days = Double(calendar.range(of: .day, in: .month, for: txn.date)?.count ?? 30)
            let daily = monthlyBudget / days
            let daySpent = monthTransactions
                .filter { $0.type == .expense && calendar.isDate($0.date, inSameDayAs: txn.date) }
                .reduce(0) { $0 + $1.amount }
            let used = max(0, daySpent - amount)
            let left = daily - daySpent
            items.append(ImpactItem(
                label: "Budget " + TransactionDates.dayShort(txn.date),
                value: left < 0 ? "Lewat Rp" + (-left).formattedAsDigits() : "Sisa Rp" + left.formattedAsDigits(),
                valueColor: left < 0 ? .appError : .appTextSecondary,
                ticks: Self.ticks(used: used, amount: amount, cap: daily),
                sub: "Rp" + used.formattedAsDigits() + " + Rp" + amount.formattedAsDigits() + " ini, dari Rp" + daily.formattedAsDigits()
            ))
        }
        if let budget = categoryBudget, budget.amount > 0 {
            let used = max(0, budget.spent - amount)
            let left = budget.amount - budget.spent
            let ratio = budget.spent / budget.amount
            items.append(ImpactItem(
                label: category?.name ?? budget.name,
                value: left < 0 ? "Lewat Rp" + (-left).formattedAsDigits() : "Sisa Rp" + left.formattedAsDigits(),
                valueColor: ratio > 1 ? .appError : ratio >= 0.75 ? .appWarning : .appTextSecondary,
                ticks: Self.ticks(used: used, amount: amount, cap: budget.amount),
                sub: "\(Int((ratio * 100).rounded()))% terpakai · \(budget.daysRemaining) hari lagi di " + Self.monthName.string(from: Date())
            ))
        }
        return items
    }

    /// Black for spending before this transaction, then this transaction in green, orange or red.
    private static func ticks(used: Double, amount: Double, cap: Double) -> (Int, Int, Color) {
        let ratio = (used + amount) / cap
        let hot: Color = ratio > 1 ? .appError : ratio >= 0.75 ? .appWarning : .appPrimary
        let before = Int((min(1, used / cap) * 30).rounded())
        let after = Int((min(1, (used + amount) / cap) * 30).rounded())
        return (before, after, hot)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button { isConfirmingDelete = true } label: {
            Label("Hapus", systemImage: "trash")
                .font(.app(16, weight: .semibold))
                .foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(light: 0xFDECEC, dark: 0x3A1D1F), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var deleteSubtitle: String {
        let amount = "Rp" + txn.amount.formattedAsDigits()
        guard let account else { return "Transaksi akan dihapus." }
        let restored: Double
        switch txn.type {
        case .expense: restored = account.balance + (account.isCreditCard ? -txn.amount : txn.amount)
        case .income: restored = account.balance - (account.isCreditCard ? -txn.amount : txn.amount)
        case .transfer where isBillPayment:
            return "\(amount) akan kembali ke \(account.name) dan tagihan \(counterparty?.name ?? "kartu") naik lagi."
        case .transfer: return "\(amount) akan kembali ke \(account.name) dan keluar dari \(counterparty?.name ?? "dompet tujuan")."
        case .adjustment: restored = account.balance - signedAdjustment
        }
        let base = (account.isCreditCard ? "Tagihan " : "Saldo ") + account.name + " kembali jadi " + rupiah(restored)
        if txn.type == .expense, let name = category?.name, categoryBudget != nil {
            return base + " dan budget \(name) bertambah \(amount)."
        }
        return base + "."
    }

    private var confirmDelete: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(isConfirmingDelete ? 0.3 : 0)
                .ignoresSafeArea()
                .onTapGesture { isConfirmingDelete = false }
                .allowsHitTesting(isConfirmingDelete)

            VStack(spacing: 6) {
                Circle()
                    .fill(Color(light: 0xFDECEC, dark: 0x3A1D1F))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "trash")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B))
                    }
                Text("Hapus transaksi ini?")
                    .font(.app(17, weight: .semibold))
                    .padding(.top, 8)
                Text(deleteSubtitle)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    Button {
                        isConfirmingDelete = false
                        startDelete()
                    } label: {
                        Text("Hapus")
                            .font(.app(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(hex: "D93636"), in: Capsule())
                    }
                    Button { isConfirmingDelete = false } label: {
                        Text("Batal")
                            .font(.app(16, weight: .medium))
                            .foregroundStyle(Color.appText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(light: 0xF2F2F4, dark: 0x2C2C2E), in: Capsule())
                    }
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 14)
            }
            .foregroundStyle(Color.appText)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(Self.dialogBackground, in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 38, bottomTrailingRadius: 38, topTrailingRadius: 28))
            .padding(.horizontal, 8)
            .offset(y: isConfirmingDelete ? 0 : 420)
        }
        .animation(.settle(0.44), value: isConfirmingDelete)
    }

    /// Hides the transaction and offers Urungkan; the real delete runs when the toast ends.
    private func startDelete() {
        show(Toast(message: "Transaksi dihapus", icon: "trash.fill", canUndo: true), duration: 3.8)
        pendingDelete = Task {
            try? await Task.sleep(for: .seconds(3.8))
            guard !Task.isCancelled else { return }
            finishDelete(now: false)
        }
    }

    private func undoDelete() {
        pendingDelete?.cancel()
        pendingDelete = nil
        toast = nil
    }

    private func finishDelete(now: Bool) {
        pendingDelete?.cancel()
        pendingDelete = nil
        let id = txn.id
        Task {
            do {
                try await SupabaseRepository.shared.softDeleteTransaction(id: id)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                if !now { dismiss() }
            } catch {
                show(Toast(message: "Gagal menghapus", icon: "exclamationmark.circle.fill"))
            }
        }
    }

    // MARK: - Toast

    private func show(_ newToast: Toast, duration: Double = 1.8) {
        withAnimation { toast = newToast }
        Task {
            try? await Task.sleep(for: .seconds(duration))
            if toast == newToast { withAnimation { toast = nil } }
        }
    }

    private var toastView: some View {
        HStack(spacing: 10) {
            Image(systemName: toast?.icon ?? "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: "5CD49A"))
            Text(toast?.message ?? "")
                .font(.app(15, weight: .medium))
            if toast?.canUndo == true {
                Button("Urungkan", action: undoDelete)
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color(hex: "5CD49A"))
                    .padding(.leading, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "111111"), in: Capsule())
        .padding(.bottom, 72)
        .opacity(toast == nil ? 0 : 1)
        .offset(y: toast == nil ? 16 : 0)
        .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.38), value: toast)
        .allowsHitTesting(toast != nil)
    }

    /// Card surface that stays distinct from the black page in dark mode.
    private static let dialogBackground = Color(light: 0xFFFFFF, dark: 0x1C1C1E)

    /// "Rp1.450.000", or "−Rp…" for a negative balance.
    private func rupiah(_ value: Double) -> String {
        (value < 0 ? "−Rp" : "Rp") + value.formattedAsDigits()
    }

    private static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "id_ID")
        return f
    }()
}

/// Small bold icon then the title, for the type pill.
private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12, weight: .bold))
            configuration.title
        }
    }
}
