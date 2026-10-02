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
    /// Keeps the form on `initialType`, e.g. a transfer started from a wallet.
    var locksType = false
    var initialAccount: Account?
    var editing: Transaction?
    var onUpdated: ((Transaction) -> Void)?

    @State private var typeIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var amount = 0
    @State private var isBumped = false
    @State private var shakeX: CGFloat = 0
    @State private var categoryShakeX: CGFloat = 0
    @State private var category: Category?
    @State private var account: Account?
    @State private var target: Account?
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var note = ""
    @FocusState private var noteFocused: Bool
    @State private var sheet: PickerKind?
    @State private var flashed: Set<PickerKind> = []
    @State private var isEntered = false
    @State private var isSaving = false
    @State private var done: DoneSummary?
    @State private var errorMessage: String?
    /// Sum of this month's budgets and every expense, for the daily-budget strip.
    @State private var monthlyBudget: Double = 0
    @State private var expenses: [Transaction] = []
    /// Every transaction, for "Terakhir dipakai" and "Sering dipakai" in the pickers.
    @State private var history: [Transaction] = []
    /// 0% installment months for a new card expense; 0 means none.
    @State private var installmentMonths = 0
    /// The expense saved but its installment didn't; closing after the alert avoids a duplicate on retry.
    @State private var closesAfterAlert = false
    /// Hidden flags and order for the category picker.
    @State private var preferences: [CategoryPreference] = []
    /// Also make this expense a recurring bill, posted again each period; nil for a one-off.
    @State private var repeatFrequency: CardSubscription.Frequency?
    /// Short screens (iPhone SE) get a tighter header, rows and keys so nothing runs under the pad.
    @State private var isCompact = false
    @State private var showsRepeatMenu = false
    /// One-line hint under the repeat icon, e.g. why it can't be used right now.
    @State private var repeatBubble: String?
    /// The first-time tooltip on the repeat icon; shown once, ever.
    @AppStorage("seenRepeatTip") private var seenRepeatTip = false
    @State private var showsRepeatTip = false

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
        if let editing { return editing.type == .transfer ? 2...2 : 0...1 }
        if locksType, let i = Self.types.firstIndex(where: { $0.type == initialType }) { return i...i }
        return 0...2
    }
    private var activeAccounts: [Account] {
        accounts.filter(\.isActive).sorted { $0.isDefault && !$1.isDefault }
    }
    private var targetAccounts: [Account] { activeAccounts.filter { !$0.isCreditCard } }
    private var isCardExpense: Bool { style.type == .expense && account?.isCreditCard == true }
    /// The plan that will actually be saved: only new card expenses can be split.
    private var planMonths: Int { isCardExpense && editing == nil ? installmentMonths : 0 }
    private static let installmentOptions = [0, 3, 6, 12, 24]
    /// New expenses can become a recurring bill, unless they're already split into installments.
    private var canRepeat: Bool { style.type == .expense && editing == nil && planMonths == 0 }
    private var repeatToSave: CardSubscription.Frequency? { canRepeat ? repeatFrequency : nil }
    private var categoryKind: CategoryType { style.type == .income ? .income : .expense }
    /// The picker's categories in the user's order, without hidden ones and Penyesuaian Saldo;
    /// a hidden one stays only when the transaction being edited already uses it.
    private var typeCategories: [Category] {
        let lists = categories.filter { $0.type == categoryKind && !CategoryCatalog.isSystem($0) }.arranged(by: preferences)
        var shown = lists.shown
        if let id = editing?.categoryId, let kept = lists.hidden.first(where: { $0.id == id }) {
            shown.append(kept)
        }
        return shown
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
        .task { await loadPreferences() }
        .alert("Gagal menyimpan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { if closesAfterAlert { dismiss() } }
        } message: { Text(errorMessage ?? "") }
    }

    private var form: some View {
        VStack(spacing: 0) {
            panel
            rows
                .padding(.top, isCompact ? 4 : 10)
            Spacer(minLength: isCompact ? 4 : 12)
            // The system keyboard replaces the number pad while typing a note.
            if !noteFocused {
                AmountPad(color: style.color, isEnabled: amount > 0 && (isTransfer || category != nil), isSaving: isSaving, onPress: press, onSave: save,
                          keyHeight: isCompact ? 46 : 52)
                    .animation(.easeInOut(duration: 0.4), value: typeIndex)
                    .disabled(isSaving || done != nil)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.height < 720 }) { isCompact = $0 }
        .simultaneousGesture(TapGesture().onEnded { hideRepeatTip() })
        .sheet(isPresented: $showsRepeatMenu) { repeatSheet }
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
            target = targetAccounts.first { $0.id != account?.id }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isEntered = true
        }
    }

    private func loadPreferences() async {
        guard let loaded = try? await SupabaseRepository.shared.fetchCategoryPreferences() else { return }
        preferences = loaded
    }

    private func loadBudgetData() async {
        async let budgets = SupabaseRepository.shared.fetchBudgets(userId: userId)
        async let transactions = SupabaseRepository.shared.fetchTransactions(userId: userId)
        monthlyBudget = ((try? await budgets) ?? []).filter(\.isActive).reduce(0) { $0 + $1.amount }
        // The transaction being edited is re-counted with its new amount as you type.
        let all = ((try? await transactions) ?? []).filter { $0.id != editing?.id }
        history = all
        expenses = all.filter { $0.type == .expense }
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
            ZStack {
                HStack {
                    Button("Batal") { dismiss() }
                        .font(.app(17))
                    Spacer()
                    repeatControl
                }
                if allowedTypes.count > 1 {
                    typeDots
                } else if editing != nil {
                    Text("Edit transaksi")
                        .font(.app(13))
                        .opacity(0.75)
                }
            }
            .frame(height: isCompact ? 40 : 44)
            .padding(.horizontal, 20)
            .zIndex(1)

            VStack(spacing: 0) {
                typeCarousel
                    .padding(.top, 4)
                amountText
                    .padding(.top, isCompact ? 4 : 12)
                info
                    .frame(height: isCompact ? 32 : 54, alignment: .top)
                    .padding(.horizontal, 24)
                    .padding(.top, isCompact ? 8 : 16)
            }
            .opacity(done == nil ? 1 : 0)
            .scaleEffect(done == nil ? 1 : 0.97)
            .offset(y: done == nil ? 0 : -14)
            .animation(.settle(0.42), value: done == nil)
            .overlay(alignment: .top) { doneOverlay }
        }
        .padding(.bottom, isCompact ? 12 : 18)
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
                    .opacity(isCurrent ? 1 : allowedTypes.contains(i) ? 0.45 : locksType ? 0 : 0.15)
                    .scaleEffect(isCurrent ? 1 : 0.8)
                    .animation(.settle(0.38), value: typeIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { setType(i) }
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                }
            }
            .offset(x: (geo.size.width - itemWidth) / 2 - CGFloat(typeIndex) * itemWidth + dragX)
        }
        .frame(height: isCompact ? 38 : 44)
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
                .font(.app(isCompact ? 44 : 56, weight: .light))
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

    private var incomeText: String { incomeMessage(done: false) }

    /// "Saldo X jadi Rp…" while typing, "Saldo X sekarang Rp…" once saved.
    private func incomeMessage(done: Bool) -> String {
        guard let account else { return "" }
        // When editing, the saved amount is already in the balance.
        let saved = editing?.type == .income && editing?.accountId == account.id ? editing?.amount ?? 0 : 0
        let next = account.balance - saved + Double(amount)
        let money = (next < 0 ? "−Rp" : "Rp") + next.formattedAsDigits()
        return done ? L("Saldo %@ sekarang %@", account.name, money) : L("Saldo %@ jadi %@", account.name, money)
    }

    private func walletChip(_ account: Account?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(walletColor(account))
                .frame(width: 16, height: 11)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.5), lineWidth: 1))
            Text(account?.name ?? L("Pilih"))
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
                Text(L("Sisa budget %@", TransactionDates.dayShort(date)))
                    .font(.app(13))
                    .opacity(0.85)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .opacity(left < 0 && daily > 0 ? 1 : 0)
                    Text(daily <= 0 ? "—" : left < 0 ? L("Lewat Rp%@", (-left).formattedAsDigits()) : "Rp" + left.formattedAsDigits())
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
            if !isCompact {
                Text(budgetFootnote(daily: daily, spent: spent, typed: typed))
                    .font(.app(12))
                    .opacity(0.75)
                    .padding(.top, 7)
            }
        }
        .monospacedDigit()
    }

    private func budgetFootnote(daily: Double, spent: Double, typed: Double) -> String {
        guard daily > 0 else { return L("Belum ada budget bulan ini") }
        let perDay = "Rp" + daily.formattedAsDigits()
        return typed > 0
            ? L("Sebelumnya Rp%@ · budget %@/hari", max(0, daily - spent).formattedAsDigits(), perDay)
            : L("Budget harian %@", perDay)
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

    // MARK: - Repeat (Ulangi)

    /// Only new expenses can repeat; a card's installment excludes it.
    private var showsRepeat: Bool { style.type == .expense && editing == nil }

    private static let repeatOptions: [(CardSubscription.Frequency?, String)] = [(nil, "Tidak"), (.monthly, "Tiap bulan"), (.yearly, "Tiap tahun")]

    /// The ↻ icon in the top corner, or a white pill with the next date once it's on.
    @ViewBuilder
    private var repeatControl: some View {
        if showsRepeat {
            let isOn = repeatToSave != nil
            Button {
                hideRepeatTip()
                if planMonths > 0 {
                    flashRepeatBubble(L("Matikan cicilan dulu"))
                } else {
                    showsRepeatMenu = true
                }
            } label: {
                Group {
                    if isOn {
                        Label(TransactionDates.dayMonth.string(from: nextRepeatDate), systemImage: "repeat")
                            .font(.app(14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(style.color)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(.white, in: Capsule())
                    } else {
                        Image(systemName: "repeat")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                }
                .opacity(planMonths > 0 ? 0.45 : 1)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(isOn ? L("Ulangi, berikutnya %@", TransactionDates.dayMonth.string(from: nextRepeatDate)) : L("Ulangi"))
            .overlay(alignment: .topTrailing) { repeatBubbles }
            .onAppear(perform: showRepeatTipOnce)
        }
    }

    /// The dark bubble under the icon: the one-time tooltip, or a short reason.
    @ViewBuilder
    private var repeatBubbles: some View {
        let text = repeatBubble ?? (showsRepeatTip ? L("Jadikan tagihan berulang") : nil)
        if let text, !showsRepeatMenu {
            Text(text)
                .font(.app(14, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "111111"), in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
                .offset(y: 46)
                .transition(.opacity.combined(with: .offset(y: -4)))
                .allowsHitTesting(false)
                .zIndex(5)
        }
    }

    private func showRepeatTipOnce() {
        guard !seenRepeatTip else { return }
        seenRepeatTip = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.25)) { showsRepeatTip = true }
            try? await Task.sleep(for: .seconds(5))
            hideRepeatTip()
        }
    }

    private func hideRepeatTip() {
        guard showsRepeatTip else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsRepeatTip = false }
    }

    private func flashRepeatBubble(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { repeatBubble = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) { repeatBubble = nil }
        }
    }

    /// Bottom sheet from the ↻ icon (Pengingat Tagihan 4b): pick Tidak / Tiap bulan / Tiap tahun,
    /// see the next date, then Selesai.
    private var repeatSheet: some View {
        PickerSheet(title: L("Tagihan berulang"), onDone: { showsRepeatMenu = false }) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Self.repeatOptions, id: \.1) { option, title in
                        Button {
                            withAnimation(.settle(0.3)) { repeatFrequency = option }
                        } label: {
                            HStack(spacing: 12) {
                                Text(L(title)).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                                Spacer()
                                if let option {
                                    Text(repeatMenuDate(option))
                                        .font(.app(14))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.appPrimary)
                                    .opacity(option == repeatFrequency ? 1 : 0)
                                    .frame(width: 16)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .rowSeparator()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityAddTraits(option == repeatFrequency ? .isSelected : [])
                    }
                }
                .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let frequency = repeatFrequency {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 38, height: 38)
                            .background(Color.appBackground, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tagihan berikutnya")
                                .font(.app(12))
                                .foregroundStyle(Color.appTextTertiary)
                            Text(Self.longDate.string(from: repeatDate(frequency)))
                                .font(.app(17, weight: .semibold))
                                .foregroundStyle(Color.appText)
                            Text("−Rp" + Double(amount).formattedAsDigits() + (account.map { " · " + $0.name } ?? ""))
                                .font(.app(13))
                                .monospacedDigit()
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 14)
                    .transition(.opacity)
                }

                Text("Dicatat otomatis sebagai pengeluaran saat kamu membuka Saku di tanggal itu. Tidak bisa digabung dengan Cicilan 0%.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private static var longDate: DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "EEEE, d MMM yyyy"
        return f
    }

    private func repeatMenuDate(_ frequency: CardSubscription.Frequency) -> String {
        let date = repeatDate(frequency)
        return frequency == .yearly ? TransactionDates.dayMonth.string(from: date) + " " + String(calendar.component(.year, from: date))
            : TransactionDates.dayMonth.string(from: date)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 0) {
            if isTransfer {
                row(.account, label: L("Dari"), value: account?.name ?? L("Pilih"), swatch: walletColor(account), index: 0)
                row(.target, label: L("Ke"), value: target?.name ?? L("Pilih"), swatch: walletColor(target), index: 1)
            } else {
                row(.category, label: L("Kategori"), value: category?.name ?? L("Belum dipilih"),
                    icon: category?.icon, iconColor: style.color, isPlaceholder: category == nil, index: 0)
                row(.account, label: L("Dompet"), value: account?.name ?? L("Pilih"), swatch: walletColor(account),
                    sub: isCardExpense && planMonths == 0 ? account.map(billingText) : nil, index: 1)
                if isCardExpense, let account, editing == nil {
                    row(.installment, label: L("Cicilan"), value: installmentMonths == 0 ? L("Tidak") : L("%lld bulan", installmentMonths),
                        icon: "calendar.badge.clock", iconColor: .appTextSecondary,
                        sub: planMonths > 0 ? planText(card: account) : nil, index: 1)
                }
            }
            row(.date, label: L("Tanggal"), value: dateValue, icon: "calendar", iconColor: .appTextSecondary, index: 2)

            HStack(spacing: 12) {
                Text("Catatan")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 76, alignment: .leading)
                TextField("Opsional", text: $note)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .submitLabel(.done)
                    .focused($noteFocused)
                    .onSubmit { noteFocused = false }
            }
            .frame(height: rowHeight)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rise(isEntered, y: 14, delay: 0.38, fade: 0.4, move: 0.5)
        }
        .opacity(done == nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: done == nil)
    }

    private func row(_ kind: PickerKind, label: String, value: String, swatch: Color? = nil,
                     icon: String? = nil, iconColor: Color = .appTextSecondary, sub: String? = nil,
                     isPlaceholder: Bool = false, index: Int) -> some View {
        Button {
            if done == nil { sheet = kind }
        } label: {
            DetailRow(label: label, value: value, swatch: swatch, icon: icon, iconColor: iconColor, sub: sub,
                      showsChevron: true, height: rowHeight, isPlaceholder: isPlaceholder)
                .background(flashed.contains(kind) ? style.color.opacity(0.1) : .clear)
                .animation(.easeInOut(duration: 0.45), value: flashed)
                .offset(x: kind == .category ? categoryShakeX : 0)
                .animation(.easeOut(duration: 0.06), value: categoryShakeX)
        }
        .buttonStyle(.plain)
        .rise(isEntered, y: 14, delay: 0.2 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    private var rowHeight: CGFloat { isCompact ? 46 : 48 }

    private var nextRepeatDate: Date { repeatDate(repeatFrequency ?? .monthly) }

    /// The bill after this one: a period on from the transaction, and never a day that is already
    /// past, so saving doesn't post extra transactions by itself.
    private func repeatDate(_ frequency: CardSubscription.Frequency) -> Date {
        let component: Calendar.Component = frequency == .yearly ? .year : .month
        let today = calendar.startOfDay(for: Date())
        var next = calendar.startOfDay(for: date)
        repeat {
            next = calendar.date(byAdding: component, value: 1, to: next) ?? today.addingTimeInterval(86_400)
        } while next <= today
        return next
    }

    private func billingText(card: Account) -> String {
        let billing = CreditStatement.billing(forPurchaseOn: date, card: card)
        return L("Tagihan %@ · bayar %@", TransactionDates.dayMonth.string(from: billing.statement), TransactionDates.dayMonth.string(from: billing.due))
    }

    private func planText(card: Account) -> String {
        let monthly = Double(amount) / Double(max(1, planMonths))
        let billing = CreditStatement.billing(forPurchaseOn: date, card: card)
        return L("Rp%@/bulan · mulai tagihan %@", monthly.formattedAsDigits(), TransactionDates.dayMonth.string(from: billing.statement))
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
            category = nil
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
        switch kind {
        case .category:
            CategoryPickerSheet(title: sheetTitle(kind), categories: typeCategories, selectedId: category?.id,
                                frequentIds: frequentCategoryIds, onDone: { sheet = nil }) { cat in
                pick(.category) { category = cat }
            }
        case .account, .target:
            let list = kind == .target ? targetAccounts : activeAccounts
            WalletPickerSheet(title: sheetTitle(kind), accounts: list,
                              selectedId: kind == .target ? target?.id : account?.id,
                              mainId: activeAccounts.first(where: \.isDefault)?.id,
                              recentIds: recentWalletIds(among: list), onDone: { sheet = nil }) { acc in
                pick(kind) { choose(acc, for: kind) }
            }
        default:
            optionSheet(kind)
        }
    }

    /// The last three wallets used, newest first.
    private func recentWalletIds(among list: [Account]) -> [String] {
        let allowed = Set(list.map(\.id))
        var seen: [String] = []
        for txn in history.newestFirst() {
            for id in [txn.accountId] + [txn.counterpartyAccountId].compactMap({ $0 }) where allowed.contains(id) && !seen.contains(id) {
                seen.append(id)
            }
            if seen.count >= 3 { break }
        }
        return seen
    }

    /// The categories used most for this kind of transaction, most used first.
    private var frequentCategoryIds: [String] {
        let allowed = Set(typeCategories.map(\.id))
        let counts = history.filter { $0.type == style.type }
            .compactMap(\.categoryId).filter(allowed.contains)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    @ViewBuilder
    private func optionSheet(_ kind: PickerKind) -> some View {
        PickerSheet(title: sheetTitle(kind), onDone: { sheet = nil }) {
            switch kind {
            case .category, .account, .target:
                EmptyView()
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
        case .category: L("Kategori")
        case .account: isTransfer ? L("Dari dompet") : L("Dompet")
        case .target: L("Ke dompet")
        case .date: L("Tanggal")
        case .installment: L("Cicilan 0%")
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
                        Text(months == 0 ? L("Tidak") : L("%lld bulan", months))
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
            shake($shakeX)
            return
        }
        guard let account else { return }
        guard isTransfer || category != nil else {
            shake($categoryShakeX)
            return
        }
        if isTransfer, target == nil || target?.id == account.id {
            errorMessage = L("Pilih dompet tujuan yang berbeda.")
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
                            errorMessage = L("Pengeluaran tersimpan, tapi cicilan gagal dibuat. %@", error.localizedDescription)
                            return
                        }
                    }
                    if let frequency = repeatToSave {
                        do {
                            await NotificationManager.shared.requestPermissionIfNeeded()
                            let bill = try await SupabaseRepository.shared.createSubscription(
                                accountId: account.id, name: description ?? category?.name ?? "Tagihan", amount: value,
                                frequency: frequency, nextBillingDate: Self.dayString(nextRepeatDate),
                                categoryId: category?.id, note: nil
                            )
                            await NotificationManager.shared.schedule(for: bill)
                        } catch {
                            isSaving = false
                            onSave()
                            NotificationCenter.default.post(name: .dataDidChange, object: nil)
                            closesAfterAlert = true
                            errorMessage = L("Pengeluaran tersimpan, tapi tagihan berulangnya gagal dibuat. %@", error.localizedDescription)
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

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func doneSummary(amount value: Double, account: Account) -> DoneSummary {
        let money = style.sign + "Rp" + value.formattedAsDigits()
        let day = TransactionDates.dayName(date)
        let detail = isTransfer
            ? money + " · " + day
            : money + " · " + (category?.name ?? L("Tanpa kategori")) + " · " + day
        let footnote: String
        switch style.type {
        case .expense:
            let left = dailyBudget - spentOnDate - value
            footnote = dailyBudget <= 0 ? ""
                : (left < 0 ? L("Lewat budget %@: Rp%@", TransactionDates.dayShort(date), abs(left).formattedAsDigits()) : L("Sisa budget %@: Rp%@", TransactionDates.dayShort(date), abs(left).formattedAsDigits()))
        case .income:
            footnote = incomeMessage(done: true)
        default:
            footnote = "\(account.name) → \(target?.name ?? "")"
        }
        let title = editing == nil ? L("%@ tersimpan", style.label) : L("Perubahan tersimpan")
        return DoneSummary(title: title, detail: detail, footnote: footnote)
    }

    private func shake(_ offset: Binding<CGFloat>) {
        Task {
            for x in [-10, 9, -6, 4, 0] as [CGFloat] {
                offset.wrappedValue = x
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
    /// A small grey line under the value.
    var sub: String?
    var showsChevron = false
    var height: CGFloat = 52
    /// Nothing chosen yet: the value reads grey.
    var isPlaceholder = false

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
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(isPlaceholder ? Color.appTextTertiary : Color.appText)
                        .lineLimit(1)
                    if let sub {
                        Text(sub)
                            .font(.app(12))
                            .foregroundStyle(Color.appTextSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
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
