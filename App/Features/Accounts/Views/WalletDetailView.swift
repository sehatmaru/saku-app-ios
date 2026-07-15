import SwiftUI

struct WalletDetailView: View {
    let account: Account
    let transactions: [Transaction]
    let categories: [Category]
    let onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double) async -> Bool)?
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
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(account: Account, transactions: [Transaction] = [],
         categories: [Category] = [],
         onSave: ((String, String, Account.AccountType, String?, Bool, Double, Double) async -> Bool)? = nil,
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
    }

    private var walletIcon: WalletIcon? {
        WalletIcon.resolve(editedIconId)
    }

    private var hasChanges: Bool {
        !hasConfirmed && (
            editedName != account.name ||
            editedIconId != account.icon ||
            balanceDigits != String(Int(account.balance))
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
        }
        .animation(.easeInOut(duration: 0.25), value: showBalanceKeyboard)
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
    }
    
    private var balanceOpacity: Double { 1.0 }

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Button {
                    if account.type != .cash {
                        showIconPicker = true
                    }
                } label: {
                    Circle()
                        .fill(walletIcon?.color ?? .appPrimary)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if let icon = walletIcon {
                                Text(icon.shortName)
                                    .font(.jakarta(10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                }
                .disabled(account.type == .cash || !account.isActive)

                TextField("Nama", text: $editedName)
                    .font(.jakarta(17, weight: .semibold))
                    .disabled(!account.isActive)
                    .focused($isNameFocused)

                Spacer()

                Text(account.type.rawValue)
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }
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

            if account.isActive {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                HStack(spacing: Spacing.md) {
                    if !account.isDefault {
                        Button {
                            Task { await onSetDefault?(account.id) }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "star.fill")
                                    .font(.jakarta(11))
                                Text("Jadikan Utama")
                                    .font(.jakarta(11, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appWarning.opacity(0.1))
                            .foregroundColor(.appWarning)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        showArchiveAlert = true
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "archivebox")
                                .font(.jakarta(11))
                            Text("Arsipkan")
                                .font(.jakarta(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appPrimary.opacity(0.1))
                        .foregroundColor(.appPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(role: .destructive) {
                        if !transactions.isEmpty {
                            deleteWarningMessage = "Tidak bisa menghapus dompet yang masih memiliki transaksi (\(transactions.count) transaksi). Jika tidak lagi digunakan, kamu bisa mengarsipkannya."
                            showDeleteWarningAlert = true
                        } else {
                            showDeleteAlert = true
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "trash")
                                .font(.jakarta(11))
                            Text("Hapus")
                                .font(.jakarta(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appError.opacity(0.1))
                        .foregroundColor(.appError)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            } else {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                Button {
                    showUnarchiveAlert = true
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "archivebox.fill")
                            .font(.jakarta(11))
                        Text("Aktifkan Dompet")
                            .font(.jakarta(11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appPrimary.opacity(0.1))
                    .foregroundColor(.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
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
        guard let newBalance = Double(balanceDigits) else { return }
        isSaving = true
        Task {
            let success = await onSave?(account.id, editedName.trimmingCharacters(in: .whitespaces), account.type, editedIconId, account.isArchived, newBalance, account.balance) ?? true
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

#Preview {
    WalletDetailView(
        account: Account(id: "1", name: "BCA", type: .bank, icon: "bca", isArchived: false, isDefault: false, openingBalance: 1000000),
        transactions: [],
        onSave: nil,
        onDelete: nil,
        onToggleArchive: nil
    )
}
