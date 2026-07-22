import SwiftUI

struct WalletIcon: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let color: Color
    let category: Account.AccountType

    static let customPrefix = "custom:"

    static func icons(for category: Account.AccountType) -> [WalletIcon] {
        allIcons.filter { $0.category == category }
    }

    static func resolve(_ id: String?) -> WalletIcon? {
        guard let id else { return nil }
        if let match = allIcons.first(where: { $0.id == id }) {
            return match
        }
        if id.hasPrefix(customPrefix) {
            let parts = id.dropFirst(customPrefix.count).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let text = parts.first.map(String.init) ?? ""
            let colorName = parts.count > 1 ? String(parts[1]) : ""
            let color = presetColor(named: colorName) ?? .appPrimary
            return WalletIcon(
                id: id,
                name: text,
                shortName: String(text.prefix(4)).uppercased(),
                color: color,
                category: .bank
            )
        }
        return WalletIcon(
            id: id,
            name: id,
            shortName: String(id.prefix(4)).uppercased(),
            color: .appPrimary,
            category: .bank
        )
    }

    static func customIconId(text: String, colorName: String) -> String {
        "\(customPrefix)\(text):\(colorName)"
    }

    // MARK: - Preset Colors

    struct PresetColor: Identifiable, Equatable {
        let name: String
        let color: Color
        var id: String { name }
    }

    static let presetColors: [PresetColor] = [
        PresetColor(name: "merah", color: Color(red: 220/255, green: 53/255, blue: 69/255)),
        PresetColor(name: "jingga", color: Color(red: 243/255, green: 146/255, blue: 0/255)),
        PresetColor(name: "kuning", color: Color(red: 255/255, green: 193/255, blue: 7/255)),
        PresetColor(name: "hijau", color: Color(red: 0/255, green: 168/255, blue: 107/255)),
        PresetColor(name: "tosca", color: Color(red: 0/255, green: 188/255, blue: 212/255)),
        PresetColor(name: "biru", color: Color(red: 0/255, green: 102/255, blue: 174/255)),
        PresetColor(name: "ungu", color: Color(red: 111/255, green: 66/255, blue: 193/255)),
        PresetColor(name: "merahmuda", color: Color(red: 233/255, green: 30/255, blue: 99/255)),
        PresetColor(name: "coklat", color: Color(red: 121/255, green: 85/255, blue: 72/255)),
        PresetColor(name: "abu", color: Color(red: 97/255, green: 97/255, blue: 97/255)),
    ]

    static func presetColor(named name: String) -> Color? {
        presetColors.first { $0.name == name }?.color
    }

    static let allIcons: [WalletIcon] = [
        WalletIcon(id: "cash", name: "Cash", shortName: "CASH", color: Color(red: 0/255, green: 168/255, blue: 107/255), category: .cash),

        WalletIcon(id: "bca", name: "BCA", shortName: "BCA", color: Color(red: 0/255, green: 102/255, blue: 174/255), category: .bank),
        WalletIcon(id: "bni", name: "BNI", shortName: "BNI", color: Color(red: 0/255, green: 61/255, blue: 121/255), category: .bank),
        WalletIcon(id: "mandiri", name: "Mandiri", shortName: "MNDR", color: Color(red: 0/255, green: 60/255, blue: 113/255), category: .bank),
        WalletIcon(id: "bri", name: "BRI", shortName: "BRI", color: Color(red: 0/255, green: 75/255, blue: 147/255), category: .bank),
        WalletIcon(id: "jago", name: "Jago", shortName: "JAGO", color: Color(red: 0/255, green: 168/255, blue: 107/255), category: .bank),
        WalletIcon(id: "cimb", name: "CIMB Niaga", shortName: "CIMB", color: Color(red: 126/255, green: 45/255, blue: 142/255), category: .bank),
        WalletIcon(id: "btn", name: "BTN", shortName: "BTN", color: Color(red: 0/255, green: 94/255, blue: 162/255), category: .bank),
        WalletIcon(id: "bnc", name: "BNC", shortName: "BNC", color: Color(red: 0/255, green: 60/255, blue: 100/255), category: .bank),
        WalletIcon(id: "danamon", name: "Danamon", shortName: "DNM", color: Color(red: 0/255, green: 122/255, blue: 61/255), category: .bank),

        WalletIcon(id: "gopay", name: "GoPay", shortName: "GOPAY", color: Color(red: 0/255, green: 170/255, blue: 68/255), category: .ewallet),
        WalletIcon(id: "ovo", name: "OVO", shortName: "OVO", color: Color(red: 71/255, green: 43/255, blue: 145/255), category: .ewallet),
        WalletIcon(id: "dana", name: "DANA", shortName: "DANA", color: Color(red: 0/255, green: 99/255, blue: 173/255), category: .ewallet),
        WalletIcon(id: "linkaja", name: "LinkAja", shortName: "LINK", color: Color(red: 212/255, green: 32/255, blue: 39/255), category: .ewallet),

        WalletIcon(id: "visa", name: "Visa", shortName: "V", color: Color(red: 26/255, green: 31/255, blue: 113/255), category: .credit),
        WalletIcon(id: "mastercard", name: "Mastercard", shortName: "MC", color: Color(red: 235/255, green: 155/255, blue: 30/255), category: .credit),
        WalletIcon(id: "jcb", name: "JCB", shortName: "JCB", color: Color(red: 0/255, green: 51/255, blue: 153/255), category: .credit),
        WalletIcon(id: "amex", name: "American Express", shortName: "AMEX", color: Color(red: 46/255, green: 119/255, blue: 188/255), category: .credit),
    ]
}
