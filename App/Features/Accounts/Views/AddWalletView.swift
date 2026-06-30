import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Account.AccountType = .bank
    @State private var amountText = ""
    @State private var amountDigits = ""
    @State private var selectedIcon: WalletIcon?
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    let onSave: (String, Account.AccountType, Double, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kategori", selection: $category) {
                        ForEach(Account.AccountType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if category == .cash {
                    Section {
                        TextField("Nama Dompet", text: $name)
                        HStack {
                            Text("Rp")
                                .foregroundColor(.appTextSecondary)
                            TextField("Jumlah Awal", text: $amountText)
                                .keyboardType(.numberPad)
                        }
                    }
                } else {
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(iconsForCategory) { icon in
                                walletIconButton(icon)
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Pilih Icon")
                    }

                    Section {
                        TextField("Nama Dompet", text: $name)
                        HStack {
                            Text("Rp")
                                .foregroundColor(.appTextSecondary)
                            TextField("Jumlah Awal", text: $amountText)
                                .keyboardType(.numberPad)
                        }
                    }
                }

                Section {
                    Button("Simpan") {
                        save()
                    }
                    .frame(maxWidth: .infinity)
                    .font(.jakarta(17, weight: .semibold))
                    .foregroundColor(.appPrimary)
                }
            }
            .navigationTitle("Tambah Dompet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
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
                if let icon = newValue {
                    name = icon.name
                }
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

    private var iconsForCategory: [WalletIcon] {
        WalletIcon.icons(for: category)
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

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Nama dompet wajib diisi."
            showValidationAlert = true
            return
        }
        if category != .cash {
            guard selectedIcon != nil else {
                validationMessage = "Pilih icon terlebih dahulu."
                showValidationAlert = true
                return
            }
        }
        guard let balance = Double(amountDigits), balance >= 0 else {
            validationMessage = "Jumlah awal tidak valid."
            showValidationAlert = true
            return
        }

        Task {
            await onSave(
                name.trimmingCharacters(in: .whitespaces),
                category,
                balance,
                selectedIcon?.id ?? "cash"
            )
            dismiss()
        }
    }
}
