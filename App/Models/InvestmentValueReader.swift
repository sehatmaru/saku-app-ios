import Foundation

/// Finds the portfolio value in the text of a screenshot from an investment app (Fitur 7 US4). One general reader:
/// it looks for an amount next to a label such as total value, balance or available funds, and the user always
/// confirms what it found. Rules only, on the device; the text is never stored.
enum InvestmentValueReader {
    struct Candidate: Equatable, Identifiable {
        /// Indonesian label, shown through `L()`.
        let label: String
        let amount: Double
        var id: String { "\(label)|\(amount)" }
    }

    /// Most likely first. A line is given the first label whose words it contains.
    private static let labels: [(label: String, words: [String])] = [
        ("Dana tersedia", ["dana tersedia", "saldo tersedia", "available", "buying power", "saldo tunai", "cash balance"]),
        ("Total nilai", ["total nilai", "nilai total", "total portofolio", "total portfolio", "nilai portofolio", "nilai portfolio",
                         "portfolio value", "total value", "nilai investasi", "total investasi", "nilai aset", "total aset",
                         "nilai saat ini", "current value", "market value", "nilai pasar", "total saldo"]),
        ("Saldo", ["saldo", "balance"]),
    ]

    /// Candidates in the order of the labels above, then top to bottom; the same amount is listed once.
    static func candidates(lines raw: [String]) -> [Candidate] {
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var found: [(rank: Int, order: Int, candidate: Candidate)] = []
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard let rank = labels.firstIndex(where: { entry in entry.words.contains { lower.contains($0) } }) else { continue }
            // the amount sits on the label's line, or on the line under it
            let amounts = ImageParser.amounts(in: line)
            let value = amounts.max() ?? (index + 1 < lines.count ? ImageParser.amounts(in: lines[index + 1]).max() : nil)
            guard let value else { continue }
            found.append((rank == 0 ? 2 : rank == 1 ? 0 : 1, index, Candidate(label: labels[rank].label, amount: value)))
        }
        var seen = Set<Double>()
        return found.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.candidate)
            .filter { seen.insert($0.amount).inserted }
    }
}
