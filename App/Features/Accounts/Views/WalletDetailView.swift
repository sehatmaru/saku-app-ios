import SwiftUI

struct WalletDetailView: View {
    let account: Account
    let transactions: [Transaction]
    let categories: [Category]
    /// Every wallet, for picking where a card bill is paid from.
    let accounts: [Account]
    let installments: [CardInstallment]
    let onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double, Double?, String?, Int?) async -> Bool)?
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
    @State private var editedStatementDay: Int?
    @State private var showStatementDayPicker = false
    @State private var showPaySheet = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(account: Account, transactions: [Transaction] = [],
         categories: [Category] = [],
         accounts: [Account] = [],
         installments: [CardInstallment] = [],
         onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double, Double?, String?, Int?) async -> Bool)? = nil,
         onDelete: ((String) async -> Bool)? = nil,
         onToggleArchive: ((String, Bool) async -> Bool)? = nil,
         onSetDefault: ((String) async -> Void)? = nil) {
        self.account = account
        self.transactions = transactions
        self.categories = categories
        self.accounts = accounts
        self.installments = installments
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
        _editedStatementDay = State(initialValue: account.statementDay)
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
            (isCreditCard ? editedDueDay != (account.dueDay ?? 1) : false) ||
            (isCreditCard ? editedStatementDay != account.statementDay : false)
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
            subscriptionsTotal: account.subscriptionsTotal,
            statementDay: isCreditCard ? editedStatementDay : account.statementDay
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WalletCard(account: previewAccount, showsStripAmount: false, isBalanceVisible: isBalanceVisible, showsUsage: false)
                    .frame(height: 216)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                if !account.isActive { archivedNote.padding(.horizontal, 24).padding(.top, 20) }

                if let statement {
                    statementSection(statement)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                }

                transactionsSection
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 28)

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
            daySheet(title: "Tanggal jatuh tempo", selection: $editedDueDay) { showDueDayPicker = false }
        }
        .sheet(isPresented: $showStatementDayPicker) {
            daySheet(title: "Tanggal cetak tagihan", selection: Binding(
                get: { editedStatementDay ?? defaultStatementDay },
                set: { editedStatementDay = $0 }
            )) {
                showStatementDayPicker = false
                if editedStatementDay == nil { editedStatementDay = defaultStatementDay }
            }
        }
        .sheet(isPresented: $showPaySheet) {
            if let statement {
                PayCardBillSheet(card: account, statement: statement, wallets: accounts)
            }
        }
    }

    // MARK: - Top

    private var statement: CreditStatement? {
        CreditStatement(card: account, transactions: transactions, installments: installments)
    }

    /// Same guess as `CreditStatement` makes for cards without a cut-off day.
    private var defaultStatementDay: Int { (editedDueDay + 15) % 31 + 1 }

    private func statementSection(_ statement: CreditStatement) -> some View {
        let limit = account.creditLimit ?? 0
        let utilization = account.creditUtilization ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            CardBillSummary(statement: statement, isVisible: isBalanceVisible)

            if account.isActive, account.balance > 0 {
                EmptyStateButton(title: "Bayar tagihan", icon: "creditcard", isFullWidth: true) { showPaySheet = true }
                    .padding(.top, 16)
            }

            if account.statementDay == nil, account.isActive {
                Button { showStatementDayPicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appWarning)
                            .frame(width: 24)
                        Text("Atur tanggal cetak tagihan supaya tagihan akurat")
                            .font(.app(15))
                            .foregroundStyle(Color.appBody)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        chevron
                    }
                    .padding(.vertical, 14)
                    .rowSeparator()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .padding(.top, 12)
            }

            statementRow("Belum ditagih", value: masked(statement.unbilled),
                         caption: "masuk tagihan \(TransactionDates.dayMonth.string(from: statement.nextStatementDate))")
            statementRow("Sisa limit", value: masked(account.availableCredit ?? 0),
                         caption: "Terpakai \(masked(account.balance)) dari \(masked(limit))")
            SegmentBar(value: utilization, color: utilization > 0.8 ? .appError : utilization > 0.5 ? .appWarning : .appPrimary)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hari terbaik belanja")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Text("Mulai \(TransactionDates.dayMonth.string(from: statement.bestPurchaseDate)), bayar \(TransactionDates.dayMonth.string(from: statement.bestPurchaseDueDate))")
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                Text("Belanja mulai hari itu dapat waktu bebas bunga paling lama.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.top, 22)
        }
    }

    private func statementRow(_ label: String, value: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Text(caption)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .monospacedDigit()
            }
            Spacer()
            Text(value)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .rowSeparator()
    }

    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
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
                valueRow("Jatuh tempo", value: "Setiap tanggal \(editedDueDay)") { showDueDayPicker = true }
                valueRow("Tanggal cetak tagihan", value: editedStatementDay.map { "Setiap tanggal \($0)" } ?? "Belum diatur") {
                    showStatementDayPicker = true
                }
                valueRow("Total utang", value: outstanding.formattedAsCurrency(), color: .appError)
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
                    .lineLimit(1)
                    .frame(minWidth: 96, alignment: .leading)
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

    private func daySheet(title: String, selection: Binding<Int>, onDone: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { showDueDayPicker = false; showStatementDayPicker = false }
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Button("Simpan") { onDone(); confirmChanges() }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .overlay {
                Text(title)
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Picker(title, selection: selection) {
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
            let statementDay = isCreditCard ? editedStatementDay : nil
            let success = await onSave?(account.id, editedName.trimmingCharacters(in: .whitespaces), account.type, editedIconId, account.isArchived, newBalance, account.balance, creditLimit, dueDateStr, statementDay) ?? true
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

}

// MARK: - Card bill

extension CreditStatement {
    var statusText: String {
        switch status {
        case .none: "Tidak ada tagihan"
        case .unpaid: "Belum dibayar"
        case .partial: "Dibayar sebagian"
        case .paid: "Lunas"
        case .overdue: "Terlambat"
        }
    }

    var statusColor: Color {
        switch status {
        case .overdue: .appError
        case .paid: .appPrimary
        default: .appTextSecondary
        }
    }

    /// "Jatuh tempo 20 Okt · 3 hari lagi"; the countdown only while something is owed.
    var dueText: String {
        let due = "Jatuh tempo " + TransactionDates.dayMonth.string(from: dueDate)
        guard status == .unpaid || status == .partial || status == .overdue else { return due }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: dueDate).day ?? 0
        let left = switch days {
        case ..<0: "lewat \(-days) hari"
        case 0: "hari ini"
        case 1: "besok"
        default: "\(days) hari lagi"
        }
        return due + " · " + left
    }
}

/// What's still owed on a card's last statement, its status and due date.
struct CardBillSummary: View {
    let statement: CreditStatement
    var isVisible = true
    /// One line for the Dompet card overlay.
    var compact = false

    private var title: String { "Tagihan " + TransactionDates.dayMonth.string(from: statement.statementDate) }

    var body: some View {
        if compact {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(isVisible ? statement.remaining.formattedAsCurrency() : "Rp" + hiddenAmount)
                        .font(.app(20, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statement.statusText)
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(statement.statusColor)
                    Text(statement.dueText)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                HeroAmount(value: statement.remaining, size: .medium, isVisible: isVisible)
                Text(statement.statusText)
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(statement.statusColor)
                Text(statement.dueText)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                if statement.status == .partial {
                    Text("Sudah dibayar " + (isVisible ? statement.paid.formattedAsCurrency() : "Rp" + hiddenAmount))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Pays a card bill: a transfer from a cash wallet into the card, which lowers its debt.
struct PayCardBillSheet: View {
    let card: Account
    let statement: CreditStatement
    let wallets: [Account]

    private enum Choice { case full, minimum, custom }

    @State private var choice = Choice.full
    @State private var customAmount = 0
    @State private var sourceId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var sources: [Account] { wallets.filter { $0.isActive && !$0.isCreditCard } }
    private var source: Account? { sources.first { $0.id == sourceId } }
    /// Nothing billed yet but the card has debt: offer paying all of it.
    private var fullAmount: Double { statement.remaining > 0 ? statement.remaining : card.balance }

    private var amount: Double {
        switch choice {
        case .full: fullAmount
        case .minimum: statement.minimumDue
        case .custom: Double(customAmount)
        }
    }

    private var canPay: Bool { amount > 0 && source != nil && !isSaving }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
            }
            .overlay {
                Text("Bayar tagihan")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeroAmount(value: amount, size: .medium)
                        .opacity(amount > 0 ? 1 : 0.55)
                    Text("ke \(card.name)")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        choiceRow(.full, title: "Bayar penuh",
                                  caption: statement.remaining > 0 ? "Sisa tagihan" : "Seluruh utang kartu",
                                  amount: fullAmount)
                        if statement.minimumDue > 0 {
                            choiceRow(.minimum, title: "Minimum", caption: "Pembayaran minimum", amount: statement.minimumDue)
                        }
                        choiceRow(.custom, title: "Nominal lain", caption: "Ketik sendiri", amount: nil)
                    }
                    .padding(.top, 20)

                    if statement.remaining > 0, amount < statement.remaining {
                        let left = statement.remaining - amount
                        Text("Sisa \(left.formattedAsCurrency()) kena bunga sekitar \((left * CreditStatement.monthlyInterest).formattedAsCurrency())/bulan")
                            .font(.app(13))
                            .foregroundStyle(Color.appWarning)
                            .monospacedDigit()
                            .padding(.top, 12)
                    }

                    SectionHeader(title: "Bayar dari")
                        .padding(.top, 28)
                        .padding(.bottom, 12)
                    if sources.isEmpty {
                        Text("Belum ada dompet untuk membayar")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                    } else {
                        WalletPickerGrid(accounts: sources, selectedId: sourceId) { sourceId = $0.id }
                        if let source {
                            Text("Saldo \(source.name) \(source.balance.formattedAsCurrency())")
                                .font(.app(13))
                                .foregroundStyle(Color.appTextSecondary)
                                .monospacedDigit()
                                .padding(.top, 12)
                            if source.balance < amount {
                                Text("Saldo tidak cukup untuk nominal ini")
                                    .font(.app(13))
                                    .foregroundStyle(Color.appError)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.app(13))
                            .foregroundStyle(Color.appError)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            Group {
                if choice == .custom {
                    AmountPad(color: .appPrimary, isEnabled: canPay, isSaving: isSaving, onPress: { key in
                        if let next = NumberPad.apply(key, to: customAmount) { customAmount = next }
                    }, onSave: pay)
                } else {
                    Button(action: pay) {
                        Group {
                            if isSaving { ProgressView().tint(.white) } else { Text("Bayar") }
                        }
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary.opacity(canPay ? 1 : 0.4), in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(!canPay)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .onAppear {
            if sourceId == nil { sourceId = (sources.first(where: \.isDefault) ?? sources.first)?.id }
        }
    }

    private func choiceRow(_ value: Choice, title: String, caption: String, amount: Double?) -> some View {
        let isOn = choice == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { choice = value }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(16, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(Color.appText)
                    Text(caption)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                if let amount {
                    Text(amount.formattedAsCurrency())
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.appPrimary)
                    .opacity(isOn ? 1 : 0)
            }
            .padding(.vertical, 12)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func pay() {
        guard canPay, let source else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SupabaseRepository.shared.createTransfer(
                    primaryAccountId: source.id, counterpartyAccountId: card.id, amount: amount,
                    description: "Bayar tagihan \(card.name)", note: nil, date: Date()
                )
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Gagal membayar tagihan. Coba lagi."
            }
        }
    }
}
