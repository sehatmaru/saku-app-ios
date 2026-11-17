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
            let stamp = try? await repo.latestTransactionStamp(userId: userId)
            let rows = try await repo.fetchTransactions(userId: userId, from: start)
            guard self.userId == userId else { return }
            transactions = rows
            loadedSince = start
            cursor = stamp
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

    private var flight: Task<Void, Error>?

    /// The whole history, fresh, for screens that need all of it (Beranda, Dompet, Budget, export...). Screens that react
    /// to the same write at the same moment share one download, and the list's own store stays complete afterwards.
    func fetchAll(userId: String) async throws -> [Transaction] {
        adopt(userId)
        if flight == nil {
            reloadTask?.cancel()
            flight = Task {
                if self.isComplete, await self.applyChanges() { return }
                let stamp = try? await self.repo.latestTransactionStamp(userId: userId)
                let rows = try await self.repo.fetchTransactions(userId: userId)
                guard self.userId == userId else { return }
                self.transactions = rows
                self.loadedSince = .distantPast
                self.isComplete = true
                self.cursor = stamp
            }
        }
        let task = flight
        defer { if flight == task { flight = nil } }
        try await task?.value
        return transactions
    }

    /// Reads the loaded months again, after a write or a pull to refresh.
    func reload() async {
        guard let userId, let since = loadedSince else { return }
        if await applyChanges() { return }
        do {
            let stamp = try? await repo.latestTransactionStamp(userId: userId)
            let rows = try await repo.fetchTransactions(userId: userId, from: isComplete ? nil : since)
            guard self.userId == userId else { return }
            transactions = rows
            cursor = stamp
        } catch {}
    }

    /// Where the last full read stopped, as the server's own `updated_at`. nil until a full read has run.
    private var cursor: String?

    /// Reads only what changed since the cursor and folds it in. False when it could not (no cursor, too many changes, offline), so the caller reads everything.
    private func applyChanges() async -> Bool {
        guard let userId, let since = cursor, let loaded = loadedSince else { return false }
        guard let changes = try? await repo.transactionChanges(userId: userId, since: since), self.userId == userId else { return false }
        let touched = Set(changes.live.map(\.id)).union(changes.deleted)
        // a row outside the months loaded stays out; one that moved out of them leaves
        let inWindow = changes.live.filter { $0.date >= loaded }
        if !touched.isEmpty {
            transactions = (inWindow + transactions.filter { !touched.contains($0.id) }).newestFirst()
        }
        cursor = changes.cursor
        return true
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

    /// A different Workspace is open: nothing loaded belongs to it (rows, delta cursor and any download in flight).
    func reset() {
        reloadTask?.cancel()
        flight = nil
        userId = nil
        transactions = []
        loadedSince = nil
        isComplete = false
        cursor = nil
    }

    // MARK: Helpers

    private func adopt(_ id: String) {
        guard userId != id else { return }
        userId = id
        transactions = []
        loadedSince = nil
        isComplete = false
        cursor = nil
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
