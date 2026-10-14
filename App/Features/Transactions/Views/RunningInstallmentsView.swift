import SwiftUI

/// "Cicilan berjalan" above the transaction list: how much 0% card installments bill per month in this period.
/// Informative only: it adds to no total, Net or budget, and search and filters never hide it.
struct RunningInstallmentsBanner: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool

    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }

    var body: some View {
        NavigationLink {
            RunningInstallmentsView(items: items, isBalanceVisible: isBalanceVisible).detailPage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Cicilan berjalan: %lld cicilan", items.count)).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                    Text(L("sekitar Rp%@ per bulan", isBalanceVisible ? monthly.formattedAsDigits() : hiddenAmount))
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 14).frame(minHeight: 62)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 16)
    }
}

/// One screen with every running installment: the card, the part it is on, about how much a month, and when it ends.
struct RunningInstallmentsView: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool

    private func money(_ value: Double) -> String { "Rp" + (isBalanceVisible ? value.formattedAsDigits() : hiddenAmount) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cicilan berjalan").font(.app(34, weight: .bold)).tracking(0.2).padding(.horizontal, 24).padding(.top, 6)
                Text("Cicilan 0% yang masih ditagih di periode ini. Hanya penanda: tidak mengubah Net, budget, atau tagihan kartu.")
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.horizontal, 24).padding(.top, 8)
                VStack(spacing: 12) {
                    ForEach(items) { item in card(item) }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ item: RunningInstallment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(.app(17, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 8)
                Text(L("sekitar %@ per bulan", money(item.monthly))).font(.app(14, weight: .medium)).monospacedDigit()
            }
            Text(item.cardName).font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, -6)
            ProgressView(value: Double(item.billedParts), total: Double(item.months)).tint(Color.appPrimary)
            VStack(spacing: 0) {
                row(L("Bagian"), item.billedParts == 0 ? L("Belum ditagih · %lld bagian", item.months)
                                                      : L("%lld dari %lld sudah ditagih", item.billedParts, item.months))
                row(L("Sisa"), L("%lld bagian", item.remainingParts))
                if let first = item.firstBillingDate {
                    row(L("Mulai ditagih"), DateFormatter.shortDay.string(from: first))
                }
                row(L("Total pembelian"), money(item.total))
                row(L("Dibeli"), DateFormatter.shortDay.string(from: item.purchaseDate), last: true)
            }
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value).foregroundStyle(Color.appText).monospacedDigit()
        }
        .font(.app(15)).frame(minHeight: 40)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
    }
}
