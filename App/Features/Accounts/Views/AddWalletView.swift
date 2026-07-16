import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Account.AccountType
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedIcon: WalletIcon?
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var creditLimitDigits = ""
    @State private var showCreditKeyboard = false
    @State private var selectedDueDay = 1
    @State private var expandedIcons = false

    let onSave: (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool

    init(initialType: Account.AccountType = .bank, onSave: @escaping (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool) {
        _category = State(initialValue: initialType)
        self.onSave = onSave
    }

    private var typeColor: Color {
        switch category {
        case .cash: .appIncome
        case .bank: .appPrimary
        case .ewallet: .appWarning
        case .credit: .appExpense
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        iconSelectionSection
                        accountTypeSection
                        nameSection
                        if category == .credit {
                            creditLimitSection
                            dueDateSection
                        } else {
                            balanceSection
                        }
                    }
                    .padding(Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)

                if showKeyboard || showCreditKeyboard {
                    AmountKeyboard(amountDigits: showCreditKeyboard ? $creditLimitDigits : $amountDigits, maxDigits: 12) {
                        showKeyboard = false
                        showCreditKeyboard = false
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .animation(.easeInOut(duration: 0.25), value: showCreditKeyboard)
            .background(Color.appGroupedBackground)
            .navigationTitle(category == .credit ? "Tambah Kartu Kredit" : "Tambah Akun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.appPrimary)
                    } else {
                        Button("Simpan") { save() }
                            .font(.jakarta(15, weight: .semibold))
                    }
                }
            }
            .toast(isPresented: $showToast, message: toastMessage)
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .onChange(of: category) { _, newValue in
                expandedIcons = false
                if newValue == .cash {
                    selectedIcon = WalletIcon.icons(for: .cash).first
                    name = selectedIcon?.name ?? "Cash"
                } else {
                    selectedIcon = nil
                    if name == "Cash" { name = "" }
                }
            }
        }
    }

    // MARK: - Icon Grid

    private var iconSelectionSection: some View {
        VStack(spacing: Spacing.xs) {
            if category != .cash {
                let icons = WalletIcon.icons(for: category)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(expandedIcons ? icons : Array(icons.prefix(4))) { icon in
                        walletIconButton(icon)
                    }
                }

                if icons.count > 4 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expandedIcons.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expandedIcons ? "chevron.up" : "chevron.down")
                                .font(.jakarta(10))
                            Text(expandedIcons ? "Sembunyikan" : "Lihat Semua (\(icons.count))")
                                .font(.jakarta(12, weight: .medium))
                        }
                        .foregroundColor(.appPrimary)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func walletIconButton(_ icon: WalletIcon) -> some View {
        let isSelected = selectedIcon?.id == icon.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedIcon = icon }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    WalletIconView(icon: icon, size: 40)
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? typeColor.opacity(0.08) : Color(.systemGray5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? typeColor : Color.clear, lineWidth: 2)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.jakarta(12))
                            .foregroundColor(typeColor)
                            .background(Circle().fill(.white).frame(width: 14, height: 14))
                            .offset(x: -3, y: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account Type

    private var accountTypeSection: some View {
        HStack(spacing: 4) {
            typeBtn(title: "Cash", icon: "banknote.fill", type: .cash)
            typeBtn(title: "Bank", icon: "building.columns.fill", type: .bank)
            typeBtn(title: "E-Wallet", icon: "wallet.pass.fill", type: .ewallet)
            typeBtn(title: "Kartu Kredit", icon: "creditcard.fill", type: .credit)
        }
        .padding(4)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func typeBtn(title: String, icon: String, type: Account.AccountType) -> some View {
        let isActive = category == type
        return Button {
            withAnimation(.interactiveSpring(response: 0.25)) { category = type }
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon).font(.jakarta(16, weight: .semibold))
                Text(title).font(.jakarta(10, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundColor(isActive ? .white : .appTextSecondary)
            .background(isActive ? typeColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name

    private var nameSection: some View {
        HStack {
            TextField(category == .credit ? "Nama Kartu" : "Nama Akun", text: $name)
                .font(.jakarta(16))
                .padding(Spacing.md)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Balance

    private var balanceSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
                if !amountDigits.isEmpty {
                    Button { amountDigits = "" } label: {
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

            HStack {
                Text("Saldo Awal")
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var creditLimitSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(creditLimitDigits.isEmpty ? "0" : creditLimitDigits.formattedWithThousandSeparator)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
                if !creditLimitDigits.isEmpty {
                    Button { creditLimitDigits = "" } label: {
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
            .onTapGesture { showCreditKeyboard = true }

            HStack {
                Text("Limit Kartu Kredit")
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dueDateSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "calendar")
                    .font(.jakarta(14))
                    .foregroundColor(.appPrimary)
                Text("Jatuh Tempo")
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            Picker("Tanggal", selection: $selectedDueDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Save

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Nama wajib diisi."
            showValidationAlert = true
            return
        }
        if category != .cash, category != .credit {
            guard selectedIcon != nil else {
                validationMessage = "Pilih bank, e-wallet, atau custom terlebih dahulu."
                showValidationAlert = true
                return
            }
        }
        let balance = Double(amountDigits) ?? 0
        let creditLimit = category == .credit ? (Double(creditLimitDigits) ?? 0) : nil
        let dueDate = category == .credit ? String(selectedDueDay) : nil

        let iconId: String?
        if category == .cash {
            iconId = "cash"
        } else {
            iconId = selectedIcon?.id
        }

        isSaving = true
        Task {
            let success = await onSave(
                name.trimmingCharacters(in: .whitespaces),
                category,
                balance,
                iconId,
                creditLimit,
                dueDate
            )
            isSaving = false
            if success {
                toastMessage = "Berhasil ditambahkan"
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
            } else {
                toastMessage = "Gagal menambahkan"
                withAnimation { showToast = true }
            }
        }
    }
}
