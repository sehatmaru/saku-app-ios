import SwiftUI

/// Kelola kategori: Pengeluaran/Pemasukan lists in the user's order with usage and budget,
/// Urutkan to drag rows, a collapsible Disembunyikan section, and Kategori baru.
struct CategoriesView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var model = CategoriesModel()
    @State private var segment = 0
    @State private var isReordering = false
    @State private var isHiddenOpen = true
    @State private var drag: RowDrag?
    @State private var flashId: String?
    @State private var form: FormItem?
    @State private var toastText = ""
    @State private var showsToast = false

    init() {}

    private static let rowHeight: CGFloat = 64

    private struct RowDrag {
        let from: Int
        var dy: CGFloat
        var isReleased = false

        func target(_ count: Int) -> Int {
            min(max(from + Int((dy / CategoriesView.rowHeight).rounded()), 0), count - 1)
        }
    }

    private struct FormItem: Identifiable {
        let id: String
        let mode: CategoryFormView.Mode
    }

    private var type: CategoryType { segment == 0 ? .expense : .income }
    private var userId: String { authViewModel.currentUser?.id ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Kategori")
                    .font(.app(34, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color.appText)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                SlidingSegment(options: ["Pengeluaran", "Pemasukan"], selection: $segment)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Text("Seret baris untuk mengubah urutan di pilihan kategori")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(height: 18)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .opacity(isReordering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isReordering)

                if model.isLoading {
                    skeleton
                } else if let error = model.errorMessage, model.categories.isEmpty {
                    VStack(spacing: 20) {
                        EmptyMessage(icon: "wifi.slash", title: "Gagal memuat kategori", message: error)
                        EmptyStateButton(title: "Coba lagi", icon: "arrow.clockwise") { Task { await model.load(userId: userId) } }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 80)
                } else {
                    content
                }
            }
        }
        .scrollDisabled(drag != nil)
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Kategori")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // The title sits large in the page, as in the design.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isReordering ? "Selesai" : "Urutkan") {
                    withAnimation(.easeInOut(duration: 0.2)) { isReordering.toggle() }
                }
                .font(.app(17, weight: isReordering ? .semibold : .regular))
                .foregroundStyle(Color.appPrimary)
                .opacity(model.isLoading ? 0.35 : 1)
                .disabled(model.isLoading)
            }
        }
        .onChange(of: segment) { _, _ in drag = nil }
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
        .task { await model.load(userId: userId) }
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
        .padding(.top, 4)
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        let lists = model.arranged(type)
        VStack(spacing: 0) {
            ForEach(Array(lists.shown.enumerated()), id: \.element.id) { index, category in
                row(category, index: index, count: lists.shown.count)
            }
        }
        if lists.shown.isEmpty {
            Text(lists.hidden.isEmpty ? "Belum ada kategori" : "Semua kategori disembunyikan")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
        }
        Button { form = FormItem(id: "new-\(type.rawValue)", mode: .new(type)) } label: {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(Color.appBorder, lineWidth: 1.5)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                    }
                Text("Kategori baru")
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appPrimary)
                Spacer()
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .opacity(isReordering ? 0.3 : 1)
        .disabled(isReordering)

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
        Color.clear.frame(height: 60)
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
        var parts = [count > 0 ? "\(count) transaksi" : "Belum dipakai"]
        if let budget = model.budgets[category.id], budget.amount > 0 {
            parts.append("Budget " + CategoryCatalog.short(budget.amount))
        }
        return parts.joined(separator: " · ")
    }

    private func row(_ category: Category, index: Int, count: Int) -> some View {
        let isMe = drag?.from == index
        let offset: CGFloat = {
            guard let drag else { return 0 }
            if isMe { return drag.dy }
            let target = drag.target(count)
            if drag.from < index && index <= target { return -Self.rowHeight }
            if target <= index && index < drag.from { return Self.rowHeight }
            return 0
        }()
        return Button {
            if !isReordering { form = FormItem(id: category.id, mode: .edit(category)) }
        } label: {
            HStack(spacing: 14) {
                iconCircle(category.icon, muted: false)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(category.name)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                        if category.isBuiltIn {
                            Text("Bawaan")
                                .font(.app(11, weight: .semibold))
                                .foregroundStyle(Color.appTextSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Text(subtitle(category))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .rowSeparator()
                ZStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(light: 0xC7C7CC, dark: 0x48484A))
                        .opacity(isReordering ? 0 : 1)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .opacity(isReordering ? 1 : 0)
                }
                .frame(width: 24, height: 24)
                .animation(.easeInOut(duration: 0.2), value: isReordering)
            }
            .frame(height: Self.rowHeight)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .background(flashId == category.id ? Color.appPrimary.opacity(0.1) : Color.appBackground)
            .animation(.easeInOut(duration: 0.7), value: flashId)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .highPriorityGesture(dragGesture(index: index, count: count), including: isReordering ? .all : .subviews)
        .scaleEffect(isMe ? 1.02 : 1)
        .shadow(color: .black.opacity(isMe ? 0.14 : 0), radius: 12, y: 10)
        .offset(y: offset)
        .animation(isMe && drag?.isReleased != true ? nil : .settle(0.22), value: offset)
        .zIndex(isMe ? 5 : 1)
    }

    private func dragGesture(index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    drag = RowDrag(from: index, dy: 0)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                guard drag?.from == index, drag?.isReleased == false else { return }
                drag?.dy = min(max(value.translation.height, -CGFloat(index) * Self.rowHeight),
                               CGFloat(count - 1 - index) * Self.rowHeight)
            }
            .onEnded { _ in
                guard let current = drag, current.from == index, !current.isReleased else { return }
                let target = current.target(count)
                drag?.isReleased = true
                drag?.dy = CGFloat(target - current.from) * Self.rowHeight
                let type = type
                Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    var instant = SwiftUI.Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        model.move(type, from: current.from, to: target)
                        drag = nil
                    }
                    await model.saveOrder(type)
                }
            }
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
            .accessibilityValue(isHiddenOpen ? "Terbuka" : "Tertutup")

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
                            Text("Tidak muncul saat mencatat" + (count > 0 ? " · \(count) transaksi" : ""))
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
        .opacity(isReordering ? 0.3 : 1)
        .disabled(isReordering)
    }

    // MARK: - Actions

    private func show(_ category: Category) {
        Task {
            guard await model.setHidden(category.id, hidden: false) else { return }
            flash(category.id, for: 1.2)
            toastText = category.name + " ditampilkan"
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
            segment = category.type == .expense ? 0 : 1
            isReordering = false
            Task {
                await model.load(userId: userId)
                flash(category.id, for: 1.1)
            }
        case .hidden(let category):
            segment = category.type == .expense ? 0 : 1
            isHiddenOpen = true
            Task {
                await model.load(userId: userId)
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

    func move(_ type: CategoryType, from: Int, to: Int) {
        var shown = arranged(type).shown
        guard shown.indices.contains(from), shown.indices.contains(to) else { return }
        shown.insert(shown.remove(at: from), at: to)
        for (i, category) in shown.enumerated() {
            updatePreference(category.id) { $0.sortOrder = i }
        }
    }

    func saveOrder(_ type: CategoryType) async {
        do {
            try await repo.setCategoryOrder(arranged(type).shown.map(\.id))
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
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
