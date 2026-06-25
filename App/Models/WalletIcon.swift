import SwiftUI

struct WalletIcon: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let color: Color
    let category: Account.AccountType

    static func icons(for category: Account.AccountType) -> [WalletIcon] {
        allIcons.filter { $0.category == category }
    }

    static let allIcons: [WalletIcon] = [
        WalletIcon(id: "cash", name: "Cash", shortName: "CASH", color: Color(red: 0/255, green: 168/255, blue: 107/255), category: .cash),

        WalletIcon(id: "bca", name: "BCA", shortName: "BCA", color: Color(red: 0/255, green: 102/255, blue: 174/255), category: .bank),
        WalletIcon(id: "bni", name: "BNI", shortName: "BNI", color: Color(red: 0/255, green: 61/255, blue: 121/255), category: .bank),
        WalletIcon(id: "mandiri", name: "Mandiri", shortName: "MNDR", color: Color(red: 0/255, green: 60/255, blue: 113/255), category: .bank),
        WalletIcon(id: "bri", name: "BRI", shortName: "BRI", color: Color(red: 0/255, green: 75/255, blue: 147/255), category: .bank),
        WalletIcon(id: "jago", name: "Jago", shortName: "JAGO", color: Color(red: 0/255, green: 168/255, blue: 107/255), category: .bank),
        WalletIcon(id: "cimb", name: "CIMB Niaga", shortName: "CIMB", color: Color(red: 126/255, green: 45/255, blue: 142/255), category: .bank),
        WalletIcon(id: "permata", name: "Permata", shortName: "PRM", color: Color(red: 0/255, green: 61/255, blue: 121/255), category: .bank),
        WalletIcon(id: "danamon", name: "Danamon", shortName: "DNM", color: Color(red: 0/255, green: 122/255, blue: 61/255), category: .bank),
        WalletIcon(id: "maybank", name: "Maybank", shortName: "MYK", color: Color(red: 253/255, green: 184/255, blue: 19/255), category: .bank),
        WalletIcon(id: "bsi", name: "BSI", shortName: "BSI", color: Color(red: 106/255, green: 27/255, blue: 154/255), category: .bank),

        WalletIcon(id: "gopay", name: "GoPay", shortName: "GOPAY", color: Color(red: 0/255, green: 170/255, blue: 68/255), category: .ewallet),
        WalletIcon(id: "ovo", name: "OVO", shortName: "OVO", color: Color(red: 71/255, green: 43/255, blue: 145/255), category: .ewallet),
        WalletIcon(id: "dana", name: "DANA", shortName: "DANA", color: Color(red: 0/255, green: 99/255, blue: 173/255), category: .ewallet),
        WalletIcon(id: "shopeepay", name: "ShopeePay", shortName: "SHP", color: Color(red: 238/255, green: 77/255, blue: 45/255), category: .ewallet),
        WalletIcon(id: "linkaja", name: "LinkAja", shortName: "LINK", color: Color(red: 212/255, green: 32/255, blue: 39/255), category: .ewallet),
    ]
}
