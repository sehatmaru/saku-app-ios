import SwiftUI

/// Manual entry: a coloured panel you swipe to change type (red expense, green income,
/// blue transfer), form rows below, and a numpad with Simpan. For expenses the panel
/// shows the day's remaining budget shrinking as you type.
///
/// Pass `editing` to reopen an existing transaction prefilled; Simpan then updates it.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let accounts: [Account]
    let userId: String
    let onSave: () -> Void
    var initialType: Transaction.TransactionType = .expense
    var initialAccount: Account?
    var editing: Transaction?
    var onUpdated: ((Transaction) -> Void)?

    @State private var typeIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var amount = 0
    @State private var isBumped = false
    @State private var shakeX: CGFloat = 0
    @State private var category: Category?
    @State private var account: Account?
    @State private var target: Account?
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var note = ""
    @State private var sheet: PickerKind?
    @State private var flashed: Set<PickerKind> = []
    @State private var isEntered = false
    @State private var isSaving = false
    @State private var done: DoneSummary?
    @State private var errorMessage: String?
    /// Sum of this month's budgets and every expense, for the daily-budget strip.
    @State private var monthlyBudget: Double = 0
    @State private var expenses: [Transaction] = []
    /// 0% installment months for a new card expense; 0 means none.
    @State private var installmentMonths = 0
    /// The expense saved but its installment didn't; closing after the alert avoids a duplicate on retry.
    @State private var closesAfterAlert = false

    enum PickerKind: String, Identifiable {
        case category, account, target, date, installment
        var id: String { rawValue }
    }

    private struct DoneSummary {
        let title: String
        let detail: String
        let footnote: String
    }

    private static let types = TransactionStyle.entryTypes

    private var style: TransactionStyle { Self.types[typeIndex] }
    private var isTransfer: Bool { style.type == .transfer }
    /// Editing keeps a transfer a transfer, and expense/income on their side of the carousel.
    private var allowedTypes: ClosedRange<Int> {
        guard let editing else { return 0...2 }
        return editing.type == .transfer ? 2...2 : 0...1
    }
    private var activeAccounts: [Account] {
        accounts.filter(\.isActive).sorted { $0.isDefault && !$1.isDefault }
    }
    private var targetAccounts: [Account] { activeAccounts.filter { !$0.isCreditCard } }
    private var isCardExpense: Bool { style.type == .expense && account?.isCreditCard == true }
    /// The plan that will actually be saved: only new card expenses can be split.
    private var planMonths: Int { isCardExpense && editing == nil ? installmentMonths : 0 }
    private static let installmentOptions = [0, 3, 6, 12, 24]
    private var typeCategories: [Category] {
        categories.filter { $0.type == (style.type == .income ? .income : .expense) }
    }

    var body: some View {
        Group {
            if activeAccounts.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Button("Batal") { dismiss() }
                        Spacer()
                    }
                    .padding(20)
                    EmptyWalletView()
                }
            } else {
                form
            }
        }
        .background(Color.appBackground)
        .onAppear(perform: setUp)
        .task { await loadBudgetData() }
        .alert("Gagal menyimpan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { if closesAfterAlert { dismiss() } }
        } message: { Text(errorMessage ?? "") }
    }

    private var form: some View {
        VStack(spacing: 0) {
            panel
            rows
                .padding(.top, 10)
            Spacer(minLength: 12)
            AmountPad(color: style.color, isEnabled: amount > 0, isSaving: isSaving, onPress: press, onSave: save)
                .animation(.easeInOut(duration: 0.4), value: typeIndex)
                .disabled(isSaving || done != nil)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .sheet(item: $sheet) { pickerSheet($0) }
    }

    // MARK: - Setup and data

    private func setUp() {
        guard account == nil else { return }
        if let editing {
            typeIndex = Self.types.firstIndex { $0.type == editing.type } ?? 0
            amount = Int(editing.amount)
            category = categories.first { $0.id == editing.categoryId }
            account = accounts.first { $0.id == editing.accountId }
            target = accounts.first { $0.id == editing.counterpartyAccountId }
            date = editing.date
            note = editing.description ?? ""
        } else {
            typeIndex = Self.types.firstIndex { $0.type == initialType } ?? 0
            account = initialAccount ?? activeAccounts.first
            category = typeCategories.first
            target = targetAccounts.first { $0.id != account?.id }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isEntered = true
        }
    }

    private func loadBudgetData() async {
        async let budgets = SupabaseRepository.shared.fetchBudgets(userId: userId)
        async let transactions = SupabaseRepository.shared.fetchTransactions(userId: userId)
        monthlyBudget = ((try? await budgets) ?? []).filter(\.isActive).reduce(0) { $0 + $1.amount }
        // The transaction being edited is re-counted with its new amount as you type.
        expenses = ((try? await transactions) ?? []).filter { $0.type == .expense && $0.id != editing?.id }
    }

    private var calendar: Calendar { .current }

    private var dailyBudget: Double {
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        return monthlyBudget / Double(days)
    }

    private var spentOnDate: Double {
        expenses.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .frame(width: 60, alignment: .leading)
                Spacer()
                if allowedTypes.count > 1 {
                    Label("Geser untuk ganti tipe", systemImage: "hand.draw")
                        .font(.app(13))
                        .opacity(0.75)
                } else {
                    Text("Edit transaksi")
                        .font(.app(13))
                        .opacity(0.75)
                }
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                typeCarousel
                    .padding(.top, 4)
                typeDots
                    .padding(.top, 6)
                amountText
                    .padding(.top, 16)
                info
                    .frame(height: 52)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
            }
            .opacity(done == nil ? 1 : 0)
            .scaleEffect(done == nil ? 1 : 0.97)
            .offset(y: done == nil ? 0 : -14)
            .animation(.settle(0.42), value: done == nil)
            .overlay(alignment: .top) { doneOverlay }
        }
        .padding(.bottom, 22)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(style.color)
                .animation(.easeInOut(duration: 0.45), value: typeIndex)
                .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .gesture(typeSwipe)
    }

    private var typeCarousel: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = 180
            HStack(spacing: 0) {
                ForEach(Self.types.indices, id: \.self) { i in
                    let isCurrent = i == typeIndex
                    HStack(spacing: 8) {
                        Image(systemName: Self.types[i].icon).font(.system(size: 17, weight: .bold))
                        Text(Self.types[i].label)
                    }
                    .font(.app(22, weight: .bold))
                    .frame(width: itemWidth, height: 44)
                    .opacity(isCurrent ? 1 : allowedTypes.contains(i) ? 0.45 : 0.15)
                    .scaleEffect(isCurrent ? 1 : 0.8)
                    .animation(.settle(0.38), value: typeIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { setType(i) }
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                }
            }
            .offset(x: (geo.size.width - itemWidth) / 2 - CGFloat(typeIndex) * itemWidth + dragX)
        }
        .frame(height: 44)
        .clipped()
    }

    /// Swiping anywhere on the coloured panel switches type, not just on the title.
    private var typeSwipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard done == nil else { return }
                var dx = value.translation.width
                if (typeIndex == allowedTypes.lowerBound && dx > 0) || (typeIndex == allowedTypes.upperBound && dx < 0) { dx *= 0.3 }
                dragX = dx
            }
            .onEnded { _ in
                let dx = dragX
                let next = dx < -40 ? typeIndex + 1 : dx > 40 ? typeIndex - 1 : typeIndex
                withAnimation(.settle(0.46)) { dragX = 0 }
                setType(min(max(next, allowedTypes.lowerBound), allowedTypes.upperBound))
            }
    }

    private var typeDots: some View {
        HStack(spacing: 6) {
            ForEach(Self.types.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: i == typeIndex ? 18 : 6, height: 6)
                    .opacity(i == typeIndex ? 1 : 0.5)
            }
        }
        .animation(.settle(0.3), value: typeIndex)
        .accessibilityHidden(true)
    }

    private var amountText: some View {
        HStack(alignment: .top, spacing: 4) {
            Text((amount > 0 ? style.sign : "") + "Rp")
                .font(.app(22))
                .opacity(0.75)
                .padding(.top, 8)
            Text(amount > 0 ? Double(amount).formattedAsDigits() : "0")
                .font(.app(56, weight: .light))
                .tracking(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .monospacedDigit()
        .padding(.horizontal, 24)
        .opacity(amount > 0 ? 1 : 0.55)
        .scaleEffect(isBumped ? 1.04 : 1)
        .offset(x: shakeX)
        .animation(.easeOut(duration: 0.12), value: isBumped)
        .animation(.easeOut(duration: 0.06), value: shakeX)
        .accessibilityElement()
        .accessibilityLabel("Nominal Rp\(amount)")
    }

    /// Budget strip for expenses, new balance for income, route for transfers; they crossfade.
    private var info: some View {
        ZStack {
            budgetStrip.opacity(style.type == .expense ? 1 : 0)
            Label(incomeText, systemImage: "wallet.bifold")
                .font(.app(15, weight: .medium))
                .monospacedDigit()
                .opacity(style.type == .income ? 1 : 0)
            HStack(spacing: 10) {
                walletChip(account)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.7)
                walletChip(target)
            }
            .font(.app(15, weight: .medium))
            .opacity(isTransfer ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.3), value: typeIndex)
    }

    private var incomeText: String {
        guard let account else { return "" }
        // When editing, the saved amount is already in the balance.
        let saved = editing?.type == .income && editing?.accountId == account.id ? editing?.amount ?? 0 : 0
        let next = account.balance - saved + Double(amount)
        return "Saldo \(account.name) jadi " + (next < 0 ? "−Rp" : "Rp") + next.formattedAsDigits()
    }

    private func walletChip(_ account: Account?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(walletColor(account))
                .frame(width: 16, height: 11)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.5), lineWidth: 1))
            Text(account?.name ?? "Pilih")
                .lineLimit(1)
        }
    }

    private var budgetStrip: some View {
        let daily = dailyBudget
        let spent = spentOnDate
        let typed = style.type == .expense ? Double(amount) : 0
        let left = daily - spent - typed
        let before = daily > 0 ? Int((min(1, spent / daily) * 30).rounded()) : 0
        let after = daily > 0 ? Int((min(1, (spent + typed) / daily) * 30).rounded()) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sisa budget " + TransactionDates.dayShort(date))
                    .font(.app(13))
                    .opacity(0.85)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .opacity(left < 0 && daily > 0 ? 1 : 0)
                    Text(daily <= 0 ? "—" : left < 0 ? "Lewat Rp" + (-left).formattedAsDigits() : "Rp" + left.formattedAsDigits())
                        .font(.app(15, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .animation(.easeInOut(duration: 0.2), value: left < 0)
            }
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < before ? Color.white : i < after ? Color.white.opacity(0.5) : Color.black.opacity(0.18))
                        .animation(.easeInOut(duration: 0.22).delay(Double(i) * 0.008), value: after)
                        .animation(.easeInOut(duration: 0.22).delay(Double(i) * 0.008), value: before)
                }
            }
            .frame(height: 6)
            .padding(.top, 8)
            Text(budgetFootnote(daily: daily, spent: spent, typed: typed))
                .font(.app(12))
                .opacity(0.75)
                .padding(.top, 7)
        }
        .monospacedDigit()
    }

    private func budgetFootnote(daily: Double, spent: Double, typed: Double) -> String {
        guard daily > 0 else { return "Belum ada budget bulan ini" }
        let perDay = "Rp" + daily.formattedAsDigits()
        return typed > 0
            ? "Sebelumnya Rp" + max(0, daily - spent).formattedAsDigits() + " · budget \(perDay)/hari"
            : "Budget harian \(perDay)"
    }

    @ViewBuilder
    private var doneOverlay: some View {
        let isDone = done != nil
        VStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(style.color)
                }
                .scaleEffect(isDone ? 1 : 0.4)
                .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.56), value: isDone)
            Text(done?.title ?? "")
                .font(.app(20, weight: .semibold))
                .padding(.top, 6)
            Text(done?.detail ?? "")
                .font(.app(14))
                .opacity(0.85)
            Text(done?.footnote ?? "")
                .font(.app(13))
                .opacity(0.75)
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isDone ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDone)
        .allowsHitTesting(false)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 0) {
            if isTransfer {
                row(.account, label: "Dari", value: account?.name ?? "Pilih", swatch: walletColor(account), index: 0)
                row(.target, label: "Ke", value: target?.name ?? "Pilih", swatch: walletColor(target), index: 1)
            } else {
                row(.category, label: "Kategori", value: category?.name ?? "Pilih",
                    icon: category?.icon ?? "tag", iconColor: style.color, index: 0)
                row(.account, label: "Dompet", value: account?.name ?? "Pilih", swatch: walletColor(account), index: 1)
                if isCardExpense, let account {
                    if planMonths == 0 {
                        cardCaption(billingText(card: account))
                    }
                    if editing == nil {
                        row(.installment, label: "Cicilan", value: installmentMonths == 0 ? "Tidak" : "\(installmentMonths) bulan",
                            icon: "calendar.badge.clock", iconColor: .appTextSecondary, index: 1)
                        if planMonths > 0 {
                            cardCaption(planText(card: account))
                        }
                    }
                }
            }
            row(.date, label: "Tanggal", value: dateValue, icon: "calendar", iconColor: .appTextSecondary, index: 2)

            HStack(spacing: 12) {
                Text("Catatan")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 76, alignment: .leading)
                TextField("Opsional", text: $note)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .submitLabel(.done)
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rise(isEntered, y: 14, delay: 0.38, fade: 0.4, move: 0.5)
        }
        .opacity(done == nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: done == nil)
    }

    private func row(_ kind: PickerKind, label: String, value: String, swatch: Color? = nil,
                     icon: String? = nil, iconColor: Color = .appTextSecondary, index: Int) -> some View {
        Button {
            if done == nil { sheet = kind }
        } label: {
            DetailRow(label: label, value: value, swatch: swatch, icon: icon, iconColor: iconColor, showsChevron: true)
                .background(flashed.contains(kind) ? style.color.opacity(0.1) : .clear)
                .animation(.easeInOut(duration: 0.45), value: flashed)
        }
        .buttonStyle(.plain)
        .rise(isEntered, y: 14, delay: 0.2 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    /// Small grey line under a card row: which statement this lands on, or the installment split.
    private func cardCaption(_ text: String) -> some View {
        Text(text)
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .transition(.opacity)
    }

    private func billingText(card: Account) -> String {
        let billing = CreditStatement.billing(forPurchaseOn: date, card: card)
        return "Masuk tagihan " + TransactionDates.dayMonth.string(from: billing.statement)
            + ", bayar " + TransactionDates.dayMonth.string(from: billing.due)
    }

    private func planText(card: Account) -> String {
        let monthly = Double(amount) / Double(max(1, planMonths))
        let billing = CreditStatement.billing(forPurchaseOn: date, card: card)
        return "Rp" + monthly.formattedAsDigits() + "/bulan · mulai tagihan " + TransactionDates.dayMonth.string(from: billing.statement)
    }

    private var dateValue: String {
        let name = TransactionDates.dayName(date)
        return calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
            ? name + " · " + TransactionDates.dayMonth.string(from: date)
            : name
    }

    // MARK: - Numpad

    private func press(_ key: String) {
        guard done == nil, let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.snappy(duration: 0.2)) { amount = next }
        isBumped = true
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            isBumped = false
        }
    }

    // MARK: - Type and pickers

    private func setType(_ index: Int) {
        guard done == nil, index != typeIndex, allowedTypes.contains(index) else { return }
        withAnimation(.settle(0.46)) { typeIndex = index }
        if !isTransfer {
            category = typeCategories.first
        } else if target == nil || target?.id == account?.id {
            target = targetAccounts.first { $0.id != account?.id }
        }
        flash([.category, .account, .target, .date])
    }

    private func flash(_ kinds: Set<PickerKind>) {
        flashed = kinds
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            flashed = []
        }
    }

    /// Applies a pick, then closes the sheet and flashes the row it changed.
    private func pick(_ kind: PickerKind, _ apply: () -> Void) {
        apply()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            sheet = nil
            flash(kind == .category || kind == .date ? [kind] : isTransfer ? [.account, .target] : [kind])
        }
    }

    @ViewBuilder
    private func pickerSheet(_ kind: PickerKind) -> some View {
        PickerSheet(title: sheetTitle(kind), onDone: { sheet = nil }) {
            switch kind {
            case .category:
                CategoryPickerGrid(categories: typeCategories, selectedId: category?.id, color: style.color) { cat in
                    pick(.category) { category = cat }
                }
            case .account, .target:
                WalletPickerGrid(accounts: kind == .target ? targetAccounts : activeAccounts,
                                 selectedId: kind == .target ? target?.id : account?.id) { acc in
                    pick(kind) { choose(acc, for: kind) }
                }
            case .date:
                DayPicker(selected: date, color: style.color) { day in
                    pick(.date) { date = keepingTime(of: date, on: day) }
                }
            case .installment:
                installmentChips
            }
        }
    }

    private func sheetTitle(_ kind: PickerKind) -> String {
        switch kind {
        case .category: "Kategori"
        case .account: isTransfer ? "Dari dompet" : "Dompet"
        case .target: "Ke dompet"
        case .date: "Tanggal"
        case .installment: "Cicilan 0%"
        }
    }

    private var installmentChips: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Self.installmentOptions, id: \.self) { months in
                    let isOn = months == installmentMonths
                    Button {
                        pick(.installment) { installmentMonths = months }
                    } label: {
                        Text(months == 0 ? "Tidak" : "\(months) bulan")
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isOn ? Color.appText : Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text("Seluruh nominal langsung memakai limit kartu, tapi tiap tagihan hanya menagih satu bagian.")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    /// Picking the other side of a transfer swaps the two wallets.
    private func choose(_ acc: Account, for kind: PickerKind) {
        if kind == .target {
            if acc.id == account?.id { account = target }
            target = acc
        } else {
            if isTransfer, acc.id == target?.id {
                target = account?.isCreditCard == false ? account : targetAccounts.first { $0.id != acc.id }
            }
            account = acc
        }
    }

    /// Moves `date` to `day` but keeps its time, so edits don't reset a recorded time to midnight.
    private func keepingTime(of date: Date, on day: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }

    // MARK: - Save

    private func save() {
        guard done == nil, !isSaving else { return }
        guard amount > 0 else {
            shake()
            return
        }
        guard let account else { return }
        if isTransfer, target == nil || target?.id == account.id {
            errorMessage = "Pilih dompet tujuan yang berbeda."
            return
        }
        let value = Double(amount)
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = noteText.isEmpty ? nil : noteText
        let summary = doneSummary(amount: value, account: account)
        isSaving = true
        Task {
            do {
                if let editing {
                    let updated = try await SupabaseRepository.shared.updateTransaction(
                        id: editing.id, accountId: account.id, counterpartyAccountId: isTransfer ? target?.id : nil,
                        categoryId: isTransfer ? nil : category?.id, amount: value, type: style.type,
                        description: description, note: editing.note, date: date
                    )
                    onUpdated?(updated)
                } else if isTransfer, let target {
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: account.id, counterpartyAccountId: target.id,
                        amount: value, description: description, note: nil, date: date
                    )
                } else {
                    let created = try await SupabaseRepository.shared.createTransaction(
                        accountId: account.id, categoryId: category?.id,
                        amount: value, type: style.type, description: description, note: nil,
                        date: date, userId: userId, isCreditAccount: account.isCreditCard
                    )
                    if planMonths > 0 {
                        do {
                            try await SupabaseRepository.shared.createInstallment(
                                accountId: account.id, transactionId: created.id, months: planMonths
                            )
                        } catch {
                            isSaving = false
                            onSave()
                            NotificationCenter.default.post(name: .dataDidChange, object: nil)
                            closesAfterAlert = true
                            errorMessage = "Pengeluaran tersimpan, tapi cicilan gagal dibuat. " + error.localizedDescription
                            return
                        }
                    }
                }
                isSaving = false
                done = summary
                onSave()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            } catch is CancellationError {
                isSaving = false
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func doneSummary(amount value: Double, account: Account) -> DoneSummary {
        let money = style.sign + "Rp" + value.formattedAsDigits()
        let day = TransactionDates.dayName(date)
        let detail = isTransfer
            ? money + " · " + day
            : money + " · " + (category?.name ?? "Tanpa kategori") + " · " + day
        let footnote: String
        switch style.type {
        case .expense:
            let left = dailyBudget - spentOnDate - value
            footnote = dailyBudget <= 0 ? ""
                : (left < 0 ? "Lewat budget " : "Sisa budget ") + TransactionDates.dayShort(date) + " Rp" + abs(left).formattedAsDigits()
        case .income:
            footnote = incomeText.replacingOccurrences(of: " jadi ", with: " sekarang ")
        default:
            footnote = "\(account.name) → \(target?.name ?? "")"
        }
        let title = editing == nil ? style.label + " tersimpan" : "Perubahan tersimpan"
        return DoneSummary(title: title, detail: detail, footnote: footnote)
    }

    private func shake() {
        Task {
            for x in [-10, 9, -6, 4, 0] as [CGFloat] {
                shakeX = x
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}

/// One form row: grey label, optional wallet swatch or icon, value, optional chevron.
struct DetailRow: View {
    let label: String
    let value: String
    var swatch: Color?
    var icon: String?
    var iconColor: Color = .appTextSecondary
    var showsChevron = false
    var height: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 8) {
                if let swatch {
                    RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 20, height: 14)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(iconColor)
                }
                Text(value)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                .opacity(showsChevron ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: showsChevron)
        }
        .frame(height: height)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
        .contentShape(Rectangle())
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
