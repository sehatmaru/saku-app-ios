import SwiftUI

/// "Cicilan berjalan" above the transaction list (design "Cicilan Revamp v2"): one line with the monthly total.
/// Informative only: it adds to no total, Net or budget, and search and filters never hide it.
/// Tapping opens the sheet with every running installment.
struct RunningInstallmentsBanner: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    /// Opens the purchase transaction of a tapped installment (the sheet closes first).
    var onOpen: (String) -> Void = { _ in }
    @State private var showsSheet = false
    /// Opened only once the sheet is gone; navigating while it is still dismissing is lost.
    @State private var pendingOpen: String?

    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }

    var body: some View {
        Button { showsSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
                Text(L("Cicilan berjalan")).font(.app(15)).foregroundStyle(Color.appText)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(isBalanceVisible ? CategoryCatalog.short(monthly) : hiddenAmount).monospacedDigit()
                    Text(L("/bln")).foregroundStyle(Color.appTextSecondary)
                }
                .font(.app(15))
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 14)
        .sheet(isPresented: $showsSheet, onDismiss: {
            if let id = pendingOpen { pendingOpen = nil; onOpen(id) }
        }) {
            RunningInstallmentsSheet(items: items, isBalanceVisible: isBalanceVisible) { id in
                pendingOpen = id
                showsSheet = false
            }
        }
    }
}

/// The monthly total, then a plain list sorted by what ends first: five at first, "Lihat semua" for the rest.
struct RunningInstallmentsSheet: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    var onOpen: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var showsAll = false
    @State private var contentHeight: CGFloat = 480

    private static let preview = 5

    private func money(_ value: Double) -> String { "Rp" + (isBalanceVisible ? value.formattedAsDigits() : hiddenAmount) }
    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }
    private var sorted: [RunningInstallment] {
        items.sorted { $0.endDate < $1.endDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("Cicilan berjalan")).font(.app(20, weight: .semibold))
                    Spacer()
                    Button(L("Tutup")) { dismiss() }.font(.app(16, weight: .semibold)).foregroundStyle(Color.appPrimary)
                }
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp").font(.app(15)).foregroundStyle(Color.appTextTertiary).padding(.top, 6)
                    Text(isBalanceVisible ? monthly.formattedAsDigits() : hiddenAmount)
                        .font(.app(40, weight: .light)).tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(L("/bulan")).font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 22)
                }
                .padding(.top, 14)

                VStack(spacing: 0) {
                    ForEach(showsAll ? sorted : Array(sorted.prefix(Self.preview))) { item in row(item) }
                }
                .padding(.top, 12)
                if !showsAll, sorted.count > Self.preview {
                    Button(L("Lihat semua (%lld)", sorted.count)) { withAnimation(.smooth) { showsAll = true } }
                        .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44).padding(.top, 8)
                }
                Text(L("Hanya penanda: tidak mengubah Net, budget, atau tagihan kartu."))
                    .font(.app(12)).lineSpacing(2).foregroundStyle(Color.appTextTertiary).padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 34)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.appText)
        .presentationDetents([.medium, .large])

        .background(Color.appBackground)
    }

    private func row(_ item: RunningInstallment) -> some View {
        Button { onOpen(item.transactionId) } label: { rowContent(item) }
            .buttonStyle(RowPressStyle())
    }

    private func rowContent(_ item: RunningInstallment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.app(16)).lineLimit(1)
                Text(L("%@ · lunas %@", item.cardName, Self.endLabel(item.endDate)))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(money(item.monthly)).font(.app(15)).monospacedDigit()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    /// "Okt", or "Mei 2027" when it ends in another year.
    private static func endLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM" : "MMM yyyy"
        return f.string(from: date)
    }
}
