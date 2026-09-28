import SwiftUI

/// Manual entry: a coloured panel you swipe to change type (red expense, green income,
/// blue transfer), form rows below, and a numpad with Simpan. For expenses the panel
/// shows the day's remaining budget shrinking as you type.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let accounts: [Account]
    let userId: String
    let onSave: () -> Void
    var initialType: Transaction.TransactionType = .expense
    var initialAccount: Account?

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

    enum PickerKind: String, Identifiable {
        case category, account, target, date
        var id: String { rawValue }
    }

    private struct DoneSummary {
        let title: String
        let detail: String
        let footnote: String
    }

    private struct TypeStyle {
        let type: Transaction.TransactionType
        let label: String
        let icon: String
        let color: Color
        let sign: String
    }

    private static let types = [
        TypeStyle(type: .expense, label: "Pengeluaran", icon: "arrow.up.right", color: Color(hex: "D93636"), sign: "−"),
        TypeStyle(type: .income, label: "Pemasukan", icon: "arrow.down.left", color: Color(hex: "16875A"), sign: "+"),
        TypeStyle(type: .transfer, label: "Transfer", icon: "arrow.left.arrow.right", color: Color(hex: "143A73"), sign: ""),
    ]

    private var style: TypeStyle { Self.types[typeIndex] }
    private var isTransfer: Bool { style.type == .transfer }
    private var activeAccounts: [Account] {
        accounts.filter(\.isActive).sorted { $0.isDefault && !$1.isDefault }
    }
    private var targetAccounts: [Account] { activeAccounts.filter { !$0.isCreditCard } }
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
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var form: some View {
        VStack(spacing: 0) {
            panel
            rows
                .padding(.top, 10)
            Spacer(minLength: 12)
            numpad
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .sheet(item: $sheet) { kind in
            pickerSheet(kind)
                .presentationDetents([.height(470)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.appBackground)
        }
    }

    // MARK: - Setup and data

    private func setUp() {
        guard account == nil else { return }
        typeIndex = Self.types.firstIndex { $0.type == initialType } ?? 0
        account = initialAccount ?? activeAccounts.first
        category = typeCategories.first
        target = targetAccounts.first { $0.id != account?.id }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isEntered = true
        }
    }

    private func loadBudgetData() async {
        async let budgets = SupabaseRepository.shared.fetchBudgets(userId: userId)
        async let transactions = SupabaseRepository.shared.fetchTransactions(userId: userId)
        monthlyBudget = ((try? await budgets) ?? []).filter(\.isActive).reduce(0) { $0 + $1.amount }
        expenses = ((try? await transactions) ?? []).filter { $0.type == .expense }
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
                Label("Geser untuk ganti tipe", systemImage: "hand.draw")
                    .font(.app(13))
                    .opacity(0.75)
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
    }

    private var typeCarousel: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = 180
            HStack(spacing: 0) {
                ForEach(Self.types.indices, id: \.self) { i in
                    let isCurrent = i == typeIndex
                    Label(Self.types[i].label, systemImage: Self.types[i].icon)
                        .font(.app(22, weight: .bold))
                        .labelStyle(TypeLabelStyle())
                        .frame(width: itemWidth, height: 44)
                        .opacity(isCurrent ? 1 : 0.45)
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard done == nil else { return }
                    var dx = value.translation.width
                    if (typeIndex == 0 && dx > 0) || (typeIndex == Self.types.count - 1 && dx < 0) { dx *= 0.3 }
                    dragX = dx
                }
                .onEnded { _ in
                    let dx = dragX
                    let next = dx < -40 ? typeIndex + 1 : dx > 40 ? typeIndex - 1 : typeIndex
                    withAnimation(.settle(0.46)) { dragX = 0 }
                    setType(min(max(next, 0), Self.types.count - 1))
                }
        )
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
        return "Saldo \(account.name) jadi Rp" + (account.balance + Double(amount)).formattedAsDigits()
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
                Text("Sisa budget " + dayShort(date))
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
                            .animation(.easeInOut(duration: 0.4), value: typeIndex)
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
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .background(flashed.contains(kind) ? style.color.opacity(0.1) : .clear)
            .animation(.easeInOut(duration: 0.45), value: flashed)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rise(isEntered, y: 14, delay: 0.2 + Double(index) * 0.06, fade: 0.4, move: 0.5)
    }

    private var dateValue: String {
        let name = dayName(date)
        return calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
            ? name + " · " + Self.dayMonth.string(from: date)
            : name
    }

    /// "Hari ini", "Kemarin" or e.g. "Sel, 15 Sep".
    private func dayName(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hari ini" }
        if calendar.isDateInYesterday(date) { return "Kemarin" }
        return Self.weekdayDayMonth.string(from: date)
    }

    private func dayShort(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "hari ini" }
        if calendar.isDateInYesterday(date) { return "kemarin" }
        return Self.dayMonth.string(from: date)
    }

    // MARK: - Numpad

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "del"]

    private var numpad: some View {
        GeometryReader { geo in
            // 3:1 split between keys and Simpan, as in the design.
            let saveWidth = (geo.size.width - 6) / 4
            HStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Self.keys, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "del" {
                                    Image(systemName: "delete.left").font(.system(size: 22))
                                } else {
                                    Text(key).font(.app(24))
                                }
                            }
                            .foregroundStyle(Color.appText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(KeyStyle())
                        .accessibilityLabel(key == "del" ? "Hapus" : key)
                    }
                }
                .frame(width: geo.size.width - saveWidth - 6)

                Button(action: save) {
                    VStack(spacing: 6) {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                        }
                        Text("Simpan").font(.app(14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(amount > 0 ? style.color : Color(light: 0xC7C7CC, dark: 0x48484A), in: RoundedRectangle(cornerRadius: 14))
                    .animation(.easeInOut(duration: 0.4), value: typeIndex)
                    .animation(.easeInOut(duration: 0.4), value: amount > 0)
                }
                .buttonStyle(PressScaleStyle())
                .frame(width: saveWidth)
                .disabled(isSaving || done != nil)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 52 * 4 + 6 * 3)
    }

    private func press(_ key: String) {
        guard done == nil else { return }
        let next: Int
        switch key {
        case "del": next = amount / 10
        case "000": next = amount * 1000
        default: next = amount * 10 + (Int(key) ?? 0)
        }
        guard next <= 99_999_999_999 else { return }
        withAnimation(.snappy(duration: 0.2)) { amount = next }
        isBumped = true
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            isBumped = false
        }
    }

    // MARK: - Type and pickers

    private func setType(_ index: Int) {
        guard done == nil, index != typeIndex else { return }
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
        VStack(spacing: 0) {
            HStack {
                Text(sheetTitle(kind)).font(.app(17, weight: .semibold))
                Spacer()
                Button("Selesai") { sheet = nil }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            ScrollView {
                switch kind {
                case .category: categoryGrid
                case .account, .target: accountGrid(kind)
                case .date: calendarPicker
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.appText)
    }

    private func sheetTitle(_ kind: PickerKind) -> String {
        switch kind {
        case .category: "Kategori"
        case .account: isTransfer ? "Dari dompet" : "Dompet"
        case .target: "Ke dompet"
        case .date: "Tanggal"
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
            ForEach(typeCategories) { cat in
                let isOn = cat.id == category?.id
                Button {
                    pick(.category) { category = cat }
                } label: {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(isOn ? style.color : Color.appFill)
                            .frame(width: 54, height: 54)
                            .overlay {
                                Image(systemName: cat.icon ?? "tag")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isOn ? Color.white : Color.appText)
                            }
                            .scaleEffect(isOn ? 1.08 : 1)
                            .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: isOn)
                        Text(cat.name)
                            .font(.app(12))
                            .foregroundStyle(isOn ? Color.appText : Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func accountGrid(_ kind: PickerKind) -> some View {
        let list = kind == .target ? targetAccounts : activeAccounts
        let selectedId = kind == .target ? target?.id : account?.id
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(list) { acc in
                let isOn = acc.id == selectedId
                let color = walletColor(acc)
                Button {
                    pick(kind) { choose(acc, for: kind) }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(WalletIcon.resolve(acc.icon)?.shortName ?? String(acc.name.prefix(4)).uppercased())
                                .font(.app(10, weight: .heavy))
                                .tracking(0.5)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(isOn ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                        Text(acc.name)
                            .font(.app(14, weight: .semibold))
                            .lineLimit(1)
                        Text(acc.isCreditCard
                             ? "Sisa limit Rp" + (acc.availableCredit ?? 0).formattedAsDigits()
                             : "Rp" + acc.balance.formattedAsDigits())
                            .font(.app(12))
                            .opacity(0.82)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(height: 76)
                    .background(color, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if isOn {
                            RoundedRectangle(cornerRadius: 16).inset(by: -2).stroke(Color.appBackground, lineWidth: 2)
                            RoundedRectangle(cornerRadius: 18).inset(by: -4).stroke(color, lineWidth: 2)
                        }
                    }
                    .scaleEffect(isOn ? 1.03 : 1)
                    .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
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

    // MARK: - Calendar

    @State private var shownMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

    private var calendarPicker: some View {
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let isCurrentMonth = calendar.isDate(shownMonth, equalTo: today, toGranularity: .month)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                quickDay("Hari ini", today)
                quickDay("Kemarin", yesterday)
            }

            HStack {
                Text(Self.monthYear.string(from: shownMonth))
                    .font(.app(15, weight: .semibold))
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Bulan sebelumnya")
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Bulan berikutnya")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.appText)
            .padding(.top, 16)

            let grid = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: grid, spacing: 0) {
                ForEach(["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"], id: \.self) {
                    Text($0).font(.app(12)).foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
                }
            }
            .padding(.top, 10)

            LazyVGrid(columns: grid, spacing: 0) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    dayCell(day, today: today)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func quickDay(_ label: String, _ day: Date) -> some View {
        let isOn = calendar.isDate(date, inSameDayAs: day)
        return Button {
            pick(.date) { date = day; shownMonth = monthStart(day) }
        } label: {
            Text(label)
                .font(.app(15, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.appText)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(isOn ? style.color : Color.appBackground, in: Capsule())
                .overlay(Capsule().stroke(isOn ? style.color : Color.appBorder, lineWidth: 1))
                .animation(.easeInOut(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
    }

    /// Days of `shownMonth`, padded with nils so the 1st lands under its weekday (Monday first).
    private var monthCells: [Date?] {
        let count = calendar.range(of: .day, in: .month, for: shownMonth)?.count ?? 30
        let weekday = calendar.component(.weekday, from: shownMonth)
        let lead = (weekday + 5) % 7
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: shownMonth) }
        return Array(repeating: nil, count: lead) + days
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, today: Date) -> some View {
        if let day {
            let isOn = calendar.isDate(day, inSameDayAs: date)
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let isFuture = day > today
            Button {
                pick(.date) { date = day }
            } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.app(16, weight: isOn || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? Color.white : isFuture ? Color(light: 0xC7C7CC, dark: 0x48484A) : Color.appText)
                    .frame(width: 38, height: 38)
                    .background(isOn ? style.color : .clear, in: Circle())
                    .overlay {
                        if isToday && !isOn { Circle().inset(by: 0.75).stroke(style.color, lineWidth: 1.5) }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isOn)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private func monthStart(_ day: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
    }

    private func moveMonth(_ delta: Int) {
        shownMonth = calendar.date(byAdding: .month, value: delta, to: shownMonth) ?? shownMonth
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
        let summary = doneSummary(amount: value, account: account)
        isSaving = true
        Task {
            do {
                if isTransfer, let target {
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: account.id, counterpartyAccountId: target.id,
                        amount: value, description: noteText.isEmpty ? nil : noteText, note: nil, date: date
                    )
                } else {
                    _ = try await SupabaseRepository.shared.createTransaction(
                        accountId: account.id, categoryId: category?.id,
                        amount: value, type: style.type, description: noteText.isEmpty ? nil : noteText, note: nil,
                        date: date, userId: userId, isCreditAccount: account.isCreditCard
                    )
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
        let detail = isTransfer
            ? money + " · " + dayName(date)
            : money + " · " + (category?.name ?? "Tanpa kategori") + " · " + dayName(date)
        let footnote: String
        switch style.type {
        case .expense:
            let left = dailyBudget - spentOnDate - value
            footnote = dailyBudget <= 0 ? ""
                : (left < 0 ? "Lewat budget " : "Sisa budget ") + dayShort(date) + " Rp" + abs(left).formattedAsDigits()
        case .income:
            footnote = "Saldo \(account.name) sekarang Rp" + (account.balance + value).formattedAsDigits()
        default:
            footnote = "\(account.name) → \(target?.name ?? "")"
        }
        return DoneSummary(title: style.label + " tersimpan", detail: detail, footnote: footnote)
    }

    private func shake() {
        Task {
            for x in [-10, 9, -6, 4, 0] as [CGFloat] {
                shakeX = x
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func walletColor(_ account: Account?) -> Color {
        account.flatMap { WalletIcon.resolve($0.icon)?.color } ?? .appPrimary
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "id_ID")
        return f
    }

    private static let dayMonth = formatter("d MMM")
    private static let weekdayDayMonth = formatter("EEE, d MMM")
    private static let monthYear = formatter("MMMM yyyy")
}

/// Icon then title, with the design's 8pt gap and a smaller bold icon.
private struct TypeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 17, weight: .bold))
            configuration.title
        }
    }
}

/// Numpad key: light fill that darkens while pressed.
private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(light: 0xE5E5EA, dark: 0x3A3A3C) : Color(light: 0xF7F7F8, dark: 0x1C1C1E),
                        in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
