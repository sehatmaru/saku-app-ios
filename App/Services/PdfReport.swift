import UIKit

/// Builds the PDF financial report for Profil › Ekspor data (design "Sheet Pengaturan").
/// Pure and read only: the pages are drawn on the device from data that is already there.
enum PdfReport {
    // MARK: Files

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

    static func data(transactions: [Transaction], accounts: [Account], categories: [Category],
                     budgets: [Budget], intervals: [DateInterval]?, periodLabel: String) -> Data? {
        let summary = summary(transactions: transactions, categories: categories, intervals: intervals)
        let income = summary.income, expense = summary.expense, topCategories = summary.topCategories
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let budgetRows = budgets.map { budget in
            (names[budget.categoryId] ?? budget.name, budget.spent, budget.amount)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 1

            func beginPage() {
                context.beginPage()
                drawFooter(page: page)
                y = margin
            }
            func ensure(_ height: CGFloat) {
                if y + height > size.height - footerSpace - margin {
                    page += 1
                    beginPage()
                }
            }

            beginPage()

            // Header
            y = draw(L("Saku"), font: .systemFont(ofSize: 12, weight: .semibold), color: green, at: y, width: contentWidth)
            y += 2
            y = draw(L("Laporan Keuangan"), font: .systemFont(ofSize: 24, weight: .bold), color: ink, at: y, width: contentWidth)
            y += 4
            y = draw(periodLabel, font: .systemFont(ofSize: 12), color: secondary, at: y, width: contentWidth)
            y = draw(L("Dibuat %@", dateLabel(Date())), font: .systemFont(ofSize: 11), color: secondary, at: y, width: contentWidth, align: .right, onLine: y - 15)
            y += 18

            // Summary
            ensure(96)
            let cellWidth = (contentWidth - 20) / 3
            summaryBox(at: CGPoint(x: margin, y: y), width: cellWidth, title: L("Pemasukan"), value: income.formattedAsCurrency(), color: green)
            summaryBox(at: CGPoint(x: margin + cellWidth + 10, y: y), width: cellWidth, title: L("Pengeluaran"), value: expense.formattedAsCurrency(), color: ink)
            summaryBox(at: CGPoint(x: margin + (cellWidth + 10) * 2, y: y), width: cellWidth, title: L("Selisih"), value: (income - expense).formattedAsCurrency(), color: income - expense < 0 ? red : green)
            y += 96

            // Top categories
            if !topCategories.isEmpty {
                ensure(46)
                y = draw(L("Kategori terbesar"), font: .systemFont(ofSize: 15, weight: .semibold), color: ink, at: y, width: contentWidth)
                y += 6
                let maxValue = topCategories.first?.1 ?? 1
                for (name, value) in topCategories {
                    ensure(40)
                    y = draw(name, font: .systemFont(ofSize: 13), color: body, at: y, width: contentWidth - 120)
                    _ = draw(value.formattedAsCurrency(), font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold), color: ink, at: y, width: contentWidth, align: .right, onLine: y)
                    y += 18
                    bar(at: y, width: contentWidth, ratio: maxValue > 0 ? value / maxValue : 0, color: green)
                    y += 16
                }
                y += 8
            }

            // Budgets
            ensure(40)
            y = draw(L("Budget"), font: .systemFont(ofSize: 15, weight: .semibold), color: ink, at: y, width: contentWidth)
            y += 6
            if budgetRows.isEmpty {
                y = draw(L("Belum ada budget di periode ini."), font: .systemFont(ofSize: 13), color: secondary, at: y, width: contentWidth)
            }
            for (name, spent, amount) in budgetRows {
                ensure(40)
                let over = amount > 0 && spent > amount
                y = draw(name, font: .systemFont(ofSize: 13), color: body, at: y, width: contentWidth - 170)
                _ = draw(L("%@ dari %@", spent.formattedAsCurrency(), amount.formattedAsCurrency()),
                         font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: over ? red : secondary,
                         at: y, width: contentWidth, align: .right, onLine: y)
                y += 18
                bar(at: y, width: contentWidth, ratio: amount > 0 ? min(spent / amount, 1) : 0, color: over ? red : green)
                y += 16
            }
        }
    }

    /// Writes the report to the temporary folder for the share sheet.
    static func write(transactions: [Transaction], accounts: [Account], categories: [Category],
                      budgets: [Budget], intervals: [DateInterval]?, periodLabel: String, name: String) -> URL? {
        guard let data = data(transactions: transactions, accounts: accounts, categories: categories,
                              budgets: budgets, intervals: intervals, periodLabel: periodLabel) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Layout

    private static let size = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 44
    private static let footerSpace: CGFloat = 44

    private static let ink = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    private static let body = UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
    private static let secondary = UIColor(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1)
    private static let green = UIColor(red: 0x16 / 255, green: 0x87 / 255, blue: 0x5A / 255, alpha: 1)
    private static let red = UIColor(red: 0xD9 / 255, green: 0x36 / 255, blue: 0x36 / 255, alpha: 1)
    private static let track = UIColor(red: 0xED / 255, green: 0xED / 255, blue: 0xF0 / 255, alpha: 1)
    private static let cardFill = UIColor(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 1)

    private static var contentWidth: CGFloat { size.width - margin * 2 }

    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor, at y: CGFloat, width: CGFloat,
                             align: NSTextAlignment = .left, onLine: CGFloat? = nil) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        let height = ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], context: nil).height)
        attributed.draw(with: CGRect(x: margin, y: onLine ?? y, width: width, height: height),
                        options: [.usesLineFragmentOrigin], context: nil)
        return y + height
    }

    private static func bar(at y: CGFloat, width: CGFloat, ratio: Double, color: UIColor) {
        let height: CGFloat = 6
        track.setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: width, height: height), cornerRadius: height / 2).fill()
        let filled = max(ratio, 0.02)
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: width * CGFloat(filled), height: height), cornerRadius: height / 2).fill()
    }

    private static func summaryBox(at point: CGPoint, width: CGFloat, title: String, value: String, color: UIColor) {
        cardFill.setFill()
        UIBezierPath(roundedRect: CGRect(x: point.x, y: point.y, width: width, height: 80), cornerRadius: 12).fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: secondary, .paragraphStyle: style])
            .draw(with: CGRect(x: point.x, y: point.y + 16, width: width, height: 14), options: [.usesLineFragmentOrigin], context: nil)
        NSAttributedString(string: value, attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold), .foregroundColor: color, .paragraphStyle: style])
            .draw(with: CGRect(x: point.x + 6, y: point.y + 38, width: width - 12, height: 22), options: [.usesLineFragmentOrigin], context: nil)
    }

    /// The small line at the bottom of every page.
    private static func drawFooter(page: Int) {
        let y = size.height - 30
        NSAttributedString(string: L("Dibuat dengan Saku"), attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: secondary])
            .draw(at: CGPoint(x: margin, y: y))
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        NSAttributedString(string: L("Halaman %lld", page), attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: secondary, .paragraphStyle: style])
            .draw(with: CGRect(x: margin, y: y, width: contentWidth, height: 12), options: [.usesLineFragmentOrigin], context: nil)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}
