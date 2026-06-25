import Foundation

struct Account: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: AccountType
    var balance: Double
    let isActive: Bool
    let icon: String

    enum AccountType: String, Codable, CaseIterable {
        case cash = "Cash"
        case bank = "Bank"
        case ewallet = "E-Wallet"
    }
}

extension Account {
    static let sample: [Account] = [
        Account(id: "acc-1", name: "Cash", type: .cash, balance: 500_000, isActive: true, icon: "cash"),
        Account(id: "acc-2", name: "BCA", type: .bank, balance: 5_000_000, isActive: true, icon: "bca"),
        Account(id: "acc-3", name: "GoPay", type: .ewallet, balance: 150_000, isActive: true, icon: "gopay"),
        Account(id: "acc-4", name: "Mandiri", type: .bank, balance: 2_000_000, isActive: false, icon: "mandiri"),
        Account(id: "acc-5", name: "BNI", type: .bank, balance: 750_000, isActive: false, icon: "bni"),
    ]
}
