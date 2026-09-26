import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    let categories: [Category]
    let accounts: [Account]
    var isEditable: Bool = true
    let onUpdate: ((Transaction) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var amountDigits = ""
    @State private var showAmountKeyboard = false
    @State private var editedTitle: String
    @State private var noteText = ""
    @State private var selectedDate: Date
    @State private var selectedCategoryId: String?
    @State private var selectedAccountId: String
    @State private var showDatePicker = false
    @State private var showWalletPicker = false
    @State private var showCategoryPicker = false
    @State private var isEditingNote = false
    @State private var showToast = false
    @State private var showDeleteConfirmation = false
    @FocusState private var isTitleFocused: Bool

    init(transaction: Transaction, categories: [Category], accounts: [Account], isEditable: Bool = true, onUpdate: ((Transaction) -> Void)? = nil) {
        self.transaction = transaction
        self.categories = categories
        self.accounts = accounts
        self.isEditable = isEditable
        self.onUpdate = onUpdate
        let digits = String(Int(transaction.amount))
        _amountDigits = State(initialValue: digits)
        _editedTitle = State(initialValue: transaction.note ?? "")
        _selectedDate = State(initialValue: transaction.date)
        _selectedCategoryId = State(initialValue: transaction.categoryId)
        _selectedAccountId = State(initialValue: transaction.accountId)
    }

    private var selectedCategory: Category? {
        guard let id = selectedCategoryId else { return nil }
        return categories.first { $0.id == id }
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId }
    }

    private var walletIcon: WalletIcon? {
        WalletIcon.resolve(selectedAccount?.icon)
    }

    private var activeAccounts: [Account] {
        accounts.filter { $0.isActive }
    }

    private var filteredCategories: [Category] {
        let target: CategoryType = transaction.type == .income ? .income : .expense
        return categories.filter { $0.type == target }
    }

    private var typeColor: Color {
        switch transaction.type {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .appText
        case .adjustment: .appText
        }
    }

    private var typeIcon: String {
        switch transaction.type {
        case .income: return "arrow.down"
        case .expense: return "arrow.up"
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "arrow.2.circlepath"
        }
    }

    private var typeLabel: String {
        switch transaction.type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        case .adjustment: "Penyesuaian saldo"
        }
    }

    private var amountOpacity: Double { 1.0 }

    private var isAdjustment: Bool { transaction.type == .adjustment }
    private var isTransfer: Bool { transaction.type == .transfer }

    private var signedAmount: Double { transaction.delta ?? transaction.amount }

    private var amountColor: Color {
        isAdjustment ? (signedAmount >= 0 ? .appIncome : .appExpense) : typeColor
    }

    private var accountForAdjustment: Account? {
        isAdjustment ? accounts.first { $0.id == transaction.accountId } : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerCard
                    .padding(.horizontal)
                    .padding(.top)

                infoCard
                    .padding(.horizontal)
                    .padding(.top, Spacing.md)

                hintCard
                    .padding(.horizontal)
                    .padding(.top, Spacing.md)

                Color.clear
                    .frame(height: Spacing.xl)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Detail Transaksi")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { if showAmountKeyboard { showAmountKeyboard = false } }
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }

            if isEditable {
                ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Selesai") {
                    isTitleFocused = false
                    isEditingNote = false
                    saveChanges()
                }
                .font(.app(15, weight: .semibold))
            }
            }
        }
        .alert("Hapus Transaksi?", isPresented: $showDeleteConfirmation) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                Task {
                    do {
                        try await SupabaseRepository.shared.softDeleteTransaction(id: transaction.id)
                        NotificationCenter.default.post(name: .dataDidChange, object: nil)
                        dismiss()
                    } catch {
                        print("❌ deleteTransaction failed: \(error)")
                    }
                }
            }
        } message: {
            Text("Transaksi akan dihapus permanen.")
        }
        .onChange(of: isTitleFocused) { _, newValue in
            if !newValue, isEditable { saveChanges() }
            if newValue { showAmountKeyboard = false }
        }
        .onChange(of: showAmountKeyboard) { _, newValue in
            if newValue { isTitleFocused = false }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showAmountKeyboard {
                AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                    showAmountKeyboard = false
                    saveChanges()
                }
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAmountKeyboard)
        .toast(isPresented: $showToast, message: "Perubahan disimpan")
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(isPresented: $showWalletPicker) {
            walletPickerSheet
        }
        .sheet(isPresented: $showCategoryPicker) {
            categoryPickerSheet
        }
    }

    private func saveChanges() {
        let amount = Double(amountDigits) ?? transaction.amount
        let updated = Transaction(
            id: transaction.id,
            accountId: selectedAccountId,
            counterpartyAccountId: transaction.counterpartyAccountId,
            categoryId: isAdjustment ? transaction.categoryId : selectedCategoryId,
            amount: amount,
            type: transaction.type,
            description: transaction.description,
            note: isAdjustment ? (noteText.isEmpty ? nil : noteText) : (editedTitle.isEmpty ? nil : editedTitle),
            date: selectedDate,
            delta: transaction.delta
        )
        Task {
            do {
                try await SupabaseRepository.shared.updateTransaction(
                    id: updated.id,
                    accountId: updated.accountId,
                    categoryId: updated.categoryId,
                    amount: updated.amount,
                    type: updated.type,
                    description: updated.description,
                    note: updated.note,
                    date: updated.date
                )
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                onUpdate?(updated)
                withAnimation { showToast = true }
            } catch {
                print("❌ updateTransaction failed: \(error)")
                withAnimation { showToast = true }
            }
        }
    }

    // MARK: Header Card
    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                let account = accounts.first { $0.id == transaction.accountId }
                let walletIcon = account.flatMap { WalletIcon.resolve($0.icon) }
                if let walletIcon {
                    WalletIconView(icon: walletIcon, size: 44)
                } else {
                    Circle()
                        .fill(typeColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: isAdjustment ? typeIcon : (selectedCategory?.icon ?? typeIcon))
                                .font(.app(18))
                                .foregroundColor(typeColor)
                        }
                        .overlay(
                            Circle()
                                .stroke(typeColor.opacity(0.3), lineWidth: 1.5)
                        )
                }

                if isAdjustment {
                    Text("Penyesuaian saldo")
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                } else if isTransfer {
                    Text("Transfer")
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                } else if isEditable {
                    TextField("Judul transaksi", text: $editedTitle)
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                        .focused($isTitleFocused)
                        .onSubmit { saveChanges() }
                } else {
                    Text(editedTitle.isEmpty ? (transaction.note ?? typeLabel) : editedTitle)
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(spacing: 6) {
                Text(isAdjustment && signedAmount < 0 ? "-Rp" : "Rp")
                    .font(.app(34, weight: .bold))
                    .foregroundColor(amountColor)

                Text(isAdjustment ? String(Int(abs(signedAmount))).formattedWithThousandSeparator : (amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator))
                    .font(.app(34, weight: .bold))
                    .foregroundColor(amountColor)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isAdjustment, isEditable { showAmountKeyboard = true } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, isAdjustment ? 0 : Spacing.lg)

            if isAdjustment {
                let account = accounts.first { $0.id == transaction.accountId }
                if let currentBalance = account?.currentBalance {
                    let newBalance = currentBalance
                    let delta = signedAmount
                    let oldBalance = newBalance - delta

                    Divider()
                        .padding(.horizontal, Spacing.xl)

                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("Sebelum")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(oldBalance.formattedAsCurrency())
                                .font(.app(13, weight: .semibold))
                                .foregroundColor(.appText)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 28)

                        VStack(spacing: 4) {
                            Text("Sesudah")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(newBalance.formattedAsCurrency())
                                .font(.app(13, weight: .semibold))
                                .foregroundColor(delta >= 0 ? .appIncome : .appExpense)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)
                }
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(typeColor.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    // MARK: Info Card
    private var infoCard: some View {
        VStack(spacing: 0) {
            if isAdjustment {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.app(13))
                                .foregroundColor(.appTextSecondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tanggal")
                            .font(.app(11))
                            .foregroundColor(.appTextSecondary)
                        Text(transaction.date.formatted(date: .long, time: .omitted))
                            .font(.app(15, weight: .medium))
                            .foregroundColor(.appText)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 10)
            } else {
                Button { showDatePicker = true } label: {
                    listRow(icon: "calendar", label: "Tanggal", value: selectedDate.formatted(date: .long, time: .omitted), iconColor: .appTextSecondary)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.leading, 52)

            if isAdjustment {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "folder")
                                .font(.app(13))
                                .foregroundColor(.appTextSecondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kategori")
                            .font(.app(11))
                            .foregroundColor(.appTextSecondary)
                        Text("-")
                            .font(.app(15, weight: .medium))
                            .foregroundColor(.appText)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 10)
            } else {
                Button { showCategoryPicker = true } label: {
                    listRow(icon: selectedCategory?.icon ?? "folder", label: "Kategori", value: selectedCategory?.name ?? "-", iconColor: typeColor)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.leading, 52)

            Button { if !isAdjustment, !isTransfer { showWalletPicker = true } } label: {
                walletRow
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            if isEditingNote {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.app(13))
                                .foregroundColor(.appTextSecondary)
                        }

                    TextField("Tambahkan catatan", text: $noteText)
                        .font(.app(15, weight: .medium))
                        .foregroundColor(.appText)
                        .onSubmit { isEditingNote = false; saveChanges() }

                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 10)
            } else {
                Button {
                    isEditingNote = true
                } label: {
                    listRow(icon: "doc.text", label: "Catatan", value: noteText.isEmpty ? "Tambahkan catatan" : noteText, iconColor: .appTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .disabled(!isEditable)
    }

    private func listRow(icon: String, label: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(iconColor.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.app(13))
                        .foregroundColor(iconColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.app(11))
                    .foregroundColor(.appTextSecondary)
                Text(value)
                    .font(.app(15, weight: .medium))
                    .foregroundColor(.appText)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var walletRow: some View {
        let isTransfer = transaction.type == .transfer
        let cparty = isTransfer ? accounts.first { $0.id == transaction.counterpartyAccountId } : nil
        let cpartyIcon = cparty.flatMap { WalletIcon.resolve($0.icon) }

        return HStack(spacing: Spacing.md) {
            if isTransfer, let srcIcon = walletIcon, let dstIcon = cpartyIcon {
                HStack(spacing: 2) {
                    iconCircle(wi: srcIcon, size: 28)
                    Image(systemName: "arrow.right")
                        .font(.app(7))
                        .foregroundColor(.appTextSecondary)
                    iconCircle(wi: dstIcon, size: 28)
                }
            } else if let icon = walletIcon {
                iconCircle(wi: icon, size: 36)
            } else {
                Circle()
                    .fill(Color.appTextSecondary.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "wallet.pass")
                            .font(.app(13))
                            .foregroundColor(.appTextSecondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isTransfer ? "Transfer" : "Dompet")
                    .font(.app(11))
                    .foregroundColor(.appTextSecondary)
                if isTransfer {
                    Text("\(selectedAccount?.name ?? "?") → \(cparty?.name ?? "?")")
                        .font(.app(15, weight: .medium))
                        .foregroundColor(.appText)
                        .lineLimit(1)
                } else {
                    Text(selectedAccount?.name ?? "-")
                        .font(.app(15, weight: .medium))
                        .foregroundColor(.appText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func iconCircle(wi: WalletIcon, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(wi.color)
                .frame(width: size, height: size)
            Text(wi.shortName)
                .font(.app(size <= 28 ? 7 : 8, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.8)
        }
    }

    private var hintCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "hand.tap.fill")
                .font(.app(18))
                .foregroundColor(.appPrimary)

            Text("Tap langsung pada bagian yang ingin diubah, perubahan akan tersimpan secara otomatis.")
                .font(.app(13))
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

    // MARK: Date Picker Sheet
    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Pilih Tanggal", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.appPrimary)
                    .padding()
            }
            .navigationTitle("Pilih Tanggal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        showDatePicker = false
                        saveChanges()
                    }
                    .font(.app(15, weight: .semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showDatePicker = false
                    }
                    .font(.app(15))
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Wallet Picker Sheet
    private var walletPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    let accounts = activeAccounts
                    ForEach(accounts) { account in
                        let wi = WalletIcon.resolve(account.icon)
                        let isLast = account.id == accounts.last?.id
                        Button {
                            selectedAccountId = account.id
                            showWalletPicker = false
                            saveChanges()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Circle()
                                    .fill(wi?.color ?? .appPrimary)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Text(wi?.shortName ?? "")
                                            .font(.app(10, weight: .bold))
                                            .foregroundColor(.white)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.app(15, weight: .medium))
                                        .foregroundColor(.appText)
                                    Text("Saldo \(account.balance.formattedAsCurrency())")
                                        .font(.app(12))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Spacer()

                                if account.id == selectedAccountId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.app(16))
                                        .foregroundColor(.appPrimary)
                                }
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if !isLast {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Dompet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showWalletPicker = false
                    }
                    .font(.app(15))
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Category Picker Sheet
    private var categoryPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    let cats = filteredCategories
                    ForEach(cats) { cat in
                        let isLast = cat.id == cats.last?.id
                        Button {
                            selectedCategoryId = cat.id
                            showCategoryPicker = false
                            saveChanges()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Circle()
                                    .fill(typeColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: cat.icon ?? "tag")
                                            .font(.app(16))
                                            .foregroundColor(typeColor)
                                    }

                                Text(cat.name)
                                    .font(.app(15, weight: .medium))
                                    .foregroundColor(.appText)

                                Spacer()

                                if cat.id == selectedCategoryId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.app(16))
                                        .foregroundColor(.appPrimary)
                                }
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if !isLast {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Kategori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showCategoryPicker = false
                    }
                    .font(.app(15))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
