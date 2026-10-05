import SwiftUI

private enum CardUI {
    static let box = Color(light: 0xF7F7F8, dark: 0x1C1C1E)
    static let warmFill = Color(light: 0xFFF1E8, dark: 0x3A2316)
    static let warmInk = Color(light: 0xC2410C, dark: 0xFFA05C)

    static func month(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.locale; f.dateFormat = "LLLL"
        return f.string(from: date).capitalized(with: AppLanguage.locale)
    }

    static func daysLeft(to date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: date).day ?? 0
        switch days {
        case ..<0: return L("lewat %lld hari", -days)
        case 0: return L("hari ini")
        case 1: return L("besok")
        default: return L("%lld hari lagi", days)
        }
    }
}

/// Design 3a: the bill, what is coming up and the way into Riwayat, under a credit card's open detail.
struct CardDetailContent: View {
    let card: Account
    let statement: CreditStatement?
    let subscriptions: [CardSubscription]
    let isBalanceVisible: Bool
    let onPay: () -> Void
    let onRecord: () -> Void
    let onSubscriptions: () -> Void
    let onHistory: () -> Void

    private func money(_ value: Double) -> String { isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let statement { billPanel(statement) }
            upcomingHeader.padding(.top, 26)
            upcomingRows
            Button(action: onHistory) {
                Label(L("Riwayat transaksi"), systemImage: "clock.arrow.circlepath")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 12)
        }
    }

    // MARK: Bill

    private struct Shown {
        var title: String
        var amount: Double
        var chip: String
        var chipFill: Color
        var chipInk: Color
        var extra: (String, Double)?
        var canPay: Bool
        var canRecord = false
    }

    private func shown(_ s: CreditStatement) -> Shown {
        let upcomingDue = CreditStatement.billing(forPurchaseOn: Date(), card: card).due
        let unbilledLabel = L("Belum ditagih (%@)", CardUI.month(upcomingDue))
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: s.dueDate).day ?? 0
        let dueChip = TransactionDates.dayMonth.string(from: s.dueDate) + " · " + CardUI.daysLeft(to: s.dueDate)
        let title = L("Tagihan %@", CardUI.month(s.dueDate))
        _ = days
        switch s.status {
        case .overdue:
            return Shown(title: title, amount: s.remaining, chip: L("Terlambat %lld hari", s.daysOverdue),
                         chipFill: Color.appError.opacity(0.12), chipInk: .appError,
                         extra: s.unbilled >= 1 ? (unbilledLabel, s.unbilled) : nil, canPay: true, canRecord: true)
        case .paid:
            return Shown(title: title, amount: s.statementAmount, chip: L("Lunas"),
                         chipFill: Color.appPrimary.opacity(0.12), chipInk: .appPrimary,
                         extra: s.unbilled >= 1 ? (unbilledLabel, s.unbilled) : nil, canPay: false)
        case .partial, .unpaid:
            return Shown(title: title, amount: s.remaining, chip: dueChip, chipFill: CardUI.warmFill, chipInk: CardUI.warmInk,
                         extra: s.unbilled >= 1 ? (unbilledLabel, s.unbilled) : nil, canPay: true)
        case .none:
            let upcoming = s.unbilled >= 1
            return Shown(title: L("Tagihan %@", CardUI.month(upcomingDue)), amount: upcoming ? s.unbilled : 0,
                         chip: upcoming ? L("Cetak %@", TransactionDates.dayMonth.string(from: s.nextStatementDate)) : L("Belum ada tagihan"),
                         chipFill: Color.appFill, chipInk: .appTextSecondary, extra: nil, canPay: false)
        }
    }

    private func billPanel(_ s: CreditStatement) -> some View {
        let v = shown(s)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(v.title).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    Text(money(v.amount))
                        .font(.app(28, weight: .semibold))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Color.appText)
                }
                Spacer(minLength: 8)
                Text(v.chip)
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(v.chipInk)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(v.chipFill, in: Capsule())
            }
            if s.status == .partial {
                row(L("Sudah dibayar"), money(s.paid))
            }
            if let extra = v.extra { row(extra.0, money(extra.1)) }
            if v.canPay {
                Button(action: onPay) {
                    Label(L("Bayar tagihan"), systemImage: "banknote")
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.appPrimary, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
            if v.canRecord {
                Button(action: onRecord) {
                    Text("Sudah, catat")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(16)
        .background(CardUI.box, in: RoundedRectangle(cornerRadius: 18))
        // No Bayar button when nothing is printed or it is paid: the box itself pays (upcoming bill) or opens Riwayat (paid).
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            if s.status == .none, v.amount >= 1 { onPay() } else if s.status == .paid { onHistory() }
        }
        .animation(.settle(0.4), value: s.remaining + s.unbilled)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Color.appText)
        }
        .font(.app(13))
        .foregroundStyle(Color.appTextSecondary)
        .monospacedDigit()
    }

    // MARK: Akan datang

    private struct Upcoming: Identifiable {
        let id: String
        let date: Date
        let title: String
        let amount: Double
        let sub: String
        let icon: String
        let isDue: Bool
        let isLate: Bool
    }

    /// Recurring bills up to the next cut-off, and the card's due date while something is still owed.
    private var upcoming: [Upcoming] {
        guard let statement else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        var items = subscriptions.compactMap { sub -> Upcoming? in
            guard sub.isActive, let date = sub.nextBillingDateAsDate, date >= today, date <= statement.nextStatementDate else { return nil }
            return Upcoming(id: sub.id, date: date, title: sub.name, amount: sub.amount,
                            sub: TransactionDates.dayMonth.string(from: date) + " · " + L("berulang"),
                            icon: "repeat", isDue: false, isLate: false)
        }
        if statement.remaining >= 1 {
            items.append(Upcoming(id: "due", date: statement.dueDate, title: L("Jatuh tempo %@", card.name), amount: statement.remaining,
                                  sub: TransactionDates.dayMonth.string(from: statement.dueDate) + " · " + CardUI.daysLeft(to: statement.dueDate),
                                  icon: "calendar.badge.clock", isDue: true, isLate: statement.status == .overdue))
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(3))
    }

    private var upcomingHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Akan datang").font(.app(17, weight: .semibold))
            Spacer()
            Button(action: onSubscriptions) {
                Text("Tagihan berulang").font(.app(15)).foregroundStyle(Color.appPrimary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var upcomingRows: some View {
        let rows = upcoming
        if rows.isEmpty {
            Text("Tidak ada tagihan dalam waktu dekat")
                .font(.app(15))
                .foregroundStyle(Color.appTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 56)
        } else {
            ForEach(rows) { item in
                HStack(spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(item.isDue ? CardUI.warmInk : Color.appBody)
                        .frame(width: 40, height: 40)
                        .background(item.isDue ? CardUI.warmFill : Color.appFill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 10) {
                            Text(item.title).font(.app(16)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(money(item.amount)).font(.app(16)).monospacedDigit()
                        }
                        Text(item.sub)
                            .font(.app(13))
                            .foregroundStyle(item.isLate ? Color.appError : item.isDue ? CardUI.warmInk : Color.appTextSecondary)
                    }
                }
                .foregroundStyle(Color.appText)
                .frame(height: 64)
            }
        }
    }
}

/// Design 3b: a credit card's history grouped by billing cycle, with search.
struct CardHistoryView: View {
    let account: Account
    let statement: CreditStatement?
    let transactions: [Transaction]
    let categories: [Category]
    let accounts: [Account]
    let isBalanceVisible: Bool

    @State private var searchText = ""
    @State private var expanded: Set<Date> = []

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cycles: [CreditStatement.BillingCycle] { CreditStatement.cycles(card: account, transactions: transactions) }

    private func money(_ value: Double) -> String { isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount }

    private func visible(_ cycle: CreditStatement.BillingCycle) -> [Transaction] {
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let list = cycle.transactions.newestFirst()
        guard !query.isEmpty else { return list }
        return list.filter { $0.matches(search: query, categoryName: $0.categoryId.flatMap { names[$0] }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                let all = cycles
                if transactions.isEmpty {
                    EmptyMessage(icon: "clock.arrow.circlepath", title: L("Belum ada transaksi"),
                                 message: L("Transaksi yang kamu catat di %@ akan muncul di sini.", account.name))
                        .padding(.top, 80)
                } else {
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, cycle in
                        cycleBox(cycle, index: index)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Color.appBackground)
        .navigationTitle("Riwayat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Color.appTextTertiary)
            TextField("Cari transaksi atau kategori", text: $searchText)
                .font(.app(16))
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 4)
    }

    private func period(_ c: CreditStatement.BillingCycle) -> String {
        TransactionDates.dayMonth.string(from: c.start) + " – " + TransactionDates.dayMonth.string(from: c.end)
    }

    @ViewBuilder private func cycleBox(_ cycle: CreditStatement.BillingCycle, index: Int) -> some View {
        let rows = visible(cycle)
        let isLatestBilled = index == 1
        let isOpen = cycle.isOpen
        let hasContent = !cycle.transactions.isEmpty || (isOpen && (statement?.unbilled ?? 0) >= 1)
        let searching = !query.isEmpty
        if (searching && rows.isEmpty) || (!searching && !hasContent && index > 1) {
            EmptyView()
        } else if isOpen || isLatestBilled {
            expandedBox(cycle, rows: rows, isLatestBilled: isLatestBilled)
        } else {
            let isExpanded = searching || expanded.contains(cycle.id)
            collapsedBox(cycle, rows: rows, isExpanded: isExpanded)
        }
    }

    private func expandedBox(_ cycle: CreditStatement.BillingCycle, rows: [Transaction], isLatestBilled: Bool) -> some View {
        let s = statement
        let amount = cycle.isOpen ? (s?.unbilled ?? cycle.charged) : (s?.statementAmount ?? cycle.charged)
        let remaining = isLatestBilled ? (s?.remaining ?? 0) : 0
        let overdue = s?.status == .overdue
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cycle.isOpen ? L("Belum ditagih") : L("Tagihan %@", CardUI.month(cycle.dueDate)))
                        .font(.app(16, weight: .semibold))
                    Spacer()
                    Text(money(amount)).font(.app(16, weight: .semibold)).monospacedDigit()
                }
                HStack {
                    Text(period(cycle)).foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    if cycle.isOpen {
                        Text(L("Ditagih %@", TransactionDates.dayMonth.string(from: cycle.end)))
                            .fontWeight(.semibold).foregroundStyle(Color.appTextSecondary)
                    } else if remaining >= 1 {
                        Text(L("Sisa %@", money(remaining)))
                            .fontWeight(.semibold).foregroundStyle(overdue ? Color.appError : CardUI.warmInk)
                    } else if amount >= 1 {
                        Label(L("Lunas"), systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold).foregroundStyle(Color.appPrimary)
                    }
                }
                .font(.app(13))
                if !cycle.isOpen, amount >= 1 {
                    ProgressView(value: min(max((amount - remaining) / amount, 0), 1))
                        .tint(Color.appPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardUI.box)
            ForEach(rows) { txn in transactionRow(txn) }
        }
        .foregroundStyle(Color.appText)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.appSeparator, lineWidth: 1))
        .padding(.top, 14)
    }

    private func collapsedBox(_ cycle: CreditStatement.BillingCycle, rows: [Transaction], isExpanded: Bool) -> some View {
        let settled = cycle.charged < 1 || cycle.paid >= cycle.charged - 1
        return VStack(spacing: 0) {
            Button {
                withAnimation(.settle(0.35)) {
                    if expanded.contains(cycle.id) { expanded.remove(cycle.id) } else { expanded.insert(cycle.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Tagihan %@", CardUI.month(cycle.dueDate))).font(.app(15, weight: .semibold))
                        Text(period(cycle) + " · " + L("%lld transaksi", cycle.transactions.count))
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 8)
                    if settled {
                        Label(L("Lunas"), systemImage: "checkmark.circle.fill")
                            .font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    } else {
                        Text(L("Sisa %@", money(max(cycle.charged - cycle.paid, 0))))
                            .font(.app(13, weight: .semibold)).foregroundStyle(CardUI.warmInk)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded { ForEach(rows) { txn in transactionRow(txn) } }
        }
        .foregroundStyle(Color.appText)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appSeparator, lineWidth: 1))
        .padding(.top, 14)
    }

    private func transactionRow(_ txn: Transaction) -> some View {
        NavigationLink(destination: TransactionDetailView(transaction: txn, categories: categories, accounts: accounts).detailPage()) {
            TransactionRowView(transaction: txn, categories: categories, accounts: accounts, showBalance: isBalanceVisible, showDate: true)
                .padding(.horizontal, 16)
        }
        .buttonStyle(RowPressStyle())
    }
}
