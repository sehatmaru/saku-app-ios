import SwiftUI

struct WalletDetailView: View {
    let account: Account
    let transactions: [Transaction]
    let categories: [Category]
    let onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double, Double?, String?) async -> Bool)?
    let onDelete: ((String) async -> Bool)?
    let onToggleArchive: ((String, Bool) async -> Bool)?
    let onSetDefault: ((String) async -> Void)?

    @State private var balanceDigits = ""
    @State private var showBalanceKeyboard = false
    @State private var editedName = ""
    @State private var editedIconId: String
    @State private var showIconPicker = false
    @State private var showDeleteAlert = false
    @State private var showArchiveAlert = false
    @State private var showUnarchiveAlert = false
    @State private var showDeleteWarningAlert = false
    @State private var deleteWarningMessage = ""
    @State private var hasConfirmed = false
    @State private var showAllTransactions = false
    @State private var isSaving = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var detailTransaction: Transaction?
    @State private var creditLimitDigits = ""
    @State private var showCreditLimitKeyboard = false
    @State private var editedDueDay: Int
    @State private var showDueDayPicker = false
    @State private var subscriptions: [CardSubscription] = []
    @State private var showAddSubscription = false
    @State private var selectedSubscription: CardSubscription?
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(account: Account, transactions: [Transaction] = [],
         categories: [Category] = [],
         onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double, Double?, String?) async -> Bool)? = nil,
         onDelete: ((String) async -> Bool)? = nil,
         onToggleArchive: ((String, Bool) async -> Bool)? = nil,
         onSetDefault: ((String) async -> Void)? = nil) {
        self.account = account
        self.transactions = transactions
        self.categories = categories
        self.onSave = onSave
        self.onDelete = onDelete
        self.onToggleArchive = onToggleArchive
        self.onSetDefault = onSetDefault
        let digits = String(Int(account.balance))
        _balanceDigits = State(initialValue: digits)
        _editedName = State(initialValue: account.name)
        _editedIconId = State(initialValue: account.icon ?? "")
        let limitDigits = account.creditLimit.map { String(Int($0)) } ?? ""
        _creditLimitDigits = State(initialValue: limitDigits)
        _editedDueDay = State(initialValue: account.dueDay ?? 1)
    }

    private var walletIcon: WalletIcon? {
        WalletIcon.resolve(editedIconId)
    }

    private var hasChanges: Bool {
        !hasConfirmed && (
            editedName != account.name ||
            editedIconId != account.icon ||
            (isCreditCard ? false : balanceDigits != String(Int(account.balance))) ||
            (isCreditCard ? creditLimitDigits != String(Int(account.creditLimit ?? 0)) : false) ||
            (isCreditCard ? editedDueDay != (account.dueDay ?? 1) : false)
        )
    }

    private var thisMonthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return transactions.filter { $0.date >= monthStart && $0.date < nextMonth }
    }

    private var monthlyIncome: Double {
        thisMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var monthlyExpense: Double {
        thisMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showEditCustomSheet = false

    private var isCreditCard: Bool { account.isCreditCard }
    private var canChangeIcon: Bool { account.type != .cash && !isCreditCard && account.isActive }

    /// The account with the unsaved edits applied, so the card follows along while editing.
    private var previewAccount: Account {
        Account(
            id: account.id,
            name: editedName.isEmpty ? account.name : editedName,
            type: account.type,
            icon: editedIconId.isEmpty ? account.icon : editedIconId,
            isArchived: account.isArchived,
            isDefault: account.isDefault,
            openingBalance: account.openingBalance,
            currentBalance: isCreditCard ? account.currentBalance : (Double(balanceDigits) ?? 0),
            creditLimit: isCreditCard ? (Double(creditLimitDigits) ?? 0) : account.creditLimit,
            dueDate: isCreditCard ? String(editedDueDay) : account.dueDate,
            subscriptionsTotal: account.subscriptionsTotal
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WalletCard(account: previewAccount, showsStripAmount: false, isBalanceVisible: isBalanceVisible)
                    .frame(height: 216)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if isCreditCard { creditBar.padding(.horizontal, 24).padding(.top, 16) }

                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                if !account.isActive { archivedNote.padding(.horizontal, 24).padding(.top, 20) }

                transactionsSection
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 28)

                if isCreditCard, account.isActive {
                    SectionDivider()
                    subscriptionsSection
                        .padding(.horizontal, 24)
                        .padding(.vertical, 28)
                }

                SectionDivider()
                detailsSection
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture { if showBalanceKeyboard { showBalanceKeyboard = false } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if hasChanges {
                    if isSaving {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        Button("Simpan") {
                            confirmChanges()
                        }
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                    }
                }
            }
        }
        .alert("Arsipkan Dompet?", isPresented: $showArchiveAlert) {
            Button("Batal", role: .cancel) {}
            Button("Arsipkan") {
                Task {
                    if await onToggleArchive?(account.id, true) ?? true {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("\(account.name) akan diarsipkan dan tidak bisa digunakan untuk transaksi baru.")
        }
        .alert("Aktifkan Dompet?", isPresented: $showUnarchiveAlert) {
            Button("Batal", role: .cancel) {}
            Button("Aktifkan") {
                Task {
                    if await onToggleArchive?(account.id, false) ?? true {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("\(account.name) akan diaktifkan kembali dan bisa digunakan untuk transaksi.")
        }
        .alert("Hapus Dompet?", isPresented: $showDeleteAlert) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                Task {
                    if await onDelete?(account.id) ?? true {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("\(account.name) dan seluruh transaksinya akan dihapus permanen.")
        }
        .alert("Tidak Dapat Menghapus", isPresented: $showDeleteWarningAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteWarningMessage)
        }
        .sheet(isPresented: $showIconPicker) {
            iconPickerSheet
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showBalanceKeyboard {
                AmountKeyboard(amountDigits: $balanceDigits, maxDigits: 12) {
                    showBalanceKeyboard = false
                    confirmChanges()
                }
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showCreditLimitKeyboard {
                AmountKeyboard(amountDigits: $creditLimitDigits, maxDigits: 12) {
                    showCreditLimitKeyboard = false
                }
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showBalanceKeyboard)
        .animation(.easeInOut(duration: 0.25), value: showCreditLimitKeyboard)
        .toast(isPresented: $showToast, message: toastMessage)
        .onChange(of: isNameFocused) { _, newValue in
            if !newValue { confirmChanges() }
        }
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(
                transaction: txn,
                categories: categories,
                accounts: [account],
                isEditable: false,
                onUpdate: nil
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDueDayPicker) {
            dueDaySheet
        }
        .sheet(isPresented: $showAddSubscription) {
            AddSubscriptionView(
                categories: categories,
                account: account,
                existing: selectedSubscription,
                onSave: {
                    showAddSubscription = false
                    Task { await loadSubscriptions() }
                }
            )
            .presentationDetents([.fraction(0.68), .large])
        }
        .task { await loadSubscriptions() }
    }

    // MARK: - Top

    private var creditBar: some View {
        let limit = Double(creditLimitDigits) ?? 0
        let outstanding = account.currentBalance ?? 0
        let utilization = limit > 0 ? outstanding / limit : 0
        return VStack(alignment: .leading, spacing: 6) {
            SegmentBar(value: utilization, color: utilization > 0.8 ? .appError : utilization > 0.5 ? .appWarning : .appPrimary)
            HStack {
                Text("Terpakai \(outstanding.formattedAsCurrency()) · \(Int(utilization * 100))%")
                Spacer()
                Text("Jatuh tempo tgl \(editedDueDay)")
            }
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            if account.isActive {
                if !account.isDefault {
                    detailAction("Jadikan utama", icon: "star") { Task { await onSetDefault?(account.id) } }
                }
                detailAction("Sesuaikan", icon: "slider.horizontal.3", perform: adjust)
                detailAction("Arsipkan", icon: "archivebox") { showArchiveAlert = true }
                detailAction("Hapus", icon: "trash", tint: .appError) {
                    if !transactions.isEmpty {
                        deleteWarningMessage = "Tidak bisa menghapus akun yang masih memiliki transaksi (\(transactions.count) transaksi). Jika tidak lagi digunakan, kamu bisa mengarsipkannya."
                        showDeleteWarningAlert = true
                    } else { showDeleteAlert = true }
                }
            } else {
                detailAction("Aktifkan", icon: "arrow.uturn.backward") { showUnarchiveAlert = true }
                detailAction("Sesuaikan", icon: "slider.horizontal.3", perform: adjust)
            }
        }
    }

    private func adjust() {
        if isCreditCard { showCreditLimitKeyboard = true } else { showBalanceKeyboard = true }
    }

    private func detailAction(_ title: String, icon: String, tint: Color = .appText, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Color.appFill, in: Circle())
                Text(title)
                    .font(.app(12))
                    .foregroundStyle(Color.appBody)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RowPressStyle())
    }

    private var archivedNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 18))
                .foregroundStyle(Color.appWarning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dompet diarsipkan")
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text("Tidak dapat digunakan untuk transaksi baru")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        let monthTxs = thisMonthTransactions
        let displayTxs = showAllTransactions ? monthTxs : Array(monthTxs.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transaksi terakhir")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                if monthTxs.count > 5 {
                    Button(showAllTransactions ? "Sembunyikan" : "Semua (\(monthTxs.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllTransactions.toggle() }
                    }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
                } else {
                    Text("\(monthTxs.count) bulan ini")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }

            if monthTxs.isEmpty {
                Text("Belum ada transaksi bulan ini")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 12)
            } else {
                ForEach(displayTxs) { transaction in
                    Button { detailTransaction = transaction } label: {
                        TransactionRowView(
                            transaction: transaction,
                            categories: categories,
                            accounts: [account],
                            showBalance: isBalanceVisible,
                            showArchivedBadge: !account.isActive
                        )
                        .rowSeparator()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Detail dompet")
                .padding(.horizontal, 24)
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                Text("Nama")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 76, alignment: .leading)
                TextField("Nama", text: $editedName)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .disabled(!account.isActive)
                    .focused($isNameFocused)
                    .submitLabel(.done)
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rowSeparator()

            if account.type != .cash, !isCreditCard {
                Button { if canChangeIcon { showIconPicker = true } } label: {
                    HStack(spacing: 12) {
                        Text("Ikon")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 76, alignment: .leading)
                        WalletIconView(icon: walletIcon, size: 24)
                        Text(walletIcon?.name ?? "Pilih")
                            .font(.app(16, weight: .medium))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                        Spacer()
                        chevron.opacity(canChangeIcon ? 1 : 0)
                    }
                    .frame(height: 52)
                    .padding(.leading, 24)
                    .padding(.trailing, 20)
                    .rowSeparator()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .disabled(!canChangeIcon)
            }

            if isCreditCard {
                let limit = Double(creditLimitDigits) ?? 0
                let outstanding = account.currentBalance ?? 0
                valueRow("Limit", value: limit.formattedAsCurrency()) { showCreditLimitKeyboard = true }
                valueRow("Sisa limit", value: (limit - outstanding).formattedAsCurrency())
                valueRow("Jatuh tempo", value: "Setiap tanggal \(editedDueDay)") { showDueDayPicker = true }
                valueRow("Tagihan", value: outstanding.formattedAsCurrency(), color: .appError)
                valueRow("Bulan ini", value: monthlyExpense > 0 ? abbreviatedAmount(monthlyExpense) : "Rp0", color: .appError)
            } else {
                valueRow("Saldo", value: "Rp" + (balanceDigits.isEmpty ? "0" : balanceDigits.formattedWithThousandSeparator)) {
                    showBalanceKeyboard = true
                }
                monthFlow
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            Text("Ketuk bagian yang ingin diubah, perubahan tersimpan otomatis.")
                .font(.app(13))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 24)
                .padding(.top, 16)
        }
    }

    private func valueRow(_ label: String, value: String, color: Color = .appText, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 96, alignment: .leading)
                Spacer()
                Text(value)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                if action != nil { chevron }
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(action == nil)
    }

    private var monthFlow: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowSplitBar(income: monthlyIncome, expense: monthlyExpense)
            HStack {
                Label(monthlyIncome > 0 ? abbreviatedAmount(monthlyIncome) : "Rp0", systemImage: "arrow.down.left")
                    .foregroundStyle(Color.appPrimary)
                Spacer()
                Label(monthlyExpense > 0 ? abbreviatedAmount(monthlyExpense) : "Rp0", systemImage: "arrow.up.right")
                    .foregroundStyle(Color.appError)
            }
            .font(.app(13))
            .monospacedDigit()
            Text("Pemasukan dan pengeluaran bulan ini")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    // MARK: - Sheets

    private var iconPickerSheet: some View {
        PickerSheet(title: "Ganti ikon", onDone: { showIconPicker = false }) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                ForEach(WalletIcon.icons(for: account.type)) { icon in
                    let isOn = editedIconId == icon.id
                    Button {
                        editedIconId = icon.id
                        showIconPicker = false
                    } label: {
                        iconCell(title: icon.name, isOn: isOn, fill: isOn ? icon.color : Color.appFill) {
                            Text(icon.shortName)
                                .font(.app(11, weight: .heavy))
                                .foregroundStyle(isOn ? Color.white : icon.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
                Button { showEditCustomSheet = true } label: {
                    iconCell(title: "Custom", isOn: false, fill: Color.appFill) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appText)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showEditCustomSheet) {
            CustomIconSheet { text, colorName in
                editedIconId = WalletIcon.customIconId(text: text, colorName: colorName)
                showIconPicker = false
            }
        }
    }

    private func iconCell<Glyph: View>(title: String, isOn: Bool, fill: Color, @ViewBuilder glyph: () -> Glyph) -> some View {
        VStack(spacing: 7) {
            Circle()
                .fill(fill)
                .frame(width: 54, height: 54)
                .overlay { glyph() }
                .scaleEffect(isOn ? 1.08 : 1)
            Text(title)
                .font(.app(12))
                .foregroundStyle(isOn ? Color.appText : Color.appTextSecondary)
                .lineLimit(1)
        }
    }

    private var dueDaySheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { showDueDayPicker = false }
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Button("Simpan") { showDueDayPicker = false; confirmChanges() }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .overlay {
                Text("Tanggal jatuh tempo")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Picker("Tanggal Jatuh Tempo", selection: $editedDueDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal, 24)
        }
        .presentationDetents([.height(300)])
        .presentationBackground(Color.appBackground)
    }

    private func confirmChanges() {
        isSaving = true
        Task {
            let dueDateStr = isCreditCard ? String(editedDueDay) : nil
            let creditLimit = isCreditCard ? (Double(creditLimitDigits) ?? 0) : nil
            let newBalance = Double(balanceDigits) ?? 0
            let success = await onSave?(account.id, editedName.trimmingCharacters(in: .whitespaces), account.type, editedIconId, account.isArchived, newBalance, account.balance, creditLimit, dueDateStr) ?? true
            hasConfirmed = success
            isSaving = false
            toastMessage = success ? "Perubahan berhasil disimpan" : "Gagal menyimpan perubahan"
            withAnimation { showToast = true }
        }
    }

    private func abbreviatedAmount(_ amount: Double) -> String {
        switch amount {
        case 1_000_000_000...:
            String(format: "%.1f Miliar", amount / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.0f Juta", amount / 1_000_000)
        case 1_000...:
            String(format: "%.0f Ribu", amount / 1_000)
        default:
            String(Int(amount))
        }
    }

    // MARK: - Subscriptions

    private func loadSubscriptions() async {
        guard account.isCreditCard else { return }
        do {
            let subs = try await SupabaseRepository.shared.fetchSubscriptions(accountIds: [account.id])
            subscriptions = subs
            await NotificationManager.shared.resyncAll(subscriptions: subs)
        } catch {
            print("❌ loadSubscriptions failed: \(error)")
        }
    }


    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Tagihan berulang", trailing: "Tambah", trailingColor: .appPrimary) {
                selectedSubscription = nil
                showAddSubscription = true
            }
            .padding(.bottom, 4)

            if subscriptions.isEmpty {
                Text("Belum ada tagihan berulang")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 8)
            } else {
                let monthlyTotal = subscriptions.filter { $0.isActive }.reduce(0) { $0 + $1.monthlyAmount }
                let yearlyTotal = subscriptions.filter { $0.isActive }.reduce(0) { $0 + $1.yearlyAmount }
                let projectedBalance = (account.currentBalance ?? account.openingBalance) + monthlyTotal

                ForEach(subscriptions) { sub in
                    subscriptionRow(sub)
                }

                VStack(spacing: 8) {
                    totalRow("Total per bulan", monthlyTotal.formattedAsCurrency(), color: .appError)
                    totalRow("Total per tahun", yearlyTotal.formattedAsCurrency(), color: .appError)
                    if let limit = account.creditLimit {
                        totalRow("Limit tersisa", (limit - projectedBalance).formattedAsCurrency())
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    private func totalRow(_ label: String, _ value: String, color: Color = .appText) -> some View {
        HStack {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value)
                .font(.app(15, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private func subscriptionRow(_ sub: CardSubscription) -> some View {
        let category = sub.categoryId.flatMap { cid in categories.first { $0.id == cid } }
        let iconName = category?.icon ?? "creditcard"

        return HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.app(16))
                    .foregroundStyle(sub.isActive ? Color.appText : Color.appTextSecondary)
                Text(sub.amount.formattedAsCurrency() + " · " + (sub.frequency == .monthly ? "Bulanan" : "Tahunan"))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }

            Spacer()

            if !sub.isActive {
                Text("Nonaktif")
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.appFill, in: Capsule())
            }

            Button {
                Task {
                    try? await SupabaseRepository.shared.deleteSubscription(id: sub.id)
                    await NotificationManager.shared.cancel(for: sub)
                    await loadSubscriptions()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appError)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("Hapus \(sub.name)")
        }
        .padding(.vertical, 12)
        .rowSeparator()
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSubscription = sub
            showAddSubscription = true
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await SupabaseRepository.shared.deleteSubscription(id: sub.id)
                    await NotificationManager.shared.cancel(for: sub)
                    await loadSubscriptions()
                }
            } label: {
                Label("Hapus", systemImage: "trash")
            }
            Button {
                Task {
                    _ = try? await SupabaseRepository.shared.updateSubscription(
                        id: sub.id, name: sub.name, amount: sub.amount,
                        frequency: sub.frequency, nextBillingDate: sub.nextBillingDate,
                        isActive: !sub.isActive, categoryId: sub.categoryId, note: sub.note
                    )
                    await loadSubscriptions()
                }
            } label: {
                Label(sub.isActive ? "Nonaktifkan" : "Aktifkan", systemImage: sub.isActive ? "pause" : "play")
            }
            .tint(.appWarning)
        }
    }
}
