import Foundation

/// The user's transactions, loaded by whole calendar months from the newest back. Screens read from here instead of
/// each downloading the whole history; a write anywhere reloads it once.
@MainActor
final class TransactionStore: ObservableObject {
    static let shared = TransactionStore()

    /// Newest first, in the order the server returned them. Only the months from `loadedSince` on are here until `isComplete`.
    @Published private(set) var transactions: [Transaction] = []
    /// The first day of the oldest month loaded; nil while nothing is.
    @Published private(set) var loadedSince: Date?
    @Published private(set) var isComplete = false
    @Published private(set) var isLoadingMore = false
    private(set) var userId: String?

    /// Months loaded on first use, counting the current one.
    static let initialMonths = 3
    /// Months added each time the list reaches its end.
    static let stepMonths = 3

    private var reloadTask: Task<Void, Never>?
    private var repo: SupabaseRepository { SupabaseRepository.shared }

    private init() {
        NotificationCenter.default.addObserver(forName: .dataDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TransactionStore.shared.scheduleReload() }
        }
    }

    var hasLoaded: Bool { loadedSince != nil }

    // MARK: Loading

    /// The first screen's data: the newest months, unless more are already here.
    func load(userId: String) async throws {
        try await ensureLoaded(userId: userId, since: Self.firstDay(monthsBack: Self.initialMonths - 1))
    }

    /// Makes sure everything from the month of `since` on is loaded.
    func ensureLoaded(userId: String, since: Date) async throws {
        adopt(userId)
        guard !isComplete else { return }
        let start = Self.monthStart(since)
        if let loaded = loadedSince {
            guard start < loaded else { return }
            let rows = try await repo.fetchTransactions(userId: userId, from: start, before: loaded)
            guard self.userId == userId else { return }
            append(rows)
            loadedSince = min(loadedSince ?? start, start)
        } else {
            let rows = try await repo.fetchTransactions(userId: userId, from: start)
            guard self.userId == userId else { return }
            transactions = rows
            loadedSince = start
        }
    }

    /// The next block of older months; finds the next transaction first, so a gap of empty months costs one request.
    func loadOlder() async {
        guard let userId, let loaded = loadedSince, !isComplete, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard let next = try await repo.newestTransaction(userId: userId, before: loaded) else {
                isComplete = true
                return
            }
            let calendar = Calendar.current
            let since = calendar.date(byAdding: .month, value: -(Self.stepMonths - 1), to: Self.monthStart(next.date)) ?? loaded
            let rows = try await repo.fetchTransactions(userId: userId, from: since, before: loaded)
            guard self.userId == userId else { return }
            append(rows)
            if !isComplete { loadedSince = since }
        } catch {}
    }

    /// Everything, for a search or a filter that has to look at the whole history.
    func loadAll() async {
        guard let userId, !isComplete else { return }
        let wasLoading = isLoadingMore
        isLoadingMore = true
        defer { if !wasLoading { isLoadingMore = false } }
        do {
            let rows = try await repo.fetchTransactions(userId: userId, before: loadedSince)
            guard self.userId == userId else { return }
            append(rows)
            loadedSince = .distantPast
            isComplete = true
        } catch {}
    }

    /// Reads the loaded months again, after a write or a pull to refresh.
    func reload() async {
        guard let userId, let since = loadedSince else { return }
        do {
            let rows = try await repo.fetchTransactions(userId: userId, from: isComplete ? nil : since)
            guard self.userId == userId else { return }
            transactions = rows
        } catch {}
    }

    /// Several writes in a row become one reload.
    private func scheduleReload() {
        guard hasLoaded else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    // MARK: Helpers

    private func adopt(_ id: String) {
        guard userId != id else { return }
        userId = id
        transactions = []
        loadedSince = nil
        isComplete = false
    }

    private func append(_ rows: [Transaction]) {
        let have = Set(transactions.map(\.id))
        transactions += rows.filter { !have.contains($0.id) }
    }

    static func monthStart(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func firstDay(monthsBack: Int) -> Date {
        let calendar = Calendar.current
        return monthStart(calendar.date(byAdding: .month, value: -monthsBack, to: Date()) ?? Date())
    }
}
