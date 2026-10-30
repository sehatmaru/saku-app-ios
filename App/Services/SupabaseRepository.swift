import Foundation
import Supabase

final class SupabaseRepository: @unchecked Sendable {
    static let shared = SupabaseRepository()
    private let client = SupabaseSDK.client

    private init() {}

    // MARK: - Accounts

    func fetchAccounts(userId: String) async throws -> [Account] {
        try await client
            .from("accounts")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func createAccount(name: String, type: Account.AccountType, openingBalance: Double, icon: String?, userId: String, isDefault: Bool = false, creditLimit: Double? = nil, dueDate: String? = nil, statementDay: Int? = nil, color: String? = nil, cardNetwork: String? = nil, openingUnbilledUntil: String? = nil) async throws -> Account {
        var payload: [String: AnyJSON] = [
            "user_id": AnyJSON.string(userId),
            "name": AnyJSON.string(name),
            "account_type": AnyJSON.string(type.rawValue),
            "opening_balance": AnyJSON.double(openingBalance),
            "current_balance": AnyJSON.double(openingBalance),
            "is_default": AnyJSON.bool(isDefault),
            "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
        ]
        if let creditLimit { payload["credit_limit"] = AnyJSON.double(creditLimit) }
        if let dueDate { payload["due_date"] = AnyJSON.string(dueDate) }
        if let statementDay { payload["statement_day"] = AnyJSON.integer(statementDay) }
        if let color { payload["color"] = AnyJSON.string(color) }
        if let cardNetwork { payload["card_network"] = AnyJSON.string(cardNetwork) }
        if let openingUnbilledUntil { payload["opening_unbilled_until"] = AnyJSON.string(openingUnbilledUntil) }
        return try await client
            .from("accounts")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateAccount(id: String, name: String, type: Account.AccountType, openingBalance: Double, currentBalance: Double?, icon: String?, isArchived: Bool, isDefault: Bool? = nil, creditLimit: Double? = nil, dueDate: String? = nil, statementDay: Int? = nil, color: String? = nil, cardNetwork: String? = nil, openingUnbilledUntil: String? = nil, clearOpeningUnbilled: Bool = false) async throws -> Account {
        var payload: [String: AnyJSON] = [
            "name": AnyJSON.string(name),
            "account_type": AnyJSON.string(type.rawValue),
            "opening_balance": AnyJSON.double(openingBalance),
            "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "is_archived": AnyJSON.bool(isArchived),
        ]
        if let currentBalance { payload["current_balance"] = AnyJSON.double(currentBalance) }
        if let isDefault { payload["is_default"] = AnyJSON.bool(isDefault) }
        if let creditLimit { payload["credit_limit"] = AnyJSON.double(creditLimit) }
        if let dueDate { payload["due_date"] = AnyJSON.string(dueDate) }
        if let statementDay { payload["statement_day"] = AnyJSON.integer(statementDay) }
        if let color { payload["color"] = AnyJSON.string(color) }
        if let cardNetwork { payload["card_network"] = AnyJSON.string(cardNetwork) }
        if let openingUnbilledUntil { payload["opening_unbilled_until"] = AnyJSON.string(openingUnbilledUntil) }
        else if clearOpeningUnbilled { payload["opening_unbilled_until"] = AnyJSON.null }
        return try await client
            .from("accounts")
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    /// Sets the stored balance directly, leaving the starting balance alone.
    func setCurrentBalance(id: String, to value: Double) async throws -> Account {
        try await client
            .from("accounts")
            .update(["current_balance": AnyJSON.double(value)])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteAccount(id: String) async throws {
        try await client
            .from("accounts")
            .update(["deleted_at": AnyJSON.string("now()")] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
    }

    func toggleArchiveAccount(id: String, archived: Bool) async throws {
        try await client
            .from("accounts")
            .update(["is_archived": AnyJSON.bool(archived)] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
    }

    /// How many wallets and transactions an account holds, for the guest switch question (Enhancement 3 US2).
    func dataCounts(userId: String) async throws -> (wallets: Int, transactions: Int) {
        async let wallets = client.from("accounts").select("id", head: true, count: .exact)
            .eq("user_id", value: userId).is("deleted_at", value: nil).execute().count
        async let transactions = client.from("transactions").select("id", head: true, count: .exact)
            .eq("user_id", value: userId).is("deleted_at", value: nil).execute().count
        return try await (wallets ?? 0, transactions ?? 0)
    }

    // MARK: - Transactions

    func fetchTransactions(userId: String) async throws -> [Transaction] {
        try await client
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("occurred_at", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchTransactions(accountId: String, userId: String) async throws -> [Transaction] {
        try await client
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .or("primary_account_id.eq.\(accountId),counterparty_account_id.eq.\(accountId)")
            .is("deleted_at", value: nil)
            .order("occurred_at", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createTransaction(accountId: String, categoryId: String?, amount: Double, type: Transaction.TransactionType, description: String?, note: String?, date: Date, userId: String, isCreditAccount: Bool = false, clientOperationId: String? = nil, startsPeriod: Bool = false) async throws -> Transaction {
        let operationId = clientOperationId ?? UUID().uuidString

        let rpcType: String
        let rpcAmount: Double
        if type == .adjustment {
            rpcType = amount >= 0 ? Transaction.TransactionType.income.rawValue : Transaction.TransactionType.expense.rawValue
            rpcAmount = abs(amount)
        } else {
            rpcType = type.rawValue
            rpcAmount = amount
        }

        let params: [String: AnyJSON] = [
            "p_amount": AnyJSON.double(rpcAmount),
            "p_category_id": categoryId.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_client_operation_id": AnyJSON.string(operationId),
            "p_description": description.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_occurred_at": AnyJSON.string(date.iso8601Formatted),
            "p_primary_account_id": AnyJSON.string(accountId),
            "p_transaction_type": AnyJSON.string(rpcType),
        ]

        let transactionId: String = try await client.rpc("create_transaction", params: params).execute().value
        // an early salary the user chose to start the period with; the flag lives on the transaction so deleting it undoes the shift
        if startsPeriod {
            try await client.from("transactions").update(["starts_period": true]).eq("id", value: transactionId).execute()
            await MainActor.run { EarlySalary.remember(date) }
        }

        var transaction: Transaction = try await client
            .from("transactions")
            .select()
            .eq("id", value: transactionId)
            .single()
            .execute()
            .value

        if type == .adjustment {
            transaction = Transaction(
                id: transaction.id,
                accountId: transaction.accountId,
                counterpartyAccountId: transaction.counterpartyAccountId,
                categoryId: transaction.categoryId,
                amount: amount,
                type: .adjustment,
                description: transaction.description,
                note: transaction.note,
                date: transaction.date,
                delta: amount
            )
        }

        let delta: Double
        switch type {
        case .income: delta = isCreditAccount ? -amount : amount
        case .expense: delta = isCreditAccount ? amount : -amount
        case .transfer: delta = 0
        case .adjustment: delta = 0
        case .cardPayment: delta = 0
        }
        if delta != 0 {
            try await client.rpc("increment_account_balance", params: [
                "p_account_id": AnyJSON.string(accountId),
                "p_delta": AnyJSON.double(delta),
            ]).execute()
        }

        return transaction
    }

    func createAdjustmentLog(accountId: String, amount: Double, note: String, date: Date) async throws {
        try await client.rpc("create_adjustment_log", params: [
            "p_primary_account_id": AnyJSON.string(accountId),
            "p_amount": AnyJSON.double(amount),
            "p_note": AnyJSON.string(note),
            "p_occurred_at": AnyJSON.string(date.iso8601Formatted),
        ]).execute()
    }

    /// Records a card bill paid from outside Saku: the card's debt drops, no wallet moves.
    func createCardPayment(cardId: String, amount: Double, note: String?, date: Date) async throws {
        let params: [String: AnyJSON] = [
            "p_card_id": AnyJSON.string(cardId),
            "p_amount": AnyJSON.double(amount),
            "p_client_operation_id": AnyJSON.string(UUID().uuidString),
            "p_note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_occurred_at": AnyJSON.string(date.iso8601Formatted),
        ]
        _ = try await client.rpc("create_card_payment", params: params).execute()
        try await client.rpc("increment_account_balance", params: [
            "p_account_id": AnyJSON.string(cardId),
            "p_delta": AnyJSON.double(-amount),
        ]).execute()
    }

    func createTransfer(primaryAccountId: String, counterpartyAccountId: String, amount: Double, description: String?, note: String?, date: Date) async throws -> Transaction {
        let operationId = UUID().uuidString

        let params: [String: AnyJSON] = [
            "p_amount": AnyJSON.double(amount),
            "p_client_operation_id": AnyJSON.string(operationId),
            "p_counterparty_account_id": AnyJSON.string(counterpartyAccountId),
            "p_description": description.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "p_occurred_at": AnyJSON.string(date.iso8601Formatted),
            "p_primary_account_id": AnyJSON.string(primaryAccountId),
        ]

        let transactionId: String = try await client.rpc("create_transfer", params: params).execute().value

        let transaction: Transaction = try await client
            .from("transactions")
            .select()
            .eq("id", value: transactionId)
            .single()
            .execute()
            .value

        let isCredit = try await creditFlags([primaryAccountId, counterpartyAccountId])
        try await applyBalanceEffects(of: transaction, isCredit: isCredit, sign: 1)

        return transaction
    }

    /// Updates a transaction and moves balances with it: the old effect is reversed on the
    /// old wallet(s) and the new effect applied on the new ones, so changing the wallet,
    /// amount, type or transfer destination keeps every balance right.
    func updateTransaction(id: String, accountId: String, counterpartyAccountId: String? = nil, categoryId: String?, amount: Double, type: Transaction.TransactionType, description: String?, note: String?, date: Date) async throws -> Transaction {
        let old: Transaction = try await client
            .from("transactions")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        var values: [String: AnyJSON] = [
            "primary_account_id": AnyJSON.string(accountId),
            "category_id": categoryId.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "amount": AnyJSON.double(amount),
            "transaction_type": AnyJSON.string(type.rawValue),
            "description": description.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "occurred_at": AnyJSON.string(date.iso8601Formatted),
        ]
        if type == .transfer, let counterpartyAccountId {
            values["counterparty_account_id"] = AnyJSON.string(counterpartyAccountId)
        }
        let updated: Transaction = try await client
            .from("transactions")
            .update(values)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value

        let ids = Set([old.accountId, accountId] + [old.counterpartyAccountId, updated.counterpartyAccountId].compactMap { $0 })
        let isCredit = try await creditFlags(Array(ids))

        // Net balance change per account: minus the old effect, plus the new one.
        var net: [String: Double] = [:]
        for (sign, txn) in [(-1.0, old), (1.0, updated)] {
            for (accountId, effect) in Self.balanceEffects(of: txn, isCredit: isCredit) {
                net[accountId, default: 0] += sign * effect
            }
        }
        for (accountId, change) in net where abs(change) > 0.001 {
            try await client.rpc("increment_account_balance", params: [
                "p_account_id": AnyJSON.string(accountId),
                "p_delta": AnyJSON.double(change),
            ]).execute()
        }

        // an edited early salary: its date may have moved, so the period dates are read again
        if updated.startsPeriod == true { await refreshShiftsAndAnnounce() }
        return updated
    }

    /// How a transaction moves each wallet's balance (credit cards track debt, so the sign flips).
    static func balanceEffects(of txn: Transaction, isCredit: [String: Bool]) -> [(String, Double)] {
        let credit = isCredit[txn.accountId] ?? false
        switch txn.type {
        case .income: return [(txn.accountId, credit ? -txn.amount : txn.amount)]
        case .expense: return [(txn.accountId, credit ? txn.amount : -txn.amount)]
        case .transfer:
            // Money leaves `from` and arrives at `to`. A card's balance is debt, so paying into
            // a card lowers it and taking cash out of one raises it.
            guard let to = txn.counterpartyAccountId else { return [] }
            return [(txn.accountId, credit ? txn.amount : -txn.amount),
                    (to, (isCredit[to] ?? false) ? -txn.amount : txn.amount)]
        case .adjustment: return []
        // Only ever on a card, whose balance is debt.
        case .cardPayment: return [(txn.accountId, -txn.amount)]
        }
    }

    /// Whether each of these accounts is a credit card.
    private func creditFlags(_ ids: [String]) async throws -> [String: Bool] {
        let accounts: [Account] = try await client
            .from("accounts")
            .select()
            .in("id", values: ids)
            .execute()
            .value
        return Dictionary(accounts.map { ($0.id, $0.isCreditCard) }, uniquingKeysWith: { first, _ in first })
    }

    private func applyBalanceEffects(of txn: Transaction, isCredit: [String: Bool], sign: Double) async throws {
        for (accountId, effect) in Self.balanceEffects(of: txn, isCredit: isCredit) {
            try await client.rpc("increment_account_balance", params: [
                "p_account_id": AnyJSON.string(accountId),
                "p_delta": AnyJSON.double(sign * effect),
            ]).execute()
        }
    }

    func softDeleteTransaction(id: String) async throws {
        let txn: Transaction = try await client
            .from("transactions")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        if txn.type == .adjustment {
            // Adjustments set the balance directly; undo exactly what they moved.
            try await client.rpc("increment_account_balance", params: [
                "p_account_id": AnyJSON.string(txn.accountId),
                "p_delta": AnyJSON.double(-(txn.delta ?? txn.amount)),
            ]).execute()
        } else {
            let isCredit = try await creditFlags([txn.accountId] + [txn.counterpartyAccountId].compactMap { $0 })
            try await applyBalanceEffects(of: txn, isCredit: isCredit, sign: -1)
        }

        try await client
            .from("transactions")
            .update(["deleted_at": AnyJSON.string("now()")] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
        // deleting an early salary that moved the period brings the usual period back (K4)
        if txn.startsPeriod == true { await refreshShiftsAndAnnounce() }
    }

    private func refreshShiftsAndAnnounce() async {
        await SupabaseSDK.refreshPaydayShifts()
        await MainActor.run { NotificationCenter.default.post(name: .dataDidChange, object: nil) }
    }

    // MARK: - Card Subscriptions

    func fetchSubscriptions(accountIds: [String]) async throws -> [CardSubscription] {
        try await client
            .from("card_subscriptions")
            .select()
            .in("account_id", values: accountIds)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func createSubscription(accountId: String, name: String, amount: Double, frequency: CardSubscription.Frequency, nextBillingDate: String?, categoryId: String?, note: String?) async throws -> CardSubscription {
        try await client
            .from("card_subscriptions")
            .insert([
                "account_id": AnyJSON.string(accountId),
                "name": AnyJSON.string(name),
                "amount": AnyJSON.double(amount),
                "frequency": AnyJSON.string(frequency.rawValue),
                "next_billing_date": nextBillingDate.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "category_id": categoryId.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            ] as [String: AnyJSON])
            .select()
            .single()
            .execute()
            .value
    }

    /// `previousAmount` is the price before this edit; it's kept only when the price changed,
    /// so the app can show a price increase.
    func updateSubscription(id: String, name: String, amount: Double, frequency: CardSubscription.Frequency, nextBillingDate: String?, isActive: Bool, categoryId: String?, note: String?, previousAmount: Double? = nil) async throws -> CardSubscription {
        var values: [String: AnyJSON] = [
            "name": AnyJSON.string(name),
            "amount": AnyJSON.double(amount),
            "frequency": AnyJSON.string(frequency.rawValue),
            "next_billing_date": nextBillingDate.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "is_active": AnyJSON.bool(isActive),
            "category_id": categoryId.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
        ]
        if let previousAmount, previousAmount != amount {
            values["previous_amount"] = AnyJSON.double(previousAmount)
        }
        return try await client
            .from("card_subscriptions")
            .update(values)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteSubscription(id: String) async throws {
        try await client
            .from("card_subscriptions")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Installments

    func fetchInstallments(accountIds: [String]) async throws -> [CardInstallment] {
        guard !accountIds.isEmpty else { return [] }
        return try await client
            .from("card_installments")
            .select()
            .in("account_id", values: accountIds)
            .is("deleted_at", value: nil)
            .execute()
            .value
    }

    /// Spreads a card purchase over `months` statements.
    func createInstallment(accountId: String, transactionId: String, months: Int) async throws {
        try await client
            .from("card_installments")
            .insert([
                "account_id": AnyJSON.string(accountId),
                "transaction_id": AnyJSON.string(transactionId),
                "months": AnyJSON.integer(months),
            ] as [String: AnyJSON])
            .execute()
    }

    // MARK: - Categories

    /// Categories under the user's own names (renamed built-in ones included).
    func fetchCategories() async throws -> [Category] {
        async let loaded: [Category] = client
            .from("categories")
            .select()
            .is("deleted_at", value: nil)
            .order("name", ascending: true)
            .execute()
            .value
        let names = ((try? await fetchCategoryPreferences()) ?? [])
            .reduce(into: [String: String]()) { if let name = $1.customName { $0[$1.categoryId] = name } }
        return try await loaded.map { names[$0.id].map($0.named) ?? $0 }
    }

    func createCategory(name: String, type: CategoryType, icon: String?, color: String?, userId: String) async throws -> Category {
        do { return try await insertCategory(name: name, type: type, icon: icon, color: color, userId: userId) }
        catch { throw FreeLimits.friendly(error) }
    }

    private func insertCategory(name: String, type: CategoryType, icon: String?, color: String?, userId: String) async throws -> Category {
        try await client
            .from("categories")
            .insert([
                "owner_type": AnyJSON.string("user"),
                "user_id": AnyJSON.string(userId),
                "name": AnyJSON.string(name),
                "normalized_name": AnyJSON.string(name.lowercased()),
                "category_kind": AnyJSON.string(type.rawValue),
                "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "color": color.map { AnyJSON.string($0) } ?? AnyJSON.null,
            ] as [String: AnyJSON])
            .select()
            .single()
            .execute()
            .value
    }

    /// Renames or restyles one of the user's own categories (built-in ones can only be hidden).
    func updateCategory(id: String, name: String, icon: String?, color: String?) async throws -> Category {
        try await client
            .from("categories")
            .update([
                "name": AnyJSON.string(name),
                "normalized_name": AnyJSON.string(name.lowercased()),
                "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "color": color.map { AnyJSON.string($0) } ?? AnyJSON.null,
            ] as [String: AnyJSON])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func fetchCategoryPreferences() async throws -> [CategoryPreference] {
        try await client
            .from("category_preferences")
            .select("category_id,is_hidden,sort_order,custom_name")
            .execute()
            .value
    }

    /// Hides or shows a category for this user. Hidden ones leave the pickers (and budgets);
    /// transactions and the budget row are kept, so showing it again brings everything back.
    func setCategoryHidden(id: String, hidden: Bool) async throws {
        do {
            try await client
                .from("category_preferences")
                .upsert([
                    "category_id": AnyJSON.string(id),
                    "is_hidden": AnyJSON.bool(hidden),
                    "updated_at": AnyJSON.string(Date().iso8601Formatted),
                ] as [String: AnyJSON], onConflict: "user_id,category_id")
                .execute()
        } catch {
            throw FreeLimits.friendly(error)
        }
    }

    /// Gives a category (built-in ones too) the user's own name; nil brings the shared name back.
    func setCategoryName(id: String, name: String?) async throws {
        try await client
            .from("category_preferences")
            .upsert([
                "category_id": AnyJSON.string(id),
                "custom_name": name.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "updated_at": AnyJSON.string(Date().iso8601Formatted),
            ] as [String: AnyJSON], onConflict: "user_id,category_id")
            .execute()
    }

    /// Hides several categories at once (guest/Google setup, step 4).
    func hideCategories(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let now = Date().iso8601Formatted
        let rows: [[String: AnyJSON]] = ids.map {
            ["category_id": .string($0), "is_hidden": .bool(true), "updated_at": .string(now)]
        }
        try await client
            .from("category_preferences")
            .upsert(rows, onConflict: "user_id,category_id")
            .execute()
    }

    func softDeleteCategory(id: String) async throws {
        try await client
            .from("categories")
            .update(["deleted_at": AnyJSON.string("now()")] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Budgets

    /// Budgets with this period's amount: a temporary change if one covers it, else the base amount.
    func fetchBudgets(userId: String) async throws -> [Budget] {
        var budgets: [Budget] = try await client
            .from("budgets")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
        let changes = (try? await fetchBudgetAmountChanges()) ?? []
        let periodStart = PaydayCycle.current.period(containing: Date()).start
        for index in budgets.indices {
            let resolved = ResolvedBudgetAmount.resolve(
                base: budgets[index].amount, changes: changes.filter { $0.budgetId == budgets[index].id },
                periodStart: periodStart)
            guard resolved.source == .temporary else { continue }
            budgets[index].baseAmount = budgets[index].amount
            budgets[index].amount = resolved.amount
            budgets[index].temporary = resolved.temporary
        }
        return budgets
    }

    /// Every amount change that still counts (canceled ones are left out), oldest first.
    func fetchBudgetAmountChanges() async throws -> [BudgetAmountChange] {
        try await client
            .from("budget_amount_changes")
            .select()
            .is("canceled_at", value: nil)
            .order("effective_from")
            .execute()
            .value
    }

    /// `kind` "base": new amount from `from` on. "temporary": the amount for `from`..<`to`.
    func setBudgetAmount(budgetId: String, amount: Double, kind: String, from: Date, to: Date?) async throws {
        var params: [String: AnyJSON] = [
            "p_budget_id": .string(budgetId), "p_amount": .double(amount), "p_kind": .string(kind),
            "p_from": .string(BudgetAmountChange.dayString(from)),
        ]
        if let to { params["p_to"] = .string(BudgetAmountChange.dayString(to)) }
        try await client.rpc("set_budget_amount", params: params).execute()
    }

    func cancelBudgetTemporary(budgetId: String, periodStart: Date) async throws {
        try await client.rpc("cancel_budget_temporary", params: [
            "p_budget_id": budgetId, "p_period_start": BudgetAmountChange.dayString(periodStart),
        ]).execute()
    }

    func createBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async throws -> Budget {
        do {
            return try await insertBudget(categoryId: categoryId, name: name, amount: amount, periodUnit: periodUnit,
                                          periodInterval: periodInterval, startDate: startDate, endDate: endDate, userId: userId)
        } catch {
            throw FreeLimits.friendly(error)
        }
    }

    private func insertBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async throws -> Budget {
        try await client
            .from("budgets")
            .insert([
                "user_id": AnyJSON.string(userId),
                "category_id": AnyJSON.string(categoryId),
                "name": AnyJSON.string(name),
                "amount": AnyJSON.double(amount),
                "period_unit": AnyJSON.string(periodUnit),
                "period_interval": AnyJSON.integer(periodInterval),
                "start_date": AnyJSON.string(startDate),
                "end_date": endDate.map { AnyJSON.string($0) } ?? AnyJSON.null,
            ] as [String: AnyJSON])
            .select()
            .single()
            .execute()
            .value
    }

    func updateBudget(id: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, isActive: Bool) async throws -> Budget {
        try await client
            .from("budgets")
            .update([
                "name": AnyJSON.string(name),
                "amount": AnyJSON.double(amount),
                "period_unit": AnyJSON.string(periodUnit),
                "period_interval": AnyJSON.integer(periodInterval),
                "start_date": AnyJSON.string(startDate),
                "end_date": endDate.map { AnyJSON.string($0) } ?? AnyJSON.null,
                "is_active": AnyJSON.bool(isActive),
            ] as [String: AnyJSON])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteBudget(id: String) async throws {
        try await client
            .from("budgets")
            .update(["deleted_at": AnyJSON.string("now()")] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Balance Computation

    func computeAccountBalance(accountId: String) async throws -> Double {
        let rows: [AmountRow] = try await client
            .from("transaction_entries")
            .select("signed_amount")
            .eq("account_id", value: accountId)
            .execute()
            .value
        return rows.reduce(0) { $0 + $1.amount }
    }
}

extension SupabaseRepository {
    struct AmountRow: Decodable {
        let amount: Double

        enum CodingKeys: String, CodingKey {
            case amount = "signed_amount"
        }
    }
}

private extension Date {
    var iso8601Formatted: String {
        ISO8601DateFormatter().string(from: self)
    }
}

extension SupabaseRepository {
    /// Every budget the user ever had, deleted ones included, for the history.
    func fetchBudgetsForHistory() async throws -> [BudgetHistoryBudget] {
        try await client.from("budgets").select().order("created_at").execute().value
    }
}
