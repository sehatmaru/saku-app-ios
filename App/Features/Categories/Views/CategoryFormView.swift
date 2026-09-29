import SwiftUI

/// Icons, colours and naming rules shared by Kelola kategori, its form and the quick create
/// in Tambah transaksi. Icons are SF Symbol names, colours "#RRGGBB", like the seeded ones.
enum CategoryCatalog {
    static let iconGroups: [(name: String, icons: [String])] = [
        ("Makanan", ["fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass"]),
        ("Transportasi", ["car", "scooter", "bus", "fuelpump"]),
        ("Rumah", ["house", "bolt", "drop", "wifi"]),
        ("Hiburan", ["film", "gamecontroller", "music.note", "airplane"]),
        ("Kesehatan", ["heart", "pills", "dumbbell", "cross.case"]),
        ("Pendidikan", ["graduationcap", "book", "backpack", "pencil"]),
        ("Keuangan", ["briefcase", "storefront", "chart.line.uptrend.xyaxis", "dollarsign.circle"]),
        ("Lainnya", ["cart", "bag", "hand.raised", "ellipsis"]),
    ]
    static var allIcons: [String] { iconGroups.flatMap(\.icons) }
    static let colors = ["#D93636", "#E8772E", "#D9A21B", "#16875A", "#0E8C8C",
                         "#1F6FD1", "#143A73", "#6B4BC8", "#C2417A", "#6E6E73"]
    static let defaultIcon = "cart"
    static let defaultColor = "#1F6FD1"

    /// "Penyesuaian Saldo": used by balance corrections on its own, never listed or offered.
    static func isSystem(_ category: Category) -> Bool { category.systemKey == "adjustment" }

    /// Why `name` can't be saved for `type`, or nil. Duplicates count hidden categories too.
    static func validate(_ name: String, type: CategoryType, excluding id: String?,
                         in categories: [Category], hiddenIds: Set<String>) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Nama belum diisi" }
        if trimmed.lowercased() == "penyesuaian saldo" { return "Nama dipakai sistem" }
        if let dup = categories.first(where: {
            $0.type == type && $0.id != id && !isSystem($0) && $0.name.lowercased() == trimmed.lowercased()
        }) {
            return "Sudah ada “\(dup.name)”" + (hiddenIds.contains(dup.id) ? " (disembunyikan)" : "")
        }
        return nil
    }

    /// "Rp1,5 jt" or "Rp400 rb".
    static func short(_ value: Double) -> String {
        guard value >= 1_000_000 else { return "Rp\(Int((value / 1000).rounded())) rb" }
        let millions = (value / 100_000).rounded() / 10
        let text = millions == millions.rounded() ? String(Int(millions)) : String(format: "%.1f", millions)
        return "Rp" + text.replacingOccurrences(of: ".", with: ",") + " jt"
    }

    static func typeColor(_ type: CategoryType) -> Color {
        type == .income ? TransactionStyle.income.color : TransactionStyle.expense.color
    }
}

/// Kategori baru / Ubah kategori: a coloured panel where the name is typed on the preview,
/// then type, budget, icon and colour rows, and a swipe to save. Editing adds Sembunyikan.
/// Built-in categories keep their name and icon; only budget and hiding apply to them.
struct CategoryFormView: View {
    enum Mode {
        case new(CategoryType)
        case edit(Category)
    }

    enum Outcome {
        case saved(Category)
        case hidden(Category)
    }

    private enum FormSheet: String, Identifiable {
        case budget, hide
        var id: String { rawValue }
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
    /// Called once when the form closes; nil for Batal.
    let onClose: (Outcome?) -> Void

    @State private var name: String
    @State private var type: CategoryType
    @State private var icon: String
    @State private var color: String
    @State private var budgetOn: Bool
    @State private var budgetAmount: Double
    @State private var triedSave = false
    @State private var shakeX: CGFloat = 0
    @State private var isBumped = false
    @State private var isEntered = false
    @State private var isDone = false
    @State private var isSaving = false
    @State private var swipeReset = 0
    @State private var sheet: FormSheet?
    @State private var isHiddenShown = false
    @State private var showsUndoToast = false
    @State private var errorMessage: String?
    @State private var outcomeAfterAlert: Outcome?

    init(mode: Mode, categories: [Category], hiddenIds: Set<String>, transactionCount: Int = 0,
         budget: Budget? = nil, average: Double = 0, userId: String, onClose: @escaping (Outcome?) -> Void) {
        self.mode = mode
        self.categories = categories
        self.hiddenIds = hiddenIds
        self.transactionCount = transactionCount
        self.budget = budget
        self.average = average
        self.userId = userId
        self.onClose = onClose
        switch mode {
        case .new(let type):
            _name = State(initialValue: "")
            _type = State(initialValue: type)
            _icon = State(initialValue: CategoryCatalog.defaultIcon)
            _color = State(initialValue: CategoryCatalog.defaultColor)
        case .edit(let category):
            _name = State(initialValue: category.name)
            _type = State(initialValue: category.type)
            _icon = State(initialValue: category.icon ?? "tag")
            _color = State(initialValue: category.color ?? CategoryCatalog.defaultColor)
        }
        _budgetOn = State(initialValue: (budget?.amount ?? 0) > 0)
        _budgetAmount = State(initialValue: budget?.amount ?? 0)
    }

    private var editing: Category? {
        if case .edit(let category) = mode { return category }
        return nil
    }
    private var isBuiltIn: Bool { editing?.isBuiltIn == true }
    private var tint: Color { CategoryCatalog.typeColor(type) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var error: String? {
        isBuiltIn ? nil : CategoryCatalog.validate(name, type: type, excluding: editing?.id, in: categories, hiddenIds: hiddenIds)
    }
    private var showsError: Bool { error != nil && (triedSave || !trimmedName.isEmpty) }
    private var savesBudget: Bool { type == .expense && budgetOn && budgetAmount > 0 }
    private var cycle: PaydayCycle { .current }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                panel
                ScrollView { rows }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .opacity(isDone ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isDone)
            }
            .overlay(alignment: .bottom) { saveBar }

            if isHiddenShown, let editing {
                HiddenEndScreen(
                    category: editing,
                    detail: hiddenDetail,
                    onDone: { close(.hidden(editing)) },
                    onUndo: undoHide
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.32)))
                .zIndex(2)
            }
        }
        .background(Color.appBackground)
        .toast((editing?.name ?? "") + " ditampilkan lagi", isShown: $showsUndoToast)
        .sheet(item: $sheet, onDismiss: {
            if budgetAmount <= 0 { budgetOn = false }
        }) { kind in
            switch kind {
            case .budget:
                BudgetAmountSheet(amount: budgetAmount, average: average, cycle: cycle) { value in
                    budgetAmount = value
                    budgetOn = value > 0
                    sheet = nil
                }
            case .hide:
                hideSheet
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
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            isEntered = true
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { close(nil) }
                    .font(.app(17))
                    .frame(width: 70, alignment: .leading)
                    .disabled(isDone)
                Spacer()
                Text(editing == nil ? "Kategori baru" : "Ubah kategori")
                    .font(.app(17, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 70, height: 1)
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            ZStack(alignment: .top) {
                preview
                    .opacity(isDone ? 0 : 1)
                    .scaleEffect(isDone ? 0.97 : 1)
                    .offset(y: isDone ? -14 : 0)
                    .animation(.settle(0.42), value: isDone)
                doneOverlay
            }
        }
        .padding(.bottom, 22)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .topTrailing) {
                tint
                LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: icon)
                    .font(.system(size: 190, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .opacity(0.07)
                    .offset(x: 34, y: 60)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
            .animation(.easeInOut(duration: 0.45), value: type)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 8)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundStyle(Color(hex: color))
                        .animation(.easeInOut(duration: 0.4), value: color)
                }
                .scaleEffect(isBumped ? 1.12 : 1)
                .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.38), value: isBumped)
                .padding(.top, 8)

            TextField("", text: $name, prompt: Text("Nama kategori").foregroundStyle(.white.opacity(0.6)))
                .font(.app(24, weight: .semibold))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .tint(.white)
                .submitLabel(.done)
                .disabled(isBuiltIn || isDone)
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .offset(x: shakeX)
                .animation(.easeOut(duration: 0.09), value: shakeX)

            ZStack {
                Text(subtitle)
                    .font(.app(13))
                    .opacity(0.85)
                    .opacity(showsError ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: showsError)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14))
                    Text(error ?? "").font(.app(13, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Color(hex: "D93025"))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(.white, in: Capsule())
                .opacity(showsError ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: showsError)
                .scaleEffect(showsError ? 1 : 0.95)
                .offset(y: showsError ? 0 : 6)
                .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.38), value: showsError)
            }
            .frame(height: 30)
            .padding(.top, 6)
        }
    }

    private var subtitle: String {
        guard let editing else { return "Ketik nama di atas" }
        return (transactionCount > 0 ? "\(transactionCount) transaksi" : "Belum dipakai")
            + (editing.isBuiltIn ? " · Kategori bawaan" : "")
    }

    private var doneOverlay: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(tint)
                }
                .scaleEffect(isDone ? 1 : 0.4)
                .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.56), value: isDone)
            Text(editing == nil ? "Kategori tersimpan" : "Perubahan tersimpan")
                .font(.app(20, weight: .semibold))
                .padding(.top, 6)
            Text(trimmedName + (savesBudget ? " · Budget Rp" + budgetAmount.formattedAsDigits() + "/periode" : ""))
                .font(.app(14))
                .opacity(0.85)
                .monospacedDigit()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .opacity(isDone ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isDone)
        .allowsHitTesting(false)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 8)
            typeRow
                .rise(isEntered, y: 14, delay: 0.16, fade: 0.4, move: 0.5)
            if type == .expense {
                budgetRows
                    .rise(isEntered, y: 14, delay: 0.23, fade: 0.4, move: 0.5)
                    .transition(.opacity)
            }
            if isBuiltIn {
                Label("Nama dan ikon kategori bawaan tidak bisa diubah", systemImage: "lock")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .rise(isEntered, y: 14, delay: 0.3, fade: 0.4, move: 0.5)
            } else {
                iconSection
                    .rise(isEntered, y: 14, delay: 0.37, fade: 0.4, move: 0.5)
                colorSection
                    .rise(isEntered, y: 14, delay: 0.44, fade: 0.4, move: 0.5)
            }
            if editing != nil {
                hideRow
                    .rise(isEntered, y: 14, delay: 0.5, fade: 0.4, move: 0.5)
            }
            Color.clear.frame(height: 130)
        }
        .animation(.settle(0.36), value: type)
        .foregroundStyle(Color.appText)
    }

    private var typeRow: some View {
        HStack(spacing: 12) {
            Text("Tipe")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
            if let editing {
                Text(editing.type == .expense ? "Pengeluaran" : "Pemasukan")
                    .font(.app(16, weight: .medium))
                Spacer()
                Label("Tidak bisa diubah", systemImage: "lock")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
            } else {
                SlidingSegment(options: ["Pengeluaran", "Pemasukan"], selection: Binding(
                    get: { type == .expense ? 0 : 1 },
                    set: { type = $0 == 0 ? .expense : .income }
                ))
            }
        }
        .frame(height: 56)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
    }

    private var budgetRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atur budget").font(.app(16))
                    Text("Nominal per periode · " + cycle.label())
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Toggle("Atur budget", isOn: Binding(get: { budgetOn }, set: setBudgetOn))
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            .frame(height: 64)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rowSeparator()
            .contentShape(Rectangle())
            .onTapGesture { setBudgetOn(!budgetOn) }

            Button { sheet = .budget } label: {
                HStack(spacing: 12) {
                    Text("Nominal")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 76, alignment: .leading)
                    Text(budgetAmount > 0 ? "Rp" + budgetAmount.formattedAsDigits() : "Belum diisi")
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if budgetAmount > 0 {
                        Text("≈Rp" + (budgetAmount / Double(max(cycle.days().total, 1))).formattedAsDigits() + "/hari")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                }
                .monospacedDigit()
                .frame(height: 52)
                .padding(.leading, 24)
                .padding(.trailing, 20)
                .rowSeparator()
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .frame(height: budgetOn ? 52 : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(budgetOn)
        }
    }

    private func setBudgetOn(_ isOn: Bool) {
        withAnimation(.settle(0.36)) { budgetOn = isOn }
        guard isOn, budgetAmount <= 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            if budgetOn { sheet = .budget }
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ikon")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ForEach(CategoryCatalog.iconGroups, id: \.name) { group in
                HStack(spacing: 12) {
                    Text(group.name)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 92, alignment: .leading)
                    HStack(spacing: 10) {
                        ForEach(group.icons, id: \.self) { symbol in
                            let isOn = symbol == icon
                            Button { choose { icon = symbol } } label: {
                                Circle()
                                    .fill(isOn ? tint : Color.appFill)
                                    .frame(width: 46, height: 46)
                                    .overlay {
                                        Image(systemName: symbol)
                                            .font(.system(size: 19))
                                            .foregroundStyle(isOn ? Color.white : Color.appBody)
                                    }
                                    .scaleEffect(isOn ? 1.08 : 1)
                                    .animation(.easeInOut(duration: 0.22), value: isOn)
                                    .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.36), value: isOn)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 5)
                .padding(.leading, 24)
                .padding(.trailing, 20)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warna")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HStack(spacing: 0) {
                ForEach(CategoryCatalog.colors, id: \.self) { hex in
                    let isOn = hex.caseInsensitiveCompare(color) == .orderedSame
                    Button { choose { color = hex } } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 26, height: 26)
                            .padding(3)
                            .overlay { Circle().stroke(Color(hex: hex), lineWidth: 2).opacity(isOn ? 1 : 0) }
                            .scaleEffect(isOn ? 1.08 : 1)
                            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.36), value: isOn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Warna \(hex)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var hideRow: some View {
        Button { sheet = .hide } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.appFill)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.appBody)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sembunyikan kategori").font(.app(16)).foregroundStyle(Color.appText)
                    Text("Riwayat transaksi tetap tersimpan")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
            }
            .frame(height: 64)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.top, 18)
    }

    private var saveBar: some View {
        SwipeToConfirm(
            label: "Geser untuk simpan",
            color: tint,
            isEnabled: error == nil && !isSaving,
            resetToken: swipeReset,
            onBlocked: blocked,
            onConfirm: save
        )
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 8)
        .background {
            LinearGradient(stops: [.init(color: Color.appBackground.opacity(0), location: 0),
                                   .init(color: Color.appBackground, location: 0.32)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.45), value: type)
    }

    // MARK: - Hide

    private var hideSheet: some View {
        PickerSheet(title: "Sembunyikan kategori?", actionTitle: "Batal", onDone: { sheet = nil }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.appFill)
                        .frame(width: 44, height: 44)
                        .overlay { Image(systemName: editing?.icon ?? icon).font(.system(size: 19)) }
                    Text(editing?.name ?? name).font(.app(18, weight: .semibold))
                }
                .padding(.top, 8)
                .padding(.bottom, 14)
                ForEach(hideInfo, id: \.text) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 22)
                            .padding(.top, 1)
                        Text(item.text)
                            .font(.app(15))
                            .foregroundStyle(Color.appBody)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                }
                Button(action: hide) {
                    Label("Sembunyikan", systemImage: "eye.slash")
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private var hideInfo: [(icon: String, text: String)] {
        let current = editing?.name ?? trimmedName
        var items: [(icon: String, text: String)] = [
            ("eye.slash", "Tidak muncul lagi di pilihan kategori saat mencatat transaksi."),
            ("clock.arrow.circlepath", transactionCount > 0
                ? "\(transactionCount) transaksi lama tetap tercatat sebagai \(current)."
                : "Belum ada transaksi di kategori ini."),
        ]
        if let budget, budget.amount > 0 {
            items.append(("chart.pie", "Budget Rp" + budget.amount.formattedAsDigits() + " berhenti mulai periode ini."))
        }
        items.append(("arrow.counterclockwise", "Bisa ditampilkan lagi kapan saja dari Kelola kategori."))
        return items
    }

    private var hiddenDetail: String {
        "Tidak muncul lagi saat mencatat."
            + (transactionCount > 0 ? " \(transactionCount) transaksi lama tetap memakai namanya." : "")
            + ((budget?.amount ?? 0) > 0 ? " Budget " + CategoryCatalog.short(budget?.amount ?? 0) + " dihentikan." : "")
    }

    private func hide() {
        guard let editing else { return }
        sheet = nil
        Task {
            do {
                try await SupabaseRepository.shared.setCategoryHidden(id: editing.id, hidden: true)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.easeInOut(duration: 0.32)) { isHiddenShown = true }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func undoHide() {
        guard let editing else { return }
        Task {
            do {
                try await SupabaseRepository.shared.setCategoryHidden(id: editing.id, hidden: false)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                withAnimation(.easeInOut(duration: 0.32)) { isHiddenShown = false }
                showsUndoToast = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
        guard !isDone, !isSaving, error == nil else { return }
        isSaving = true
        let name = trimmedName, type = type, icon = icon, color = color
        let amount = savesBudget ? budgetAmount : 0
        let repo = SupabaseRepository.shared
        Task {
            let category: Category
            do {
                if let editing {
                    category = editing.isBuiltIn ? editing
                        : try await repo.updateCategory(id: editing.id, name: name, icon: icon, color: color)
                } else {
                    category = try await repo.createCategory(name: name, type: type, icon: icon, color: color, userId: userId)
                }
            } catch {
                isSaving = false
                swipeReset += 1
                errorMessage = error.localizedDescription
                return
            }
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
            } catch {
                // The category is saved; closing after the alert avoids a duplicate on retry.
                isSaving = false
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                outcomeAfterAlert = .saved(category)
                errorMessage = "Kategori tersimpan, tapi budget gagal disimpan. " + error.localizedDescription
                return
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            isSaving = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            isDone = true
            try? await Task.sleep(for: .seconds(1.4))
            close(.saved(category))
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

    init(amount: Double, average: Double, cycle: PaydayCycle, onDone: @escaping (Double) -> Void) {
        self.average = average
        self.cycle = cycle
        self.onDone = onDone
        _amount = State(initialValue: Int(amount))
    }

    private var suggestion: Int { Int((average / 1000).rounded() * 1000) }

    var body: some View {
        PickerSheet(title: "Budget per periode", onDone: { onDone(Double(amount)) }) {
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
                        Label("Rata-rata 3 bulan terakhir Rp" + Double(suggestion).formattedAsDigits(), systemImage: "sparkles")
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
            .padding(.top, 12)
            .padding(.bottom, 18)

            NumberPadKeys(onPress: press)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var info: String {
        let days = max(cycle.days().total, 1)
        return "Periode " + cycle.label()
            + (amount > 0 ? " · ≈Rp" + (Double(amount) / Double(days)).formattedAsDigits() + " per hari" : "")
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

/// End screen after hiding: the icon with an eye-slash badge, what changes, Selesai and Urungkan.
private struct HiddenEndScreen: View {
    let category: Category
    let detail: String
    let onDone: () -> Void
    let onUndo: () -> Void

    @State private var isShown = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Circle()
                    .fill(Color.appFill)
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: category.icon ?? "tag")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.appText)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.appBackground)
                            }
                            .padding(4)
                            .background(Color.appBackground, in: Circle())
                            .offset(x: 8, y: 8)
                            .scaleEffect(isShown ? 1 : 0)
                            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.52).delay(0.18), value: isShown)
                    }
                Text(category.name + " disembunyikan")
                    .font(.app(24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.appText)
                    .padding(.top, 14)
                Text(detail)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineSpacing(4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .frame(maxHeight: .infinity)
            .scaleEffect(isShown ? 1 : 0.97)
            .offset(y: isShown ? 0 : 18)
            .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.52), value: isShown)

            VStack(spacing: 6) {
                EmptyStateButton(title: "Selesai", icon: nil, isFullWidth: true, action: onDone)
                Button(action: onUndo) {
                    Label("Urungkan", systemImage: "arrow.counterclockwise")
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .task { isShown = true }
    }
}
