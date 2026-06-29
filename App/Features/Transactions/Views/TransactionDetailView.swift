import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var amountDigits = ""
    @State private var editedTitle: String
    @State private var noteText = ""
    @State private var selectedDate: Date
    @State private var selectedCategoryId: String?
    @State private var selectedAccountId: String
    @State private var isFirstEdit = true
    @State private var showDatePicker = false
    @State private var showWalletPicker = false
    @State private var showCategoryPicker = false
    @State private var isEditingNote = false
    @State private var showToast = false
    @State private var showDeleteConfirmation = false
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTitleFocused: Bool

    private let initialDigits: String

    init(transaction: Transaction) {
        self.transaction = transaction
        let digits = String(Int(transaction.amount))
        initialDigits = digits
        _amountText = State(initialValue: digits.formattedWithThousandSeparator)
        _amountDigits = State(initialValue: digits)
        _editedTitle = State(initialValue: transaction.note ?? "")
        _selectedDate = State(initialValue: transaction.date)
        _selectedCategoryId = State(initialValue: transaction.categoryId)
        _selectedAccountId = State(initialValue: transaction.accountId)
    }

    private var selectedCategory: Category? {
        guard let id = selectedCategoryId else { return nil }
        return Category.sample.first { $0.id == id }
    }

    private var selectedAccount: Account? {
        Account.sample.first { $0.id == selectedAccountId }
    }

    private var walletIcon: WalletIcon? {
        WalletIcon.allIcons.first { $0.id == selectedAccount?.icon }
    }

    private var activeAccounts: [Account] {
        Account.sample.filter { $0.isActive }
    }

    private var filteredCategories: [Category] {
        let target: CategoryType = transaction.type == .income ? .income : .expense
        return Category.sample.filter { $0.type == target }
    }

    private var typeColor: Color {
        transaction.type == .income ? .appIncome : .appExpense
    }

    private var amountOpacity: Double {
        isFirstEdit && isAmountFocused ? 0.5 : 1.0
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Selesai") {
                    isAmountFocused = false
                    isTitleFocused = false
                    isEditingNote = false
                    saveChanges()
                }
                .font(.jakarta(15, weight: .semibold))
            }
        }
        .alert("Hapus Transaksi?", isPresented: $showDeleteConfirmation) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Transaksi akan dihapus permanen.")
        }
        .onChange(of: isAmountFocused) { _, newValue in
            if !newValue { saveChanges() }
        }
        .onChange(of: isTitleFocused) { _, newValue in
            if !newValue { saveChanges() }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                toast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 32)
            }
        }
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
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showToast = false
            }
        }
    }

    private var toast: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.jakarta(14))
                .foregroundColor(.appPrimary)
            Text("Perubahan disimpan")
                .font(.jakarta(14, weight: .medium))
                .foregroundColor(.appText)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 12)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: Header Card
    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: selectedCategory?.icon ?? (transaction.type == .income ? "arrow.down" : "arrow.up"))
                            .font(.jakarta(18))
                            .foregroundColor(typeColor)
                    }

                TextField("Judul transaksi", text: $editedTitle)
                    .font(.jakarta(17, weight: .semibold))
                    .foregroundColor(.appText)
                    .focused($isTitleFocused)
                    .onSubmit { saveChanges() }

                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(spacing: 6) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)

                TextField("0", text: $amountText)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText.opacity(amountOpacity))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .focused($isAmountFocused)
                    .onChange(of: amountText) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        let oldDigits = String(oldValue.filter { $0.isWholeNumber })
                        let newDigits = String(newValue.filter { $0.isWholeNumber })
                        if isFirstEdit && oldDigits == initialDigits {
                            let typed = String(newDigits.suffix(newDigits.count - oldDigits.count))
                            amountText = typed.formattedWithThousandSeparator
                            amountDigits = typed
                            isFirstEdit = false
                        } else {
                            let formatted = newDigits.formattedWithThousandSeparator
                            if formatted != newValue {
                                amountText = formatted
                            }
                            amountDigits = newDigits
                        }
                    }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
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
            Button {
                showDatePicker = true
            } label: {
                listRow(icon: "calendar", label: "Tanggal", value: selectedDate.formatted(date: .long, time: .omitted), iconColor: .appTextSecondary)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            Button {
                showCategoryPicker = true
            } label: {
                listRow(icon: selectedCategory?.icon ?? "folder", label: "Kategori", value: selectedCategory?.name ?? "-", iconColor: typeColor)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            Button {
                showWalletPicker = true
            } label: {
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
                                .font(.jakarta(13))
                                .foregroundColor(.appTextSecondary)
                        }

                    TextField("Tambahkan catatan", text: $noteText)
                        .font(.jakarta(15, weight: .medium))
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
    }

    private func listRow(icon: String, label: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(iconColor.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.jakarta(13))
                        .foregroundColor(iconColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
                Text(value)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var walletRow: some View {
        HStack(spacing: Spacing.md) {
            if let icon = walletIcon {
                Circle()
                    .fill(icon.color)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(icon.shortName)
                            .font(.jakarta(8, weight: .bold))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.8)
                    }
            } else {
                Circle()
                    .fill(Color.appTextSecondary.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "wallet.pass")
                            .font(.jakarta(13))
                            .foregroundColor(.appTextSecondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Dompet")
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
                Text(selectedAccount?.name ?? "-")
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
                    .font(.jakarta(15, weight: .semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showDatePicker = false
                    }
                    .font(.jakarta(15))
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
                        let wi = WalletIcon.allIcons.first { $0.id == account.icon }
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
                                            .font(.jakarta(10, weight: .bold))
                                            .foregroundColor(.white)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.jakarta(15, weight: .medium))
                                        .foregroundColor(.appText)
                                    Text("Saldo \(account.balance.formattedAsCurrency())")
                                        .font(.jakarta(12))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Spacer()

                                if account.id == selectedAccountId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.jakarta(16))
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
                    .font(.jakarta(15))
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
                                        Image(systemName: cat.icon)
                                            .font(.jakarta(16))
                                            .foregroundColor(typeColor)
                                    }

                                Text(cat.name)
                                    .font(.jakarta(15, weight: .medium))
                                    .foregroundColor(.appText)

                                Spacer()

                                if cat.id == selectedCategoryId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.jakarta(16))
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
                    .font(.jakarta(15))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
