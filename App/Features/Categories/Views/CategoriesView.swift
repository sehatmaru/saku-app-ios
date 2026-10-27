import SwiftUI

/// Kategori: a title, a Pengeluaran / Pemasukan pill, one summary line and a plain list. Tapping a row or the
/// floating + opens the form as a sheet. Hidden categories sit in a collapsed section at the bottom.
struct CategoriesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var model: CategoriesModel
    /// 0 = Pengeluaran, 1 = Pemasukan.
    @State private var typeIndex = 0
    @State private var rowsShown = false
    @State private var isHiddenOpen = false
    @State private var flashId: String?
    @State private var form: FormItem?
    @State private var limitReason: PlusReason?
    @ObservedObject private var plus = PlusStore.shared
    @State private var toastText = ""
    @State private var showsToast = false
    private let loadsOnAppear: Bool

    init() {
        _model = StateObject(wrappedValue: CategoriesModel())
        loadsOnAppear = true
    }

    #if DEBUG
    /// Screenshots and previews: a model that is already filled, nothing is fetched.
    init(previewModel: CategoriesModel) {
        _model = StateObject(wrappedValue: previewModel)
        loadsOnAppear = false
    }
    #endif

    private static let rowHeight: CGFloat = 60
    private static let types = [TransactionStyle.expense, TransactionStyle.income]

    private struct FormItem: Identifiable {
        let id: String
        let mode: CategoryFormView.Mode
    }

    private var style: TransactionStyle { Self.types[typeIndex] }
    private var type: CategoryType { typeIndex == 0 ? .expense : .income }
    private var userId: String { authViewModel.currentUser?.id ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.isLoading {
                        skeleton
                    } else if let error = model.errorMessage, model.categories.isEmpty {
                        VStack(spacing: 20) {
                            EmptyMessage(icon: "wifi.slash", title: L("Gagal memuat kategori"), message: error)
                            EmptyStateButton(title: L("Coba lagi"), icon: "arrow.clockwise", isSecondary: true) { Task { await load() } }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 100)
                    } else {
                        content
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        // Swiping anywhere on the page switches type.
        .simultaneousGesture(typeSwipe)
        .background(Color.appBackground)
        .navigationTitle(L("Kategori"))
        .navigationBarTitleDisplayMode(.inline)
        .toast(toastText, isShown: $showsToast)
        .sheet(item: $form) { item in
            let id: String? = if case .edit(let c) = item.mode { c.id } else { nil }
            CategoryFormView(
                mode: item.mode,
                categories: model.categories,
                hiddenIds: model.hiddenIds,
                transactionCount: id.flatMap { model.counts[$0] } ?? 0,
                budget: id.flatMap { model.budgets[$0] },
                average: id.flatMap { model.averages[$0] } ?? 0,
                userId: userId,
                canUnhide: !atLimit(type),
                onClose: handle
            )
        }
        .detailPage(addLabel: L("Tambah kategori")) { add() }
        .plusOffer($limitReason)
        .task { if loadsOnAppear { await load() } else { replayRows() } }
    }

    private func load() async {
        await model.load(userId: userId)
        replayRows()
    }

    private func add() {
        if atLimit(type) { limitReason = .categories(type) } else { form = FormItem(id: "new-\(type.rawValue)", mode: .new(type)) }
    }

    // MARK: - Header

    private var header: some View {
        let lists = model.arranged(type)
        let used = lists.shown.filter { (model.counts[$0.id] ?? 0) > 0 }.count
        let withBudget = lists.shown.filter { (model.budgets[$0.id]?.amount ?? 0) > 0 }.count
        return VStack(alignment: .leading, spacing: 0) {
            TypePill(options: Self.types.map { L($0.label) }, selection: Binding(get: { typeIndex }, set: setType))
            HStack(spacing: 8) {
                Circle().fill(style.color).frame(width: 8, height: 8)
                Text(type == .expense
                     ? L("%lld kategori · %lld dipakai · %lld punya budget", lists.shown.count, used, withBudget)
                     : L("%lld kategori · %lld dipakai", lists.shown.count, used))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            .frame(height: 28)
            .padding(.top, 10)
            .opacity(model.isLoading || (model.errorMessage != nil && model.categories.isEmpty) ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: typeIndex)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Horizontal drags only; a mostly vertical drag is the list scrolling.
    private var typeSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 70, abs(value.translation.height) < 50 else { return }
                setType(dx < 0 ? 1 : 0)
            }
    }

    private func setType(_ index: Int) {
        guard index != typeIndex else { return }
        withAnimation(.settle(0.4)) { typeIndex = index }
        UISelectionFeedbackGenerator().selectionChanged()
        replayRows()
    }

    /// Rows rise in one after another.
    private func replayRows() {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { rowsShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            rowsShown = true
        }
    }

    // MARK: - Content

    private var skeleton: some View {
        VStack(spacing: 0) {
            ForEach(Array([150, 120, 170, 130, 160, 110].enumerated()), id: \.offset) { _, width in
                HStack(spacing: 14) {
                    SkeletonBlock(width: 40, height: 40, radius: 20)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(width: CGFloat(width), height: 12, radius: 6)
                        SkeletonBlock(width: 110, height: 10, radius: 5)
                    }
                    Spacer()
                }
                .frame(height: Self.rowHeight)
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        let lists = model.arranged(type)
        VStack(spacing: 0) {
            ForEach(Array(lists.shown.enumerated()), id: \.element.id) { index, category in
                row(category)
                    .opacity(rowsShown ? 1 : 0)
                    .offset(y: rowsShown ? 0 : 14)
                    .animation(.settle(0.46).delay(Double(min(index, 10)) * 0.04), value: rowsShown)
            }
        }
        .padding(.top, 8)
        if lists.shown.isEmpty {
            let allHidden = !lists.hidden.isEmpty
            VStack(spacing: 20) {
                EmptyMessage(
                    icon: "tag",
                    title: allHidden ? L("Semua kategori disembunyikan") : L("Belum ada kategori"),
                    message: allHidden ? L("Tampilkan lagi dari bagian Disembunyikan di bawah.")
                        : type == .expense ? L("Kategori pengeluaran yang kamu tambah akan muncul di sini.")
                        : L("Kategori pemasukan yang kamu tambah akan muncul di sini."))
                if !allHidden {
                    EmptyStateButton(title: L("Tambah kategori"), icon: nil) { add() }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 70)
        }

        if !lists.hidden.isEmpty {
            hiddenSection(lists.hidden, forceOpen: lists.shown.isEmpty)
        }
        if type == .expense, !lists.shown.isEmpty || !lists.hidden.isEmpty {
            Text("Penyesuaian Saldo dipakai otomatis saat kamu mengoreksi saldo dompet, jadi tidak tampil di daftar dan pilihan.")
                .font(.app(12))
                .foregroundStyle(Color.appTextTertiary)
                .lineSpacing(3)
                .padding(.horizontal, 24)
                .padding(.top, 18)
        }
        // Room for the floating +.
        Color.clear.frame(height: 100)
    }

    /// The category's own colour, softly tinted behind its icon.
    private func tint(_ category: Category) -> Color { Color(hex: category.color ?? "#6E6E73") }

    private func iconCircle(_ category: Category, size: CGFloat, muted: Bool) -> some View {
        Circle()
            .fill(muted ? Color.appFill : tint(category).opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(muted ? Color.appTextTertiary : tint(category))
            }
    }

    private func subtitle(_ category: Category) -> String {
        let count = model.counts[category.id] ?? 0
        var parts = [count > 0 ? L("%lld transaksi", count) : L("Belum dipakai")]
        if let budget = model.budgets[category.id], budget.amount > 0 {
            parts.append(L("Budget %@", CategoryCatalog.short(budget.amount)))
        }
        return parts.joined(separator: " · ")
    }

    private func row(_ category: Category) -> some View {
        Button {
            form = FormItem(id: category.id, mode: .edit(category))
        } label: {
            HStack(spacing: 14) {
                iconCircle(category, size: 42, muted: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Text(subtitle(category))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
            }
            .frame(minHeight: Self.rowHeight)
            .padding(.horizontal, 24)
            .background(flashId == category.id ? Color.appPrimary.opacity(0.1) : Color.appBackground)
            .animation(.easeInOut(duration: 0.7), value: flashId)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func hiddenSection(_ hidden: [Category], forceOpen: Bool) -> some View {
        let isOpen = isHiddenOpen || forceOpen
        return VStack(spacing: 0) {
            Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 24)
            Button {
                withAnimation(.settle(0.38)) { isHiddenOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Disembunyikan · \(hidden.count)")
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appTextTertiary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                        .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.3), value: isOpen)
                }
                .frame(height: 52)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? L("Terbuka") : L("Tertutup"))

            VStack(spacing: 0) {
                ForEach(hidden) { category in
                    HStack(spacing: 14) {
                        iconCircle(category, size: 38, muted: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .font(.app(15))
                                .foregroundStyle(Color.appText)
                                .lineLimit(1)
                            let count = model.counts[category.id] ?? 0
                            Text(count > 0 ? L("Tidak muncul saat mencatat · %lld transaksi", count) : L("Tidak muncul saat mencatat"))
                                .font(.app(12))
                                .foregroundStyle(Color.appTextSecondary)
                                .lineLimit(1)
                        }
                        .opacity(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Tampilkan") { show(category) }
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(PressScaleStyle())
                    }
                    .frame(height: 56)
                    .padding(.horizontal, 24)
                    .background(flashId == category.id ? Color.appFill : Color.appBackground)
                    .animation(.easeInOut(duration: 0.6), value: flashId)
                    .contentShape(Rectangle())
                    .onTapGesture { form = FormItem(id: category.id, mode: .edit(category)) }
                }
            }
            .frame(height: isOpen ? CGFloat(hidden.count) * 56 : 0, alignment: .top)
            .clipped()
        }
        .padding(.top, 10)
    }

    // MARK: - Actions

    /// Free accounts hold at most 7 expense and 5 income categories that are shown.
    private func atLimit(_ type: CategoryType) -> Bool {
        !plus.isPlus && FreeLimits.activeCount(model.arranged(type).shown, type: type) >= FreeLimits.categories(type)
    }

    private func show(_ category: Category) {
        if atLimit(category.type) { limitReason = .categories(category.type); return }
        Task {
            guard await model.setHidden(category.id, hidden: false) else { return }
            flash(category.id, for: 1.2)
            say(L("%@ ditampilkan", category.name))
        }
    }

    private func say(_ text: String) {
        toastText = text
        showsToast = true
    }

    private func flash(_ id: String, for seconds: Double) {
        flashId = id
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if flashId == id { flashId = nil }
        }
    }

    private func handle(_ outcome: CategoryFormView.Outcome?) {
        guard let outcome else { return }
        switch outcome {
        case .saved(let category, let isNew):
            setType(category.type == .expense ? 0 : 1)
            say(isNew ? L("Kategori ditambahkan") : L("Perubahan disimpan"))
            Task {
                await load()
                flash(category.id, for: 1.1)
            }
        case .hidden(let category):
            setType(category.type == .expense ? 0 : 1)
            isHiddenOpen = true
            say(L("%@ disembunyikan", category.name))
            Task {
                await load()
                flash(category.id, for: 1.5)
            }
        case .shown(let category):
            setType(category.type == .expense ? 0 : 1)
            say(L("%@ ditampilkan", category.name))
            Task {
                await load()
                flash(category.id, for: 1.2)
            }
        case .limit(let type):
            // the form is closing; the offer opens once it has gone
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                limitReason = .categories(type)
            }
        }
    }
}

/// A two-way pill: a dark capsule slides under the chosen label.
struct TypePill: View {
    let options: [String]
    @Binding var selection: Int
    var height: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width - 6) / CGFloat(max(options.count, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appFill)
                Capsule()
                    .fill(Color.appText)
                    .frame(width: width, height: geo.size.height - 6)
                    .offset(x: 3 + CGFloat(selection) * width)
                    .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.26), value: selection)
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button { selection = i } label: {
                            Text(options[i])
                                .font(.app(height > 42 ? 15 : 14, weight: .semibold))
                                .foregroundStyle(selection == i ? Color.appBackground : Color.appTextSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .animation(.easeInOut(duration: 0.2), value: selection)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == i ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .frame(height: height)
    }
}

/// Categories (without the system one), the user's preferences and per-category stats.
@MainActor
final class CategoriesModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var preferences: [CategoryPreference] = []
    @Published var counts: [String: Int] = [:]
    @Published var budgets: [String: Budget] = [:]
    /// Average expense per period over the last three full periods.
    @Published var averages: [String: Double] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let repo = SupabaseRepository.shared

    var hiddenIds: Set<String> { Set(preferences.filter(\.isHidden).map(\.categoryId)) }

    func arranged(_ type: CategoryType) -> (shown: [Category], hidden: [Category]) {
        categories.filter { $0.type == type }.arranged(by: preferences)
    }

    func load(userId: String) async {
        do {
            async let cats = repo.fetchCategories()
            async let prefs = repo.fetchCategoryPreferences()
            async let txns = repo.fetchTransactions(userId: userId)
            async let buds = repo.fetchBudgets(userId: userId)
            let (c, p, t, b) = try await (cats, prefs, txns, buds)
            categories = c.filter { !CategoryCatalog.isSystem($0) }
            preferences = p
            counts = Dictionary(grouping: t.compactMap(\.categoryId), by: { $0 }).mapValues(\.count)
            budgets = Dictionary(b.filter(\.isActive).map { ($0.categoryId, $0) }, uniquingKeysWith: { first, _ in first })
            let cycle = PaydayCycle.current
            let start = cycle.period(offset: -3).start, end = cycle.period(offset: -1).end
            var sums: [String: Double] = [:]
            for txn in t where txn.type == .expense && txn.date >= start && txn.date < end {
                if let id = txn.categoryId { sums[id, default: 0] += txn.amount }
            }
            averages = sums.mapValues { $0 / 3 }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        withAnimation(.easeInOut(duration: 0.3)) { isLoading = false }
    }

    /// Shows or hides on the server, then locally; false when the write failed.
    func setHidden(_ id: String, hidden: Bool) async -> Bool {
        do {
            try await repo.setCategoryHidden(id: id, hidden: hidden)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        withAnimation(.settle(0.3)) { updatePreference(id) { $0.isHidden = hidden } }
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        return true
    }

    private func updatePreference(_ id: String, _ change: (inout CategoryPreference) -> Void) {
        if let i = preferences.firstIndex(where: { $0.categoryId == id }) {
            change(&preferences[i])
        } else {
            var pref = CategoryPreference(categoryId: id, isHidden: false, sortOrder: nil)
            change(&pref)
            preferences.append(pref)
        }
    }
}
