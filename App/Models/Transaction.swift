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

        // variasi per bulan pakai m mod pattern
        for m in 0..<30 {
            let isBonusMonth = m % 3 == 0
            let isHighSpendMonth = m % 4 == 2
            let isLowSpendMonth = m % 5 == 3
            let isBigPurchaseMonth = m % 6 == 4

            let salaryBase: Double = isBonusMonth ? 7_000_000 : 5_000_000
            let rentCost: Double = 1_500_000
            let groceryBase: Double = isHighSpendMonth ? 450_000 : isLowSpendMonth ? 200_000 : 300_000

            // MARK: Cash (acc-1) — daily spending
            let cashFood: Double = isHighSpendMonth ? 95_000 : isLowSpendMonth ? 50_000 : 75_000
            let cashFuel: Double = isHighSpendMonth ? 250_000 : isLowSpendMonth ? 150_000 : 200_000
            let cashGroceries: Double = isHighSpendMonth ? 500_000 : isLowSpendMonth ? 250_000 : 350_000
            let cashSnack: Double = isHighSpendMonth ? 75_000 : isLowSpendMonth ? 30_000 : 50_000
            let cashHealth: Double = isHighSpendMonth ? 150_000 : 120_000

            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-1", categoryId: "cat-exp-1", subcategoryId: nil, amount: cashFood, type: .expense, note: "Nasi Goreng", date: day(3, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-1", categoryId: "cat-exp-7", subcategoryId: nil, amount: cashFuel, type: .expense, note: "Bensin", date: day(7, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-1", categoryId: "cat-exp-6", subcategoryId: nil, amount: cashGroceries, type: .expense, note: "Belanja Bulanan", date: day(10, m)),
                Transaction(id: "tx-\(id+3)", accountId: "acc-1", categoryId: "cat-exp-1", subcategoryId: nil, amount: cashSnack, type: .expense, note: "Bakso", date: day(14, m)),
                Transaction(id: "tx-\(id+4)", accountId: "acc-1", categoryId: "cat-exp-8", subcategoryId: nil, amount: cashHealth, type: .expense, note: "Vitamin", date: day(18, m)),
            ]
            id += 5

            // MARK: BCA (acc-2) — salary & bills
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-2", categoryId: "cat-2", subcategoryId: nil, amount: salaryBase, type: .income, note: isBonusMonth ? "Gaji + Bonus Bulanan" : "Gaji Bulanan", date: day(1, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-2", categoryId: "cat-exp-11", subcategoryId: nil, amount: rentCost, type: .expense, note: "Sewa Kost", date: day(2, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-2", categoryId: "cat-exp-6", subcategoryId: nil, amount: groceryBase, type: .expense, note: "Belanja Bulanan", date: day(5, m)),
            ]
            id += 3

            // MARK: GoPay (acc-3) — e-wallet daily
            let gopayCoffee: Double = isHighSpendMonth ? 35_000 : isLowSpendMonth ? 18_000 : 25_000
            let gopaySubscription: Double = isHighSpendMonth ? 79_000 : 49_000
            let gopayTopup: Double = isBigPurchaseMonth ? 200_000 : 85_000

            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-3", categoryId: "cat-exp-2", subcategoryId: nil, amount: gopayCoffee, type: .expense, note: "Kopi Kenangan", date: day(4, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-3", categoryId: "cat-exp-5", subcategoryId: nil, amount: gopaySubscription, type: .expense, note: "Netflix", date: day(8, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-3", categoryId: "cat-exp-4", subcategoryId: nil, amount: gopayTopup, type: .expense, note: "Top Up Shopee", date: day(15, m)),
            ]
            id += 3

            // MARK: Transfer antar dompet
            let transferCash: Double = isHighSpendMonth ? 700_000 : 500_000
            all += [
                Transaction(id: "tx-\(id)", accountId: "acc-2", categoryId: nil, subcategoryId: nil, amount: transferCash, type: .transfer, note: "Tarik Tunai BCA → Cash", date: day(6, m)),
                Transaction(id: "tx-\(id+1)", accountId: "acc-2", categoryId: nil, subcategoryId: nil, amount: 200_000, type: .transfer, note: "Top Up GoPay dari BCA", date: day(12, m)),
                Transaction(id: "tx-\(id+2)", accountId: "acc-3", categoryId: nil, subcategoryId: nil, amount: 100_000, type: .transfer, note: "Top Up GoPay dari BCA", date: day(12, m)),
            ]
            id += 3

            // MARK: Extra transactions (bulanan tambahan)
            if isBigPurchaseMonth {
                all.append(
                    Transaction(id: "tx-\(id)", accountId: "acc-1", categoryId: "cat-exp-4", subcategoryId: nil, amount: 750_000, type: .expense, note: "Beli Sepatu", date: day(20, m))
                )
                id += 1
            }

            if isHighSpendMonth {
                all.append(
                    Transaction(id: "tx-\(id)", accountId: "acc-2", categoryId: "cat-exp-1", subcategoryId: nil, amount: 350_000, type: .expense, note: "Makan Malam Keluarga", date: day(22, m))
                )
                id += 1
            }
        }

        return all
    }
}
