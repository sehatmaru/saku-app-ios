import Foundation

struct TransactionFilter: Equatable {
    var transactionTypes: Set<Transaction.TransactionType> = []
    var expenseCategoryIds: Set<String> = []
    var incomeCategoryIds: Set<String> = []
    var dateFrom: Date?
    var dateTo: Date?
    /// Only transactions posted from recurring bills.
    var recurringOnly = false

    var hasActiveFilters: Bool {
        !transactionTypes.isEmpty
            || !expenseCategoryIds.isEmpty
            || !incomeCategoryIds.isEmpty
            || dateFrom != nil
            || dateTo != nil
            || recurringOnly
    }

    var activeFilterCount: Int {
        var count = 0
        if !transactionTypes.isEmpty { count += 1 }
        if !expenseCategoryIds.isEmpty { count += 1 }
        if !incomeCategoryIds.isEmpty { count += 1 }
        if dateFrom != nil || dateTo != nil { count += 1 }
        if recurringOnly { count += 1 }
        return count
    }

    mutating func reset() {
        transactionTypes = []
        expenseCategoryIds = []
        incomeCategoryIds = []
        dateFrom = nil
        dateTo = nil
        recurringOnly = false
    }
}
