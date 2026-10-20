import SwiftUI
import UIKit

/// Draws the PDF report of design "Laporan Keuangan v3" (Fitur 8 US3): A4 portrait, 595 × 842 pt, margins 36 / 34.5 pt,
/// every size taken from the design's SwiftUI specification (px × 0.75). Page 1 never changes layout; page 2 only
/// carries the full budget and wallet tables when page 1 had to cut them. The analysis and the three suggestions are
/// not drawn yet: they come with Analisis Periode (Fitur 7).
@MainActor
enum ReportRenderer {
    // MARK: Page and palette

    private static let page = CGSize(width: 595, height: 842)
    private static let marginX: CGFloat = 36
    private static let marginY: CGFloat = 34.5
    private static var width: CGFloat { page.width - marginX * 2 }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    private static let ink = color(0x111111), body = color(0x3A3A3C), secondary = color(0x6E6E73)
    private static let green = color(0x16875A), rule = color(0xEDEDF0), rowRule = color(0xF2F2F4)
    private static let warningText = color(0xA8520A), dangerText = color(0xC22F2F)
    private static let warningBar = color(0xC4610A), dangerBar = color(0xD93636)
    private static let investment = color(0x946200), tagLine = color(0xD2D2D7)
    private static let palette = [color(0x16875A), color(0x1A1F71), color(0xD9A93A), color(0x472B91), color(0xA1A1A6)]

    // MARK: Entry

    static func data(_ model: ReportModel) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        return renderer.pdfData { context in
            context.beginPage()
            drawFirstPage(model)
            if model.needsSecondPage {
                context.beginPage()
                drawSecondPage(model)
            }
        }
    }

    // MARK: Pages

    private static func drawFirstPage(_ model: ReportModel) {
        var y = marginY
        y = header(model, y: y, secondPage: false)
        y += 13.5
        y = periodLine(model, y: y)
        y += 4.5
        y = headline(model, y: y)
        y += 12

        y = section(L("Data pendukung"), caption: model.showsWallets ? L("Saldo per %@", shortDate(model.createdAt)) : nil, y: y)
        y += 6
        y = flow(model, y: y)
        y += 9
        let columns = model.showsWallets
        let budgetWidth = columns ? (width - 21) * 1.6 / 2.6 : width
        let walletWidth = width - 21 - budgetWidth
        let top = y
        let budgetBottom = model.hasBudgets
            ? budgetTable(model, rows: Array(model.budgets.prefix(ReportModel.budgetsOnFirstPage)), x: marginX, width: budgetWidth,
                          y: top, moreOnNextPage: model.budgets.count - ReportModel.budgetsOnFirstPage)
            : categoryList(model, x: marginX, width: budgetWidth, y: top)
        var walletBottom = top
        if columns {
            walletBottom = walletList(model, rows: Array(model.wallets.prefix(ReportModel.walletsOnFirstPage)),
                                      x: marginX + budgetWidth + 21, width: walletWidth, y: top,
                                      moreOnNextPage: model.wallets.count - ReportModel.walletsOnFirstPage)
        }
        _ = max(budgetBottom, walletBottom)

        footnote(model)
        footer(page: 1, of: model.pageCount)
    }

    private static func drawSecondPage(_ model: ReportModel) {
        var y = marginY
        y = header(model, y: y, secondPage: true)
        y += 14
        y = periodLine(model, y: y)
        y += 14
        let columns = model.showsWallets
        let budgetWidth = columns ? (width - 21) * 1.6 / 2.6 : width
        let walletWidth = width - 21 - budgetWidth
        if model.hasBudgets {
            _ = budgetTable(model, rows: model.budgets, x: marginX, width: budgetWidth, y: y, moreOnNextPage: 0)
        } else {
            _ = categoryList(model, x: marginX, width: budgetWidth, y: y, limit: .max)
        }
        if columns {
            _ = walletList(model, rows: model.wallets, x: marginX + budgetWidth + 21, width: walletWidth, y: y, moreOnNextPage: 0)
        }
        footer(page: 2, of: 2)
    }

    // MARK: Header and headline

    private static func header(_ model: ReportModel, y: CGFloat, secondPage: Bool) -> CGFloat {
        let logoSize: CGFloat = 21
        if let logo = logoImage() { logo.draw(in: CGRect(x: marginX, y: y - 1, width: logoSize, height: logoSize)) }
        let wordmark = UIFont(name: "PlusJakartaSans-Regular_ExtraBold", size: 14.25) ?? .systemFont(ofSize: 14.25, weight: .heavy)
        text("Saku", font: wordmark, color: ink, x: marginX + logoSize + 5.25, y: y + 1, width: 100, kern: -0.3)

        let right = marginX + width
        let title = secondPage ? L("Lanjutan") : L("Laporan Keuangan")
        let titleFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        var x = right - textWidth(title, font: titleFont)
        text(title, font: titleFont, color: ink, x: x, y: y, width: 200)
        let tags = (model.isPrivate ? [L("Mode privasi")] : []) + (model.isPreview ? [L("Pratinjau")] : [])
        for tag in tags {
            let tagFont = UIFont.systemFont(ofSize: 7.5)
            let w = textWidth(tag, font: tagFont) + 7.5
            x -= w + 4.5
            let box = CGRect(x: x, y: y - 0.5, width: w, height: 12)
            let path = UIBezierPath(roundedRect: box, cornerRadius: 3)
            path.lineWidth = 0.75
            tagLine.setStroke(); path.stroke()
            text(tag, font: tagFont, color: body, x: x + 3.75, y: y + 1.5, width: w)
        }
        let line = secondPage ? model.periodTitle : "\(model.userName) · \(L("Dibuat %@", stamp(model.createdAt)))"
        let small = UIFont.systemFont(ofSize: 8.25)
        text(line, font: small, color: secondary, x: right - textWidth(line, font: small), y: y + 14, width: 300)
        return y + 30
    }

    private static func periodLine(_ model: ReportModel, y: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 9)
        let bold = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let string = NSMutableAttributedString(string: model.periodTitle, attributes: [.font: bold, .foregroundColor: ink])
        string.append(NSAttributedString(string: " · \(model.periodKind)", attributes: [.font: font, .foregroundColor: secondary]))
        return draw(string, x: marginX, y: y, width: width)
    }

    private static func headline(_ model: ReportModel, y: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let string = NSMutableAttributedString()
        for run in model.headline {
            let tone: UIColor
            switch run.tone {
            case .neutral: tone = ink
            case .positive: tone = green
            case .warning: tone = warningText
            case .danger: tone = dangerText
            }
            string.append(NSAttributedString(string: run.text, attributes: [.font: font, .foregroundColor: tone, .kern: -0.5]))
        }
        return draw(string, x: marginX, y: y, width: 495, lineHeight: 24)
    }

    // MARK: Sections

    private static func section(_ title: String, caption: String?, y: CGFloat) -> CGFloat {
        fill(rule, CGRect(x: marginX, y: y, width: width, height: 0.75))
        let top = y + 7.5
        text(title, font: .systemFont(ofSize: 9, weight: .semibold), color: ink, x: marginX, y: top, width: 300)
        if let caption {
            let font = UIFont.systemFont(ofSize: 7.9)
            text(caption, font: font, color: secondary, x: marginX + width - textWidth(caption, font: font), y: top + 0.5, width: 300)
        }
        return top + 12
    }

    private static func flow(_ model: ReportModel, y: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 7.9), bold = UIFont.systemFont(ofSize: 7.9, weight: .semibold)
        var x = marginX
        let netTone = model.net < 0 ? dangerText : green
        let items: [(String, String, UIColor)] = [
            (L("Masuk"), ReportModel.rupiah(model.income, hidden: model.isPrivate), green),
            (L("Keluar"), ReportModel.rupiah(model.expense, hidden: model.isPrivate), ink),
            (L("Net"), ReportModel.rupiah(model.net, sign: true, hidden: model.isPrivate), netTone),
        ]
        for (label, value, tone) in items {
            text(label, font: font, color: secondary, x: x, y: y, width: 80)
            x += textWidth(label + " ", font: font)
            text(value, font: bold, color: tone, x: x, y: y, width: 140)
            x += textWidth(value, font: bold) + 15
        }
        text(L("Per kategori"), font: font, color: secondary, x: x, y: y, width: 80)
        x += textWidth(L("Per kategori"), font: font) + 6
        let barWidth = marginX + width - x
        if barWidth > 40, !model.slices.isEmpty {
            var segmentX = x
            for slice in model.slices {
                let w = max(2, barWidth * CGFloat(slice.share) - 1.5)
                palette[slice.colorIndex].setFill()
                UIBezierPath(roundedRect: CGRect(x: segmentX, y: y + 2, width: w, height: 4), cornerRadius: 0.75).fill()
                segmentX += w + 1.5
            }
        }
        var legendY = y + 14
        var legendX = marginX
        let legendFont = UIFont.systemFont(ofSize: 7.5)
        for slice in model.slices {
            let label = "\(slice.name) \(ReportModel.percent(slice.share))"
            let w = textWidth(label, font: legendFont) + 12
            if legendX + w > marginX + width { legendX = marginX; legendY += 11 }
            palette[slice.colorIndex].setFill()
            UIBezierPath(roundedRect: CGRect(x: legendX, y: legendY + 2.5, width: 4.5, height: 4.5), cornerRadius: 1).fill()
            text(label, font: legendFont, color: body, x: legendX + 7.5, y: legendY, width: w)
            legendX += w + 10.5
        }
        return legendY + 11
    }

    // MARK: Tables

    private static func budgetTable(_ model: ReportModel, rows: [ReportModel.BudgetLine], x: CGFloat, width w: CGFloat,
                                    y: CGFloat, moreOnNextPage: Int) -> CGFloat {
        let tiny = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        text(L("Budget"), font: tiny, color: secondary, x: x, y: y, width: 100)
        let caption = L("Terpakai / budget · status")
        text(caption, font: tiny, color: secondary, x: x + w - textWidth(caption, font: tiny), y: y, width: w)
        var cursor = y + 11
        fill(rule, CGRect(x: x, y: cursor, width: w, height: 0.75))
        cursor += 2
        let font = UIFont.systemFont(ofSize: 7.9), medium = UIFont.systemFont(ofSize: 7.9, weight: .medium)
        let statusFont = UIFont.systemFont(ofSize: 7.9, weight: .semibold)
        for line in rows {
            let progress = CGFloat(min(line.progress, 1))
            let (label, barColor, textColor) = style(line.status)
            let amounts = "\(ReportModel.rupiah(line.spent, hidden: model.isPrivate)) / \(ReportModel.rupiah(line.amount, hidden: model.isPrivate))"
            let statusX = x + w - 43.5, percentX = statusX - 22.5 - 5
            let amountsX = percentX - 4.5 - textWidth(amounts, font: font)
            text(line.name, font: font, color: body, x: x, y: cursor, width: max(10, amountsX - x - 4))
            if line.isProvisional {
                let tagFont = UIFont.systemFont(ofSize: 6.4)
                let nameWidth = min(textWidth(line.name, font: font), amountsX - x - 40)
                let tag = L("Sementara"); let tw = textWidth(tag, font: tagFont) + 4.5
                let box = CGRect(x: x + nameWidth + 3.5, y: cursor + 0.5, width: tw, height: 9)
                let path = UIBezierPath(roundedRect: box, cornerRadius: 2.25); path.lineWidth = 0.75
                tagLine.setStroke(); path.stroke()
                text(tag, font: tagFont, color: secondary, x: box.minX + 2.25, y: cursor + 2, width: tw)
            }
            text(amounts, font: font, color: secondary, x: amountsX, y: cursor, width: 140)
            text(ReportModel.percent(line.progress), font: medium, color: body, x: percentX, y: cursor, width: 22.5, align: .right)
            text(label, font: statusFont, color: textColor, x: statusX, y: cursor, width: 43.5, align: .right)
            fill(rule, CGRect(x: x, y: cursor + 13, width: w, height: 1.9))
            barColor.setFill()
            UIRectFill(CGRect(x: x, y: cursor + 13, width: w * progress, height: 1.9))
            cursor += 18.5
            fill(rowRule, CGRect(x: x, y: cursor - 2, width: w, height: 0.75))
        }
        if moreOnNextPage > 0 {
            text(L("+%lld kategori lain di halaman 2", moreOnNextPage), font: font, color: secondary, x: x, y: cursor, width: w)
            cursor += 12
        }
        cursor += 2
        let total = "\(ReportModel.rupiah(model.totalSpent, hidden: model.isPrivate)) / \(ReportModel.rupiah(model.totalBudget, hidden: model.isPrivate))"
        let totalPercent = ReportModel.percent(model.totalBudget > 0 ? model.totalSpent / model.totalBudget : 0)
        let percentX = x + w - 43.5 - 22.5 - 5
        text(L("Total"), font: statusFont, color: body, x: x, y: cursor, width: 80)
        text(total, font: statusFont, color: body, x: percentX - 4.5 - textWidth(total, font: statusFont), y: cursor, width: 160)
        text(totalPercent, font: statusFont, color: body, x: percentX, y: cursor, width: 22.5, align: .right)
        return cursor + 12
    }

    /// No budget: expenses per category and an invitation to make one.
    private static func categoryList(_ model: ReportModel, x: CGFloat, width w: CGFloat, y: CGFloat, limit: Int = 5) -> CGFloat {
        let tiny = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        text(L("Pengeluaran per kategori"), font: tiny, color: secondary, x: x, y: y, width: 150)
        let caption = L("Belum ada budget")
        text(caption, font: tiny, color: secondary, x: x + w - textWidth(caption, font: tiny), y: y, width: w)
        var cursor = y + 11
        fill(rule, CGRect(x: x, y: cursor, width: w, height: 0.75))
        cursor += 2.25
        let font = UIFont.systemFont(ofSize: 7.9)
        for slice in model.allSlices.prefix(limit) {
            let amount = ReportModel.rupiah(slice.amount, hidden: model.isPrivate)
            text(slice.name, font: font, color: body, x: x, y: cursor, width: w - 120)
            text(amount, font: font, color: body, x: x + w - 22.5 - 4.5 - textWidth(amount, font: font), y: cursor, width: 140)
            text(ReportModel.percent(slice.share), font: font, color: secondary, x: x + w - 22.5, y: cursor, width: 22.5, align: .right)
            cursor += 14
            fill(rowRule, CGRect(x: x, y: cursor - 2, width: w, height: 0.75))
        }
        let invite = NSMutableAttributedString(string: L("Buat budget di Saku"),
                                               attributes: [.font: UIFont.systemFont(ofSize: 7.9, weight: .semibold), .foregroundColor: green])
        invite.append(NSAttributedString(string: " " + L("agar laporan berikutnya menampilkan status Aman, Mendekati, atau Lewat per kategori."),
                                         attributes: [.font: font, .foregroundColor: body]))
        return draw(invite, x: x, y: cursor + 4.5, width: w, lineHeight: 11.5)
    }

    private static func walletList(_ model: ReportModel, rows: [ReportModel.WalletLine], x: CGFloat, width w: CGFloat,
                                   y: CGFloat, moreOnNextPage: Int) -> CGFloat {
        let tiny = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        text(L("Saldo dompet"), font: tiny, color: secondary, x: x, y: y, width: w)
        var cursor = y + 11
        fill(rule, CGRect(x: x, y: cursor, width: w, height: 0.75))
        cursor += 2.25
        let font = UIFont.systemFont(ofSize: 7.9)
        for wallet in rows {
            let amount = ReportModel.rupiah(wallet.balance, hidden: false)
            text(wallet.name, font: font, color: body, x: x, y: cursor, width: w - 70)
            if wallet.isInvestment {
                let tagFont = UIFont.systemFont(ofSize: 7.1)
                text(L("Investasi"), font: tagFont, color: investment, x: x + min(textWidth(wallet.name, font: font), w - 100) + 3, y: cursor + 0.5, width: 50)
            }
            text(amount, font: font, color: body, x: x + w - textWidth(amount, font: font), y: cursor, width: 120)
            cursor += 14
            fill(rowRule, CGRect(x: x, y: cursor - 2, width: w, height: 0.75))
        }
        if moreOnNextPage > 0 {
            text(L("+%lld dompet lain di halaman 2", moreOnNextPage), font: font, color: secondary, x: x, y: cursor, width: w)
            cursor += 12
        }
        cursor += 2
        let total = ReportModel.rupiah(model.totalWallets)
        let bold = UIFont.systemFont(ofSize: 7.9, weight: .semibold)
        text(L("Total saldo"), font: bold, color: body, x: x, y: cursor, width: w - 60)
        text(total, font: bold, color: body, x: x + w - textWidth(total, font: bold), y: cursor, width: 120)
        return cursor + 12
    }

    private static func style(_ status: ReportModel.BudgetStatus) -> (String, UIColor, UIColor) {
        switch status {
        case .safe: (L("Aman"), green, green)
        case .near: (L("Mendekati"), warningBar, warningText)
        case .over: (L("Lewat"), dangerBar, dangerText)
        }
    }

    // MARK: Footnote and footer

    private static func footnote(_ model: ReportModel) {
        let font = UIFont.systemFont(ofSize: 7.5)
        let string = NSAttributedString(string: model.footnote, attributes: [.font: font, .foregroundColor: secondary])
        let height = ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                              options: .usesLineFragmentOrigin, context: nil).height)
        let footerTop = page.height - marginY - 7.5 - 6.75 - 11
        draw(string, x: marginX, y: footerTop - 7.5 - height, width: width, lineHeight: 11.25)
    }

    private static func footer(page number: Int, of count: Int) {
        let top = page.height - marginY - 11
        fill(rule, CGRect(x: marginX, y: top - 6.75, width: width, height: 0.75))
        let font = UIFont.systemFont(ofSize: 7.5)
        text(L("Dibuat dengan Saku"), font: font, color: secondary, x: marginX, y: top, width: 200)
        let label = L("Halaman %lld dari %lld", number, count)
        text(label, font: font, color: secondary, x: marginX + width - textWidth(label, font: font), y: top, width: 200)
    }

    // MARK: Drawing helpers

    @discardableResult
    private static func text(_ string: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat,
                             align: NSTextAlignment = .left, kern: CGFloat = 0) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern])
        attributed.draw(with: CGRect(x: x, y: y, width: width, height: ceil(font.lineHeight)), options: .usesLineFragmentOrigin, context: nil)
        return y + ceil(font.lineHeight)
    }

    @discardableResult
    private static func draw(_ string: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat, lineHeight: CGFloat? = nil) -> CGFloat {
        let mutable = NSMutableAttributedString(attributedString: string)
        if let lineHeight {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = lineHeight; style.maximumLineHeight = lineHeight
            mutable.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: mutable.length))
        }
        let height = ceil(mutable.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                               options: .usesLineFragmentOrigin, context: nil).height)
        mutable.draw(with: CGRect(x: x, y: y, width: width, height: height), options: .usesLineFragmentOrigin, context: nil)
        return y + height
    }

    private static func textWidth(_ string: String, font: UIFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func fill(_ color: UIColor, _ rect: CGRect) {
        color.setFill()
        UIRectFill(rect)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "d MMM yyyy, HH.mm"
        return formatter.string(from: date)
    }

    /// The app's own logo (cards in a green pocket), drawn once as an image.
    private static func logoImage() -> UIImage? {
        let renderer = ImageRenderer(content: PocketLogo(isOpen: true, pocketColor: Color(hex: "16875A"), isPlain: true)
            .frame(width: 21, height: 21))
        renderer.scale = 6
        return renderer.uiImage
    }
}
