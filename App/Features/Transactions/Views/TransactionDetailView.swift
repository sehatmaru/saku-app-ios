import SwiftUI

/// Transaction detail in the add form's style: a panel in the type colour, the details
/// below, then what the transaction did to the budget or balances. Delete asks first and
/// can be undone for a few seconds.
///
/// Edit reopens the add form prefilled with this transaction.
struct TransactionDetailView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var workspace = WorkspaceStore.shared
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
    /// The recurring bill made from this transaction (Enhancement "Cicilan dan berulang setelah transaksi"), if any.
    @State private var subscription: CardSubscription?
    @State private var planKind: TransactionPlanSheet.Kind?
    @State private var payoffItem: RunningInstallment?
    @State private var isEntered = false

    @State private var showsForm = false

    @State private var isConfirmingDelete = false
    @State private var pendingDelete: Task<Void, Never>?

    init(transaction: Transaction, categories: [Category], accounts: [Account], isEditable: Bool = true, onUpdate: ((Transaction) -> Void)? = nil) {
        self.categories = categories
        self.isEditable = isEditable
        self.onUpdate = onUpdate
        _txn = State(initialValue: transaction)
        _accounts = State(initialValue: accounts)
    }

    private struct PlanSheetID: Identifiable {
        let kind: TransactionPlanSheet.Kind
        var id: Int { kind == .installment ? 0 : 1 }
    }

    private var style: TransactionStyle { .of(txn.type) }
    private var category: Category? { categories.first { $0.id == txn.categoryId } }
    private var account: Account? { accounts.first { $0.id == txn.accountId } }
    private var counterparty: Account? { accounts.first { $0.id == txn.counterpartyAccountId } }
    private var isTransfer: Bool { txn.type == .transfer }
    private var isAdjustment: Bool { txn.type == .adjustment }
    /// A transfer into a card pays its bill: debt goes down, not an expense.
    private var isBillPayment: Bool { isTransfer && counterparty?.isCreditCard == true }
    private var typeLabel: String { isBillPayment ? L("Bayar tagihan") : style.label }
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
                        planActions
                        impact
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                    // exactly as wide as the screen: a long note or amount can no longer make the detail scroll sideways
                    .containerRelativeFrame(.horizontal)
                }
                .sheetScrollSlack()
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .opacity(isDeleted ? 0.3 : 1)
            .allowsHitTesting(!isDeleted)
            .animation(.easeInOut(duration: 0.4), value: isDeleted)

            if isEditable {
                deleteButton
                    .opacity(isDeleted ? 0.3 : 1)
                    .allowsHitTesting(!isDeleted)
            }
        }
        .background(Color.appBackground)
        .confirmDialog(isPresented: $isConfirmingDelete, icon: "trash", destructive: true,
                       title: L("Hapus transaksi ini?"), message: deleteSubtitle,
                       confirmTitle: L("Hapus")) { isConfirmingDelete = false; startDelete() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .hidesTabBarWhilePushed()
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .sheet(item: Binding(get: { planKind.map(PlanSheetID.init) }, set: { planKind = $0?.kind })) { id in
            if let account, let userId = authViewModel.currentUser?.id {
                TransactionPlanSheet(kind: id.kind, txn: txn, account: account, category: category, plan: installment,
                                     subscription: subscription, userId: userId, onDone: { Task { await loadContext() } })
            }
        }
        .sheet(item: $payoffItem) { item in
            if let card = account, let userId = authViewModel.currentUser?.id {
                InstallmentPayoffSheet(item: item, card: card, wallets: accounts.filter { $0.isActive && !$0.isCreditCard && !$0.isInvestment },
                                       categories: categories, userId: userId, onDone: { Task { await loadContext() } })
            }
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
        async let budgets = SupabaseRepository.shared.fetchBudgets(userId: userId)
        // The month of this transaction and everything since come from the shared store, not a download of the whole history.
        let store = TransactionStore.shared
        try? await store.ensureLoaded(userId: userId, since: PaydayCycle.current.period(containing: txn.date).start)
        if let fetched = try? await fetchedAccounts { accounts = fetched }
        let calendar = Calendar.current
        let allTransactions = store.transactions
        monthTransactions = allTransactions.filter {
            PaydayCycle.current.contains($0.date, periodOf: txn.date, calendar: calendar)
        }
        let active = ((try? await budgets) ?? []).filter(\.isActive)
        monthlyBudget = active.reduce(0) { $0 + $1.amount }
        if var budget = active.first(where: { $0.categoryId == txn.categoryId && txn.type == .expense }) {
            budget.spent = budget.spentInCurrentPeriod(transactions: allTransactions)
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
        subscription = txn.type == .expense ? (try? await SupabaseRepository.shared.fetchSubscription(sourceTransactionId: txn.id)) ?? nil : nil
    }

    // MARK: - Installment and recurring from here (C1)

    private var runningPlan: RunningInstallment? {
        guard let installment else { return nil }
        return RunningInstallments.compute(installments: [installment], transactions: [txn], accounts: accounts, periodEnd: Date()).first
    }

    /// "Jadikan cicilan" / "Jadikan berulang", or the way to manage what is already set. Only when C2 allows it.
    @ViewBuilder private var planActions: some View {
        if isEditable, txn.type == .expense, !isDeleted {
            let canInstall = account?.isCreditCard == true
            VStack(spacing: 0) {
                if installment != nil {
                    action(L("Kelola cicilan"), "calendar.badge.clock") { planKind = .installment }
                    if let running = runningPlan, running.settlement == nil, running.remainingParts > 0 {
                        action(L("Lunasi lebih cepat"), "checkmark.circle") { payoffItem = running }
                    }
                } else if subscription != nil {
                    action(L("Atur berulang"), "repeat") { planKind = .recurring }
                } else if !txn.isRecurring {
                    if canInstall { action(L("Jadikan cicilan"), "calendar.badge.clock") { planKind = .installment } }
                    action(L("Jadikan berulang"), "repeat") { planKind = .recurring }
                }
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Color.appPrimary).frame(width: 24)
                Text(title).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if let note = txn.recurringName ?? txn.displayNote { return note }
        if isTransfer { return "\(account?.name ?? "?") → \(counterparty?.name ?? "?")" }
        return category?.name ?? style.label
    }

    /// Balance adjustments and card payments have no form to edit them in.
    private var canEdit: Bool { !isAdjustment && txn.type != .cardPayment }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 0) {
            if isTransfer {
                row(label: L("Dari"), value: account?.name ?? "—", wallet: account, index: 0)
                row(label: L("Ke"), value: counterparty?.name ?? "—", wallet: counterparty, index: 1)
            } else if isAdjustment {
                row(label: L("Dompet"), value: account?.name ?? "—", wallet: account, index: 0)
            } else {
                row(label: L("Kategori"), value: category?.name ?? "—", categoryMark: category, index: 0)
                row(label: L("Dompet"), value: account?.name ?? "—", wallet: account, index: 1)
                if let installment, let card = account {
                    installmentRow(installment, card: card)
                }
            }
            row(label: L("Tanggal"), value: TransactionDates.long(txn.date, withYear: false), icon: "calendar", index: 2)
            if txn.isRecurring {
                row(label: L("Sumber"), value: L("Tagihan berulang · otomatis"), icon: "repeat", index: 2)
            }
            row(label: L("Catatan"), value: txn.description?.isEmpty == false ? txn.description! : "—", icon: "square.and.pencil", index: 3)
            if workspace.showsAttribution, let by = workspace.member(txn.recorderId) {
                memberRow(label: L("Dicatat"), member: by, sub: nil, index: 4)
                if let editor = workspace.member(txn.updatedBy), editor.id != by.id {
                    let when = Workspace.parseTimestamp(txn.updatedAtRaw ?? "").map { TransactionDates.long($0, withYear: false) }
                    memberRow(label: L("Diubah"), member: editor, sub: when, index: 5)
                }
            }
        }
    }

    /// Who recorded or last changed it (K17, K24): the photo, the name and, for a change, when.
    private func memberRow(label: String, member: WorkspaceMember, sub: String?, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
            MemberAvatar(member: member, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name).font(.app(16, weight: .medium)).foregroundStyle(Color.appText).lineLimit(1)
                if let sub { Text(sub).font(.app(12)).foregroundStyle(Color.appTextSecondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 50)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
        .rise(isEntered, y: 12, delay: 0.18 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    private func row(label: String, value: String, wallet: Account? = nil, categoryMark: Category? = nil, icon: String? = nil, index: Int) -> some View {
        DetailRow(label: label, value: value, wallet: wallet, categoryMark: categoryMark, icon: icon, height: 50)
            .rise(isEntered, y: 12, delay: 0.18 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    /// "Cicilan 6 bulan · Rp…/bulan" and how many parts the statements have billed so far.
    private func installmentRow(_ plan: CardInstallment, card: Account) -> some View {
        let billed = CreditStatement.billedParts(of: plan, purchaseDate: txn.date, card: card)
        let monthly = txn.amount / Double(max(1, plan.months))
        return VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: L("Cicilan"), value: L("%lld bulan · Rp%@/bulan", plan.months, monthly.formattedAsDigits()),
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
            Text(txn.type == .expense ? L("Dampak ke budget") : L("Dampak ke saldo"))
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
            var items = account.map { [balanceItem($0, sub: L("Transaksi ini +Rp%@", txn.amount.formattedAsDigits()))] } ?? []
            items.append(cashflowItem)
            return items
        case .transfer:
            return [account, counterparty].compactMap { $0 }.map { balanceItem($0, sub: transferSub(for: $0)) }
        case .adjustment:
            let change = (signedAdjustment < 0 ? "−Rp" : "+Rp") + abs(signedAdjustment).formattedAsDigits()
            return account.map { [balanceItem($0, sub: L("Penyesuaian %@", change))] } ?? []
        case .cardPayment:
            return account.map { [balanceItem($0, sub: L("Tagihan turun Rp%@", txn.amount.formattedAsDigits()))] } ?? []
        }
    }

    /// Wording follows what the transfer did to each side: a card's balance is debt, so money
    /// into it lowers the bill and cash out of it raises the bill.
    private func transferSub(for wallet: Account) -> String {
        let isCredit = Dictionary(accounts.map { ($0.id, $0.isCreditCard) }, uniquingKeysWith: { first, _ in first })
        let effect = SupabaseRepository.balanceEffects(of: txn, isCredit: isCredit)
            .filter { $0.0 == wallet.id }.reduce(0) { $0 + $1.1 }
        let amount = "Rp" + abs(effect).formattedAsDigits()
        if wallet.isCreditCard { return effect < 0 ? L("Tagihan turun %@", amount) : L("Tagihan naik %@", amount) }
        return effect < 0 ? L("Keluar %@", amount) : L("Masuk %@", amount)
    }

    private var impactNote: String? {
        switch txn.type {
        case .transfer where isBillPayment: L("Bayar tagihan kartu kredit bukan pengeluaran, jadi tidak memengaruhi budget.")
        case .transfer: L("Transfer antar dompet tidak memengaruhi budget.")
        case .expense where budgetItems.isEmpty: L("Belum ada budget untuk transaksi ini.")
        default: nil
        }
    }

    private func balanceItem(_ account: Account, sub: String) -> ImpactItem {
        ImpactItem(label: account.isCreditCard ? L("Tagihan %@", account.name) : L("Saldo %@", account.name),
                   value: L("%@ sekarang", rupiah(account.balance)), sub: sub)
    }

    private var cashflowItem: ImpactItem {
        let income = monthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = monthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let net = income - expense
        return ImpactItem(label: L("Net cashflow %@", Self.monthName.string(from: txn.date)),
                          value: (net < 0 ? "−Rp" : "+Rp") + abs(net).formattedAsDigits(),
                          valueColor: net < 0 ? .appError : .appPrimary,
                          sub: L("Masuk Rp%@ · keluar Rp%@", income.abbreviatedRupiah(), expense.abbreviatedRupiah()))
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
                label: L("Budget %@", TransactionDates.dayShort(txn.date)),
                value: left < 0 ? L("Lewat Rp%@", (-left).formattedAsDigits()) : L("Sisa Rp%@", left.formattedAsDigits()),
                valueColor: left < 0 ? .appError : .appTextSecondary,
                ticks: Self.ticks(used: used, amount: amount, cap: daily),
                sub: L("Rp%@ + Rp%@ ini, dari Rp%@", used.formattedAsDigits(), amount.formattedAsDigits(), daily.formattedAsDigits())
            ))
        }
        if let budget = categoryBudget, budget.amount > 0 {
            let used = max(0, budget.spent - amount)
            let left = budget.amount - budget.spent
            let ratio = budget.spent / budget.amount
            items.append(ImpactItem(
                label: category?.name ?? budget.name,
                value: left < 0 ? L("Lewat Rp%@", (-left).formattedAsDigits()) : L("Sisa Rp%@", left.formattedAsDigits()),
                valueColor: ratio > 1 ? .appError : ratio >= 0.75 ? .appWarning : .appTextSecondary,
                ticks: Self.ticks(used: used, amount: amount, cap: budget.amount),
                sub: L("%lld%% terpakai · %lld hari lagi di %@", Int((ratio * 100).rounded()), Int(budget.daysRemaining), Self.monthName.string(from: Date()))
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
        HStack(spacing: 12) {
            if canEdit {
                Button { showsForm = true } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.appBackground)
                        .frame(width: 50, height: 50)
                        .background(Color.appText, in: Circle())
                }
                .accessibilityLabel(L("Ubah"))
            }
            Button { isConfirmingDelete = true } label: {
                Label("Hapus", systemImage: "trash")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "D93636"), in: Capsule())
            }
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24)
        .padding(.bottom, Self.footerBottomPadding)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var deleteSubtitle: String {
        let amount = "Rp" + txn.amount.formattedAsDigits()
        guard let account else { return L("Transaksi akan dihapus.") }
        let restored: Double
        switch txn.type {
        case .expense: restored = account.balance + (account.isCreditCard ? -txn.amount : txn.amount)
        case .income: restored = account.balance - (account.isCreditCard ? -txn.amount : txn.amount)
        case .transfer where isBillPayment:
            return L("%@ akan kembali ke %@ dan tagihan %@ naik lagi.", amount, account.name, counterparty?.name ?? L("kartu"))
        case .transfer: return L("%@ akan kembali ke %@ dan keluar dari %@.", amount, account.name, counterparty?.name ?? L("dompet tujuan"))
        case .adjustment: restored = account.balance - signedAdjustment
        case .cardPayment: restored = account.balance + txn.amount
        }
        let base = account.isCreditCard ? L("Tagihan %@ kembali jadi %@", account.name, rupiah(restored)) : L("Saldo %@ kembali jadi %@", account.name, rupiah(restored))
        if txn.type == .expense, let name = category?.name, categoryBudget != nil {
            return L("%@ dan budget %@ bertambah %@.", base, name, amount)
        }
        return L("%@.", base)
    }

    /// Hides the transaction and offers Urungkan; the real delete runs when the toast ends.
    private func startDelete() {
        ToastCenter.shared.show(L("Transaksi dihapus"), icon: .trash, undo: .init(run: undoDelete), duration: 3.8)
        pendingDelete = Task {
            try? await Task.sleep(for: .seconds(3.8))
            guard !Task.isCancelled else { return }
            finishDelete(now: false)
        }
    }

    private func undoDelete() {
        pendingDelete?.cancel()
        pendingDelete = nil
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
                ToastCenter.shared.show(L("Gagal menghapus"), icon: .error)
            }
        }
    }

    /// Card surface that stays distinct from the black page in dark mode.

    /// "Rp1.450.000", or "−Rp…" for a negative balance.
    private func rupiah(_ value: Double) -> String {
        (value < 0 ? "−Rp" : "Rp") + value.formattedAsDigits()
    }

    private static var monthName: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = AppLanguage.locale
        return f
    }
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
