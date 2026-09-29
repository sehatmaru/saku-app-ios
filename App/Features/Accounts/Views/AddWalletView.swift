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
    @State private var selectedDueDay = 1
    /// Credit cards: cut-off day; nil when the user skips it.
    @State private var selectedStatementDay: Int?
    @FocusState private var nameFieldFocused: Bool

    let onSave: (String, Account.AccountType, Double, String?, Double?, String?, Int?) async -> Bool

    init(initialType: Account.AccountType = .bank, onSave: @escaping (String, Account.AccountType, Double, String?, Double?, String?, Int?) async -> Bool) {
        _category = State(initialValue: initialType)
        self.onSave = onSave
    }

    private var totalSteps: Int {
        switch category {
        case .cash: 3
        case .credit: 6
        default: 4
        }
    }

    private var canProceed: Bool {
        switch step {
        case 1: true
        case 2: category == .cash ? !name.trimmingCharacters(in: .whitespaces).isEmpty : selectedIcon != nil
        case 3: category == .cash ? true : !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 4, 5, 6: true
        default: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // Progress bar: finished steps can be tapped to jump back.
            HStack(spacing: 4) {
                ForEach(1...totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.appPrimary : Color.appDivider)
                        .frame(height: 6)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onTapGesture { if i < step { jumpToStep(i) } }
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.25), value: step)

            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case 1: typeStep
                    case 2: Group { if category == .cash { nameStep } else { iconStep } }
                    case 3: Group { if category == .cash { amountStep } else { nameStep } }
                    case 4: amountStep
                    case 5: creditStep
                    case 6: statementStep
                    default: EmptyView()
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

            // Navigation buttons
            HStack(spacing: 12) {
                if step > 1 {
                    Button {
                        withAnimation {
                            if step == 2 { selectedIcon = nil }
                            else if step == 3 { name = "" }
                            else if step == 4 { amountDigits = "" }
                            else if step == 5 { selectedDueDay = 1 }
                            else if step == 6 { selectedStatementDay = nil }
                            step -= 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Kembali")
                                .font(.app(16, weight: .semibold))
                        }
                        .foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                }

                Button {
                    if step == totalSteps {
                        save()
                    } else {
                        withAnimation { step += 1 }
                    }
                } label: {
                    Text(step == totalSteps ? "Simpan" : "Lanjut")
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appPrimary.opacity(canProceed ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canProceed)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.appBackground)
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
            if showKeyboard {
                AmountKeyboard(
                    amountDigits: $amountDigits,
                    maxDigits: 12,
                    onDone: {
                        showKeyboard = false
                        currentDetent = .medium
                    }
                )
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showKeyboard)
        .presentationDetents([.medium, .large], selection: $currentDetent)
        .presentationBackground(Color.appBackground)
    }

    private var topBar: some View {
        HStack {
            Button("Batal") { dismiss() }
                .font(.app(17))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
        }
        .overlay {
            Text("Tambah dompet")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func stepTitle(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.app(20, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.appText)
            if let subtitle {
                Text(subtitle)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.appPrimary)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Step 1: Type

    private var typeStep: some View {
        VStack(spacing: 0) {
            stepTitle("Pilih jenis dompet")
            typeRow(icon: "creditcard", title: "Kartu Kredit", desc: "VISA, MasterCard, JBC", type: .credit)
            typeRow(icon: "building.columns", title: "Bank", desc: "Rekening bank", type: .bank)
            typeRow(icon: "wallet.pass", title: "E-Wallet", desc: "Dompet digital", type: .ewallet)
            typeRow(icon: "banknote", title: "Cash", desc: "Tunai fisik", type: .cash)
        }
    }

    private func typeRow(icon: String, title: String, desc: String, type: Account.AccountType) -> some View {
        let isActive = category == type
        return Button {
            withAnimation(.interactiveSpring(response: 0.25)) {
                category = type
                selectedIcon = nil
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? Color.appText : Color.appTextSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(16, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color.appText)
                    Text(desc)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }

                Spacer()

                if isActive { checkmark }
            }
            .padding(.vertical, 12)
            .rowSeparator()
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Step 2: Icon

    private var iconStep: some View {
        VStack(spacing: 0) {
            stepTitle("Pilih \(category == .credit ? "kartu" : category == .bank ? "bank" : "e-wallet")")

            let icons = WalletIcon.icons(for: category)
            LazyVStack(spacing: 0) {
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
                WalletIconView(icon: icon, size: 28)
                    .frame(width: 28)

                Text(icon.name)
                    .font(.app(16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.appText)

                Spacer()

                if isSelected { checkmark }
            }
            .padding(.vertical, 12)
            .rowSeparator()
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Step 3: Name

    private var nameStep: some View {
        VStack(spacing: 0) {
            stepTitle("Nama \(category == .credit ? "kartu" : "dompet")", "Beri nama yang mudah dikenali")

            TextField(category == .credit ? "cth: BCA Visa Platinum" : "cth: BCA Payroll", text: $name)
                .font(.app(16))
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                .focused($nameFieldFocused)
                .submitLabel(.done)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 4: Amount

    private var amountStep: some View {
        VStack(spacing: 0) {
            stepTitle(category == .credit ? "Limit kartu kredit" : "Saldo awal",
                      category == .credit ? "Masukkan limit kartu kredit" : "Masukkan saldo saat ini")

            HStack(alignment: .center) {
                HeroAmount(value: Double(amountDigits) ?? 0, size: .medium)
                    .opacity(amountDigits.isEmpty ? 0.55 : 1)
                Spacer()
                if !amountDigits.isEmpty {
                    Button { amountDigits = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hapus nominal")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { showKeyboard = true }
        }
    }

    // MARK: - Step 5: Credit only (Due Date)

    private var creditStep: some View {
        VStack(spacing: 0) {
            stepTitle("Jatuh tempo", "Tagihan akan jatuh tempo setiap tanggal")

            HStack {
                Text("Tanggal jatuh tempo")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text("\(selectedDueDay)")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .monospacedDigit()
            }
            .frame(height: 44)
            .rowSeparator()
            .padding(.horizontal, 24)

            dayGrid(selected: selectedDueDay) { selectedDueDay = $0 }
        }
    }

    // MARK: - Step 6: Credit only (Statement day)

    private var statementStep: some View {
        VStack(spacing: 0) {
            stepTitle("Tanggal cetak tagihan", "Belanja sampai tanggal ini masuk tagihan bulan itu. Lewati jika belum tahu.")

            HStack {
                Text("Tanggal cetak tagihan")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text(selectedStatementDay.map { "\($0)" } ?? "Belum diatur")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(selectedStatementDay == nil ? Color.appTextTertiary : Color.appText)
                    .monospacedDigit()
            }
            .frame(height: 44)
            .rowSeparator()
            .padding(.horizontal, 24)

            dayGrid(selected: selectedStatementDay) { selectedStatementDay = $0 }
        }
    }

    /// Days 1–31 laid out like this month's calendar.
    private func dayGrid(selected: Int?, onPick: @escaping (Int) -> Void) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            let today = Date()
            let firstOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
            let offsetDays = Calendar.current.component(.weekday, from: firstOfMonth) - 1
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: today)?.count ?? 31
            ForEach(0..<offsetDays, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                let isSelected = day == selected
                Button {
                    withAnimation(.spring(response: 0.3)) { onPick(day) }
                } label: {
                    Text("\(day)")
                        .font(.app(16, weight: isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white : Color.appText)
                        .frame(width: 38, height: 38)
                        .background(isSelected ? Color.appPrimary : .clear, in: Circle())
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Navigation

    private func jumpToStep(_ target: Int) {
        let amountStep = category == .cash ? 3 : 4
        withAnimation {
            if target < 2 { selectedIcon = nil }
            if target < 3 { name = "" }
            if target < 4 { amountDigits = "" }
            if target < 5 { selectedDueDay = 1 }
            if target < 6 { selectedStatementDay = nil }
            step = target
            if step < amountStep {
                showKeyboard = false
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
        // A new card's amount step asks for its limit; it starts with nothing used.
        let amount = Double(amountDigits) ?? 0
        let balance = category == .credit ? 0 : amount
        let creditLimit = category == .credit ? amount : nil
        let dueDate = category == .credit ? String(selectedDueDay) : nil
        let statementDay = category == .credit ? selectedStatementDay : nil
        let iconId: String?
        if category == .cash { iconId = "cash" } else { iconId = selectedIcon?.id }

        isSaving = true
        Task {
            let success = await onSave(name.trimmingCharacters(in: .whitespaces), category, balance, iconId, creditLimit, dueDate, statementDay)
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
