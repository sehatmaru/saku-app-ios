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
