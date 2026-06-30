import SwiftUI

struct WalletDetailView: View {
    let account: Account
    let transactions: [Transaction]
    let onSave: ((String, String, Account.AccountType, Double, String?, Bool) async -> Void)?
    let onDelete: ((String) async -> Void)?
    let onToggleArchive: ((String, Bool) async -> Void)?

    @State private var balanceText = ""
    @State private var balanceDigits = ""
    @State private var editedName = ""
    @State private var editedIconId: String
    @State private var showIconPicker = false
    @State private var showDeleteAlert = false
    @State private var showArchiveAlert = false
    @State private var showUnarchiveAlert = false
    @State private var showDeleteWarningAlert = false
    @State private var deleteWarningMessage = ""
    @State private var hasConfirmed = false
    @State private var isFirstEdit = true
    @FocusState private var isBalanceFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let initialDigits: String

    init(account: Account, transactions: [Transaction] = [],
         onSave: ((String, String, Account.AccountType, Double, String?, Bool) async -> Void)? = nil,
         onDelete: ((String) async -> Void)? = nil,
         onToggleArchive: ((String, Bool) async -> Void)? = nil) {
        self.account = account
        self.transactions = transactions
        self.onSave = onSave
        self.onDelete = onDelete
        self.onToggleArchive = onToggleArchive
        let digits = String(Int(account.balance))
        initialDigits = digits
        _balanceText = State(initialValue: digits.formattedWithThousandSeparator)
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

                HStack {
                    Text("Transaksi Terbaru")
                        .font(.jakarta(15, weight: .semibold))
                    Spacer()
                    Text("\(transactions.count) transaksi")
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        if account.isActive {
                            showArchiveAlert = true
                        } else {
                            showUnarchiveAlert = true
                        }
                    } label: {
                        Label(account.isActive ? "Arsipkan" : "Aktifkan", systemImage: account.isActive ? "archivebox" : "archivebox.fill")
                    }
                    .tint(.primary)

                    Divider()

                    Button(role: .destructive) {
                        if !transactions.isEmpty {
                            deleteWarningMessage = "Tidak bisa menghapus dompet yang masih memiliki transaksi (\(transactions.count) transaksi). Jika tidak lagi digunakan, kamu bisa mengarsipkannya."
                            showDeleteWarningAlert = true
                        } else {
                            showDeleteAlert = true
                        }
                    } label: {
                        Label("Hapus Dompet", systemImage: "trash")
                    }
                    .tint(.red)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.jakarta(17))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if hasChanges {
                    Button("Simpan") {
                        confirmChanges()
                    }
                    .font(.jakarta(15, weight: .semibold))
                }
            }
        }
        .alert("Arsipkan Dompet?", isPresented: $showArchiveAlert) {
            Button("Batal", role: .cancel) {}
            Button("Arsipkan") {
                Task {
                    await onToggleArchive?(account.id, true)
                    dismiss()
                }
            }
        } message: {
            Text("\(account.name) akan diarsipkan dan tidak bisa digunakan untuk transaksi baru.")
        }
        .alert("Aktifkan Dompet?", isPresented: $showUnarchiveAlert) {
            Button("Batal", role: .cancel) {}
            Button("Aktifkan") {
                Task {
                    await onToggleArchive?(account.id, false)
                    dismiss()
                }
            }
        } message: {
            Text("\(account.name) akan diaktifkan kembali dan bisa digunakan untuk transaksi.")
        }
        .alert("Hapus Dompet?", isPresented: $showDeleteAlert) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                Task {
                    await onDelete?(account.id)
                    dismiss()
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
    }

    private var balanceOpacity: Double {
        isFirstEdit && isBalanceFocused ? 0.5 : 1.0
    }

    private func miniStatCard(label: String, amount: Double, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: label == "Pemasukan" ? "arrow.down" : "arrow.up")
                        .font(.jakarta(11))
                        .foregroundColor(color)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.jakarta(10))
                    .foregroundColor(.appTextSecondary)
                Text(amount > 0 ? abbreviatedAmount(amount) : "Rp0")
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

                TextField("0", text: $balanceText)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText.opacity(balanceOpacity))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .focused($isBalanceFocused)
                    .disabled(!account.isActive)
                    .onChange(of: balanceText) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        let oldDigits = String(oldValue.filter { $0.isWholeNumber })
                        let newDigits = String(newValue.filter { $0.isWholeNumber })
                        if isFirstEdit && oldDigits == initialDigits {
                            let typed = String(newDigits.suffix(newDigits.count - oldDigits.count))
                            balanceText = typed.formattedWithThousandSeparator
                            balanceDigits = typed
                            isFirstEdit = false
                        } else {
                            let formatted = newDigits.formattedWithThousandSeparator
                            if formatted != newValue {
                                balanceText = formatted
                            }
                            balanceDigits = newDigits
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)

            HStack(spacing: Spacing.md) {
                miniStatCard(
                    label: "Pemasukan",
                    amount: monthlyIncome,
                    color: .appIncome
                )

                miniStatCard(
                    label: "Pengeluaran",
                    amount: monthlyExpense,
                    color: .appExpense
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
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
            isBalanceFocused = true
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
        guard let balance = Double(balanceDigits) else { return }
        Task {
            await onSave?(account.id, editedName.trimmingCharacters(in: .whitespaces), account.type, balance, editedIconId, account.isArchived)
            hasConfirmed = true
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
        Group {
            if transactions.isEmpty {
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
                    ForEach(transactions) { transaction in
                        transactionRow(transaction)
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
            }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(transaction.type == .income ? Color.appIncome : Color.appExpense)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: transaction.type == .income ? "arrow.down" : "arrow.up")
                        .font(.jakarta(11))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.note ?? (transaction.type == .income ? "Pemasukan" : "Pengeluaran"))
                        .font(.jakarta(14, weight: .medium))
                    if !account.isActive {
                        Text("Diarsipkan")
                            .font(.jakarta(9, weight: .medium))
                            .foregroundColor(.appWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(transaction.amount.formattedAsCurrency())
                .font(.jakarta(14, weight: .semibold))
                .foregroundColor(transaction.type == .income ? .appIncome : .appExpense)
        }
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    WalletDetailView(
        account: Account(id: "1", name: "BCA", type: .bank, icon: "bca", isArchived: false, openingBalance: 1000000),
        transactions: [],
        onSave: nil,
        onDelete: nil,
        onToggleArchive: nil
    )
}
