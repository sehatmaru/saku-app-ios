import UIKit

/// The PDF financial report for Profil › Ekspor data and Riwayat Budget (Fitur 8, design "Laporan Keuangan v3").
/// Pure and read only: the pages are drawn on the device from data that is already there. `ReportModel` works the
/// numbers out and `ReportRenderer` draws them.
enum PdfReport {
    /// The numbers at the top of the report: totals and the biggest expense categories of the picked periods.
    /// Shared with the free preview (Fitur 8 US4), which shows these and blurs the analysis.
    struct Summary {
        var income: Double
        var expense: Double
        var topCategories: [(String, Double)]
    }

    static func summary(transactions: [Transaction], categories: [Category], intervals: [DateInterval]?) -> Summary {
        let rows = transactions.filter { txn in
            guard let intervals else { return true }
            return intervals.contains { txn.date >= $0.start && txn.date < $0.end }
        }
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Double] = [:]
        for txn in rows where txn.type == .expense {
            totals[txn.categoryId.flatMap { names[$0] } ?? L("Tanpa kategori"), default: 0] += txn.amount
        }
        return Summary(income: rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount },
                       expense: rows.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount },
                       topCategories: totals.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) })
    }

    /// The report as PDF data.
    @MainActor
    static func data(_ model: ReportModel) -> Data { ReportRenderer.data(model) }

    /// Writes the report to the temporary folder for the share sheet; the file name carries the period.
    @MainActor
    static func write(_ model: ReportModel) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(model.fileName)
        do {
            try data(model).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
