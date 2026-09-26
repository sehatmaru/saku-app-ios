import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let accounts: [Account]
    let userId: String
    let onSave: () -> Void
    var initialType: Transaction.TransactionType = .expense
    var initialAccount: Account?

    @State private var selectedType: Transaction.TransactionType = .expense
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var selectedTargetAccount: Account?
    @State private var selectedDate = Date()
    @State private var titleText = ""
    @State private var showCategoryPicker = false
    @State private var showWalletPicker = false
    @State private var showTargetWalletPicker = false
    @State private var showDatePicker = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false
    @State private var showToast = false
    @State private var noteText = ""
    @State private var toastMessage = ""
    @State private var expandedWallets = false
    @State private var expandedCredits = false

    private var activeAccounts: [Account] {
        accounts.filter { $0.isActive }.sorted { $0.isDefault && !$1.isDefault }
    }
    private var walletAccounts: [Account] { activeAccounts.filter { !$0.isCreditCard } }
    private var creditAccounts: [Account] { activeAccounts.filter { $0.isCreditCard } }
    private var filteredCategories: [Category] {
        categories.filter { $0.type == (selectedType == .income ? .income : .expense) }
    }
    private var isTransfer: Bool { selectedType == .transfer }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if activeAccounts.isEmpty {
                    EmptyWalletView()
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.lg) {
                        amountSection
                        typePickerSection
                        formCard
                    }
                    .padding(Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .gesture(showKeyboard ? TapGesture().onEnded { showKeyboard = false } : nil)
                }

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
                    if isSaving {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        Button("Simpan") { save() }
                            .font(.app(15, weight: .bold))
                            .foregroundColor(canSave ? .appPrimary : .appTextSecondary.opacity(0.4))
                            .disabled(!canSave)
                    }
                }
            }
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(validationMessage) }
            .toast(isPresented: $showToast, message: toastMessage)
            .onAppear {
                if selectedAccount == nil {
                    selectedType = initialType
                    selectedAccount = initialAccount ?? activeAccounts.first { $0.isDefault } ?? activeAccounts.first
                }
                if !activeAccounts.isEmpty { showKeyboard = true }
            }
            .onChange(of: selectedType) { _, _ in
                if selectedCategory != nil && !filteredCategories.contains(where: { $0.id == selectedCategory?.id }) {
                    selectedCategory = nil
                }
            }
            .sheet(isPresented: $showCategoryPicker) { categoryPickerContent }
            .sheet(isPresented: $showWalletPicker) {
                accountPickerContent(
                    title: "Pilih Akun",
                    wallets: walletAccounts,
                    credits: creditAccounts,
                    selectedId: selectedAccount?.id,
                    onSelect: { selectedAccount = $0; showWalletPicker = false }
                )
            }
            .sheet(isPresented: $showTargetWalletPicker) {
                accountPickerContent(
                    title: "Pilih Dompet Tujuan",
                    wallets: walletAccounts,
                    credits: [],
                    selectedId: selectedTargetAccount?.id,
                    onSelect: { selectedTargetAccount = $0; showTargetWalletPicker = false }
                )
            }
            .sheet(isPresented: $showDatePicker) { datePickerContent }
        }
    }

    private var typeColor: Color {
        switch selectedType {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .blue
        case .adjustment: .appText
        }
    }

    // MARK: Helpers

    private func accountIcon(_ acc: Account?) -> String {
        guard let acc else { return "wallet.pass.fill" }
        switch acc.type {
        case .bank: return "building.columns.fill"
        case .ewallet: return "wallet.pass.fill"
        case .cash: return "banknote.fill"
        case .credit: return "creditcard.fill"
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
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Spacer()
            if !amountDigits.isEmpty {
                Button {
                    amountDigits = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(20))
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
                Image(systemName: icon).font(.app(18, weight: .semibold))
                Text(title).font(.app(11, weight: .medium))
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
                    .font(.app(15)).foregroundColor(.appText)
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

            tappableWalletRow(icon: isTransfer ? selectedTargetAccount : selectedAccount, label: isTransfer ? "Ke Dompet" : "Akun", value: (isTransfer ? selectedTargetAccount?.name : selectedAccount?.name) ?? "Pilih", isSelected: (isTransfer ? selectedTargetAccount : selectedAccount) != nil)
                .onTapGesture { if isTransfer { showTargetWalletPicker = true } else { showWalletPicker = true } }

            rowDivider

            tappableRow(icon: "calendar", iconColor: .appPrimary, label: "Tanggal", value: formattedDate(selectedDate), isSelected: true)
                .onTapGesture { showDatePicker = true }

            if !isTransfer {
                rowDivider
                inputRow(icon: "doc.text", iconColor: .appTextSecondary, label: "Catatan") {
                    TextField("Opsional", text: $noteText)
                        .font(.app(15)).foregroundColor(.appText)
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
                Text(label).font(.app(10)).foregroundColor(.appTextSecondary)
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
                Text(label).font(.app(10)).foregroundColor(.appTextSecondary)
                Text(value).font(.app(15)).foregroundColor(isSelected ? .appText : .appTextSecondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.app(10)).foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func tappableWalletRow(icon account: Account?, label: String, value: String, isSelected: Bool) -> some View {
        let wi = account.flatMap { WalletIcon.resolve($0.icon) }
        return HStack(spacing: Spacing.md) {
            if let wi {
                WalletIconView(icon: wi, size: 34)
            } else {
                iconCircle("wallet.pass.fill", isSelected ? .appPrimary : .appTextSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.app(10)).foregroundColor(.appTextSecondary)
                Text(value).font(.app(15)).foregroundColor(isSelected ? .appText : .appTextSecondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.app(10)).foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func iconCircle(_ icon: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
            Image(systemName: icon).font(.app(14, weight: .semibold)).foregroundColor(color)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func clearBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.app(16))
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
                Image(systemName: icon).font(.app(15)).foregroundColor(isSelected ? color : color.opacity(0.7))
                Text(label).font(.app(14)).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.app(11, weight: .bold)).foregroundColor(color) }
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

    private func accountPickerContent(title: String, wallets: [Account], credits: [Account], selectedId: String?, onSelect: @escaping (Account) -> Void) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !wallets.isEmpty {
                        sectionHeader("Dompet", count: wallets.count)
                        let displayWallets = expandedWallets ? wallets : Array(wallets.prefix(2))
                        ForEach(displayWallets) { acc in accountRow(acc, selectedId: selectedId, onSelect: onSelect) }
                        if wallets.count > 2 {
                            expandToggle($expandedWallets, count: wallets.count)
                        }
                    }

                    if !credits.isEmpty {
                        sectionHeader("Kartu Kredit", count: credits.count)
                        let displayCredits = expandedCredits ? credits : Array(credits.prefix(2))
                        ForEach(displayCredits) { acc in accountRow(acc, selectedId: selectedId, onSelect: onSelect) }
                        if credits.count > 2 {
                            expandToggle($expandedCredits, count: credits.count)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { showWalletPicker = false; showTargetWalletPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ name: String, count: Int) -> some View {
        HStack {
            Text(name)
                .font(.app(13, weight: .semibold))
                .foregroundColor(.appText)
            Spacer()
            Text("\(count)")
                .font(.app(11))
                .foregroundColor(.appTextSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func expandToggle(_ expanded: Binding<Bool>, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.app(10))
                Text(expanded.wrappedValue ? "Sembunyikan" : "Lihat Semua (\(count))")
                    .font(.app(12, weight: .medium))
            }
            .foregroundColor(.appPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func accountRow(_ acc: Account, selectedId: String?, onSelect: @escaping (Account) -> Void) -> some View {
        let wi = WalletIcon.resolve(acc.icon)
        return Button { onSelect(acc) } label: {
            HStack(spacing: Spacing.sm) {
                WalletIconView(icon: wi, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(acc.name).font(.app(14, weight: selectedId == acc.id ? .semibold : .regular))
                        .foregroundColor(selectedId == acc.id ? .appPrimary : .appText).lineLimit(1)
                    Text(acc.isCreditCard ? "Sisa Limit \(acc.availableCredit?.formattedAsCurrency() ?? "-")" : acc.balance.formattedAsCurrency())
                        .font(.app(10)).foregroundColor(.appTextSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selectedId == acc.id { Image(systemName: "checkmark").font(.app(11, weight: .bold)).foregroundColor(.appPrimary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .background(selectedId == acc.id ? Color.appPrimary.opacity(0.1) : Color.clear)
            .foregroundColor(selectedId == acc.id ? .appPrimary : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Date Picker

    private var datePickerContent: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.appPrimary)
                    .labelsHidden()
                    .onChange(of: selectedDate) { _, _ in showDatePicker = false }
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Tanggal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { showDatePicker = false } }
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
        isSaving = true
        Task {
            do {
                if isTransfer {
                    guard let src = selectedAccount, let dst = selectedTargetAccount else {
                        validationMessage = "Pilih dompet sumber dan tujuan."; showValidationAlert = true; isSaving = false; return
                    }
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: src.id, counterpartyAccountId: dst.id,
                        amount: amount, description: note, note: title, date: selectedDate
                    )
                } else {
                    _ = try await SupabaseRepository.shared.createTransaction(
                        accountId: selectedAccount?.id ?? "", categoryId: selectedCategory?.id,
                        amount: amount, type: selectedType, description: note, note: title,
                        date: selectedDate, userId: userId, isCreditAccount: selectedAccount?.isCreditCard ?? false
                    )
                }
                isSaving = false
                onSave()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                toastMessage = "Transaksi berhasil disimpan"
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                validationMessage = "Gagal menyimpan: \(error.localizedDescription)"; showValidationAlert = true
            }
        }
    }
}

struct EmptyWalletView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundColor(.appTextSecondary.opacity(0.5))
            Text("Belum ada dompet")
                .font(.app(17, weight: .semibold))
                .foregroundColor(.appText)
            Text("Buat dompet terlebih dahulu\nsebelum menambahkan transaksi.")
                .font(.app(13))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
