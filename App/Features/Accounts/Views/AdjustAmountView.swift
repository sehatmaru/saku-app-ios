import SwiftUI

/// Sesuaikan saldo / limit / tagihan, laid out like Tambah transaksi: coloured panel with the amount
/// and before → after rows, the number pad with Simpan beside it. A card's bill also asks whether the
/// bank has printed it yet.
struct AdjustAmountView: View {
    enum Kind { case balance, limit, bill }

    let account: Account
    let kind: Kind
    /// The value as currently shown in the edit form.
    let current: Int
    /// The card's limit in the form (for the bill's remaining-limit row).
    var limit: Int = 0
    var initialPrinted = false
    /// Card with a statement: what is not billed yet (installment parts, spending since the cut-off).
    /// With it, "already printed" asks for the bank's bill and Saku adds this on top for the total debt.
    var unbilled: Int? = nil
    let onApply: (Int, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int
    @State private var printed: Bool
    @State private var isFresh = true
    @State private var bump = false
    @State private var shake: CGFloat = 0

    init(account: Account, kind: Kind, current: Int, limit: Int = 0, initialPrinted: Bool = false, unbilled: Int? = nil,
         onApply: @escaping (Int, Bool) -> Void) {
        self.account = account
        self.kind = kind
        self.current = current
        self.limit = limit
        self.initialPrinted = initialPrinted
        self.unbilled = unbilled
        self.onApply = onApply
        let asBill = kind == .bill && initialPrinted && unbilled != nil
        _amount = State(initialValue: asBill ? max(current - (unbilled ?? 0), 0) : current)
        _printed = State(initialValue: initialPrinted)
    }

    private var color: Color { account.walletColor }
    /// "Already printed" on a card with a statement: the number typed is the bank's bill.
    private var asBill: Bool { kind == .bill && printed && unbilled != nil }
    private var reference: Int { asBill ? max(current - (unbilled ?? 0), 0) : current }
    /// Total debt the typed number leads to.
    private var total: Int { asBill ? amount + (unbilled ?? 0) : amount }
    private var changed: Bool { amount != reference }
    private var overLimit: Bool { kind == .bill && limit > 0 && total > limit }
    private var canApply: Bool { changed && !overLimit }

    private var title: String {
        switch kind {
        case .balance: L("Sesuaikan saldo")
        case .limit: L("Limit kredit")
        case .bill: L("Sesuaikan tagihan")
        }
    }

    private var note: String {
        switch kind {
        case .balance: L("Selisihnya dicatat sebagai transaksi Penyesuaian saldo.")
        case .limit: L("Limit baru berlaku untuk perhitungan sisa limit.")
        case .bill: asBill ? L("Isi sesuai tagihan dari bank. Belanja yang belum ditagih ditambahkan otomatis.")
            : printed ? L("Tagihan ini perlu dibayar sebelum jatuh tempo.")
            : L("Pemakaian sejak cut-off terakhir. Baru ditagih di cut-off berikutnya.")
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

            if kind == .bill {
                HStack(spacing: 8) {
                    chip(L("Sudah dicetak bank"), on: printed) { setPrinted(true) }
                    chip(L("Belum dicetak"), on: !printed) { setPrinted(false) }
                }
                .padding(.top, 14)
            }

            VStack(spacing: 6) {
                switch kind {
                case .balance:
                    row(L("Saldo"), "\(rp(current)) → \(rp(amount))")
                case .limit:
                    row(L("Limit kredit"), "\(rp(current)) → \(rp(amount))")
                case .bill:
                    row(asBill ? L("Tagihan terbit") : L("Tagihan"), "\(rp(reference)) → \(rp(amount))")
                    if asBill, let unbilled {
                        row(L("Belum ditagih"), rp(unbilled))
                        row(L("Total utang"), "\(rp(current)) → \(rp(total))")
                    }
                    if limit > 0 {
                        row(L("Sisa limit"), "\(rp(max(limit - current, 0))) → \(rp(max(limit - total, 0)))")
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

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? color : .white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(on ? Color.white : Color.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
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

    private func setPrinted(_ value: Bool) {
        guard printed != value else { return }
        let was = total
        printed = value
        // Switching the meaning of the number: start from what the other mode would show for the same debt.
        amount = value && unbilled != nil ? max(was - (unbilled ?? 0), 0) : was
        isFresh = true
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
        onApply(total, printed)
        dismiss()
    }
}
