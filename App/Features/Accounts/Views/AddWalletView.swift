import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Account.AccountType
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedIcon: WalletIcon?
    @State private var showCustomSheet = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var creditLimitDigits = ""
    @State private var showCreditKeyboard = false
    @State private var selectedDueDay = 1

    let onSave: (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool

    init(initialType: Account.AccountType = .bank, onSave: @escaping (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool) {
        _category = State(initialValue: initialType)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                accountTypeSection
                iconSelectionSection
                nameSection
                if category == .credit {
                    creditLimitSection
                    dueDateSection
                } else {
                    balanceSection
                }
            }
            .overlay(alignment: .bottom) {
                if showKeyboard {
                    AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                        showKeyboard = false
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showCreditKeyboard {
                    AmountKeyboard(amountDigits: $creditLimitDigits, maxDigits: 12) {
                        showCreditKeyboard = false
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onTapGesture {
                showKeyboard = false
                showCreditKeyboard = false
            }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .animation(.easeInOut(duration: 0.25), value: showCreditKeyboard)
            .navigationTitle(category == .credit ? "Tambah Kartu Kredit" : "Tambah Dompet")
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
                if newValue == .cash {
                    selectedIcon = WalletIcon.icons(for: .cash).first
                    name = selectedIcon?.name ?? "Cash"
                } else {
                    selectedIcon = nil
                    if name == "Cash" { name = "" }
                }
            }
            .onChange(of: selectedIcon) { _, newValue in
                guard let icon = newValue else { return }
                if !icon.id.hasPrefix(WalletIcon.customPrefix), category == .cash {
                    name = icon.name
                }
            }
            .sheet(isPresented: $showCustomSheet) {
                CustomIconSheet { text, colorName in
                    let iconId = WalletIcon.customIconId(text: text, colorName: colorName)
                    let resolved = WalletIcon.resolve(iconId)!
                    selectedIcon = resolved
                    name = text
                }
            }
        }
    }

    // MARK: - Account Type

    private var accountTypeSection: some View {
        Section {
            Picker("Kategori", selection: $category) {
                ForEach(Account.AccountType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Icon Selection

    private var iconSelectionSection: some View {
        Group {
            if category == .cash {
                EmptyView()
            } else {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(WalletIcon.icons(for: category)) { icon in
                            walletIconButton(icon)
                        }
                        if category == .cash { customIconButton }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(category == .credit ? "Pilih Kartu" : category == .bank ? "Pilih Bank" : category == .ewallet ? "Pilih E-Wallet" : "Pilih Icon")
                }
            }
        }
    }

    private var customIconButton: some View {
        Button {
            showCustomSheet = true
        } label: {
            VStack(spacing: 4) {
                if let icon = selectedIcon, icon.id.hasPrefix(WalletIcon.customPrefix) {
                    WalletIconView(icon: icon, size: 52)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.2))
                            .frame(width: 52, height: 52)
                        Image(systemName: "plus")
                            .font(.jakarta(14, weight: .bold))
                            .foregroundColor(.appPrimary)
                    }
                }
                Text("Custom")
                    .font(.jakarta(9))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func walletIconButton(_ icon: WalletIcon) -> some View {
        let isSelected = selectedIcon?.id == icon.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedIcon = icon }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    WalletIconView(icon: icon, size: 48)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? Color.appPrimary.opacity(0.08) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Color.appPrimary : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: isSelected ? Color.appPrimary.opacity(0.15) : .clear, radius: 4, y: 2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.jakarta(14))
                            .foregroundColor(.appPrimary)
                            .background(Circle().fill(.white).frame(width: 16, height: 16))
                            .offset(x: -4, y: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if category != .credit {
                    Text(icon.name)
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name

    private var nameSection: some View {
        Section {
            TextField(category == .credit ? "Nama Kartu" : "Nama Dompet", text: $name)
        }
    }

    // MARK: - Balance

    private var balanceSection: some View {
        Section {
            HStack(spacing: 6) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { showKeyboard = true }
        } header: {
            Text("Saldo Awal")
        }
    }

    private var creditLimitSection: some View {
        Section {
            HStack(spacing: 6) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(creditLimitDigits.isEmpty ? "0" : creditLimitDigits.formattedWithThousandSeparator)
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { showCreditKeyboard = true }
        } header: {
            Text("Limit Kartu Kredit")
        }
    }

    private var dueDateSection: some View {
        Section {
            Picker("Tanggal", selection: $selectedDueDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.wheel)
        } header: {
            Text("Tanggal Jatuh Tempo (setiap bulan)")
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = category == .credit ? "Nama kartu wajib diisi." : "Nama dompet wajib diisi."
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
                toastMessage = category == .credit ? "Kartu kredit berhasil ditambahkan" : "Dompet berhasil ditambahkan"
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
            } else {
                toastMessage = category == .credit ? "Gagal menambahkan kartu kredit" : "Gagal menambahkan dompet"
                withAnimation { showToast = true }
            }
        }
    }
}
