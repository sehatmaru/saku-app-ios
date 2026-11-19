import Foundation

/// Reminders for every Workspace the person belongs to, not only the open one (TD T4). The per-screen resyncs only know the
/// open Workspace and would clear the others' reminders, so with shared Workspaces this reads each one under its own
/// `x-saku-space` header and schedules everything at once. A person with only Workspace Pribadi keeps the old path.
@MainActor
enum ReminderSync {
    private static var running = false

    /// True when this sync, not the open screen, owns the reminders.
    static var ownsReminders: Bool { !WorkspaceStore.shared.shared.isEmpty }

    static func run(userId: String) async {
        guard ownsReminders, !running else { return }
        running = true
        defer { running = false }
        let repo = SupabaseRepository.shared
        var cards: [Account] = [], statements: [CreditStatement] = []
        var investments: [Account] = [], investmentTx: [Transaction] = []
        var subs: [CardSubscription] = []
        var tags: [String: NotificationManager.SpaceTag] = [:]
        var failed = false

        for space in WorkspaceStore.shared.spaces where space.deletionScheduledFor == nil {
            let id = space.id.uuidString.lowercased()
            let tag = space.isPersonal ? nil : NotificationManager.SpaceTag(id: id, name: space.displayName)
            let loaded: Bool = await SpaceStore.$override.withValue(id) {
                do {
                    let accounts = try await repo.fetchAccounts(userId: userId).filter(\.isActive)
                    let spaceCards = accounts.filter(\.isCreditCard)
                    let transactions = try await repo.fetchTransactions(userId: userId)
                    let plans = (try? await repo.fetchInstallments(accountIds: spaceCards.map(\.id))) ?? []
                    let spaceSubs = accounts.isEmpty ? [] : try await repo.fetchSubscriptions(accountIds: accounts.map(\.id))
                    for card in spaceCards {
                        if let statement = CreditStatement(card: card, transactions: transactions, installments: plans) {
                            cards.append(card); statements.append(statement)
                        }
                    }
                    for account in accounts where account.isInvestment {
                        investments.append(account)
                        investmentTx += transactions.filter { $0.accountId == account.id || $0.counterpartyAccountId == account.id }
                    }
                    subs += spaceSubs
                    if let tag {
                        for a in accounts { tags[a.id] = tag }
                        for s in spaceSubs { tags[s.id] = tag }
                    }
                    return true
                } catch { return false }
            }
            if !loaded { failed = true }
        }
        // a Workspace that could not be read must not wipe its reminders: try again on the next sync
        guard !failed else { return }
        NotificationManager.shared.setTags(tags)
        await NotificationManager.shared.resyncCardDue(cards: cards, statements: statements)
        await NotificationManager.shared.resyncInvestmentReminders(accounts: investments, transactions: investmentTx)
        await NotificationManager.shared.resyncAll(subscriptions: subs)
    }
}
