import Foundation

/// What a free account can hold (PRD "Perampingan Kategori Bawaan & Batas Kategori"): active categories are
/// built-in plus own, hidden ones don't count; budgets are one per expense category. Existing data is never
/// removed; the limit only stops adding. The server enforces the same numbers (migration free_limits).
enum FreeLimits {
    static let expenseCategories = 7
    static let incomeCategories = 5
    static let budgets = 7

    static func categories(_ type: CategoryType) -> Int { type == .income ? incomeCategories : expenseCategories }

    /// Active (shown) categories of one type, the internal balance-correction category excluded.
    static func activeCount(_ shown: [Category], type: CategoryType) -> Int {
        shown.filter { $0.type == type && !CategoryCatalog.isSystem($0) }.count
    }

    static func categoryMessage(_ type: CategoryType) -> String {
        L("Paket gratis maksimal %lld kategori %@ aktif. Sembunyikan kategori yang tidak kamu pakai untuk memberi ruang. Saku Plus tanpa batas segera hadir.",
          categories(type), type == .income ? L("pemasukan") : L("pengeluaran"))
    }

    static func budgetMessage() -> String {
        L("Paket gratis maksimal %lld budget. Budget yang sudah ada tetap aman. Saku Plus tanpa batas segera hadir.", budgets)
    }

    /// The server's refusal (`category_limit_*`, `budget_limit`) as a readable error; any other error is returned as is.
    static func friendly(_ error: Error) -> Error {
        let text = String(describing: error)
        if text.contains("category_limit_income") { return LimitError(message: categoryMessage(.income)) }
        if text.contains("category_limit_expense") { return LimitError(message: categoryMessage(.expense)) }
        if text.contains("budget_limit") { return LimitError(message: budgetMessage()) }
        return error
    }

    struct LimitError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
