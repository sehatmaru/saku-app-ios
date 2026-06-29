import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

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

    private let categories = Category.sample
    private let accounts = Account.sample.filter { $0.isActive }

    private var filteredCategories: [Category] {
        let target: CategoryType = selectedType == .income ? .income : .expense
        return categories.filter { $0.type == target }
    }

    private var isTransfer: Bool {
        selectedType == .transfer
    }

    private var typeColor: Color {
        selectedType == .income ? .appIncome : selectedType == .expense ? .appExpense : .appPrimary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    typeSection
                    AmountInputSection(amountText: $amountText, amountDigits: $amountDigits, typeColor: typeColor)
                    dateSection
                    if !isTransfer {
                        titleSection
                        categorySection
                    }
                    walletSection
                    noteSection
                    saveButton
                }
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Tambah Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .onChange(of: selectedType) { _, _ in
                selectedCategory = nil
                selectedTargetAccount = nil
                showAllCategories = false
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
        }
    }

    // MARK: Type Section
    private var typeSection: some View {
        HStack(spacing: Spacing.sm) {
            typeButton(type: .income, icon: "arrow.down.left", color: .appIncome, label: "Pemasukan")
            typeButton(type: .expense, icon: "arrow.up.right", color: .appExpense, label: "Pengeluaran")
            typeButton(type: .transfer, icon: "arrow.left.arrow.right", color: .appPrimary, label: "Transfer")
        }
    }

    private func typeButton(type: Transaction.TransactionType, icon: String, color: Color, label: String) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.jakarta(18, weight: .semibold))
                Text(label)
                    .font(.jakarta(11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? color.opacity(0.12) : Color.appCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? color : Color(.systemGray4), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .foregroundColor(isSelected ? color : .appTextSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Note Section

    // MARK: Date Section
    private var dateSection: some View {
        Button {
            showDatePicker = true
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "calendar")
                        .font(.jakarta(13))
                        .foregroundColor(.appTextSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tanggal")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Text(selectedDate.formatted(date: .long, time: .omitted))
                        .font(.jakarta(15, weight: .medium))
                        .foregroundColor(.appText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: Title Section
    private var titleSection: some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.appTextSecondary.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.alignleft")
                        .font(.jakarta(13))
                        .foregroundColor(.appTextSecondary)
                }

                TextField("Judul transaksi (opsional)", text: $titleText)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Kategori", icon: "square.grid.2x2")

            let items = showAllCategories
                ? filteredCategories
                : Array(filteredCategories.prefix(4))

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

            let available = accounts.filter { exclude == nil || $0.id != exclude?.id }
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
                Image(systemName: category.icon)
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
        let wi = WalletIcon.allIcons.first { $0.id == account.icon }
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

    // MARK: Save Button
    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Simpan")
                .font(.jakarta(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canSave ? Color.appPrimary : Color.appPrimary.opacity(0.4))
                )
                .foregroundColor(.white)
        }
        .disabled(!canSave)
        .buttonStyle(.plain)
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

        var finalNote = ""
        if isTransfer {
            if !titleText.isEmpty {
                finalNote = titleText
            }
        } else {
            finalNote = titleText
        }
        if !noteText.isEmpty {
            if finalNote.isEmpty {
                finalNote = noteText
            } else {
                finalNote += "\n\(noteText)"
            }
        }

        let transaction = Transaction(
            id: UUID().uuidString,
            accountId: isTransfer ? (selectedAccount?.id ?? "") : (selectedAccount?.id ?? ""),
            categoryId: selectedCategory?.id,
            subcategoryId: nil,
            amount: amount,
            type: selectedType,
            note: finalNote.isEmpty ? nil : finalNote,
            date: selectedDate
        )

        print("Transaction saved: \(transaction)")
        dismiss()
    }
}

// MARK: - Isolated Amount Input

struct AmountInputSection: View {
    @Binding var amountText: String
    @Binding var amountDigits: String
    let typeColor: Color
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                TextField("0", text: $amountText)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                    .focused($isAmountFocused)
                Spacer()
                if !amountDigits.isEmpty {
                    Button {
                        amountText = ""
                        amountDigits = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.jakarta(20))
                            .foregroundColor(.appTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.xl)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture {
            isAmountFocused = true
        }
        .onAppear {
            isAmountFocused = true
        }
        .onChange(of: amountText) { _, newValue in
            let digits = String(newValue.filter { $0.isWholeNumber })
            let formatted = digits.formattedWithThousandSeparator
            if formatted != newValue {
                amountText = formatted
            }
            amountDigits = digits
        }
    }
}
