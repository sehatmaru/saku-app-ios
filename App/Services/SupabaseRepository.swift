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

    func createAccount(name: String, type: Account.AccountType, openingBalance: Double, icon: String?, userId: String, isDefault: Bool = false) async throws -> Account {
        try await client
            .from("accounts")
            .insert([
                "user_id": AnyJSON.string(userId),
                "name": AnyJSON.string(name),
                "account_type": AnyJSON.string(type.rawValue),
                "opening_balance": AnyJSON.double(openingBalance),
                "current_balance": AnyJSON.double(openingBalance),
                "is_default": AnyJSON.bool(isDefault),
                "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
            ] as [String: AnyJSON])
            .select()
            .single()
            .execute()
            .value
    }

    func updateAccount(id: String, name: String, type: Account.AccountType, openingBalance: Double, currentBalance: Double?, icon: String?, isArchived: Bool, isDefault: Bool? = nil) async throws -> Account {
        var payload: [String: AnyJSON] = [
            "name": AnyJSON.string(name),
            "account_type": AnyJSON.string(type.rawValue),
            "opening_balance": AnyJSON.double(openingBalance),
            "icon": icon.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "is_archived": AnyJSON.bool(isArchived),
        ]
        if let currentBalance {
            payload["current_balance"] = AnyJSON.double(currentBalance)
        }
        if let isDefault {
            payload["is_default"] = AnyJSON.bool(isDefault)
        }
        return try await client
            .from("accounts")
            .update(payload)
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

    // MARK: - Transactions

    func fetchTransactions(userId: String) async throws -> [Transaction] {
        try await client
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("occurred_at", ascending: false)
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
            .execute()
            .value
    }

    func createTransaction(accountId: String, categoryId: String?, amount: Double, type: Transaction.TransactionType, description: String?, note: String?, date: Date, userId: String) async throws -> Transaction {
        let operationId = UUID().uuidString

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
        case .income: delta = amount
        case .expense: delta = -amount
        case .transfer: delta = 0
        case .adjustment: delta = 0
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

        try await client.rpc("increment_account_balance", params: [
            "p_account_id": AnyJSON.string(primaryAccountId),
            "p_delta": AnyJSON.double(-amount),
        ]).execute()

        try await client.rpc("increment_account_balance", params: [
            "p_account_id": AnyJSON.string(counterpartyAccountId),
            "p_delta": AnyJSON.double(amount),
        ]).execute()

        return transaction
    }

    func updateTransaction(id: String, accountId: String, categoryId: String?, amount: Double, type: Transaction.TransactionType, description: String?, note: String?, date: Date) async throws -> Transaction {
        let values: [String: AnyJSON] = [
            "primary_account_id": AnyJSON.string(accountId),
            "category_id": categoryId.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "amount": AnyJSON.double(amount),
            "transaction_type": AnyJSON.string(type.rawValue),
            "description": description.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "note": note.map { AnyJSON.string($0) } ?? AnyJSON.null,
            "occurred_at": AnyJSON.string(date.iso8601Formatted),
        ]
        return try await client
            .from("transactions")
            .update(values)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteTransaction(id: String) async throws {
        try await client
            .from("transactions")
            .update(["deleted_at": AnyJSON.string("now()")] as [String: AnyJSON])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Categories

    func fetchCategories() async throws -> [Category] {
        try await client
            .from("categories")
            .select()
            .is("deleted_at", value: nil)
            .order("name", ascending: true)
            .execute()
            .value
    }

    // MARK: - Budgets

    func fetchBudgets(userId: String) async throws -> [Budget] {
        try await client
            .from("budgets")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchBudgetSpent(categoryId: String, userId: String, startDate: String, endDate: String?) async throws -> Double {
        struct Row: Decodable { let amount: Double }

        var query = client
            .from("transactions")
            .select("amount")
            .eq("user_id", value: userId)
            .eq("category_id", value: categoryId)
            .eq("transaction_type", value: "expense")
            .gte("occurred_at", value: startDate)
            .is("deleted_at", value: nil)

        if let endDate {
            query = query.lt("occurred_at", value: endDate)
        }

        let rows: [Row] = try await query.execute().value
        return rows.reduce(0) { $0 + $1.amount }
    }

    func createBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async throws -> Budget {
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
