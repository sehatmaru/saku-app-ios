import SwiftUI

/// "Cicilan berjalan" above the transaction list (design "Cicilan Revamp"): how much 0% card installments bill
/// per month in this period. Informative only: it adds to no total, Net or budget, and search and filters
/// never hide it. Tapping opens the sheet with every running installment.
struct RunningInstallmentsBanner: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    @State private var showsSheet = false

    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }
    private var cards: [RunningInstallment] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.cardName).inserted }
    }

    var body: some View {
        Button { showsSheet = true } label: {
            HStack(spacing: 12) {
                logos
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%lld cicilan berjalan", items.count)).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(L("%lld kartu kredit", cards.count)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isBalanceVisible ? CategoryCatalog.short(monthly) : hiddenAmount)
                        .font(.app(15)).foregroundStyle(Color.appText).monospacedDigit()
                    Text(L("per bulan")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24).padding(.top, 16)
        .sheet(isPresented: $showsSheet) {
            RunningInstallmentsSheet(items: items, isBalanceVisible: isBalanceVisible)
        }
    }

    /// The first two cards' logos, overlapped, and a "+N" for the rest.
    private var logos: some View {
        HStack(spacing: -9) {
            ForEach(Array(cards.prefix(2).enumerated()), id: \.offset) { _, item in
                InstallmentLogo(icon: item.cardIcon, size: 28).overlay(Circle().stroke(Color.appFill, lineWidth: 2))
            }
            if cards.count > 2 {
                Text("+\(cards.count - 2)").font(.app(11, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    .frame(width: 28, height: 28).background(Color.appDivider, in: Circle())
                    .overlay(Circle().stroke(Color.appFill, lineWidth: 2))
            }
        }
    }
}

/// The card's bank logo on a white disc with a hairline, as in the design.
private struct InstallmentLogo: View {
    let icon: String?
    let size: CGFloat

    var body: some View {
        WalletIconView(icon: WalletIcon.resolve(icon), size: size)
            .overlay(Circle().stroke(Color.appSeparator, lineWidth: 1))
    }
}

/// Every running installment in a sheet. One installment shows in full; a few are grouped by card with a
/// tick per part; more than four collapse to a card filter and compact rows.
struct RunningInstallmentsSheet: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var filter: String?
    @State private var contentHeight: CGFloat = 480

    private static let compactFrom = 5

    private func money(_ value: Double) -> String { "Rp" + (isBalanceVisible ? value.formattedAsDigits() : hiddenAmount) }
    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }
    private var cardNames: [String] {
        var seen = Set<String>()
        return items.map(\.cardName).filter { seen.insert($0).inserted }
    }
    private var isCompact: Bool { items.count >= Self.compactFrom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if items.count > 1 { total }
                if isCompact { compact } else { grouped }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(isCompact ? 720 : min(contentHeight + 12, 720)), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("Cicilan berjalan")).font(.app(20, weight: .semibold))
                Spacer()
                Button(L("Tutup")) { dismiss() }.font(.app(16, weight: .semibold)).foregroundStyle(Color.appPrimary)
            }
            Text(L("Cicilan 0% yang masih ditagih di periode ini. Hanya penanda: tidak mengubah Net, budget, atau tagihan kartu."))
                .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Text("Rp").font(.app(15)).foregroundStyle(Color.appTextTertiary).padding(.top, 6)
                Text(isBalanceVisible ? monthly.formattedAsDigits() : hiddenAmount)
                    .font(.app(40, weight: .light)).tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(L("/bulan")).font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 22)
            }
            Text(cardNames.count > 1 ? L("%lld cicilan di %lld kartu", items.count, cardNames.count) : L("%lld cicilan", items.count))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
        .padding(.top, 18)
    }

    // MARK: Few: grouped by card, a tick per part

    private var grouped: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cardNames, id: \.self) { card in
                let rows = items.filter { $0.cardName == card }
                VStack(alignment: .leading, spacing: 0) {
                    if cardNames.count > 1 {
                        HStack {
                            Text(card)
                            Spacer()
                            Text(L("%@/bln", money(rows.reduce(0) { $0 + $1.monthly }))).monospacedDigit()
                        }
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 16)
                    }
                    ForEach(rows) { item in detail(item, showsCard: cardNames.count == 1) }
                }
            }
        }
        .padding(.top, 8)
    }

    private func detail(_ item: RunningInstallment, showsCard: Bool) -> some View {
        let single = items.count == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                InstallmentLogo(icon: item.cardIcon, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.app(16, weight: .semibold)).lineLimit(2)
                    Text((showsCard ? item.cardName + " · " : "") + L("dibeli %@", DateFormatter.shortDay.string(from: item.purchaseDate)))
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Text(money(item.monthly)).font(.app(single ? 26 : 16, weight: single ? .light : .regular))
                    .tracking(-0.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: 3) {
                ForEach(0..<item.months, id: \.self) { part in
                    RoundedRectangle(cornerRadius: 1).fill(part < item.billedParts ? Color.appPrimary : Color.appDivider).frame(height: 6)
                }
            }
            HStack {
                Text(item.billedParts == 0 ? L("Belum ditagih · %lld bagian", item.months)
                                           : L("%lld dari %lld sudah ditagih", item.billedParts, item.months))
                Spacer()
                Text(L("Lunas %@", Self.endLabel(item.endDate)))
            }
            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            if single {
                HStack {
                    Text(L("Total pembelian")).foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text(money(item.total)).monospacedDigit()
                }
                .font(.app(15)).padding(.top, 8)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    /// "Okt", or "Mei 2027" when it ends in another year.
    private static func endLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM" : "MMM yyyy"
        return f.string(from: date)
    }

    // MARK: Many: card filter and compact rows

    private var compact: some View {
        let shown = items.filter { filter == nil || $0.cardName == filter }
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(L("Semua"), on: filter == nil) { filter = nil }
                    ForEach(cardNames, id: \.self) { name in chip(name, on: filter == name) { filter = name } }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden).padding(.horizontal, -24).padding(.top, 16)
            HStack {
                Text(filter.map { L("%@ · %lld cicilan", $0, shown.count) } ?? L("%lld cicilan", shown.count))
                Spacer()
                Text(L("%@/bln", money(shown.reduce(0) { $0 + $1.monthly }))).monospacedDigit()
            }
            .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 14).padding(.bottom, 4)
            ForEach(shown) { item in row(item) }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(14, weight: .medium)).lineLimit(1).padding(.horizontal, 14).frame(height: 34)
                .foregroundStyle(on ? Color.appBackground : Color.appText)
                .background(on ? Color.appText : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.appText : Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ item: RunningInstallment) -> some View {
        HStack(spacing: 12) {
            InstallmentLogo(icon: item.cardIcon, size: 28)
            VStack(spacing: 5) {
                HStack {
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(money(item.monthly)).monospacedDigit()
                }
                .font(.app(15))
                HStack(spacing: 8) {
                    ProgressView(value: Double(item.billedParts), total: Double(item.months))
                        .tint(Color.appPrimary).scaleEffect(y: 0.5)
                    Text("\(item.cardName) · \(item.billedParts)/\(item.months)").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1).frame(minWidth: 84, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 10)
    }
}
