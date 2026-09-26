import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var currentDetent: PresentationDetent = .medium
    @State private var category: Account.AccountType
    @State private var name = ""
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
    @FocusState private var nameFieldFocused: Bool

    let onSave: (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool

    init(initialType: Account.AccountType = .bank, onSave: @escaping (String, Account.AccountType, Double, String?, Double?, String?) async -> Bool) {
        _category = State(initialValue: initialType)
        self.onSave = onSave
    }

    private var totalSteps: Int {
        switch category {
        case .cash: 3
        case .credit: 5
        default: 4
        }
    }

    private var typeColor: Color {
        switch category {
        case .cash: .appIncome
        case .bank: .appPrimary
        case .ewallet: .appWarning
        case .credit: .appExpense
        }
    }

    private var canProceed: Bool {
        switch step {
        case 1: true
        case 2: category == .cash ? !name.trimmingCharacters(in: .whitespaces).isEmpty : selectedIcon != nil
        case 3: category == .cash ? true : !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 4, 5: true
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                HStack(spacing: 4) {
                    ForEach(1...totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color.appPrimary : Color(.systemGray5))
                            .frame(height: i < step ? 10 : 3)
                            .overlay(
                                i < step
                                    ? Color.clear.contentShape(Rectangle()).onTapGesture { jumpToStep(i) }
                                    : nil
                            )
                    }
                }
                .padding()

                // Step content
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        switch step {
                        case 1: typeStep
                        case 2: Group { if category == .cash { nameStep } else { iconStep } }
                        case 3: Group { if category == .cash { amountStep } else { nameStep } }
                        case 4: amountStep
                        case 5: creditStep
                        default: EmptyView()
                        }
                    }
                    .padding(Spacing.lg)
                }

                Spacer()

                // Navigation buttons
                HStack(spacing: Spacing.md) {
                    if step > 1 {
                        Button {
                            withAnimation {
                                if step == 2 { selectedIcon = nil }
                                else if step == 3 { name = "" }
                                else if step == 4 { amountDigits = ""; creditLimitDigits = "" }
                                else if step == 5 { selectedDueDay = 1 }
                                step -= 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.app(12, weight: .semibold))
                                Text("Kembali")
                                    .font(.app(15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray6))
                            .foregroundColor(.appText)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button {
                        if step == totalSteps {
                            save()
                        } else {
                            withAnimation { step += 1 }
                        }
                    } label: {
                        Text(step == totalSteps ? "Simpan" : "Lanjut")
                            .font(.app(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canProceed ? Color.appPrimary : Color.appPrimary.opacity(0.4))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canProceed)
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Tambah Akun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .toast(isPresented: $showToast, message: toastMessage)
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(validationMessage) }
            .onChange(of: step) { _, newValue in
                let nameStep = category == .cash ? 2 : 3
                let amountStep = category == .cash ? 3 : 4
                if newValue == nameStep {
                    nameFieldFocused = true
                } else if newValue == amountStep {
                    showKeyboard = true; currentDetent = .large
                }
            }
            .overlay(alignment: .bottom) {
                if showKeyboard || showCreditKeyboard {
                    AmountKeyboard(
                        amountDigits: showCreditKeyboard ? $creditLimitDigits : $amountDigits,
                        maxDigits: 12,
                        onDone: {
                            showKeyboard = false
                            showCreditKeyboard = false
                            currentDetent = .medium
                        }
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .animation(.easeInOut(duration: 0.25), value: showCreditKeyboard)
            .presentationDetents([.medium, .large], selection: $currentDetent)
        }
    }

    // MARK: - Step 1: Type

    private var typeStep: some View {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pilih Jenis Akun")
                    .font(.app(22, weight: .bold))
                    .foregroundColor(.appText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            typeRow(icon: "creditcard.fill", title: "Kartu Kredit", desc: "VISA, MasterCard, JBC", type: .credit)
            typeRow(icon: "building.columns.fill", title: "Bank", desc: "Rekening bank", type: .bank)
            typeRow(icon: "wallet.pass.fill", title: "E-Wallet", desc: "Dompet digital", type: .ewallet)
            typeRow(icon: "banknote.fill", title: "Cash", desc: "Tunai fisik", type: .cash)
        }
    }

    private func typeRow(icon: String, title: String, desc: String, type: Account.AccountType) -> some View {
        let isActive = category == type
        var cardColor: Color {
            switch type {
            case .cash: .appIncome
            case .bank: .appPrimary
            case .ewallet: .appWarning
            case .credit: .appExpense
            }
        }
        return Button {
            withAnimation(.interactiveSpring(response: 0.25)) {
                category = type
                selectedIcon = nil
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? cardColor : Color(.systemGray6))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.app(18, weight: .semibold))
                        .foregroundColor(isActive ? .white : cardColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(15, weight: .semibold))
                        .foregroundColor(.appText)
                    Text(desc)
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(20))
                        .foregroundColor(cardColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? cardColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Icon

    private var iconStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pilih \(category == .credit ? "Kartu" : category == .bank ? "Bank" : "E-Wallet")")
                    .font(.app(22, weight: .bold))
                    .foregroundColor(.appText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let icons = WalletIcon.icons(for: category)
            LazyVStack(spacing: 10) {
                ForEach(icons) { icon in
                    walletIconRow(icon)
                }
            }
        }
    }

    private func walletIconRow(_ icon: WalletIcon) -> some View {
        let isSelected = selectedIcon?.id == icon.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedIcon = icon }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                    WalletIconView(icon: icon, size: 24)
                }

                Text(icon.name)
                    .font(.app(15, weight: .medium))
                    .foregroundColor(.appText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(20))
                        .foregroundColor(typeColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appCardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? typeColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Name

    private var nameStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nama \(category == .credit ? "Kartu" : "Akun")")
                    .font(.app(22, weight: .bold))
                    .foregroundColor(.appText)
                Text("Beri nama yang mudah dikenali")
                    .font(.app(13))
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(category == .credit ? "cth: BCA Visa Platinum" : "cth: BCA Payroll", text: $name)
                .font(.app(16))
                .padding(Spacing.md)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .focused($nameFieldFocused)
        }
    }

    // MARK: - Step 4: Amount

    private var amountStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text(category == .credit ? "Limit Kartu Kredit" : "Saldo Awal")
                    .font(.app(22, weight: .bold))
                    .foregroundColor(.appText)
                Text(category == .credit ? "Masukkan limit kartu kredit" : "Masukkan saldo saat ini")
                    .font(.app(13))
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("Rp")
                        .font(.app(34, weight: .bold))
                        .foregroundColor(.appText)
                    Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                        .font(.app(34, weight: .bold))
                        .foregroundColor(.appText)
                    Spacer()
                    if !amountDigits.isEmpty {
                        Button { amountDigits = "" } label: {
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
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Step 5: Credit only (Due Date)

    private var creditStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Jatuh Tempo")
                    .font(.app(22, weight: .bold))
                    .foregroundColor(.appText)
                Text("Tagihan akan jatuh tempo setiap tanggal")
                    .font(.app(13))
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.app(14))
                        .foregroundColor(.appPrimary)
                    Text("Tanggal Tagihan")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text("\(selectedDueDay)")
                        .font(.app(20, weight: .bold))
                        .foregroundColor(.appPrimary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 4) {
                    let today = Date()
                    let firstOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
                    let offsetDays = Calendar.current.component(.weekday, from: firstOfMonth) - 1
                    let daysInMonth = Calendar.current.range(of: .day, in: .month, for: today)?.count ?? 31
                    ForEach(0..<offsetDays, id: \.self) { _ in
                        Color.clear
                            .padding(.vertical, 8)
                    }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        let isSelected = day == selectedDueDay
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedDueDay = day }
                        } label: {
                            Text("\(day)")
                                .font(.app(14, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .appText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.appPrimary : Color(.systemGray6))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Navigation

    private func jumpToStep(_ target: Int) {
        let amountStep = category == .cash ? 3 : 4
        withAnimation {
            if target < 2 { selectedIcon = nil }
            if target < 3 { name = "" }
            if target < 4 { amountDigits = ""; creditLimitDigits = "" }
            if target < 5 { selectedDueDay = 1 }
            step = target
            if step < amountStep {
                showKeyboard = false
                showCreditKeyboard = false
                currentDetent = .medium
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Nama wajib diisi."
            showValidationAlert = true; return
        }
        let balance = Double(amountDigits) ?? 0
        let creditLimit = category == .credit ? (Double(creditLimitDigits) ?? 0) : nil
        let dueDate = category == .credit ? String(selectedDueDay) : nil
        let iconId: String?
        if category == .cash { iconId = "cash" } else { iconId = selectedIcon?.id }

        isSaving = true
        Task {
            let success = await onSave(name.trimmingCharacters(in: .whitespaces), category, balance, iconId, creditLimit, dueDate)
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
