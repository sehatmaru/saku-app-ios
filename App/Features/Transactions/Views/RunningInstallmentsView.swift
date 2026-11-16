import SwiftUI

/// "Cicilan berjalan" above the transaction list (design "Cicilan Revamp v2"): one line with the monthly total.
/// Informative only: it adds to no total, Net or budget. Filters never hide it; a text search does.
/// Tapping opens the sheet with every running installment.
struct RunningInstallmentsBanner: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    /// Opens the purchase transaction of a tapped installment (the sheet closes first).
    var onOpen: (String) -> Void = { _ in }
    /// Plan id and a new tenor, or nil to settle now; true when it saved.
    var onChange: (String, Int?) async -> Bool = { _, _ in false }
    @State private var showsSheet = false
    /// Opened only once the sheet is gone; navigating while it is still dismissing is lost.
    @State private var pendingOpen: String?

    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }
    var body: some View {
        Button { showsSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appPrimary)
                (Text(L("Cicilan berjalan") + " ").foregroundStyle(Color.appTextSecondary)
                 + Text("Rp" + (isBalanceVisible ? monthly.formattedAsDigits() : hiddenAmount) + "/" + L("bulan"))
                    .fontWeight(.semibold).foregroundStyle(Color.appText))
                    .font(.app(16)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 0).padding(.bottom, 20)
        .sheet(isPresented: $showsSheet, onDismiss: {
            if let id = pendingOpen { pendingOpen = nil; onOpen(id) }
        }) {
            RunningInstallmentsSheet(items: items, isBalanceVisible: isBalanceVisible, onOpen: { id in
                pendingOpen = id
                showsSheet = false
            }, onChange: onChange)
        }
    }
}

/// The monthly total, then a plain list sorted by what ends first: five at first, "Lihat semua" for the rest.
struct RunningInstallmentsSheet: View {
    let items: [RunningInstallment]
    let isBalanceVisible: Bool
    var onOpen: (String) -> Void = { _ in }
    var onChange: (String, Int?) async -> Bool = { _, _ in false }
    @State private var settling: RunningInstallment?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    @State private var showsAll = false

    private static let preview = 5

    private func money(_ value: Double) -> String { "Rp" + (isBalanceVisible ? value.formattedAsDigits() : hiddenAmount) }
    private var monthly: Double { items.reduce(0) { $0 + $1.monthly } }
    private var sorted: [RunningInstallment] {
        items.sorted { $0.endDate < $1.endDate }
    }

    var body: some View {
        PickerSheet(title: L("Cicilan berjalan"), actionTitle: L("Mengerti"), onDone: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
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
                Text(L("Net dan budget tidak berubah. Tenor dan pelunasan hanya mengatur cara Saku menagih."))
                    .font(.app(12)).lineSpacing(2).foregroundStyle(Color.appTextTertiary).padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .environment(\.fixedSheetDetents, true)
        .background(Color.appBackground)
        .confirmDialog(isPresented: Binding(get: { settling != nil }, set: { if !$0 { settling = nil } }),
                       icon: "checkmark.circle", title: L("Lunasi cicilan sekarang?"),
                       message: L("Sisa cicilan masuk sekaligus ke tagihan berikutnya. Ini hanya mengubah cara Saku menagih, bukan pembayaran ke bank."),
                       confirmTitle: L("Lunasi"), cancelTitle: L("Tidak jadi")) {
            if let item = settling { Task { if await onChange(item.id, nil) == false { failed = true }; settling = nil } }
        }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: L("Cicilan belum berubah. Coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private func row(_ item: RunningInstallment) -> some View {
        HStack(spacing: 0) {
            Button { onOpen(item.transactionId) } label: { rowContent(item) }
                .buttonStyle(RowPressStyle())
            Menu {
                ForEach([3, 6, 12, 24].filter { $0 > item.billedParts && $0 != item.months }, id: \.self) { months in
                    Button(L("Ubah tenor ke %lld bulan", months)) { Task { if await onChange(item.id, months) == false { failed = true } } }
                }
                Button(L("Lunasi sekarang")) { settling = item }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Kelola cicilan"))
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
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
        }
        .contentShape(Rectangle())
        .padding(.vertical, 13)
    }

    /// "Okt", or "Mei 2027" when it ends in another year.
    private static func endLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM" : "MMM yyyy"
        return f.string(from: date)
    }
}
