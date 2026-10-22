import SwiftUI

/// What a new user picked during setup (name, wallets, categories, payday), applied once
/// right after their account exists: guests sign in first with it, Google/Apple after sign-in.
struct OnboardingSetup {
    struct Wallet {
        let name: String
        let type: Account.AccountType
        let icon: String
        let balance: Double
    }

    var name: String
    var wallets: [Wallet]
    /// `systemKey`s of the built-in categories the user unselected; they get hidden.
    var hiddenCategoryKeys: Set<String>
    /// Nil when skipped: Budget asks again later.
    var paydayDay: Int?
    /// Monthly budget per expense category, by `systemKey`; only the ones the user gave an amount.
    var budgets: [String: Double] = [:]
    /// Agreed to Smart Tracker in step 6; recorded on the account once it exists.
    var smartTrackerConsent = false
    /// Also keep Ingatan on the server (real accounts only).
    var memorySync = false
    /// Chose "Coba 7 hari" in step 8 (real accounts only).
    var joinsPlus = false
}

/// The built-in categories offered in setup step 4, matched to the database by `systemKey`
/// (categories can't be read before a guest signs in, so the list lives here).
struct OnboardingCategory: Identifiable {
    let key: String
    let name: String
    let icon: String
    let isExpense: Bool
    var id: String { key }

    /// Onboarding-only tint, cycled through a saturated palette (the saved colours are pastel).
    var hex: String {
        let palette = ["E8772E", "1F6FD1", "C2417A", "16875A", "6B4BC8", "D9A21B", "0E8C8C", "D93636", "143A73", "6E6E73"]
        let index = Self.all.firstIndex { $0.key == key } ?? 0
        return palette[index % palette.count]
    }
    var color: Color { Color(hex: hex) }

    /// The built-in list for accounts created from the "Perampingan Kategori" release on (category set 2).
    static let expense: [OnboardingCategory] = [
        .init(key: "expense_transport", name: "Transportasi", icon: "car", isExpense: true),
        .init(key: "expense_snack_coffee", name: "Jajan & Kopi", icon: "cup.and.saucer", isExpense: true),
        .init(key: "expense_daily_meals", name: "Makan Harian", icon: "fork.knife", isExpense: true),
        .init(key: "expense_groceries_household", name: "Belanja & Rumah Tangga", icon: "cart", isExpense: true),
        .init(key: "expense_bills_subscriptions", name: "Tagihan & Langganan", icon: "doc.text", isExpense: true),
        .init(key: "expense_health_sport", name: "Kesehatan & Olahraga", icon: "heart", isExpense: true),
        .init(key: "expense_etc", name: "Lain-lain", icon: "ellipsis", isExpense: true),
    ]

    static let income: [OnboardingCategory] = [
        .init(key: "income_salary", name: "Gaji", icon: "dollarsign.circle", isExpense: false),
        .init(key: "income_business", name: "Bisnis", icon: "briefcase", isExpense: false),
        .init(key: "income_investment", name: "Investasi", icon: "chart.line.uptrend.xyaxis", isExpense: false),
        .init(key: "income_other", name: "Lainnya", icon: "ellipsis", isExpense: false),
    ]

    static let all = expense + income
}

/// What the welcome screen after setup shows (design "Siap"): the counts, the payday, the budget total, and Plus.
struct SetupWelcome: Equatable {
    var name: String
    var wallets: Int
    var categories: Int
    /// 31 means "Akhir bulan", 1 "Tidak tentu / tanggal 1"; nil when the step was skipped.
    var paydayDay: Int?
    /// 0 when no budget was set.
    var budgetTotal: Double
    var joinedPlus: Bool
    var plusUntil: Date?
}
