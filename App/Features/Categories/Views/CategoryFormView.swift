import SwiftUI

/// Icons, colours and naming rules shared by Kelola kategori and its form.
/// Icons are SF Symbol names, colours "#RRGGBB", like the seeded ones.
enum CategoryCatalog {
    /// Every icon on offer in one open pool, no grouping. Names this iOS doesn't know are dropped.
    static let allIcons: [String] = [
        "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass", "mug", "birthday.cake",
        "carrot", "fish", "leaf", "cart", "basket", "bag", "gift", "tshirt", "scissors", "shippingbox",
        "car", "bus", "tram", "bicycle", "scooter", "airplane", "ferry", "fuelpump", "parkingsign",
        "house", "bed.double", "sofa", "lightbulb", "bolt", "drop", "flame", "wifi", "tv", "washer",
        "key", "hammer", "paintbrush", "phone", "envelope", "printer",
        "film", "gamecontroller", "music.note", "headphones", "ticket", "camera", "theatermasks",
        "party.popper", "book", "graduationcap", "pencil", "backpack", "books.vertical",
        "heart", "pills", "cross.case", "stethoscope", "bandage", "eyeglasses", "dumbbell",
        "figure.run", "figure.walk", "figure.2.and.child.holdinghands", "pawprint",
        "briefcase", "banknote", "creditcard", "wallet.bifold", "chart.line.uptrend.xyaxis",
        "dollarsign.circle", "percent", "storefront", "building.2", "hand.raised", "globe",
        "sun.max", "moon", "umbrella", "star", "flag", "gearshape", "tag", "ellipsis",
    ].filter { UIImage(systemName: $0) != nil }
    static let colors = ["#D93636", "#E8772E", "#D9A21B", "#16875A", "#0E8C8C",
                         "#1F6FD1", "#143A73", "#6B4BC8", "#C2417A", "#6E6E73"]
    /// The icons shown first, in the order of the design; the rest sit behind "Lihat semua ikon".
    static let featuredIcons: [String] = [
        "fork.knife", "cup.and.saucer", "cart", "basket", "car", "house", "phone", "heart", "dumbbell",
        "gamecontroller", "film", "dollarsign.circle", "bag", "airplane", "pawprint", "gift", "book",
        "chart.line.uptrend.xyaxis",
    ].filter { allIcons.contains($0) }

    static func visibleIcons(expanded: Bool) -> [String] { expanded ? allIcons : featuredIcons }
    /// A category whose icon is outside the first set opens with the whole list, so its icon is in view.
    static func needsAllIcons(for icon: String) -> Bool { !featuredIcons.contains(icon) }

    static let defaultIcon = "cart"
    static let defaultColor = "#1F6FD1"

    /// "Penyesuaian Saldo": used by balance corrections on its own, never listed or offered.
    static func isSystem(_ category: Category) -> Bool { category.systemKey == "adjustment" }

    /// Why `name` can't be saved for `type`, or nil. Duplicates count hidden categories too.
    static func validate(_ name: String, type: CategoryType, excluding id: String?,
                         in categories: [Category], hiddenIds: Set<String>) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return L("Nama belum diisi") }
        if trimmed.lowercased() == "penyesuaian saldo" { return L("Nama dipakai sistem") }
        if let dup = categories.first(where: {
            $0.type == type && $0.id != id && !isSystem($0) && $0.name.lowercased() == trimmed.lowercased()
        }) {
            return hiddenIds.contains(dup.id) ? L("Sudah ada “%@” (disembunyikan)", dup.name) : L("Sudah ada “%@”", dup.name)
        }
        return nil
    }

    /// "Rp1,5 jt" or "Rp400 rb".
    static func short(_ value: Double) -> String {
        guard value >= 1_000_000 else { return L("Rp%lld rb", Int((value / 1000).rounded())) }
        let millions = (value / 100_000).rounded() / 10
        let text = millions == millions.rounded() ? String(Int(millions)) : String(format: "%.1f", millions)
        return L("Rp%@ jt", text.replacingOccurrences(of: ".", with: AppLanguage.code == "en" ? "." : ","))
    }

    static func typeColor(_ type: CategoryType) -> Color {
        type == .income ? TransactionStyle.income.color : TransactionStyle.expense.color
    }
}

/// Kategori baru / Ubah kategori, as a sheet: the icon and the name typed on it, then (for a new one) the type,
/// the icon and colour panel, the budget and (when editing) the Sembunyikan switch, and one Simpan button.
/// Built-in categories keep their icon and colour; only the name, budget and hiding apply to them.
struct CategoryFormView: View {
    enum Mode {
        case new(CategoryType)
        case edit(Category)
    }

    enum Outcome {
        case saved(Category, isNew: Bool)
        case hidden(Category)
        case shown(Category)
        /// Showing it again would go over the free limit: the list offers Saku Plus.
        case limit(CategoryType)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    /// Every category (hidden ones too) for the duplicate check.
    let categories: [Category]
    let hiddenIds: Set<String>
    let transactionCount: Int
    let budget: Budget?
    /// Average expense of the last three full periods, for the budget suggestion.
    let average: Double
    let userId: String
    /// False when the free limit is reached: switching Sembunyikan off then opens the Saku Plus offer.
    let canUnhide: Bool
    /// Called once when the form closes; nil for Batal.
    let onClose: (Outcome?) -> Void

    @State private var name: String
    @State private var type: CategoryType
    @State private var icon: String
    @State private var color: String
    @State private var budgetAmount: Double
    @State private var isHidden: Bool
    @State private var showsAllIcons: Bool
    @State private var triedSave = false
    @State private var shakeX: CGFloat = 0
    @State private var isBumped = false
    @State private var isSaving = false
    @State private var showsBudget = false
    @State private var detent: PresentationDetent = .large
    @State private var budgetOn: Bool
    @State private var errorMessage: String?
    @State private var outcomeAfterAlert: Outcome?

    init(mode: Mode, categories: [Category], hiddenIds: Set<String>, transactionCount: Int = 0,
         budget: Budget? = nil, average: Double = 0, userId: String, canUnhide: Bool = true,
         onClose: @escaping (Outcome?) -> Void) {
        self.mode = mode
        self.categories = categories
        self.hiddenIds = hiddenIds
        self.transactionCount = transactionCount
        self.budget = budget
        self.average = average
        self.userId = userId
        self.canUnhide = canUnhide
        self.onClose = onClose
        switch mode {
        case .new(let type):
            _name = State(initialValue: "")
            _type = State(initialValue: type)
            _icon = State(initialValue: CategoryCatalog.defaultIcon)
            _color = State(initialValue: CategoryCatalog.defaultColor)
            _isHidden = State(initialValue: false)
            _showsAllIcons = State(initialValue: CategoryCatalog.needsAllIcons(for: CategoryCatalog.defaultIcon))
        case .edit(let category):
            _name = State(initialValue: category.name)
            _type = State(initialValue: category.type)
            _icon = State(initialValue: category.icon ?? "tag")
            _color = State(initialValue: category.color ?? CategoryCatalog.defaultColor)
            _isHidden = State(initialValue: hiddenIds.contains(category.id))
            _showsAllIcons = State(initialValue: CategoryCatalog.needsAllIcons(for: category.icon ?? "tag"))
        }
        _budgetAmount = State(initialValue: budget?.amount ?? 0)
        _budgetOn = State(initialValue: (budget?.amount ?? 0) > 0)
    }

    private var editing: Category? {
        if case .edit(let category) = mode { return category }
        return nil
    }
    private var isBuiltIn: Bool { editing?.isBuiltIn == true }
    private var wasHidden: Bool { editing.map { hiddenIds.contains($0.id) } ?? false }
    private var tint: Color { Color(hex: color) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var error: String? {
        CategoryCatalog.validate(name, type: type, excluding: editing?.id, in: categories, hiddenIds: hiddenIds)
    }
    private var showsError: Bool { error != nil && (triedSave || !trimmedName.isEmpty) }
    private var savesBudget: Bool { type == .expense && budgetAmount > 0 }
    private var cycle: PaydayCycle { .current }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView { content }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.appText)
        .pinnedFooter { saveBar }
        .background(Color.appBackground)
        .presentationDetents([.medium, .large], selection: $detent)

        .background(Color.appBackground)
        .sheet(isPresented: $showsBudget) {
            BudgetAmountSheet(amount: budgetAmount, average: average, cycle: cycle) { value in
                budgetAmount = value
                budgetOn = value > 0
                showsBudget = false
            }
        }
        .alert("Gagal menyimpan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {
                if let outcomeAfterAlert { close(outcomeAfterAlert) }
            }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: name) { _, value in
            if value.count > 24 { name = String(value.prefix(24)) }
        }
    }

    // MARK: - Top bar and header

    private var topBar: some View {
        Text(editing == nil ? L("Kategori baru") : L("Ubah kategori"))
            .font(.app(22, weight: .bold)).tracking(-0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 4)
    }

    private var content: some View {
        VStack(spacing: 0) {
            preview
            if isBuiltIn {
                Label("Ikon dan warna kategori bawaan tidak bisa diubah", systemImage: "lock")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
            } else {
                pickerPanel
                    .padding(.top, 14)
            }
            VStack(spacing: 0) {
                if type == .expense { budgetRow }
                if editing != nil { hideRow }
            }
            .padding(.top, 6)
            Color.clear.frame(height: 24)
        }
        .animation(.settle(0.36), value: type)
        .padding(.horizontal, 24)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundStyle(tint)
                }
                .scaleEffect(isBumped ? 1.1 : 1)
                .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.38), value: isBumped)
                .animation(.easeInOut(duration: 0.24), value: color)

            TextField("", text: $name, prompt: Text("Nama kategori").foregroundStyle(Color.appTextTertiary))
                .font(.app(26, weight: .bold))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .tint(.appPrimary)
                .submitLabel(.done)
                .frame(height: 36)
                .offset(x: shakeX)
                .animation(.easeOut(duration: 0.09), value: shakeX)

            ZStack {
                Text(statLine)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .opacity(showsError ? 0 : 1)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14))
                    Text(error ?? "").font(.app(13, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Color.appError)
                .opacity(showsError ? 1 : 0)
                .offset(y: showsError ? 0 : 6)
            }
            .frame(height: 20)
            .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.38), value: showsError)
        }
        .padding(.top, 4)
    }

    private var statLine: String {
        guard let editing else { return "" }
        var text = transactionCount > 0
            ? (average > 0 ? L("%lld transaksi · rata-rata %@ per periode", transactionCount, CategoryCatalog.short(average))
                           : L("%lld transaksi", transactionCount))
            : L("Belum ada transaksi")
        if editing.isBuiltIn { text += " · " + L("Kategori bawaan") }
        return text
    }

    // MARK: - Icon and colour

    private var pickerPanel: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 4) {
                ForEach(CategoryCatalog.visibleIcons(expanded: showsAllIcons), id: \.self) { symbol in
                    let isOn = symbol == icon
                    Button { choose { icon = symbol } } label: {
                        Circle()
                            .fill(isOn ? tint.opacity(0.14) : .clear)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: symbol)
                                    .font(.system(size: 21))
                                    .foregroundStyle(isOn ? tint : Color.appTextSecondary)
                            }
                            .animation(.easeInOut(duration: 0.18), value: isOn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Button(showsAllIcons ? L("Lebih sedikit") : L("Lihat semua ikon")) {
                withAnimation(.settle(0.36)) { showsAllIcons.toggle() }
            }
            .font(.app(13, weight: .semibold))
            .foregroundStyle(Color.appPrimary)
            .frame(maxWidth: .infinity, minHeight: 36)
            Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 10)
            HStack(spacing: 0) {
                ForEach(CategoryCatalog.colors, id: \.self) { hex in
                    let isOn = hex.caseInsensitiveCompare(color) == .orderedSame
                    Button { choose { color = hex } } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .overlay { Circle().stroke(Color(hex: hex), lineWidth: 2).opacity(isOn ? 1 : 0) }
                            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.36), value: isOn)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Warna \(hex)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(Color.appFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Budget and hide

    /// "Budget" switch; when on, "Atur budget" opens the amount sheet.
    private var budgetRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 24)
                Text("Budget").font(.app(16))
                Spacer()
                Toggle("Budget", isOn: Binding(get: { budgetOn }, set: setBudgetOn))
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            .frame(minHeight: 60)
            .rowSeparator()
            if budgetOn {
                Button { showsBudget = true } label: {
                    HStack(spacing: 14) {
                        Color.clear.frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Atur budget").font(.app(16))
                            if budgetAmount > 0 {
                                Text(L("≈Rp%@/hari", (budgetAmount / Double(max(cycle.days().total, 1))).formattedAsDigits()))
                                    .font(.app(13))
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }
                        Spacer()
                        Text(budgetAmount > 0 ? "Rp" + budgetAmount.formattedAsDigits() : L("Atur"))
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(budgetAmount > 0 ? Color.appText : Color.appPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                    }
                    .monospacedDigit()
                    .frame(minHeight: 60)
                    .rowSeparator()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .transition(.opacity)
            }
        }
        .animation(.settle(0.3), value: budgetOn)
    }

    private func setBudgetOn(_ on: Bool) {
        budgetOn = on
        if on { showsBudget = true } else { budgetAmount = 0 }
    }

    private var hideRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sembunyikan kategori").font(.app(16))
                    Text("Riwayat transaksi tetap tersimpan")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Toggle("Sembunyikan kategori", isOn: Binding(get: { isHidden }, set: setHidden))
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            .frame(minHeight: 60)
            if isHidden, !wasHidden, let budget, budget.amount > 0 {
                Text(L("Budget Rp%@ berhenti mulai periode ini.", budget.amount.formattedAsDigits()))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.leading, 38)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .animation(.settle(0.3), value: isHidden)
    }

    private func setHidden(_ value: Bool) {
        if !value, wasHidden, !canUnhide, let editing {
            close(.limit(editing.type))
            return
        }
        isHidden = value
    }

    private var saveBar: some View {
        // Tapping Simpan while the form isn't valid shows why (shake + message).
        let isValid = error == nil && !isSaving
        return SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, isEnabled: true, secondary: L("Batal"),
                                onPrimary: { if isValid { save() } else if !isSaving { blocked() } }) { close(nil) }
            .opacity(isValid ? 1 : 0.55)
            .animation(.easeInOut(duration: 0.3), value: isValid)
    }

    // MARK: - Actions

    private func choose(_ apply: () -> Void) {
        apply()
        isBumped = true
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            isBumped = false
        }
    }

    private func blocked() {
        triedSave = true
        Task {
            for x in [-10, 9, -6, 4, 0] as [CGFloat] {
                shakeX = x
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func close(_ outcome: Outcome?) {
        onClose(outcome)
        dismiss()
    }

    private func save() {
        guard !isSaving, error == nil else { return }
        isSaving = true
        let name = trimmedName, type = type, icon = icon, color = color
        let amount = savesBudget ? budgetAmount : 0
        let hiddenNow = isHidden
        let repo = SupabaseRepository.shared
        Task {
            let category: Category
            do {
                if let editing {
                    if editing.isBuiltIn {
                        // Only the user's own name changes; typing the shared name again restores it.
                        category = editing.named(name)
                        if name != editing.name {
                            try await repo.setCategoryName(id: editing.id, name: category.defaultName == nil ? nil : name)
                        }
                    } else {
                        category = try await repo.updateCategory(id: editing.id, name: name, icon: icon, color: color)
                    }
                } else {
                    category = try await repo.createCategory(name: name, type: type, icon: icon, color: color, userId: userId)
                }
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                return
            }
            let isNew = editing == nil
            do {
                if type == .expense {
                    if amount > 0, let budget {
                        if budget.amount != amount || budget.name != name {
                            _ = try await repo.updateBudget(
                                id: budget.id, name: name, amount: amount, periodUnit: budget.periodUnit,
                                periodInterval: budget.periodInterval, startDate: budget.startDate,
                                endDate: budget.endDate, isActive: true)
                        }
                    } else if amount > 0 {
                        let start = ISO8601DateFormatter().string(from: PaydayCycle.current.period(containing: Date()).start)
                        _ = try await repo.createBudget(
                            categoryId: category.id, name: name, amount: amount, periodUnit: "month",
                            periodInterval: 1, startDate: start, endDate: nil, userId: userId)
                    } else if let budget {
                        try await repo.softDeleteBudget(id: budget.id)
                    }
                }
                if !isNew, hiddenNow != wasHidden {
                    try await repo.setCategoryHidden(id: category.id, hidden: hiddenNow)
                }
            } catch {
                // The category is saved; closing after the alert avoids a duplicate on retry.
                isSaving = false
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                outcomeAfterAlert = .saved(category, isNew: isNew)
                errorMessage = L("Kategori tersimpan, tapi budget gagal disimpan. %@", error.localizedDescription)
                return
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            isSaving = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if !isNew, hiddenNow != wasHidden {
                close(hiddenNow ? .hidden(category) : .shown(category))
            } else {
                close(.saved(category, isNew: isNew))
            }
        }
    }
}

/// "Budget per periode": big amount, the period and per-day share, an average suggestion
/// and the number pad. The first key replaces the shown amount.
private struct BudgetAmountSheet: View {
    let average: Double
    let cycle: PaydayCycle
    let onDone: (Double) -> Void

    @State private var amount: Int
    @State private var isFresh = true
    @State private var isBumped = false
    @State private var detent: PresentationDetent = .medium

    init(amount: Double, average: Double, cycle: PaydayCycle, onDone: @escaping (Double) -> Void) {
        self.average = average
        self.cycle = cycle
        self.onDone = onDone
        _amount = State(initialValue: Int(amount))
    }

    private var suggestion: Int { Int((average / 1000).rounded() * 1000) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp")
                        .font(.app(20))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 7)
                    Text(Double(amount).formattedAsDigits())
                        .font(.app(48, weight: .light))
                        .tracking(-1.8)
                        .foregroundStyle(amount > 0 ? Color.appText : Color(light: 0xC7C7CC, dark: 0x48484A))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                .scaleEffect(isBumped ? 1.04 : 1)
                .animation(.easeOut(duration: 0.14), value: isBumped)
                Text(info)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                if suggestion > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { amount = suggestion }
                        isFresh = true
                        bump()
                    } label: {
                        Label(L("Rata-rata 3 bulan terakhir Rp%@", Double(suggestion).formattedAsDigits()), systemImage: "sparkles")
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.leading, 10)
                            .padding(.trailing, 14)
                            .frame(height: 32)
                            .background(Color.appPrimary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .padding(.top, 6)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 18)

            AmountPad(color: .appPrimary, isEnabled: amount > 0, onPress: press, onSave: { onDone(Double(amount)) })
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Color.appText)
        .filterSheet()
        .background(Color.appBackground)
        .presentationDetents([.medium, .large], selection: $detent)
    }

    private var info: String {
        let days = max(cycle.days().total, 1)
        return L("Periode %@", cycle.label())
            + (amount > 0 ? " · " + L("≈Rp%@ per hari", (Double(amount) / Double(days)).formattedAsDigits()) : "")
    }

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: isFresh ? 0 : amount) else { return }
        isFresh = false
        withAnimation(.snappy(duration: 0.2)) { amount = next }
        bump()
    }

    private func bump() {
        isBumped = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            isBumped = false
        }
    }
}
