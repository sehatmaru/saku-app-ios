import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Account.AccountType = .bank
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedIcon: WalletIcon?
    @State private var showCustomSheet = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    let onSave: (String, Account.AccountType, Double, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                accountTypeSection
                iconSelectionSection
                nameSection
                amountSection
            }
            .overlay(alignment: .bottom) {
                if showKeyboard {
                    AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                        showKeyboard = false
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onTapGesture { if showKeyboard { showKeyboard = false } }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .navigationTitle("Tambah Dompet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .font(.jakarta(15, weight: .semibold))
                }
            }
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
                    if name == "Cash" {
                        name = ""
                    }
                }
            }
            .onChange(of: selectedIcon) { _, newValue in
                guard let icon = newValue else { return }
                if !icon.id.hasPrefix(WalletIcon.customPrefix) {
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
                        customIconButton
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Pilih Icon")
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
                    Circle()
                        .fill(icon.color)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Text(icon.shortName)
                                .font(.jakarta(10, weight: .bold))
                                .foregroundColor(.white)
                        }
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
        Button {
            selectedIcon = icon
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(selectedIcon?.id == icon.id ? icon.color : icon.color.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Text(icon.shortName)
                        .font(.jakarta(10, weight: .bold))
                        .foregroundColor(selectedIcon?.id == icon.id ? .white : icon.color)
                }
                Text(icon.name)
                    .font(.jakarta(9))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name

    private var nameSection: some View {
        Section {
            TextField("Nama Dompet", text: $name)
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
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

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Nama dompet wajib diisi."
            showValidationAlert = true
            return
        }
        if category != .cash {
            guard selectedIcon != nil else {
                validationMessage = "Pilih bank, e-wallet, atau custom terlebih dahulu."
                showValidationAlert = true
                return
            }
        }
        let balance = Double(amountDigits) ?? 0

        let iconId: String?
        if category == .cash {
            iconId = "cash"
        } else {
            iconId = selectedIcon?.id
        }

        Task {
            await onSave(
                name.trimmingCharacters(in: .whitespaces),
                category,
                balance,
                iconId
            )
            dismiss()
        }
    }
}
