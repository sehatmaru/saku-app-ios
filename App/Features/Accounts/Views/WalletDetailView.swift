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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal)
                    .padding(.top)

                hintCard
                    .padding(.horizontal)
                    .padding(.top, Spacing.md)

                if !account.isActive {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.appWarning.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "archivebox.fill")
                                .font(.jakarta(14))
                                .foregroundColor(.appWarning)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dompet Diarsipkan")
                                .font(.jakarta(13, weight: .semibold))
                                .foregroundColor(.appText)
                            Text("Tidak dapat digunakan untuk transaksi baru")
                                .font(.jakarta(11))
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 12)
                    .background(Color.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.appWarning.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.top, Spacing.md)
                }

                let monthTxs = thisMonthTransactions
                HStack {
                    Text("Transaksi Bulan Ini")
                        .font(.jakarta(15, weight: .semibold))
                    Spacer()
                    Text("\(monthTxs.count) transaksi")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal)
                .padding(.top, Spacing.md)

                transactionListContent
                    .padding([.horizontal, .top])
                    .padding(.bottom)
            }
        }
        .background(Color.appGroupedBackground)
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
                        .font(.jakarta(15, weight: .semibold))
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
                .presentationDetents([.medium])
                .presentationBackground(Color.appCardBackground)
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
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Tanggal Jatuh Tempo", selection: $editedDueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .pickerStyle(.wheel)
                    .padding()
                }
                .navigationTitle("Pilih Tanggal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Simpan") { showDueDayPicker = false; confirmChanges() }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Batal") { showDueDayPicker = false }
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
    }
    
    private var balanceOpacity: Double { 1.0 }
    private var isCreditCard: Bool { account.isCreditCard }

    private var dueDateFormatted: String {
        "Setiap tanggal \(editedDueDay)"
    }

    private var headerSection: some View {
        Group {
            if isCreditCard {
                creditCardSection
            } else {
                walletHeaderSection
            }
        }
    }

    private var creditCardSection: some View {
        VStack(spacing: Spacing.md) {
            // Card 1: Header + Limit + Actions
            VStack(spacing: 0) {
                headerRow
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)

                let limit = Double(creditLimitDigits) ?? 0
                let outstanding = account.currentBalance ?? 0
                let utilization = limit > 0 ? outstanding / limit : 0

                VStack(spacing: 4) {
                    HStack {
                        Text("Total Limit")
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                        Spacer()
                        Text(limit.formattedAsCurrency())
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(.appText)
                            .contentShape(Rectangle())
                            .onTapGesture { showCreditLimitKeyboard = true }
                    }

                    HStack {
                        Text("Sisa Limit")
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                        Spacer()
                        Text((limit - outstanding).formattedAsCurrency())
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(.appText)
                    }

                    Spacer().frame(height: 4)

                    ProgressView(value: min(utilization, 1.0))
                        .tint(utilization > 0.8 ? .appError : utilization > 0.5 ? .appWarning : .appPrimary)

                    Text("\(Int(utilization * 100))% terpakai")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)

                actionButtons
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.lg)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Card 2: Due Date + Stats
            VStack(spacing: 0) {
                Button {
                    showDueDayPicker = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "calendar")
                                    .font(.jakarta(13))
                                    .foregroundColor(.appPrimary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Jatuh Tempo")
                                .font(.jakarta(11))
                                .foregroundColor(.appTextSecondary)
                            Text(dueDateFormatted)
                                .font(.jakarta(15, weight: .medium))
                                .foregroundColor(.appText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.jakarta(10))
                            .foregroundColor(.appTextSecondary.opacity(0.4))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 52)
                    .padding(.trailing, Spacing.lg)

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("Total Tagihan")
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                        Text((account.currentBalance ?? 0).formattedAsCurrency())
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(.appExpense)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 28)
                    VStack(spacing: 4) {
                        Text("Bulan Ini")
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                        Text(monthlyExpense > 0 ? abbreviatedAmount(monthlyExpense) : "Rp0")
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(.appExpense)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: isCreditCard ? "creditcard.fill" : "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundColor(.appExpense.opacity(0.08))
                .offset(x: -12, y: -4)
        }
        .onTapGesture {
            if !isCreditCard { showBalanceKeyboard = true }
            if isCreditCard { showCreditLimitKeyboard = true }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            Button { if account.type != .cash, !isCreditCard { showIconPicker = true } } label: {
                WalletIconView(icon: walletIcon, size: 36)
            }
            .disabled(account.type == .cash || isCreditCard || !account.isActive)

            TextField("Nama", text: $editedName)
                .font(.jakarta(17, weight: .semibold))
                .disabled(!account.isActive)
                .focused($isNameFocused)

            Spacer()

            Text(isCreditCard ? "Kartu Kredit" : account.type.rawValue)
                .font(.jakarta(12))
                .foregroundColor(.appTextSecondary)
        }
    }

    private var actionButtons: some View {
        Group {
            if account.isActive {
                HStack(spacing: Spacing.md) {
                    if !account.isDefault {
                        Button { Task { await onSetDefault?(account.id) } } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "star.fill").font(.jakarta(11))
                                Text("Jadikan Utama").font(.jakarta(11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.appWarning.opacity(0.1)).foregroundColor(.appWarning)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Button { showArchiveAlert = true } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "archivebox").font(.jakarta(11))
                            Text("Arsipkan").font(.jakarta(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.appPrimary.opacity(0.1)).foregroundColor(.appPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button(role: .destructive) {
                        if !transactions.isEmpty {
                            deleteWarningMessage = "Tidak bisa menghapus akun yang masih memiliki transaksi (\(transactions.count) transaksi). Jika tidak lagi digunakan, kamu bisa mengarsipkannya."
                            showDeleteWarningAlert = true
                        } else { showDeleteAlert = true }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "trash").font(.jakarta(11))
                            Text("Hapus").font(.jakarta(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.appError.opacity(0.1)).foregroundColor(.appError)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Button { showUnarchiveAlert = true } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "archivebox.fill").font(.jakarta(11))
                        Text("Aktifkan").font(.jakarta(11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.appPrimary.opacity(0.1)).foregroundColor(.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var walletHeaderSection: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            HStack(spacing: 6) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)

                Text(balanceDigits.isEmpty ? "0" : balanceDigits.formattedWithThousandSeparator)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                    .contentShape(Rectangle())
                    .onTapGesture { showBalanceKeyboard = true }
                    .disabled(!account.isActive)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Pemasukan Bulan Ini")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Text(monthlyIncome > 0 ? abbreviatedAmount(monthlyIncome) : "Rp0")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(.appIncome)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 28)
                VStack(spacing: 4) {
                    Text("Pengeluaran Bulan Ini")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Text(monthlyExpense > 0 ? abbreviatedAmount(monthlyExpense) : "Rp0")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(.appExpense)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            actionButtons
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
        .onTapGesture {
            showBalanceKeyboard = true
        }
    }

    @State private var showEditCustomSheet = false

    private var iconPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(WalletIcon.icons(for: account.type)) { icon in
                            Button {
                                editedIconId = icon.id
                                showIconPicker = false
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(editedIconId == icon.id ? icon.color : icon.color.opacity(0.2))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Text(icon.shortName)
                                                .font(.jakarta(10, weight: .bold))
                                                .foregroundColor(editedIconId == icon.id ? .white : icon.color)
                                        }
                                    Text(icon.name)
                                        .font(.jakarta(9))
                                        .foregroundColor(.appTextSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showEditCustomSheet = true
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.appPrimary.opacity(0.2))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "plus")
                                        .font(.jakarta(14, weight: .bold))
                                        .foregroundColor(.appPrimary)
                                }
                                Text("Custom")
                                    .font(.jakarta(9))
                                    .foregroundColor(.appTextSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Pilih Icon")
                }
            }
            .navigationTitle("Ganti Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { showIconPicker = false }
                }
            }
            .sheet(isPresented: $showEditCustomSheet) {
                CustomIconSheet { text, colorName in
                    editedIconId = WalletIcon.customIconId(text: text, colorName: colorName)
                    showIconPicker = false
                }
            }
        }
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

    private var transactionListContent: some View {
        let monthTxs = thisMonthTransactions
        let displayTxs = showAllTransactions ? monthTxs : Array(monthTxs.prefix(5))

        return Group {
            if monthTxs.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "tray")
                        .font(.jakarta(32))
                        .foregroundColor(.appTextSecondary.opacity(0.5))
                    Text("Belum ada transaksi")
                        .font(.jakarta(13))
                        .foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxxl)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(displayTxs) { transaction in
                        Button { detailTransaction = transaction } label: { transactionRow(transaction) }
                            .buttonStyle(.plain)
                        if transaction.id != displayTxs.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }

                    if monthTxs.count > 5 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllTransactions.toggle()
                            }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: showAllTransactions ? "chevron.up" : "chevron.down")
                                    .font(.jakarta(10))
                                Text(showAllTransactions ? "Sembunyikan" : "Lihat Semua (\(monthTxs.count))")
                                    .font(.jakarta(12, weight: .medium))
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
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        TransactionRowView(transaction: transaction, categories: categories, accounts: [account], showWalletBadge: false, showArchivedBadge: !account.isActive)
    }

    private var hintCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "hand.tap.fill")
                .font(.jakarta(18))
                .foregroundColor(.appPrimary)

            Text("Tap langsung pada bagian yang ingin diubah, perubahan akan tersimpan secara otomatis.")
                .font(.jakarta(13))
                .foregroundColor(.appTextSecondary)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(Color.appPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appPrimary.opacity(0.15), lineWidth: 1)
        )
    }
}
