import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let accounts: [Account]
    let userId: String
    let onSave: () -> Void

    @State private var selectedType: Transaction.TransactionType = .expense
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var selectedTargetAccount: Account?
    @State private var selectedDate = Date()
    @State private var titleText = ""
    @State private var noteText = ""
    @State private var showCategoryPicker = false
    @State private var showWalletPicker = false
    @State private var showTargetWalletPicker = false
    @State private var showDatePicker = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var datePickerTemp = Date()

    private var activeAccounts: [Account] { accounts.filter { $0.isActive } }
    private var filteredCategories: [Category] {
        categories.filter { $0.type == (selectedType == .income ? .income : .expense) }
    }
    private var isTransfer: Bool { selectedType == .transfer }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        amountSection
                        typePickerSection
                        formCard
                    }
                    .padding(Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            .onTapGesture { if showKeyboard { showKeyboard = false } }

                if showKeyboard {
                    AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                        showKeyboard = false
                    }
                    .padding(.top, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .background(Color.appGroupedBackground)
            .navigationTitle("Tambah Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .font(.jakarta(15, weight: .bold))
                        .foregroundColor(canSave ? typeColor : .appTextSecondary.opacity(0.4))
                        .disabled(!canSave)
                }
            }
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(validationMessage) }
            .onAppear {
                if selectedAccount == nil { selectedAccount = activeAccounts.first }
                showKeyboard = true
            }
            .onChange(of: selectedType) { _, _ in
                if selectedCategory != nil && !filteredCategories.contains(where: { $0.id == selectedCategory?.id }) {
                    selectedCategory = nil
                }
            }
            .sheet(isPresented: $showCategoryPicker) { categoryPickerContent }
            .sheet(isPresented: $showWalletPicker) {
                walletPickerContent(title: "Pilih Dompet", list: activeAccounts.filter { $0.id != selectedTargetAccount?.id }, selectedId: selectedAccount?.id, onSelect: { selectedAccount = $0; showWalletPicker = false })
            }
            .sheet(isPresented: $showTargetWalletPicker) {
                walletPickerContent(title: "Pilih Dompet Tujuan", list: activeAccounts.filter { $0.id != selectedAccount?.id }, selectedId: selectedTargetAccount?.id, onSelect: { selectedTargetAccount = $0; showTargetWalletPicker = false })
            }
            .sheet(isPresented: $showDatePicker) { datePickerContent }
        }
    }

    private var typeColor: Color {
        switch selectedType {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .blue
        }
    }

    // MARK: Helpers

    private func accountIcon(_ acc: Account?) -> String {
        guard let acc else { return "wallet.pass.fill" }
        switch acc.type {
        case .bank: return "building.columns.fill"
        case .ewallet: return "wallet.pass.fill"
        case .cash: return "banknote.fill"
        }
    }
    private func accountColor(_ acc: Account?) -> Color {
        guard let acc, let wi = WalletIcon.resolve(acc.icon) else { return .appPrimary }
        return wi.color
    }
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }

    // MARK: Amount

    private var amountSection: some View {
        HStack(spacing: 4) {
            Text("Rp")
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
            Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
            Spacer()
            if !amountDigits.isEmpty {
                Button {
                    amountDigits = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.jakarta(20))
                        .foregroundColor(.appTextSecondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { showKeyboard = true }
    }

    // MARK: Type Picker

    private var typePickerSection: some View {
        HStack(spacing: 4) {
            typeBtn(title: "Pemasukan", icon: "arrow.down", type: .income)
            typeBtn(title: "Pengeluaran", icon: "arrow.up", type: .expense)
            typeBtn(title: "Transfer", icon: "arrow.left.arrow.right", type: .transfer)
        }
        .padding(4)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func typeBtn(title: String, icon: String, type: Transaction.TransactionType) -> some View {
        let isActive = selectedType == type
        return Button {
            withAnimation(.interactiveSpring(response: 0.25)) { selectedType = type }
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon).font(.jakarta(18, weight: .semibold))
                Text(title).font(.jakarta(11, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundColor(isActive ? .white : .appTextSecondary)
            .background(isActive ? typeColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Form Card

    private var formCard: some View {
        VStack(spacing: 0) {
            inputRow(icon: "pencil", iconColor: .appTextSecondary, label: "Judul") {
                TextField("Deskripsi transaksi", text: $titleText)
                    .font(.jakarta(15)).foregroundColor(.appText)
            } accessory: {
                if !titleText.isEmpty { clearBtn { titleText = "" } }
            }

            rowDivider

            if !isTransfer {
                tappableRow(icon: selectedCategory?.icon ?? "tag.fill", iconColor: typeColor, label: "Kategori", value: selectedCategory?.name ?? "Pilih", isSelected: selectedCategory != nil)
                    .onTapGesture { showCategoryPicker = true }
                rowDivider
            }

            if isTransfer {
                tappableWalletRow(icon: selectedAccount, label: "Dari Dompet", value: selectedAccount?.name ?? "Pilih", isSelected: selectedAccount != nil)
                    .onTapGesture { showWalletPicker = true }
                rowDivider
            }

            tappableWalletRow(icon: isTransfer ? selectedTargetAccount : selectedAccount, label: isTransfer ? "Ke Dompet" : "Dompet", value: (isTransfer ? selectedTargetAccount?.name : selectedAccount?.name) ?? "Pilih", isSelected: (isTransfer ? selectedTargetAccount : selectedAccount) != nil)
                .onTapGesture { if isTransfer { showTargetWalletPicker = true } else { showWalletPicker = true } }

            rowDivider

            tappableRow(icon: "calendar", iconColor: .appPrimary, label: "Tanggal", value: formattedDate(selectedDate), isSelected: true)
                .onTapGesture { datePickerTemp = selectedDate; showDatePicker = true }

            if !isTransfer {
                rowDivider
                inputRow(icon: "doc.text", iconColor: .appTextSecondary, label: "Catatan") {
                    TextField("Opsional", text: $noteText)
                        .font(.jakarta(15)).foregroundColor(.appText)
                } accessory: {
                    if !noteText.isEmpty { clearBtn { noteText = "" } }
                }
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Rows

    private func inputRow<Content: View, Accessory: View>(
        icon: String, iconColor: Color, label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: Spacing.md) {
            iconCircle(icon, iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.jakarta(10)).foregroundColor(.appTextSecondary)
                content()
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    private func tappableRow(icon: String, iconColor: Color, label: String, value: String, isSelected: Bool = false) -> some View {
        HStack(spacing: Spacing.md) {
            iconCircle(icon, isSelected ? iconColor : .appTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.jakarta(10)).foregroundColor(.appTextSecondary)
                Text(value).font(.jakarta(15)).foregroundColor(isSelected ? .appText : .appTextSecondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.jakarta(10)).foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func tappableWalletRow(icon account: Account?, label: String, value: String, isSelected: Bool) -> some View {
        let wi = account.flatMap { WalletIcon.resolve($0.icon) }
        return HStack(spacing: Spacing.md) {
            if let wi {
                ZStack {
                    Circle().fill(wi.color).frame(width: 34, height: 34)
                    Text(wi.shortName).font(.jakarta(8, weight: .bold)).foregroundColor(.white).minimumScaleFactor(0.7)
                }
            } else {
                iconCircle("wallet.pass.fill", isSelected ? .appPrimary : .appTextSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.jakarta(10)).foregroundColor(.appTextSecondary)
                Text(value).font(.jakarta(15)).foregroundColor(isSelected ? .appText : .appTextSecondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.jakarta(10)).foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func iconCircle(_ icon: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
            Image(systemName: icon).font(.jakarta(14, weight: .semibold)).foregroundColor(color)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func clearBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.jakarta(16))
                .foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Category Picker

    private var categoryPickerContent: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(filteredCategories) { cat in
                        chipBtn(icon: cat.icon ?? "tag", label: cat.name, color: typeColor, isSelected: selectedCategory?.id == cat.id) {
                            selectedCategory = cat; showCategoryPicker = false
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Kategori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { showCategoryPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private func chipBtn(icon: String, label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon).font(.jakarta(15)).foregroundColor(isSelected ? color : color.opacity(0.7))
                Text(label).font(.jakarta(14)).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.jakarta(11, weight: .bold)).foregroundColor(color) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(isSelected ? color.opacity(0.1) : Color.appCardBackground)
            .foregroundColor(isSelected ? color : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Wallet Picker

    private func walletPickerContent(title: String, list: [Account], selectedId: String?, onSelect: @escaping (Account) -> Void) -> some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(list) { acc in
                        let wi = WalletIcon.resolve(acc.icon)
                        Button { onSelect(acc) } label: {
                            HStack(spacing: Spacing.sm) {
                                ZStack {
                                    Circle().fill(wi?.color ?? .appPrimary).frame(width: 32, height: 32)
                                    Text(wi?.shortName ?? "").font(.jakarta(8, weight: .bold)).foregroundColor(.white).minimumScaleFactor(0.7)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.name).font(.jakarta(14)).fontWeight(selectedId == acc.id ? .semibold : .regular)
                                        .foregroundColor(selectedId == acc.id ? .appPrimary : .appText).lineLimit(1)
                                    Text(acc.balance.formattedAsCurrency()).font(.jakarta(10)).foregroundColor(.appTextSecondary).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                Spacer(minLength: 0)
                                if selectedId == acc.id { Image(systemName: "checkmark").font(.jakarta(11, weight: .bold)).foregroundColor(.appPrimary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 12)
                            .background(selectedId == acc.id ? Color.appPrimary.opacity(0.1) : Color.appCardBackground)
                            .foregroundColor(selectedId == acc.id ? .appPrimary : .appText)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { if title.contains("Tujuan") { showTargetWalletPicker = false } else { showWalletPicker = false } }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Date Picker

    private var datePickerContent: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                DatePicker("", selection: $datePickerTemp, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.appPrimary)
                    .labelsHidden()
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Tanggal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { showDatePicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pilih") { selectedDate = datePickerTemp; showDatePicker = false }
                        .font(.jakarta(15, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Save

    private var canSave: Bool {
        guard !amountDigits.isEmpty, let amount = Double(amountDigits), amount > 0 else { return false }
        if isTransfer { return selectedAccount != nil && selectedTargetAccount != nil }
        return selectedCategory != nil && selectedAccount != nil
    }

    private func save() {
        guard let amount = Double(amountDigits), amount > 0 else {
            validationMessage = "Nominal tidak valid."; showValidationAlert = true; return
        }
        let title = titleText.isEmpty ? nil : titleText
        let note = noteText.isEmpty ? nil : noteText
        Task {
            do {
                if isTransfer {
                    guard let src = selectedAccount, let dst = selectedTargetAccount else {
                        validationMessage = "Pilih dompet sumber dan tujuan."; showValidationAlert = true; return
                    }
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: src.id, counterpartyAccountId: dst.id,
                        amount: amount, description: note, note: title, date: selectedDate
                    )
                } else {
                    _ = try await SupabaseRepository.shared.createTransaction(
                        accountId: selectedAccount?.id ?? "", categoryId: selectedCategory?.id,
                        amount: amount, type: selectedType, description: note, note: title,
                        date: selectedDate, userId: userId
                    )
                }
                onSave()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                dismiss()
            } catch {
                validationMessage = "Gagal menyimpan: \(error.localizedDescription)"; showValidationAlert = true
            }
        }
    }
}

#Preview {
    AddTransactionView(categories: [], accounts: [], userId: "", onSave: {})
}
