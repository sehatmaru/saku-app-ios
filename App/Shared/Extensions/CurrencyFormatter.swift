import Foundation

extension Double {
    func formattedAsCurrency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "id_ID")
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "Rp0"
    }
}

extension String {
    var formattedWithThousandSeparator: String {
        guard !isEmpty else { return "" }
        var result = ""
        let chars = Array(self)
        for (index, char) in chars.enumerated() {
            if index > 0 && (chars.count - index) % 3 == 0 {
                result.append(".")
            }
            result.append(char)
        }
        return result
    }
}

extension Double {
    /// Absolute amount without symbol: 24350000 -> "24.350.000".
    func formattedAsDigits() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "id_ID")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: abs(self))) ?? "0"
    }

    /// Short absolute amount: 12000000 -> "12 jt", 5120000 -> "5,1 jt", 45000 -> "45 rb".
    func abbreviatedRupiah() -> String {
        let value = abs(self)
        let (divisor, unit): (Double, String) = switch value {
        case 1_000_000_000...: (1_000_000_000, " M")
        case 1_000_000...: (1_000_000, " jt")
        case 1_000...: (1_000, " rb")
        default: (1, "")
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.maximumFractionDigits = divisor >= 1_000_000 ? 1 : 0
        return (formatter.string(from: NSNumber(value: value / divisor)) ?? "0") + unit
    }
}
