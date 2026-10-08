import Foundation

/// Turns a free sentence ("kopi 25rb gopay kemarin", "top up gopay 100rb dari bca") into drafts.
/// Rules only, on the device: works offline and sends nothing anywhere. Indonesian and English.
enum SmartParser {
    /// What the parser knows about the user.
    struct Context {
        var accounts: [Account]
        var categories: [Category]
        /// Learned keyword -> choices, from earlier saves.
        var memory: [MerchantMemory.Entry] = []
        var now = Date()
        var calendar = Calendar.current
    }

    static func parse(_ text: String, source: Draft.Source = .typed, context: Context) -> [Draft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let chunks = chunks(of: trimmed)
        let drafts = chunks.map { draft(from: $0, source: source, context: context) }
        // A sentence with no amount anywhere is kept whole as one empty draft with the user's words.
        if drafts.allSatisfy({ $0.amount == nil }) {
            var empty = Draft()
            empty.source = source
            empty.title = trimmed
            empty.isUnreadable = drafts.allSatisfy { $0.title.isEmpty || $0.amount == nil }
            empty.date = context.now
            return [empty]
        }
        return drafts
    }

    // MARK: Splitting

    /// "kopi 25rb, parkir 5rb" -> two chunks. A piece without an amount joins its neighbour.
    static func chunks(of text: String) -> [String] {
        let separators = try! NSRegularExpression(pattern: #"\s*(?:[,;\n]|\s&\s|\sdan\s|\slalu\s|\sterus\s|\sand\s|\sthen\s)\s*"#, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        var pieces: [String] = []
        var last = text.startIndex
        for match in separators.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            pieces.append(String(text[last..<r.lowerBound]))
            last = r.upperBound
        }
        pieces.append(String(text[last...]))
        pieces = pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var merged: [String] = []
        for piece in pieces {
            if amount(in: piece) == nil, !merged.isEmpty {
                merged[merged.count - 1] += " " + piece
            } else if let previous = merged.last, amount(in: previous) == nil {
                merged[merged.count - 1] = previous + " " + piece
            } else {
                merged.append(piece)
            }
        }
        return merged.isEmpty ? [text] : merged
    }

    // MARK: One chunk

    private static func draft(from chunk: String, source: Draft.Source, context: Context) -> Draft {
        var draft = Draft()
        draft.source = source
        var work = " " + chunk.lowercased() + " "

        // date first, so "tanggal 3" or "3 hari lalu" is not read as an amount
        let (date, afterDate) = extractDate(from: work, context: context)
        draft.date = date
        work = afterDate

        guard let found = amount(in: work) else {
            draft.title = chunk
            return draft
        }
        draft.amount = found.value
        work = work.replacingCharacters(in: found.range, with: " ")

        // wallets
        let wallets = findWallets(in: work, accounts: context.accounts)
        for wallet in wallets { work = work.replacingOccurrences(of: wallet.matched, with: " ", options: .caseInsensitive) }

        // kind
        draft.kind = kind(of: work, wallets: wallets)
        assignWallets(&draft, wallets: wallets, text: work, context: context)

        // title: what is left once keywords are stripped
        let title = cleanTitle(work)
        draft.title = title.isEmpty ? defaultTitle(for: draft.kind) : title.prefix(1).uppercased() + title.dropFirst()

        if draft.kind == .expense || draft.kind == .income {
            applyCategory(&draft, text: work, context: context)
        }
        return draft
    }

    // MARK: Amount

    struct FoundAmount { let value: Double; let range: Range<String.Index> }

    private static let slang: [(String, Double)] = [
        ("goceng", 5_000), ("ceban", 10_000), ("gocap", 50_000), ("cepek", 100_000),
        ("seceng", 1_000), ("gopek", 500), ("sejuta", 1_000_000), ("seribu", 1_000), ("serebu", 1_000),
    ]
    private static let unitPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(juta|jt|ribu|rb|k)\b"#, options: .caseInsensitive)
    private static let plainPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[.,]\d{3})+|\d{3,})(?![\d.,]*\d)"#)
    private static let rpPattern = try! NSRegularExpression(pattern: #"\brp\.?\s*"#, options: .caseInsensitive)

    static func amount(in text: String) -> FoundAmount? {
        let lower = text.lowercased()
        let full = NSRange(lower.startIndex..., in: lower)
        // 25rb, 2,5jt, 2.5 juta
        if let m = unitPattern.firstMatch(in: lower, range: full),
           let r = Range(m.range, in: lower), let nr = Range(m.range(at: 1), in: lower), let ur = Range(m.range(at: 2), in: lower) {
            let number = Double(lower[nr].replacingOccurrences(of: ",", with: ".")) ?? 0
            let unit = lower[ur]
            let multiplier: Double = (unit == "juta" || unit == "jt") ? 1_000_000 : 1_000
            return FoundAmount(value: (number * multiplier).rounded(), range: r)
        }
        // goceng, cepek, sejuta
        for (word, value) in slang {
            if let r = lower.range(of: word) { return FoundAmount(value: value, range: r) }
        }
        // 25.000, 25000
        if let m = plainPattern.firstMatch(in: lower, range: full), let r = Range(m.range, in: lower),
           let nr = Range(m.range(at: 1), in: lower) {
            let digits = lower[nr].filter(\.isNumber)
            if let value = Double(digits), value >= 100 { return FoundAmount(value: value, range: r) }
        }
        return nil
    }

    // MARK: Date

    private static let weekdays: [(String, Int)] = [
        ("minggu", 1), ("senin", 2), ("selasa", 3), ("rabu", 4), ("kamis", 5), ("jumat", 6), ("jum'at", 6), ("sabtu", 7),
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]

    static func extractDate(from text: String, context: Context) -> (Date, String) {
        var work = text
        let cal = context.calendar
        let now = context.now
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: today) ?? today
            guard let hour else { return offset == 0 ? now : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d) }
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        func strip(_ phrase: String) { work = work.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive) }

        if work.contains("kemarin lusa") || work.contains("lusa lalu") { strip("kemarin lusa"); strip("lusa lalu"); return (day(-2), work) }
        if work.contains("tadi malam") || work.contains("semalam") || work.contains("last night") {
            strip("tadi malam"); strip("semalam"); strip("last night")
            // before evening, "last night" is yesterday; after it, still tonight
            return (cal.component(.hour, from: now) < 18 ? day(-1, hour: 20) : day(0, hour: 20), work)
        }
        if work.contains("kemarin") || work.contains("yesterday") { strip("kemarin"); strip("yesterday"); return (day(-1), work) }
        for phrase in ["tadi pagi", "tadi siang", "tadi sore", "hari ini", "today", "barusan", "tadi"] where work.contains(phrase) {
            strip(phrase)
            return (now, work)
        }
        let ago = try! NSRegularExpression(pattern: #"(\d+)\s*(?:hari lalu|hari yang lalu|days? ago)"#)
        if let m = ago.firstMatch(in: work, range: NSRange(work.startIndex..., in: work)),
           let r = Range(m.range, in: work), let nr = Range(m.range(at: 1), in: work), let n = Int(work[nr]) {
            work.replaceSubrange(r, with: " ")
            return (day(-n), work)
        }
        let dayOfMonth = try! NSRegularExpression(pattern: #"(?:tanggal|tgl\.?)\s*(\d{1,2})\b"#)
        if let m = dayOfMonth.firstMatch(in: work, range: NSRange(work.startIndex..., in: work)),
           let r = Range(m.range, in: work), let nr = Range(m.range(at: 1), in: work), let n = Int(work[nr]), (1...31).contains(n) {
            work.replaceSubrange(r, with: " ")
            var comps = cal.dateComponents([.year, .month], from: today)
            comps.day = n
            comps.hour = 12
            var date = cal.date(from: comps) ?? today
            // a day later than today means last month's
            if date > now, let previous = cal.date(byAdding: .month, value: -1, to: date) { date = previous }
            return (date, work)
        }
        for (name, number) in weekdays {
            for pattern in ["\(name) lalu", "\(name) kemarin", "last \(name)", "\(name) kmrn"] where work.contains(pattern) {
                strip(pattern)
                let current = cal.component(.weekday, from: today)
                var back = (current - number + 7) % 7
                if back == 0 { back = 7 }
                return (day(-back), work)
            }
        }
        return (now, work)
    }

    // MARK: Wallets

    struct WalletMatch { let account: Account; let matched: String; let position: Int }

    private static let aliases: [String: [String]] = [
        "gopay": ["gopay", "go-pay", "gojek"], "ovo": ["ovo"], "dana": ["dana"], "shopeepay": ["shopeepay", "spay"],
        "linkaja": ["linkaja"], "bca": ["bca"], "bni": ["bni"], "mandiri": ["mandiri"], "bri": ["bri"], "jago": ["jago"],
        "bnc": ["bnc", "neo"], "cimb": ["cimb"], "bibit": ["bibit"], "ajaib": ["ajaib"], "stockbit": ["stockbit"],
        "binance": ["binance"], "tunai": ["tunai", "cash"],
    ]

    /// Wallets named in the text, in order. A short name like "BCA" matches "BCA Visa" only if nothing is a better fit.
    static func findWallets(in text: String, accounts: [Account]) -> [WalletMatch] {
        let lower = text.lowercased()
        var matches: [WalletMatch] = []
        for account in accounts where account.isActive {
            let name = account.name.lowercased()
            var candidates = [name]
            // first word / brand: "BCA Visa" -> "bca"
            if let first = name.split(separator: " ").first.map(String.init), first.count >= 3 { candidates.append(first) }
            for (key, words) in aliases where name.contains(key) { candidates.append(contentsOf: words) }
            for candidate in candidates.sorted(by: { $0.count > $1.count }) {
                guard let range = wordRange(of: candidate, in: lower) else { continue }
                matches.append(WalletMatch(account: account, matched: String(lower[range]),
                                           position: lower.distance(from: lower.startIndex, to: range.lowerBound)))
                break
            }
        }
        // one wallet per spot in the text: prefer the one whose name is most specific
        var byPosition: [Int: WalletMatch] = [:]
        for match in matches {
            if let existing = byPosition[match.position] {
                let better = existing.account.name.count == match.matched.count ? existing
                    : (match.account.name.lowercased() == match.matched ? match : existing)
                byPosition[match.position] = better
            } else {
                byPosition[match.position] = match
            }
        }
        return byPosition.values.sorted { $0.position < $1.position }
    }

    private static func wordRange(of word: String, in text: String) -> Range<String.Index>? {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: word, options: .caseInsensitive, range: search) {
            let before = r.lowerBound == text.startIndex ? " " : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? " " : text[r.upperBound]
            if !before.isLetter && !before.isNumber && !after.isLetter && !after.isNumber { return r }
            search = r.upperBound..<text.endIndex
        }
        return nil
    }

    // MARK: Kind

    private static func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { wordRange(of: $0, in: text) != nil }
    }

    static func kind(of text: String, wallets: [WalletMatch]) -> Draft.Kind {
        if contains(text, ["bayar kartu", "bayar cc", "bayar kredit", "bayar tagihan kartu", "pay credit card", "pay card", "bayar kartu kredit", "tagihan kartu"]) {
            return .cardPayment
        }
        if contains(text, ["top up", "topup", "isi saldo", "transfer", "tf", "kirim ke", "pindah", "nabung", "invest", "investasi", "setor", "beli reksa", "reksadana", "saham", "crypto"]) {
            return .transfer
        }
        if wallets.count >= 2, contains(text, ["dari"]), contains(text, ["ke"]) { return .transfer }
        if contains(text, ["gaji", "gajian", "salary", "bonus", "thr", "terima", "diterima", "dapat", "received", "refund", "cashback", "masuk", "income", "pemasukan"]) {
            return .income
        }
        return .expense
    }

    private static func assignWallets(_ draft: inout Draft, wallets: [WalletMatch], text: String, context: Context) {
        let accounts = context.accounts.filter(\.isActive)
        switch draft.kind {
        case .expense, .income:
            draft.accountId = wallets.first(where: { $0.account.type != .investment })?.account.id
        case .cardPayment:
            let card = wallets.first { $0.account.isCreditCard }
            draft.counterpartyAccountId = card?.account.id
            draft.accountId = wallets.first { !$0.account.isCreditCard }?.account.id
        case .transfer:
            let investmentWanted = contains(text, ["nabung", "invest", "investasi", "setor", "reksa", "reksadana", "saham", "crypto", "emas"])
            // "dari X" is the source, "ke Y" / "top up Y" the destination
            var source: Account?, destination: Account?
            for wallet in wallets {
                let before = String(text.lowercased().prefix(wallet.position))
                let words = before.split(separator: " ").suffix(2).joined(separator: " ")
                if words.hasSuffix("dari") || words.hasSuffix("from") { source = wallet.account }
                else if words.hasSuffix("ke") || words.hasSuffix("to") || words.hasSuffix("top up") || words.hasSuffix("topup")
                            || words.hasSuffix("setor") || words.hasSuffix("nabung") || words.hasSuffix("saldo") { destination = wallet.account }
            }
            let unassigned = wallets.map(\.account).filter { $0.id != source?.id && $0.id != destination?.id }
            if investmentWanted, destination == nil {
                destination = unassigned.first { $0.type == .investment } ?? wallets.map(\.account).first { $0.type == .investment }
                if destination == nil { draft.needsInvestmentWallet = true }
            }
            if destination == nil { destination = unassigned.first { $0.type == .ewallet || $0.type == .investment } ?? unassigned.last }
            if source == nil { source = wallets.map(\.account).first { $0.id != destination?.id } }
            if destination?.id == source?.id { source = nil }
            draft.accountId = source?.id
            draft.counterpartyAccountId = destination?.id
            _ = accounts
        }
    }

    // MARK: Title and category

    private static let noise: Set<String> = [
        "dari", "ke", "di", "pakai", "pake", "via", "dengan", "untuk", "buat", "from", "to", "with", "for", "on", "at", "the", "a",
        "top", "up", "topup", "bayar", "beli", "transfer", "tf", "isi", "saldo", "pay", "paid", "bought", "spent", "kemarin", "nabung",
        "setor", "gaji", "terima", "dapat", "received", "masuk", "rp", "idr", "lalu", "kartu", "kredit", "cc", "tadi", "pagi",
        "siang", "sore", "malam", "ini", "hari",
    ]

    private static func cleanTitle(_ text: String) -> String {
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "&" && $0 != "'" }
            .map(String.init)
            .filter { !noise.contains($0) }
        return words.joined(separator: " ")
    }

    private static func defaultTitle(for kind: Draft.Kind) -> String {
        switch kind {
        case .expense: return L("Pengeluaran")
        case .income: return L("Pemasukan")
        case .transfer: return L("Transfer")
        case .cardPayment: return L("Bayar kartu")
        }
    }

    private static let categoryWords: [(name: String, words: [String])] = [
        ("jajan", ["kopi", "ngopi", "coffee", "jajan", "snack", "boba", "kafe", "cafe", "teh", "minum"]),
        ("makan", ["makan", "lunch", "dinner", "sarapan", "nasi", "warteg", "breakfast", "meal", "bakso", "ayam", "soto", "mie"]),
        ("restoran", ["resto", "restoran", "restaurant", "mall"]),
        ("transportasi", ["parkir", "bensin", "grab", "gojek", "ojek", "tol", "taksi", "kereta", "mrt", "bus", "fuel", "parking", "toll", "uber", "krl"]),
        ("belanja", ["belanja", "indomaret", "alfamart", "supermarket", "sabun", "groceries", "listrik", "pulsa", "galon", "shopping"]),
        ("hiburan", ["nonton", "bioskop", "netflix", "spotify", "game", "movie", "konser"]),
        ("perawatan", ["dokter", "obat", "apotek", "salon", "doctor", "medicine", "klinik", "potong rambut"]),
        ("olahraga", ["gym", "futsal", "olahraga", "badminton", "renang"]),
        ("sosial", ["donasi", "sedekah", "zakat", "hadiah", "kado", "gift", "donation"]),
        ("gaji", ["gaji", "gajian", "salary", "thr"]),
        ("bisnis", ["bisnis", "usaha", "jualan", "omzet"]),
    ]

    private static func applyCategory(_ draft: inout Draft, text: String, context: Context) {
        let wanted: CategoryType = draft.kind == .income ? .income : .expense
        let pool = context.categories.filter { $0.type == wanted && !CategoryCatalog.isSystem($0) }
        let lower = text.lowercased()
        // 1. what the user chose before for this merchant
        if let hit = MerchantMemory.match(in: lower, entries: context.memory, kind: draft.kind) {
            draft.merchant = hit.keyword
            if let id = hit.categoryId, pool.contains(where: { $0.id == id }) { draft.categoryId = id }
            if draft.accountId == nil, let id = hit.accountId, context.accounts.contains(where: { $0.id == id && $0.isActive }) { draft.accountId = id }
            if draft.categoryId != nil { return }
        }
        // 2. the category's own name in the sentence
        if let named = pool.first(where: { wordRange(of: $0.name.lowercased(), in: lower) != nil }) {
            draft.categoryId = named.id
            return
        }
        // 3. keywords
        for entry in categoryWords where contains(lower, entry.words) {
            if let category = pool.first(where: { $0.name.lowercased().contains(entry.name) }) {
                draft.categoryId = category.id
                return
            }
        }
    }
}
