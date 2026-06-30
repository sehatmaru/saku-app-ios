import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let accounts: [Account]
    let userId: String
    let onSave: () -> Void

    @State private var selectedType: Transaction.TransactionType = .expense
    @State private var amountText = ""
    @State private var amountDigits = ""
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var selectedTargetAccount: Account?
    @State private var selectedDate = Date()
    @State private var titleText = ""
    @State private var noteText = ""
    @State private var showDatePicker = false
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showAllTargetWallets = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    private var activeAccounts: [Account] {
        accounts.filter { $0.isActive }
    }

    private var filteredCategories: [Category] {
        let target: CategoryType = selectedType == .income ? .income : .expense
        return categories.filter { $0.type == target }
    }

    private var isTransfer: Bool {
        selectedType == .transfer
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    typePicker
                    AmountInputSection(amountText: $amountText, amountDigits: $amountDigits, typeColor: typeColor)
                    if !isTransfer {
                        categorySection
                    }
                    walletSection
                    if !isTransfer {
                        titleSection
                    }
                    noteSection
                    DatePicker("Tanggal", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(.appPrimary)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Tambah Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        save()
                    }
                    .font(.jakarta(15, weight: .bold))
                    .disabled(!canSave)
                }
            }
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .onAppear {
                if selectedAccount == nil, let first = activeAccounts.first {
                    selectedAccount = first
                }
                if selectedCategory == nil, let first = filteredCategories.first {
                    selectedCategory = first
                }
            }
            .onChange(of: selectedType) { _, _ in
                if selectedCategory == nil || !filteredCategories.contains(where: { $0.id == selectedCategory?.id }) {
                    selectedCategory = filteredCategories.first
                }
            }
        }
    }

    private var typeColor: Color {
        switch selectedType {
        case .income: return .appIncome
        case .expense: return .appExpense
        case .transfer: return .appPrimary
        }
    }

    // MARK: Type Picker
    private var typePicker: some View {
        Picker("Tipe", selection: $selectedType) {
            Text("Pemasukan").tag(Transaction.TransactionType.income)
            Text("Pengeluaran").tag(Transaction.TransactionType.expense)
            Text("Transfer").tag(Transaction.TransactionType.transfer)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Kategori", icon: "tag.fill")

            let items = showAllCategories ? filteredCategories : Array(filteredCategories.prefix(4))

            LazyVGrid(
                columns: Array(repeating: .init(.flexible(), spacing: Spacing.sm), count: 2),
                spacing: Spacing.sm
            ) {
                ForEach(items) { category in
                    categoryChip(
                        category: category,
                        color: typeColor,
                        isSelected: selectedCategory?.id == category.id
                    ) {
                        withAnimation(.interactiveSpring(response: 0.25)) {
                            if selectedCategory?.id == category.id {
                                selectedCategory = nil
                            } else {
                                selectedCategory = category
                            }
                        }
                    }
                }
            }

            if filteredCategories.count > 4 {
                Button {
                    withAnimation { showAllCategories.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(showAllCategories ? "Ringkas" : "Lihat Semua (\(filteredCategories.count))")
                            .font(.jakarta(13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.jakarta(10))
                            .rotationEffect(.degrees(showAllCategories ? 180 : 0))
                    }
                    .foregroundColor(.appPrimary)
                }
            }
        }
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.lg)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Wallet Section
    private var walletSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if isTransfer {
                walletGroup(title: "Dari Dompet", icon: "arrowshape.turn.up.right.fill", selected: $selectedAccount, exclude: selectedTargetAccount, showAll: $showAllWallets)
                walletGroup(title: "Ke Dompet", icon: "arrowshape.turn.down.left.fill", selected: $selectedTargetAccount, exclude: selectedAccount, showAll: $showAllTargetWallets)
            } else {
                walletGroup(title: "Dompet", icon: "wallet.pass", selected: $selectedAccount, exclude: nil, showAll: $showAllWallets)
            }
        }
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.lg)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func walletGroup(title: String, icon: String, selected: Binding<Account?>, exclude: Account?, showAll: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader(title, icon: icon)

            let available = activeAccounts.filter { exclude == nil || $0.id != exclude?.id }
            let items = showAll.wrappedValue ? available : Array(available.prefix(4))

            LazyVGrid(
                columns: Array(repeating: .init(.flexible(), spacing: Spacing.sm), count: 2),
                spacing: Spacing.sm
            ) {
                ForEach(items) { account in
                    walletChip(
                        account: account,
                        isSelected: selected.wrappedValue?.id == account.id
                    ) {
                        withAnimation(.interactiveSpring(response: 0.25)) {
                            if selected.wrappedValue?.id == account.id {
                                selected.wrappedValue = nil
                            } else {
                                selected.wrappedValue = account
                            }
                        }
                    }
                }
            }

            if available.count > 4 {
                Button {
                    withAnimation { showAll.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(showAll.wrappedValue ? "Ringkas" : "Lihat Semua (\(available.count))")
                            .font(.jakarta(13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.jakarta(10))
                            .rotationEffect(.degrees(showAll.wrappedValue ? 180 : 0))
                    }
                    .foregroundColor(.appPrimary)
                }
            }
        }
    }

    // MARK: Chips

    private func categoryChip(category: Category, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon ?? "tag")
                    .font(.jakarta(14))
                    .foregroundColor(isSelected ? color : color.opacity(0.7))

                Text(category.name)
                    .font(.jakarta(13))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.jakarta(10, weight: .bold))
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.12) : Color(.systemGray6))
            .foregroundColor(isSelected ? color : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func walletChip(account: Account, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let wi = WalletIcon.resolve(account.icon)
        return Button(action: action) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(wi?.color ?? .appPrimary)
                        .frame(width: 28, height: 28)
                    Text(wi?.shortName ?? "")
                        .font(.jakarta(7, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.7)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                        .font(.jakarta(13))
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .appPrimary : .appText)
                        .lineLimit(1)
                    Text(account.balance.formattedAsCurrency())
                        .font(.jakarta(10))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.jakarta(10, weight: .bold))
                        .foregroundColor(.appPrimary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(isSelected ? Color.appPrimary.opacity(0.12) : Color(.systemGray6))
            .foregroundColor(isSelected ? .appPrimary : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.jakarta(12))
                .foregroundColor(.appPrimary)
            Text(title)
                .font(.jakarta(13, weight: .semibold))
        }
        .foregroundColor(.appPrimary)
    }

    // MARK: Title Section

    private var titleSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "pencil")
                        .font(.jakarta(13))
                        .foregroundColor(.appTextSecondary)
                }

                TextField("Judul transaksi (opsional)", text: $titleText)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
                Spacer()
                if !titleText.isEmpty {
                    Button {
                        titleText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.jakarta(16))
                            .foregroundColor(.appTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Note Section
    private var noteSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.text")
                        .font(.jakarta(13))
                        .foregroundColor(.appTextSecondary)
                }

                TextField("Catatan tambahan (opsional)", text: $noteText)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
                Spacer()
                if !noteText.isEmpty {
                    Button {
                        noteText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.jakarta(16))
                            .foregroundColor(.appTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }


    private var canSave: Bool {
        guard !amountDigits.isEmpty, let amount = Double(amountDigits), amount > 0 else { return false }
        if isTransfer {
            return selectedAccount != nil && selectedTargetAccount != nil
        }
        return selectedCategory != nil && selectedAccount != nil
    }

    private func save() {
        guard let amount = Double(amountDigits), amount > 0 else {
            validationMessage = "Nominal tidak valid."
            showValidationAlert = true
            return
        }

        let title = titleText.isEmpty ? nil : titleText
        let detailNote = noteText.isEmpty ? nil : noteText

        Task {
            do {
                if isTransfer {
                    guard let sourceAccount = selectedAccount,
                          let targetAccount = selectedTargetAccount else {
                        validationMessage = "Pilih dompet sumber dan tujuan."
                        showValidationAlert = true
                        return
                    }
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: sourceAccount.id,
                        counterpartyAccountId: targetAccount.id,
                        amount: amount,
                        description: detailNote,
                        note: title,
                        date: selectedDate
                    )
                } else {
                    _ = try await SupabaseRepository.shared.createTransaction(
                        accountId: selectedAccount?.id ?? "",
                        categoryId: selectedCategory?.id,
                        amount: amount,
                        type: selectedType,
                        description: detailNote,
                        note: title,
                        date: selectedDate,
                        userId: userId
                    )
                }
                onSave()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                dismiss()
            } catch {
                validationMessage = "Gagal menyimpan transaksi: \(error.localizedDescription)"
                showValidationAlert = true
            }
        }
    }
}

private struct AmountInputSection: View {
    @Binding var amountText: String
    @Binding var amountDigits: String
    let typeColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("Rp")
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)

            TextField("0", text: $amountText)
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.leading)
                .onChange(of: amountText) { _, newValue in
                    let digits = String(newValue.filter { $0.isWholeNumber })
                    let formatted = digits.formattedWithThousandSeparator
                    if formatted != newValue {
                        amountText = formatted
                    }
                    amountDigits = digits
                }

            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
    }
}

#Preview {
    AddTransactionView(categories: [], accounts: [], userId: "", onSave: {})
}
