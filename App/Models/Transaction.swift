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
    static var sample: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        var all: [Transaction] = []
        var id = 1

        func day(_ offset: Int, _ monthOffset: Int = 0) -> Date {
            var comp = calendar.dateComponents([.year, .month], from: now)
            comp.month = (comp.month ?? 1) - monthOffset
            comp.day = offset
            comp.hour = 10
            comp.minute = 0
            return calendar.date(from: comp) ?? now
        }

        // MARK: Cash (acc-1) — daily spending
        for m in 0..<30 {
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-1", categoryId: "cat-exp-1", subcategoryId: nil, amount: 75_000, type: .expense, note: "Nasi Goreng", date: day(3, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-1", categoryId: "cat-exp-7", subcategoryId: nil, amount: 200_000, type: .expense, note: "Bensin", date: day(7, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-1", categoryId: "cat-exp-6", subcategoryId: nil, amount: 350_000, type: .expense, note: "Belanja Bulanan", date: day(10, m)),
                Transaction(id: "tx-\(id+3)", accountId: "acc-1", categoryId: "cat-exp-1", subcategoryId: nil, amount: 50_000, type: .expense, note: "Bakso", date: day(14, m)),
                Transaction(id: "tx-\(id+4)", accountId: "acc-1", categoryId: "cat-exp-8", subcategoryId: nil, amount: 120_000, type: .expense, note: "Vitamin", date: day(18, m)),
            ]
            id += 5
        }

        // MARK: BCA (acc-2) — salary & bills
        for m in 0..<30 {
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-2", categoryId: "cat-2", subcategoryId: nil, amount: 5_000_000, type: .income, note: "Gaji Bulanan", date: day(1, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-2", categoryId: "cat-exp-11", subcategoryId: nil, amount: 1_500_000, type: .expense, note: "Sewa Kost", date: day(2, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-2", categoryId: "cat-exp-6", subcategoryId: nil, amount: 300_000, type: .expense, note: "Belanja Bulanan", date: day(5, m)),
            ]
            id += 3
        }

        // MARK: GoPay (acc-3) — e-wallet daily
        for m in 0..<30 {
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-3", categoryId: "cat-exp-2", subcategoryId: nil, amount: 25_000, type: .expense, note: "Kopi Kenangan", date: day(4, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-3", categoryId: "cat-exp-5", subcategoryId: nil, amount: 49_000, type: .expense, note: "Netflix", date: day(8, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-3", categoryId: "cat-exp-4", subcategoryId: nil, amount: 85_000, type: .expense, note: "Top Up Shopee", date: day(15, m)),
            ]
            id += 3
        }

        // MARK: Transfer antar dompet
        for m in 0..<30 {
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-2", categoryId: nil, subcategoryId: nil, amount: 500_000, type: .transfer, note: "Tarik Tunai BCA → Cash", date: day(6, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-2", categoryId: nil, subcategoryId: nil, amount: 200_000, type: .transfer, note: "Top Up GoPay dari BCA", date: day(12, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-3", categoryId: nil, subcategoryId: nil, amount: 100_000, type: .transfer, note: "Top Up GoPay dari BCA", date: day(12, m)),
            ]
            id += 3
        }

        return all
    }
}
