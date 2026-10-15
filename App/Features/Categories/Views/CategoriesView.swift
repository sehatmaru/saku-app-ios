import SwiftUI

/// Kelola kategori in the add form's style: a coloured panel with a Pengeluaran / Pemasukan
/// carousel you swipe (the panel turns red or green), the list below, a collapsed
/// Disembunyikan section, and the floating + for a new category.
struct CategoriesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var model = CategoriesModel()
    /// 0 = Pengeluaran, 1 = Pemasukan.
    @State private var typeIndex = 0
    @State private var dragX: CGFloat = 0
    @State private var rowsShown = false
    @State private var isHiddenOpen = false
    @State private var flashId: String?
    @State private var form: FormItem?
    @State private var limitType: CategoryType?
    @State private var toastText = ""
    @State private var showsToast = false

    init() {}

    private static let rowHeight: CGFloat = 64
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
            panel
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.isLoading {
                        skeleton
                    } else if let error = model.errorMessage, model.categories.isEmpty {
                        VStack(spacing: 20) {
                            EmptyMessage(icon: "wifi.slash", title: L("Gagal memuat kategori"), message: error)
                            EmptyStateButton(title: L("Coba lagi"), icon: "arrow.clockwise") { Task { await load() } }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 60)
                    } else {
                        content
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        // Swiping anywhere on the page switches type, not just on the title.
        .simultaneousGesture(typeSwipe)
        .background(Color.appBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toast(toastText, isShown: $showsToast)
        .fullScreenCover(item: $form) { item in
            let id: String? = if case .edit(let c) = item.mode { c.id } else { nil }
            CategoryFormView(
                mode: item.mode,
                categories: model.categories,
                hiddenIds: model.hiddenIds,
                transactionCount: id.flatMap { model.counts[$0] } ?? 0,
                budget: id.flatMap { model.budgets[$0] },
                average: id.flatMap { model.averages[$0] } ?? 0,
                userId: userId,
                onClose: handle
            )
        }
        .detailPage(addLabel: L("Tambah kategori")) {
            if atLimit(type) { limitType = type } else { form = FormItem(id: "new-\(type.rawValue)", mode: .new(type)) }
        }
        .confirmDialog(isPresented: Binding(get: { limitType != nil }, set: { if !$0 { limitType = nil } }),
                       icon: "lock", title: L("Batas kategori tercapai"),
                       message: FreeLimits.categoryMessage(limitType ?? type), confirmTitle: nil, cancelTitle: L("Mengerti"))
        .task { await load() }
    }

    private func load() async {
        await model.load(userId: userId)
        replayRows()
    }

    // MARK: - Panel

    private var panel: some View {
        let lists = model.arranged(type)
        let used = lists.shown.filter { (model.counts[$0.id] ?? 0) > 0 }.count
        let withBudget = lists.shown.filter { (model.budgets[$0.id]?.amount ?? 0) > 0 }.count
        return VStack(spacing: 0) {
            typeCarousel
                .padding(.top, 4)
            typeDots
                .padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.isLoading ? 0 : lists.shown.count)")
                    .font(.app(56, weight: .light))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("kategori")
                    .font(.app(20))
                    .opacity(0.75)
            }
            .padding(.top, 14)
            .animation(.settle(0.5), value: lists.shown.count)
            Text(model.isLoading ? " " : type == .expense
                 ? L("%lld dipakai · %lld punya budget", used, withBudget)
                 : L("%lld dipakai", used))
                .font(.app(14))
                .opacity(0.8)
                .monospacedDigit()
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.2), value: used)
        }
        .padding(.bottom, 26)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(style.color)
                .animation(.easeInOut(duration: 0.45), value: typeIndex)
                .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
    }

    private var typeCarousel: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = 180
            HStack(spacing: 0) {
                ForEach(Self.types.indices, id: \.self) { i in
                    let isCurrent = i == typeIndex
                    HStack(spacing: 8) {
                        Image(systemName: Self.types[i].icon).font(.system(size: 17, weight: .bold))
                        Text(L(Self.types[i].label))
                    }
                    .font(.app(22, weight: .bold))
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

    /// Horizontal drags only; a mostly vertical drag is the list scrolling.
    private var typeSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                var dx = value.translation.width
                if (typeIndex == 0 && dx > 0) || (typeIndex == Self.types.count - 1 && dx < 0) { dx *= 0.3 }
                dragX = dx
            }
            .onEnded { value in
                let dx = dragX
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4
                let next = !isHorizontal ? typeIndex : dx < -40 ? typeIndex + 1 : dx > 40 ? typeIndex - 1 : typeIndex
                withAnimation(.settle(0.46)) { dragX = 0 }
                setType(min(max(next, 0), Self.types.count - 1))
            }
    }

    private func setType(_ index: Int) {
        guard index != typeIndex else { return }
        withAnimation(.settle(0.46)) { typeIndex = index }
        UISelectionFeedbackGenerator().selectionChanged()
        replayRows()
    }

    /// Rows rise in one after another, like the add form's rows.
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
            ForEach(Array([174, 134, 196, 112, 157, 185, 123].enumerated()), id: \.offset) { _, width in
                HStack(spacing: 14) {
                    SkeletonBlock(width: 40, height: 40, radius: 20)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(width: CGFloat(width), height: 14, radius: 7)
                        SkeletonBlock(width: 110, height: 11, radius: 6)
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
            Text(lists.hidden.isEmpty ? L("Belum ada kategori") : L("Semua kategori disembunyikan"))
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
        }

        if !lists.hidden.isEmpty {
            hiddenSection(lists.hidden)
        }
        if type == .expense {
            Text("Penyesuaian Saldo dipakai otomatis saat kamu mengoreksi saldo dompet, jadi tidak tampil di daftar dan pilihan.")
                .font(.app(13))
                .foregroundStyle(Color.appTextTertiary)
                .lineSpacing(3)
                .padding(.horizontal, 24)
                .padding(.top, 18)
        }
        // Room for the floating +.
        Color.clear.frame(height: 100)
    }

    private func iconCircle(_ icon: String?, muted: Bool) -> some View {
        Circle()
            .fill(muted ? Color.appFill.opacity(0.6) : Color.appFill)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: icon ?? "tag")
                    .font(.system(size: 18))
                    .foregroundStyle(muted ? Color.appTextTertiary : Color.appBody)
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
                iconCircle(category.icon, muted: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Text(subtitle(category))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .rowSeparator()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                    .frame(width: 24, height: 24)
            }
            .frame(height: Self.rowHeight)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .background(flashId == category.id ? Color.appPrimary.opacity(0.1) : Color.appBackground)
            .animation(.easeInOut(duration: 0.7), value: flashId)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func hiddenSection(_ hidden: [Category]) -> some View {
        VStack(spacing: 0) {
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
                        .rotationEffect(.degrees(isHiddenOpen ? 0 : -90))
                        .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.3), value: isHiddenOpen)
                }
                .frame(height: 44)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isHiddenOpen ? L("Terbuka") : L("Tertutup"))

            VStack(spacing: 0) {
                ForEach(hidden) { category in
                    HStack(spacing: 14) {
                        iconCircle(category.icon, muted: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .font(.app(16))
                                .foregroundStyle(Color.appTextSecondary)
                                .lineLimit(1)
                            let count = model.counts[category.id] ?? 0
                            Text(count > 0 ? L("Tidak muncul saat mencatat · %lld transaksi", count) : L("Tidak muncul saat mencatat"))
                                .font(.app(13))
                                .foregroundStyle(Color.appTextTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("Tampilkan") { show(category) }
                            .font(.app(14, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color.appPrimary.opacity(0.1), in: Capsule())
                            .buttonStyle(PressScaleStyle())
                    }
                    .frame(height: Self.rowHeight)
                    .padding(.horizontal, 24)
                    .background(flashId == category.id ? Color.appFill : Color.appBackground)
                    .animation(.easeInOut(duration: 0.6), value: flashId)
                }
            }
            .frame(height: isHiddenOpen ? CGFloat(hidden.count) * Self.rowHeight : 0, alignment: .top)
            .clipped()
        }
        .padding(.top, 14)
    }

    // MARK: - Actions

    /// Free accounts hold at most 7 expense and 5 income categories that are shown.
    private func atLimit(_ type: CategoryType) -> Bool {
        FreeLimits.activeCount(model.arranged(type).shown, type: type) >= FreeLimits.categories(type)
    }

    private func show(_ category: Category) {
        if atLimit(category.type) { limitType = category.type; return }
        Task {
            guard await model.setHidden(category.id, hidden: false) else { return }
            flash(category.id, for: 1.2)
            toastText = L("%@ ditampilkan", category.name)
            showsToast = true
        }
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
        case .saved(let category):
            setType(category.type == .expense ? 0 : 1)
            Task {
                await load()
                flash(category.id, for: 1.1)
            }
        case .hidden(let category):
            setType(category.type == .expense ? 0 : 1)
            isHiddenOpen = true
            Task {
                await load()
                flash(category.id, for: 1.5)
            }
        }
    }
}

/// Grey two-or-more-way segmented control with a white pill that slides to the pick.
struct SlidingSegment: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width / CGFloat(max(options.count, 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.appFill)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(light: 0xFFFFFF, dark: 0x3A3A3C))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                    .frame(width: width - 2, height: geo.size.height - 4)
                    .offset(x: 2 + CGFloat(selection) * (width - 2))
                    .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.38), value: selection)
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button { selection = i } label: {
                            Text(options[i])
                                .font(.app(14, weight: selection == i ? .semibold : .medium))
                                .foregroundStyle(Color.appText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == i ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: 36)
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
