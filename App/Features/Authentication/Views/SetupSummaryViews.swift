import SwiftUI

/// The pieces the saving screen and the welcome screen share, so the rows stay put when one turns into the other
/// (design B: "Menyimpan setup" becomes "Selamat datang" without a cut).

/// One line of the summary: a ring while saving, a check once saved, a count on the welcome screen.
struct SetupSummaryRow: Identifiable {
    let id: String
    let label: String
    let icon: String
    let number: Double?
    /// The count as text when it isn't a plain number, and the format of a counted number.
    let text: String
    let format: (Double) -> String
    let detail: String

    func count(_ value: Double) -> String { number == nil ? text : format(value) }

    static func rows(wallets: [String], expense: Int, income: Int, paydayDay: Int?) -> [SetupSummaryRow] {
        let plain: (Double) -> String = { $0.formattedAsDigits() }
        let payday: SetupSummaryRow
        switch paydayDay {
        case .some(31):
            payday = .init(id: "payday", label: L("Tanggal gajian"), icon: "calendar", number: nil, text: L("Akhir bulan"),
                           format: plain, detail: L("Periode anggaranmu mulai tiap akhir bulan"))
        case .some(let day) where day > 1:
            payday = .init(id: "payday", label: L("Tanggal gajian"), icon: "calendar", number: Double(day), text: "",
                           format: { L("Tgl %@", $0.formattedAsDigits()) },
                           detail: L("Periode anggaranmu mulai tiap tanggal %lld", day))
        default:
            payday = .init(id: "payday", label: L("Tanggal mulai periode"), icon: "calendar", number: nil, text: L("Tgl 1"),
                           format: plain, detail: L("Periode anggaranmu mulai tanggal 1"))
        }
        return [
            .init(id: "wallets", label: L("Dompet"), icon: "wallet.bifold", number: Double(wallets.count), text: "",
                  format: plain, detail: wallets.joined(separator: ", ")),
            .init(id: "categories", label: L("Kategori"), icon: "square.grid.2x2", number: Double(expense + income), text: "",
                  format: plain, detail: L("%lld pengeluaran dan %lld pemasukan", expense, income)),
            payday,
        ]
    }
}

/// Title, line and progress bar. `saved` swaps the words and fills the bar.
struct SetupSavingHeader: View {
    let saved: Bool
    @State private var sweep = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swapped(L("Menyimpan setup-mu"), L("Setup tersimpan"), font: .app(28, weight: .bold), tracking: -0.3, color: Color.appText)
                .frame(height: 36)
            swapped(L("Jawabanmu masih ada di iPhone ini sampai selesai."), L("Menyiapkan halaman utamamu."),
                    font: .app(15), tracking: 0, color: Color.appTextSecondary)
                .frame(height: 44, alignment: .topLeading)
                .padding(.top, 10)
            bar.padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { sweep = true }
    }

    private func swapped(_ first: String, _ second: String, font: Font, tracking: CGFloat, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Text(first).opacity(saved ? 0 : 1).offset(y: saved ? -8 : 0)
            Text(second).opacity(saved ? 1 : 0).offset(y: saved ? 0 : 8)
                .animation(.settle(0.45).delay(saved ? 0.35 : 0), value: saved)
        }
        .font(font).tracking(tracking).foregroundStyle(color)
        .animation(.settle(0.45), value: saved)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appDivider)
                Capsule().fill(Color.appPrimary)
                    .frame(width: saved ? width : width * 0.38)
                    .offset(x: saved ? 0 : (sweep ? width * 1.0 : -width * 0.38))
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: sweep)
                    .animation(.settle(0.6), value: saved)
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }
}

/// The summary rows. On the welcome screen (`win`) they turn white; Gratis rows show their count and open on tap,
/// Plus rows turn into the three things the trial gives.
struct SetupSummaryList: View {
    let rows: [SetupSummaryRow]
    var saved = false
    var win = false
    var plus = false
    var counted = false
    @State private var open: String?

    private static let perks = ["Bantuan AI tanpa batas", "Laporan PDF", "Analisis keuangan"]
    private static let gold = Color(hex: "E3B34F")

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        guard win, !plus else { return }
                        open = open == row.id ? nil : row.id
                    } label: { line(row, index: index) }
                    .buttonStyle(.plain)
                    .disabled(!win || plus)
                    if open == row.id, !plus {
                        Text(row.detail)
                            .font(.app(14)).foregroundStyle(Color.white.opacity(0.85))
                            .padding(.leading, 38).padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
            }
        }
        .animation(.settle(0.4), value: open)
        .animation(.settle(0.5), value: win)
    }

    private func line(_ row: SetupSummaryRow, index: Int) -> some View {
        let perkShown = plus && win
        return HStack(spacing: 14) {
            Image(systemName: row.icon).font(.system(size: 20)).frame(width: 24)
                .foregroundStyle(win ? Color.white : Color.appTextSecondary)
                .opacity(perkShown ? 0 : 1)
            ZStack(alignment: .leading) {
                Text(row.label).opacity(perkShown ? 0 : 1)
                Text(L(Self.perks[min(index, Self.perks.count - 1)])).fontWeight(.semibold).opacity(perkShown ? 1 : 0)
                    .animation(.settle(0.35).delay(0.15), value: perkShown)
            }
            .font(.app(16, weight: .medium))
            .foregroundStyle(win ? Color.white : Color.appText)
            .frame(maxWidth: .infinity, alignment: .leading)
            CountingText(value: counted ? (row.number ?? 0) : 0) { row.count($0) }
                .font(.app(15)).foregroundStyle(.white).monospacedDigit()
                .opacity(win && !plus ? 1 : 0)
                .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9), value: counted)
            status(index: index)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func status(index: Int) -> some View {
        let fill: Color = win ? (plus ? Self.gold : .white) : Color.appPrimary
        let ink: Color = win ? (plus ? Color(hex: "111111") : Color(hex: "0F6B46")) : .white
        return ZStack {
            Circle().strokeBorder(Color.appDivider, lineWidth: 2).frame(width: 18, height: 18)
                .opacity(saved ? 0 : 1)
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(ink)
                .frame(width: 22, height: 22).background(fill, in: Circle())
                .scaleEffect(saved ? 1 : 0.4).opacity(saved ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.5).delay(Double(index) * 0.11), value: saved)
    }
}
