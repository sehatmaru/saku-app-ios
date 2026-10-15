import SwiftUI

/// Sesuaikan saldo / limit / tagihan, laid out like Tambah transaksi: coloured panel with the amount
/// and before → after rows, the number pad with Simpan beside it. A card has two separate bills to
/// adjust: the one the bank already printed, and the running one (spending since the last cut-off).
struct AdjustAmountView: View {
    enum Kind { case balance, limit, billed, running }

    let account: Account
    let kind: Kind
    /// The value as currently shown in the edit form.
    let current: Int
    /// The card's limit in the form (for the bill's remaining-limit row).
    var limit: Int = 0
    /// The card's whole debt in the form: the two bills together.
    var total: Int = 0
    let onApply: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int
    @State private var isFresh = true
    @State private var bump = false
    @State private var shake: CGFloat = 0

    init(account: Account, kind: Kind, current: Int, limit: Int = 0, total: Int = 0,
         onApply: @escaping (Int) -> Void) {
        self.account = account
        self.kind = kind
        self.current = current
        self.limit = limit
        self.total = total
        self.onApply = onApply
        _amount = State(initialValue: current)
    }

    private var color: Color { account.walletColor }
    private var changed: Bool { amount != current }
    private var isBill: Bool { kind == .billed || kind == .running }
    /// The card's whole debt once this amount is applied.
    private var newTotal: Int { total - current + amount }
    private var overLimit: Bool { isBill && limit > 0 && newTotal > limit }
    private var canApply: Bool { changed && !overLimit }

    private var title: String {
        switch kind {
        case .balance: L("Sesuaikan saldo")
        case .limit: L("Limit kredit")
        case .billed: L("Tagihan terbit")
        case .running: L("Tagihan berjalan")
        }
    }

    private var note: String {
        switch kind {
        case .balance: L("Selisihnya dicatat sebagai transaksi Penyesuaian saldo.")
        case .limit: L("Limit baru berlaku untuk perhitungan sisa limit.")
        case .billed: L("Nominal tagihan yang sudah dicetak bank. Jatuh tempo tetap sama.")
        case .running: L("Pemakaian sejak cut-off terakhir. Baru ditagih di cut-off berikutnya.")
        }
    }

    private func rp(_ value: Int) -> String { Double(value).formattedAsCurrency() }

    var body: some View {
        VStack(spacing: 0) {
            panel
            Text(overLimit ? L("Melebihi limit kredit %@", rp(limit)) : note)
                .font(.app(13))
                .foregroundStyle(overLimit ? Color.appError : Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Spacer(minLength: 8)
            AmountPad(color: color, isEnabled: canApply, onPress: press, onSave: apply, title: "Terapkan")
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(.white)
                Spacer()
            }
            .overlay { Text(title).font(.app(17, weight: .semibold)) }
            .frame(height: 44)
            .padding(.horizontal, 20)

            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 16, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1))
                Text(account.name).lineLimit(1)
            }
            .font(.app(13, weight: .medium))
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(.white.opacity(0.14), in: Capsule())
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 4) {
                Text("Rp").font(.app(22)).opacity(0.75).padding(.top, 8)
                Text(Double(amount).formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(isFresh ? 0.55 : 1)
            .scaleEffect(bump ? 1.04 : 1)
            .offset(x: shake)
            .animation(.easeOut(duration: 0.12), value: bump)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 6) {
                switch kind {
                case .balance:
                    row(L("Saldo"), "\(rp(current)) → \(rp(amount))")
                case .limit:
                    row(L("Limit kredit"), "\(rp(current)) → \(rp(amount))")
                case .billed, .running:
                    row(title, "\(rp(current)) → \(rp(amount))")
                    row(L("Total utang"), "\(rp(total)) → \(rp(newTotal))")
                    if limit > 0 {
                        row(L("Sisa limit"), "\(rp(max(limit - total, 0))) → \(rp(max(limit - newTotal, 0)))")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(color)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).opacity(0.85).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).lineLimit(1)
        }
        .font(.app(13))
        .monospacedDigit()
    }

    private func press(_ key: String) {
        if isFresh && key == "del" {
            amount = 0
        } else if let next = NumberPad.apply(key, to: isFresh ? 0 : amount) {
            withAnimation(.settle(0.2)) { amount = next }
        }
        isFresh = false
        bump = true
        Task { try? await Task.sleep(for: .seconds(0.11)); bump = false }
    }

    private func apply() {
        guard canApply else {
            withAnimation(.default) { shake = 8 }
            Task {
                try? await Task.sleep(for: .seconds(0.12))
                withAnimation(.spring(duration: 0.3, bounce: 0.6)) { shake = 0 }
            }
            return
        }
        onApply(amount)
        dismiss()
    }
}
