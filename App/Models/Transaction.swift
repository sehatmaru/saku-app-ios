import Foundation

struct Transaction: Identifiable, Codable {
    let id: String
    let accountId: String
    let categoryId: String?
    let subcategoryId: String?
    let amount: Double
    let type: TransactionType
    let note: String?
    let date: Date

    enum TransactionType: String, Codable {
        case income = "income"
        case expense = "expense"
        case transfer = "transfer"
    }
}

extension Transaction {
    static let sample: [Transaction] = [
        Transaction(id: "tx-1", accountId: "acc-1", categoryId: "cat-1", subcategoryId: nil, amount: 75_000, type: .expense, note: "Nasi Goreng", date: Date()),
        Transaction(id: "tx-2", accountId: "acc-2", categoryId: "cat-2", subcategoryId: nil, amount: 5_000_000, type: .income, note: "Gaji Bulanan", date: Date()),
        Transaction(id: "tx-3", accountId: "acc-3", categoryId: "cat-3", subcategoryId: nil, amount: 25_000, type: .expense, note: "Kopi", date: Date()),
        Transaction(id: "tx-4", accountId: "acc-1", categoryId: "cat-4", subcategoryId: nil, amount: 200_000, type: .expense, note: "Bensin", date: Date()),
        Transaction(id: "tx-5", accountId: "acc-2", categoryId: "cat-5", subcategoryId: nil, amount: 1_500_000, type: .expense, note: "Sewa Kost", date: Date()),
        Transaction(id: "tx-6", accountId: "acc-1", categoryId: "cat-6", subcategoryId: nil, amount: 350_000, type: .expense, note: "Baju", date: Date()),
        Transaction(id: "tx-7", accountId: "acc-3", categoryId: "cat-7", subcategoryId: nil, amount: 45_000, type: .expense, note: "Netflix", date: Date()),
    ]
}
