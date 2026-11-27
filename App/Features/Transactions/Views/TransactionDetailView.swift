import SwiftUI

/// Transaction detail in the add form's style: a panel in the type colour, the details
/// below, then what the transaction did to the budget or balances. Delete asks first and
/// can be undone for a few seconds.
///
/// Every row edits in place: changes wait in the draft fields until Simpan.
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
    @State private var activeBudgets: [Budget] = []
    @State private var allTransactions: [Transaction] = []
    /// The 0% plan this card purchase is split into, if any.
    @State private var installment: CardInstallment?
    /// The recurring bill made from this transaction (Enhancement "Cicilan dan berulang setelah transaksi"), if any.
    @State private var subscription: CardSubscription?
    @State private var planKind: TransactionPlanSheet.Kind?
    @State private var payoffItem: RunningInstallment?
    @State private var isEntered = false

    // Draft: what the rows show; `txn` stays the saved version until Simpan.
    @State private var amount = 0
    @State private var categoryId: String?
    @State private var accountId: String?
    @State private var targetId: String?
    @State private var date = Date()
    @State private var note = ""
    @State private var isEditingAmount = false
    /// The type being edited (expense or income can switch), and the installment / recurring bill waiting for Simpan.
    @State private var draftType: Transaction.TransactionType
    @State private var draftRepeat: CardSubscription.Frequency?
    @State private var draftMonths = 0
    @State private var showsRepeatSheet = false
    @State private var showsInstallmentSheet = false
    @State private var dragX: CGFloat = 0
    @State private var sheet: PickerKind?
    @State private var preferences: [CategoryPreference] = []
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var errorMessage: String?
    @State private var closesAfterAlert = false
    @FocusState private var noteFocused: Bool

    enum PickerKind: String, Identifiable {
        case category, account, target, date
        var id: String { rawValue }
    }

    @State private var isConfirmingDelete = false
    @State private var pendingDelete: Task<Void, Never>?

    init(transaction: Transaction, categories: [Category], accounts: [Account], isEditable: Bool = true, onUpdate: ((Transaction) -> Void)? = nil) {
        self.categories = categories
        self.isEditable = isEditable
        self.onUpdate = onUpdate
        _txn = State(initialValue: transaction)
        _accounts = State(initialValue: accounts)
        _draftType = State(initialValue: transaction.type)
        _amount = State(initialValue: Int(transaction.amount))
        _categoryId = State(initialValue: transaction.categoryId)
        _accountId = State(initialValue: transaction.accountId)
        _targetId = State(initialValue: transaction.counterpartyAccountId)
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.description ?? "")
    }

    private struct PlanSheetID: Identifiable {
        let kind: TransactionPlanSheet.Kind
        var id: Int { kind == .installment ? 0 : 1 }
    }

    private var style: TransactionStyle { .of(draftType) }
    private var category: Category? { categories.first { $0.id == categoryId } }
    private var account: Account? { accounts.first { $0.id == accountId } }
    private var counterparty: Account? { accounts.first { $0.id == targetId } }
    /// The wallet the saved transaction sits on: installments and bills belong to it, not to a draft pick.
    private var savedAccount: Account? { accounts.first { $0.id == txn.accountId } }
    private var isTransfer: Bool { draftType == .transfer }
    private var isAdjustment: Bool { draftType == .adjustment }
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
                if isEditingAmount {
                    amountSummary
                    Spacer(minLength: 0)
                    AmountPad(color: .appPrimary, isEnabled: amount > 0, onPress: press,
                              onSave: { withAnimation(.settle(0.3)) { isEditingAmount = false } }, title: "Selesai")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            rows
                            planActions
                            others
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 96)
                        // exactly as wide as the screen: a long note or amount can no longer make the detail scroll sideways
                        .containerRelativeFrame(.horizontal)
                    }
                    .sheetScrollSlack()
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .opacity(isDeleted ? 0.3 : 1)
            .allowsHitTesting(!isDeleted)
            .animation(.easeInOut(duration: 0.4), value: isDeleted)

            if !isEditingAmount, !noteFocused, isDirty {
                footer
                    .opacity(isDeleted ? 0.3 : 1)
                    .allowsHitTesting(!isDeleted)
            }
        }
        .background(Color.appBackground)
        .confirmDialog(isPresented: $isConfirmingDelete, icon: "trash", destructive: true,
                       title: L("Hapus transaksi ini?"), message: deleteSubtitle,
                       confirmTitle: L("Hapus")) { isConfirmingDelete = false; startDelete() }
        .confirmDialog(isPresented: $isConfirmingDiscard, icon: "arrow.uturn.backward", destructive: true,
                       title: L("Buang perubahan?"), message: L("Perubahan yang belum disimpan akan hilang."),
                       confirmTitle: L("Buang")) { isConfirmingDiscard = false; dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .background(KeepSwipeBack())
        .hidesTabBarWhilePushed()
        .tint(.white)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            isEntered = true
        }
        .task { await loadContext() }
        .task { preferences = (try? await SupabaseRepository.shared.fetchCategoryPreferences()) ?? [] }
        .onDisappear {
            // Leaving during the undo window still deletes.
            if pendingDelete != nil { finishDelete(now: true) }
        }
        .sheet(item: Binding(get: { planKind.map(PlanSheetID.init) }, set: { planKind = $0?.kind })) { id in
            if let savedAccount, let userId = authViewModel.currentUser?.id {
                TransactionPlanSheet(kind: id.kind, txn: txn, account: savedAccount, category: categories.first { $0.id == txn.categoryId }, plan: installment,
                                     subscription: nil, userId: userId, onDone: {})
            }
        }
        .sheet(isPresented: $showsInstallmentSheet) {
            InstallmentChoiceSheet(selected: draftMonths,
                                   onSelect: { months in withAnimation(.settle(0.3)) { draftMonths = months } },
                                   onDone: { showsInstallmentSheet = false })
        }
        .sheet(isPresented: $showsRepeatSheet) {
            RepeatChoiceSheet(selected: draftRepeat, amount: Double(amount), accountName: account?.name,
                              date: { RepeatChoiceSheet.nextDate(from: date, $0) },
                              onSelect: { value in withAnimation(.settle(0.3)) { draftRepeat = value } },
                              onDone: { showsRepeatSheet = false })
        }
        .sheet(item: $payoffItem) { item in
            if let card = savedAccount, let userId = authViewModel.currentUser?.id {
                InstallmentPayoffSheet(item: item, card: card, wallets: accounts.filter { $0.isActive && !$0.isCreditCard && !$0.isInvestment },
                                       categories: categories, userId: userId, onDone: { Task { await loadContext() } })
            }
        }
        .sheet(item: $sheet) { pickerSheet($0) }
        .alert("Gagal menyimpan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { if closesAfterAlert { dismiss() } }
        } message: { Text(errorMessage ?? "") }
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
        activeBudgets = ((try? await budgets) ?? []).filter(\.isActive)
        self.allTransactions = allTransactions
        if txn.type == .expense, let card = savedAccount, card.isCreditCard {
            installment = (try? await SupabaseRepository.shared.fetchInstallments(accountIds: [card.id]))?
                .first { $0.transactionId == txn.id }
        } else {
            installment = nil
        }
        subscription = txn.type == .expense ? (try? await SupabaseRepository.shared.fetchSubscription(sourceTransactionId: txn.id)) ?? nil : nil
        draftMonths = savedMonths
        draftRepeat = savedRepeat
    }

    // MARK: - Installment and recurring from here (C1)

    private var runningPlan: RunningInstallment? {
        guard let installment else { return nil }
        return RunningInstallments.compute(installments: [installment], transactions: [txn], accounts: accounts, periodEnd: Date()).first
    }

    private var savedMonths: Int { installment?.months ?? 0 }
    private var savedRepeat: CardSubscription.Frequency? { subscription?.isActive == true ? subscription?.frequency : nil }

    /// The two exclude each other (C2): turn the other off first.
    private func openInstallment() {
        if draftRepeat != nil {
            ToastCenter.shared.show(L("Matikan berulangnya dulu untuk membuatnya cicilan."), icon: .error)
        } else if let installment, !installment.isUntouchedByBilling(billed: billedParts(of: installment)) {
            planKind = .installment   // part of it is billed: only the explanation
        } else {
            showsInstallmentSheet = true
        }
    }

    private func billedParts(of plan: CardInstallment) -> Int {
        savedAccount.map { CreditStatement.billedParts(of: plan, purchaseDate: txn.date, card: $0) } ?? 0
    }

    /// "Lunasi lebih cepat" for a running installment; setting or changing it is the chip under the amount.
    @ViewBuilder private var planActions: some View {
        if isEditable, draftType == .expense, !isDeleted, installment != nil, draftMonths > 0,
           let running = runningPlan, running.settlement == nil, running.remainingParts > 0 {
            action(L("Lunasi lebih cepat"), "checkmark.circle") { payoffItem = running }
                .padding(.horizontal, 24)
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

    // MARK: - Panel

    private static let types = TransactionStyle.entryTypes
    private var typeIndex: Int { Self.types.firstIndex { $0.type == draftType } ?? 0 }
    /// Expense and income switch by swiping the panel, like the add page; any other type keeps its label.
    private var canSwitchType: Bool { canChange && (txn.type == .expense || txn.type == .income) }
    private let switchable = 0...1

    private var panel: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button("Tutup") { close() }.font(.app(17))
                    Spacer()
                }
                if canSwitchType { typeDots }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .zIndex(1)

            if canSwitchType {
                typeCarousel.padding(.top, 4)
            } else {
                Label(typeLabel, systemImage: typeIcon)
                    .font(.app(13, weight: .semibold))
                    .labelStyle(PillLabelStyle())
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            HStack(alignment: .top, spacing: 4) {
                Text(amountSign + "Rp")
                    .font(.app(22))
                    .opacity(0.75)
                    .padding(.top, 8)
                Text((isAdjustment ? abs(signedAdjustment) : Double(amount)).formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            // a tap, not a Button: a swipe that starts on the amount still switches the type
            .onTapGesture {
                guard canChange else { return }
                noteFocused = false
                withAnimation(.settle(0.3)) { isEditingAmount = true }
            }
            .padding(.top, 10)
            .accessibilityElement()
            .accessibilityLabel(L("Nominal Rp%@", amount.formatted()))
            .accessibilityAddTraits(canChange ? .isButton : [])

            heroChips
        }
        .rise(isEntered, y: 14, fade: 0.5, move: 0.6)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(style.color)
                .animation(.easeInOut(duration: 0.45), value: draftType)
                .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .gesture(typeSwipe, including: canSwitchType ? .all : .subviews)
    }

    /// The add page's type strip: the current type large, its neighbour faded, sliding as you swipe.
    private var typeCarousel: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = 180
            HStack(spacing: 0) {
                ForEach(Self.types.indices, id: \.self) { i in
                    let isCurrent = i == typeIndex
                    HStack(spacing: 8) {
                        Image(systemName: Self.types[i].icon).font(.system(size: 17, weight: .bold))
                        Text(Self.types[i].label)
                    }
                    .font(.app(22, weight: .bold))
                    .frame(width: itemWidth, height: 44)
                    .opacity(isCurrent ? 1 : switchable.contains(i) ? 0.45 : 0.15)
                    .scaleEffect(isCurrent ? 1 : 0.8)
                    .animation(.settle(0.38), value: typeIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { setType(i) }
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                }
            }
            .offset(x: (geo.size.width - itemWidth) / 2 - CGFloat(typeIndex) * itemWidth + dragX)
        }
        .frame(height: 44)
        .clipped()
    }

    private var typeSwipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                var dx = value.translation.width
                if (typeIndex == switchable.lowerBound && dx > 0) || (typeIndex == switchable.upperBound && dx < 0) { dx *= 0.3 }
                dragX = dx
            }
            .onEnded { _ in
                let dx = dragX
                let next = dx < -40 ? typeIndex + 1 : dx > 40 ? typeIndex - 1 : typeIndex
                withAnimation(.settle(0.46)) { dragX = 0 }
                setType(min(max(next, switchable.lowerBound), switchable.upperBound))
            }
    }

    private var typeDots: some View {
        HStack(spacing: 6) {
            ForEach(Self.types.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: i == typeIndex ? 18 : 6, height: 6)
                    .opacity(i == typeIndex ? 1 : 0.5)
            }
        }
        .animation(.settle(0.3), value: typeIndex)
        .accessibilityHidden(true)
    }

    /// The category belongs to the old type, so it is cleared; the other kinds of plan do not apply to income.
    private func setType(_ index: Int) {
        guard switchable.contains(index), index != typeIndex else { return }
        noteFocused = false
        withAnimation(.settle(0.46)) { draftType = Self.types[index].type }
        categoryId = nil
        if draftType != .expense { draftRepeat = nil; draftMonths = 0 }
    }

    private var amountSign: String {
        isAdjustment ? (signedAdjustment < 0 ? "−" : "+") : style.sign
    }

    /// Balance adjustments and card payments have no rows to edit; so does a Workspace you can only read.
    private var canEdit: Bool { !isAdjustment && txn.type != .cardPayment }
    private var canChange: Bool { isEditable && canEdit && !isDeleted }

    // MARK: - Draft

    private var isDirty: Bool {
        guard canChange else { return false }
        let saved = (txn.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return draftType != txn.type || draftRepeat != savedRepeat || draftMonths != savedMonths || Int(txn.amount) != amount || categoryId != txn.categoryId || accountId != txn.accountId
            || (isTransfer && targetId != txn.counterpartyAccountId) || abs(date.timeIntervalSince(txn.date)) >= 1
            || note.trimmingCharacters(in: .whitespacesAndNewlines) != saved
    }

    private func close() {
        if isDirty { isConfirmingDiscard = true } else { dismiss() }
    }

    private func resetDraft(to saved: Transaction) {
        draftType = saved.type
        draftRepeat = savedRepeat
        draftMonths = savedMonths
        amount = Int(saved.amount)
        categoryId = saved.categoryId
        accountId = saved.accountId
        targetId = saved.counterpartyAccountId
        date = saved.date
        note = saved.description ?? ""
    }

    /// Batal: the rows go back to what is saved and the page stays.
    private func discardDraft() {
        withAnimation(.settle(0.3)) { resetDraft(to: txn) }
    }

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.snappy(duration: 0.2)) { amount = next }
    }

    /// What the draft would do to the wallets, as a transaction that is not saved.
    private var draftTxn: Transaction {
        Transaction(id: txn.id, accountId: accountId ?? txn.accountId, counterpartyAccountId: isTransfer ? targetId : nil, categoryId: categoryId,
                    amount: Double(amount), type: draftType, description: txn.description, note: txn.note, date: date, delta: txn.delta)
    }

    // MARK: - Hero

    @ViewBuilder private var heroChips: some View {
        if hasChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    attributionChip
                    if canRepeat {
                        chip("repeat", draftRepeat.map {
                            ($0 == .yearly ? L("Tiap tahun") : L("Tiap bulan")) + " · " + TransactionDates.dayMonth.string(from: RepeatChoiceSheet.nextDate(from: date, $0))
                        }, empty: L("Buat berulang")) { openRepeat() }
                    }
                    if canInstall {
                        chip("calendar.badge.clock", draftMonths > 0 ? L("Cicilan %lld bulan", draftMonths) : nil, empty: L("Atur cicilan")) { openInstallment() }
                    }
                }
                .padding(.horizontal, 24)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, 14)
        }
    }

    /// A recurring bill only for an expense that is not itself one; an installment only for a card expense.
    private var canRepeat: Bool { isEditable && draftType == .expense && !isDeleted && !txn.isRecurring }
    private var canInstall: Bool { canRepeat && savedAccount?.isCreditCard == true }

    private func openRepeat() {
        if draftMonths > 0 {
            ToastCenter.shared.show(L("Matikan cicilan dulu"), icon: .error)
        } else {
            showsRepeatSheet = true
        }
    }

    private var hasChips: Bool {
        (workspace.showsAttribution && workspace.member(txn.recorderId) != nil) || canRepeat
    }

    /// Like the draft cards: translucent while empty ("Buat berulang"), white with the value once set.
    private func chip(_ icon: String, _ value: String?, empty: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(value ?? empty).font(.app(14, weight: value == nil ? .medium : .semibold)).lineLimit(1)
            }
            .foregroundStyle(value == nil ? Color.white : style.color)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(value == nil ? Color.white.opacity(0.18) : Color.white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!canChange)
    }

    /// Who recorded it (K17): the photo and the name, plus the editor when someone else changed it last (K24).
    @ViewBuilder private var attributionChip: some View {
        if workspace.showsAttribution, let by = workspace.member(txn.recorderId) {
            let editor = workspace.member(txn.updatedBy)
            let name = editor.map { $0.id != by.id ? L("%@ · diubah %@", by.name, $0.name) : by.name } ?? by.name
            HStack(spacing: 8) {
                MemberAvatar(member: by, size: 24)
                Text(name).font(.app(14, weight: .semibold)).lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(.white.opacity(0.18), in: Capsule())
        }
    }

    struct BudgetImpact {
        let name: String
        let cap: Double
        let used: Double
        var left: Double { cap - used }
    }

    /// The category's budget with this transaction counted at its draft amount and category.
    private var draftBudget: BudgetImpact? {
        guard draftType == .expense, let id = categoryId, let budget = activeBudgets.first(where: { $0.categoryId == id }), budget.amount > 0 else { return nil }
        var spent = budget.spentInCurrentPeriod(transactions: allTransactions)
        if txn.categoryId == id { spent = max(0, spent - txn.amount) }
        return BudgetImpact(name: category?.name ?? budget.name, cap: budget.amount, used: spent + Double(amount))
    }

    /// While the keypad is open: what it was, what changed and what is left of the budget.
    private var amountSummary: some View {
        let diff = Double(amount) - txn.amount
        return VStack(spacing: 16) {
            HStack {
                Text(L("Sebelumnya")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text("Rp" + txn.amount.formattedAsDigits()).font(.app(16, weight: .medium))
            }
            HStack {
                Text(L("Selisih")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text((diff < 0 ? "−Rp" : "+Rp") + abs(diff).formattedAsDigits()).font(.app(16, weight: .medium))
            }
            if let b = draftBudget {
                VStack(spacing: 10) {
                    HStack {
                        Text(L("Budget %@", b.name)).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                        Spacer(minLength: 12)
                        Text(b.left < 0 ? L("lewat Rp%@", (-b.left).abbreviatedRupiah()) : L("sisa Rp%@", b.left.abbreviatedRupiah()))
                            .font(.app(16, weight: .medium))
                    }
                    let filled = Int((min(1, b.used / b.cap) * 30).rounded())
                    HStack(spacing: 2) {
                        ForEach(0..<30, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1).fill(i < filled ? style.color : Color.appDivider)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: - Rows

    private var activeAccounts: [Account] { accounts.filter(\.isActive).sorted { $0.isDefault && !$1.isDefault } }
    private var cashWallets: [Account] { activeAccounts.filter { !$0.isInvestment && !$0.isCreditCard } }
    private var investmentWallets: [Account] { activeAccounts.filter(\.isInvestment) }

    /// A transfer to or from an investment wallet keeps that side locked to the right kind of wallet.
    private enum AssetMode { case deposit, withdraw }
    private var assetMode: AssetMode? {
        if savedAccount?.isInvestment == true { return .withdraw }
        if accounts.first(where: { $0.id == txn.counterpartyAccountId })?.isInvestment == true { return .deposit }
        return nil
    }
    private var sourceAccounts: [Account] {
        guard isTransfer else { return WalletRules.spendingSources(activeAccounts) }
        switch assetMode {
        case .deposit: return cashWallets
        case .withdraw: return investmentWallets
        case nil: return activeAccounts
        }
    }
    private var targetAccounts: [Account] {
        switch assetMode {
        case .deposit: return investmentWallets
        case .withdraw: return cashWallets
        case nil: return WalletRules.transferTargets(from: account, in: activeAccounts)
        }
    }

    /// The picker's categories in the user's order; a hidden one stays when this transaction already uses it.
    private var typeCategories: [Category] {
        let kind: CategoryType = draftType == .income ? .income : .expense
        let lists = categories.filter { $0.type == kind && !CategoryCatalog.isSystem($0) }.arranged(by: preferences)
        var shown = lists.shown
        if let id = txn.categoryId, let kept = lists.hidden.first(where: { $0.id == id }) { shown.append(kept) }
        return shown
    }

    private var rows: some View {
        VStack(spacing: 0) {
            noteRow
            if isTransfer {
                pickRow(.account, label: L("Dari"), value: account?.name ?? "—", wallet: account, index: 1)
                pickRow(.target, label: L("Ke"), value: counterparty?.name ?? "—", wallet: counterparty, index: 2)
            } else if isAdjustment {
                pickRow(.account, label: L("Dompet"), value: account?.name ?? "—", wallet: account, index: 1)
            } else {
                pickRow(.category, label: L("Kategori"), value: category?.name ?? L("Belum dipilih"), categoryMark: category, isPlaceholder: category == nil, index: 1)
                pickRow(.account, label: L("Dompet"), value: account?.name ?? "—", wallet: account, index: 2)
                if let installment, draftMonths > 0, let card = savedAccount {
                    installmentRow(installment, months: draftMonths, card: card)
                }
            }
            pickRow(.date, label: L("Tanggal"), value: TransactionDates.long(date, withYear: false), icon: "calendar", index: 3)
            if txn.isRecurring {
                DetailRow(label: L("Sumber"), value: L("Tagihan berulang · otomatis"), icon: "repeat", height: 50, showsSeparator: false)
                    .rise(isEntered, y: 12, delay: 0.5, fade: 0.4, move: 0.5)
            }
        }
    }

    /// "Judul": the note, typed in place.
    private var noteRow: some View {
        HStack(spacing: 12) {
            Text(L("Judul"))
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
            if canChange {
                TextField(L("Tambah judul"), text: $note)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .submitLabel(.done)
                    .focused($noteFocused)
                    .onSubmit { noteFocused = false }
            } else {
                Text(note.isEmpty ? "—" : note)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                .opacity(canChange ? 1 : 0)
        }
        .frame(height: 50)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rise(isEntered, y: 12, delay: 0.18, fade: 0.4, move: 0.5)
    }

    private func pickRow(_ kind: PickerKind, label: String, value: String, wallet: Account? = nil, categoryMark: Category? = nil,
                         icon: String? = nil, isPlaceholder: Bool = false, index: Int) -> some View {
        Button {
            noteFocused = false
            sheet = kind
        } label: {
            DetailRow(label: label, value: value, wallet: wallet, categoryMark: categoryMark, icon: icon, showsChevron: canChange, height: 50, isPlaceholder: isPlaceholder, showsSeparator: false)
        }
        .buttonStyle(.plain)
        .disabled(!canChange)
        .rise(isEntered, y: 12, delay: 0.18 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    /// "Cicilan 6 bulan · Rp…/bulan" and how many parts the statements have billed so far.
    private func installmentRow(_ plan: CardInstallment, months: Int, card: Account) -> some View {
        let billed = CreditStatement.billedParts(of: plan, purchaseDate: txn.date, card: card)
        let monthly = txn.amount / Double(max(1, months))
        return VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: L("Cicilan"), value: L("%lld bulan · Rp%@/bulan", months, monthly.formattedAsDigits()),
                      icon: "calendar.badge.clock", height: 50, showsSeparator: false)
            VStack(alignment: .leading, spacing: 8) {
                SegmentBar(value: Double(billed) / Double(max(1, months)), count: months, height: 6, spacing: 3)
                Text("\(billed) dari \(months) sudah ditagih")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .rise(isEntered, y: 12, delay: 0.3, fade: 0.4, move: 0.5)
    }

    /// "Lainnya": delete, a red row like "Hapus Workspace".
    @ViewBuilder private var others: some View {
        if isEditable {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Lainnya"))
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 4)
                Button { isConfirmingDelete = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").font(.system(size: 17)).frame(width: 24)
                        Text(L("Hapus transaksi")).font(.app(16, weight: .medium))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                    }
                    .foregroundStyle(Color.appError)
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pickers

    @ViewBuilder private func pickerSheet(_ kind: PickerKind) -> some View {
        switch kind {
        case .category:
            CategoryPickerSheet(title: L("Kategori"), categories: typeCategories, selectedId: categoryId, frequentIds: [],
                                onDone: { sheet = nil }) { cat in
                categoryId = cat.id
                closeSheet()
            }
        case .account, .target:
            WalletPickerSheet(title: kind == .target ? L("Ke dompet") : (isTransfer ? L("Dari dompet") : L("Dompet")),
                              accounts: kind == .target ? targetAccounts : sourceAccounts,
                              selectedId: kind == .target ? targetId : accountId,
                              mainId: activeAccounts.first(where: \.isDefault)?.id, recentIds: [],
                              onDone: { sheet = nil }, onPick: { acc in
                choose(acc, for: kind)
                closeSheet()
            })
        case .date:
            PickerSheet(title: L("Tanggal"), actionTitle: nil, onDone: { sheet = nil }) {
                DayPicker(selected: date, color: style.color) { day in
                    date = keepingTime(of: date, on: day)
                    closeSheet()
                }
            }
        }
    }

    private func closeSheet() {
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            sheet = nil
        }
    }

    /// Picking the other side of a transfer swaps the two wallets.
    private func choose(_ acc: Account, for kind: PickerKind) {
        if kind == .target {
            if acc.id == accountId { accountId = targetId }
            targetId = acc.id
        } else {
            if isTransfer, acc.id == targetId {
                targetId = account.flatMap { WalletRules.canTransfer(from: acc, to: $0) ? $0.id : nil }
                    ?? WalletRules.transferTargets(from: acc, in: activeAccounts).first?.id
            }
            accountId = acc.id
        }
    }

    /// Moves `date` to `day` but keeps its time, so edits don't reset a recorded time to midnight.
    private func keepingTime(of date: Date, on day: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }

    // MARK: - Save

    private func save() {
        guard isDirty, !isSaving else { return }
        guard amount > 0 else { errorMessage = L("Nominal belum diisi."); return }
        guard let account else { return }
        guard isTransfer || categoryId != nil else { errorMessage = L("Pilih kategori dulu."); return }
        if isTransfer, targetId == nil || targetId == account.id {
            errorMessage = L("Pilih dompet tujuan yang berbeda.")
            return
        }
        // A transfer into or out of an asset cannot exceed what the source holds (the saved amount is already out of it).
        if isTransfer, assetMode != nil {
            let available = account.balance + (account.id == txn.accountId ? txn.amount : 0)
            if Double(amount) > available {
                let money = "Rp" + available.formattedAsDigits()
                errorMessage = assetMode == .withdraw ? L("Melebihi nilai %@ %@", account.name, money) : L("Melebihi saldo %@ %@", account.name, money)
                return
            }
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            do {
                let updated = try await SupabaseRepository.shared.updateTransaction(
                    id: txn.id, accountId: account.id, counterpartyAccountId: isTransfer ? targetId : nil,
                    categoryId: isTransfer ? nil : categoryId, amount: Double(amount), type: draftType,
                    description: trimmed.isEmpty ? nil : trimmed, note: txn.note, date: date)
                try await applyPlans(to: updated, wallet: account)
                txn = updated
                isSaving = false
                onUpdate?(updated)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                ToastCenter.shared.show(L("Perubahan tersimpan"), icon: .success)
                await loadContext()
                resetDraft(to: updated)
            } catch is CancellationError {
                isSaving = false
            } catch {
                isSaving = false
                // A8 (7): another member deleted this record meanwhile
                let text = String(describing: error)
                if text.contains("PGRST116") || text.contains("transaction_not_found") || text.contains("0 rows") {
                    errorMessage = L("Catatan ini sudah dihapus oleh anggota lain.")
                    closesAfterAlert = true
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The installment and the recurring bill held until Simpan: written now, after the transaction itself.
    private func applyPlans(to updated: Transaction, wallet: Account) async throws {
        let repo = SupabaseRepository.shared
        if draftRepeat != savedRepeat {
            if let frequency = draftRepeat {
                await NotificationManager.shared.requestPermissionIfNeeded()
                let day = CardInstallment.dateOnly.string(from: RepeatChoiceSheet.nextDate(from: updated.date, frequency))
                let bill: CardSubscription
                if let existing = subscription {
                    bill = try await repo.updateSubscription(id: existing.id, name: existing.name, amount: existing.amount, frequency: frequency,
                                                             nextBillingDate: day, isActive: true, categoryId: existing.categoryId, note: existing.note)
                } else {
                    bill = try await repo.createSubscription(accountId: wallet.id, name: updated.displayNote ?? category?.name ?? "Tagihan", amount: updated.amount,
                                                             frequency: frequency, nextBillingDate: day, categoryId: updated.categoryId, note: nil, sourceTransactionId: updated.id)
                }
                await NotificationManager.shared.schedule(for: bill)
            } else if let existing = subscription {
                _ = try await repo.updateSubscription(id: existing.id, name: existing.name, amount: existing.amount, frequency: existing.frequency,
                                                      nextBillingDate: existing.nextBillingDate, isActive: false, categoryId: existing.categoryId, note: existing.note)
                await NotificationManager.shared.cancel(for: existing)
            }
        }
        if draftMonths != savedMonths {
            if draftMonths == 0 {
                if let installment { try await repo.deleteInstallment(id: installment.id) }
            } else if let installment {
                try await repo.updateInstallmentMonths(id: installment.id, months: draftMonths)
            } else {
                try await repo.createInstallment(accountId: wallet.id, transactionId: updated.id, months: draftMonths,
                                                 startsFrom: InstallmentConversion.startsFrom(purchaseDate: updated.date, card: wallet))
            }
        }
    }

    // MARK: - Footer

    /// Shown once something changed. Batal puts the rows back and stays on the page.
    private var footer: some View {
        SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, secondary: L("Batal"),
                         onPrimary: save, onSecondary: discardDraft)
        .padding(.horizontal, 24)
        .padding(.bottom, Self.footerBottomPadding)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Delete

    private var deleteSubtitle: String {
        let amount = "Rp" + txn.amount.formattedAsDigits()
        guard let account = savedAccount else { return L("Transaksi akan dihapus.") }
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
        if txn.type == .expense, let name = categories.first(where: { $0.id == txn.categoryId })?.name, activeBudgets.contains(where: { $0.categoryId == txn.categoryId }) {
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

/// A page with its own header hides the system bar, which also switches the edge-swipe back off: turn it back on.
private struct KeepSwipeBack: UIViewControllerRepresentable {
    final class Host: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}
}
