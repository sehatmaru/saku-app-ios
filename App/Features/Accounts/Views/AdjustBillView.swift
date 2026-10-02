import SwiftUI

/// Sesuaikan tagihan, laid out like Bayar tagihan: coloured panel with the amount, chips for what
/// the amount is, before → after rows, number pad and a Terapkan button.
struct AdjustBillView: View {
    let card: Account
    /// The bill and limit as currently shown in the edit form.
    let current: Int
    let limit: Int
    let initialPrinted: Bool
    let onApply: (Int, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int
    @State private var printed: Bool
    @State private var isFresh = true
    @State private var bump = false
    @State private var shake: CGFloat = 0

    init(card: Account, current: Int, limit: Int, initialPrinted: Bool, onApply: @escaping (Int, Bool) -> Void) {
        self.card = card
        self.current = current
        self.limit = limit
        self.initialPrinted = initialPrinted
        self.onApply = onApply
        _amount = State(initialValue: current)
        _printed = State(initialValue: initialPrinted)
    }

    private var color: Color { card.walletColor }
    private var changed: Bool { amount != current }
    private var overLimit: Bool { limit > 0 && amount > limit }
    private var canApply: Bool { changed && !overLimit }

    private var buttonLabel: String {
        if overLimit { return L("Melebihi limit") }
        if !changed { return L("Ubah nominal dulu") }
        return L("Terapkan")
    }

    var body: some View {
        VStack(spacing: 0) {
            panel
            Text(printed ? L("Tagihan ini perlu dibayar sebelum jatuh tempo.")
                 : L("Pemakaian sejak cut-off terakhir. Baru ditagih di cut-off berikutnya."))
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                NumberPadKeys(onPress: press)
                Button {
                    if canApply { onApply(amount, printed); dismiss() } else { blocked() }
                } label: {
                    Text(buttonLabel)
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(canApply ? color : Color.appTextTertiary.opacity(0.5), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .offset(x: shake)
                .padding(.horizontal, 12)
            }
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
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard").font(.system(size: 15, weight: .bold))
                    Text("Sesuaikan tagihan").font(.app(17, weight: .semibold))
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 16, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1))
                Text(card.name).lineLimit(1)
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

            HStack(spacing: 8) {
                chip(L("Sudah dicetak bank"), on: printed) { printed = true }
                chip(L("Belum dicetak"), on: !printed) { printed = false }
            }
            .padding(.top, 14)

            VStack(spacing: 6) {
                row(L("Tagihan"), "\(Double(current).formattedAsCurrency()) → \(Double(amount).formattedAsCurrency())")
                if limit > 0 {
                    row(L("Sisa limit"), "\(Double(max(limit - current, 0)).formattedAsCurrency()) → \(Double(max(limit - amount, 0)).formattedAsCurrency())")
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
                .overlay {
                    LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 170, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.06))
                        .offset(x: 40, y: 90)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
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

    private func blocked() {
        withAnimation(.default) { shake = 8 }
        Task {
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.spring(duration: 0.3, bounce: 0.6)) { shake = 0 }
        }
    }
}
