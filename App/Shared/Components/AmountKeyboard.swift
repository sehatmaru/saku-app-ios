import SwiftUI

struct AmountKeyboard: View {
    @Binding var amountDigits: String
    var maxDigits: Int = 12
    var onDone: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let btnW = (geo.size.width - gap * 5) / 4
            let btnH: CGFloat = 54
            let gridH = 4 * btnH + 3 * gap

            HStack(spacing: gap) {
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        numBtn("1") { tap("1") }.frame(width: btnW, height: btnH)
                        numBtn("2") { tap("2") }.frame(width: btnW, height: btnH)
                        numBtn("3") { tap("3") }.frame(width: btnW, height: btnH)
                    }
                    HStack(spacing: gap) {
                        numBtn("4") { tap("4") }.frame(width: btnW, height: btnH)
                        numBtn("5") { tap("5") }.frame(width: btnW, height: btnH)
                        numBtn("6") { tap("6") }.frame(width: btnW, height: btnH)
                    }
                    HStack(spacing: gap) {
                        numBtn("7") { tap("7") }.frame(width: btnW, height: btnH)
                        numBtn("8") { tap("8") }.frame(width: btnW, height: btnH)
                        numBtn("9") { tap("9") }.frame(width: btnW, height: btnH)
                    }
                    HStack(spacing: gap) {
                        Color.clear.frame(width: btnW, height: btnH)
                        numBtn("0") { tap("0") }.frame(width: btnW, height: btnH)
                        numBtn(".000") { tapThousand() }.frame(width: btnW, height: btnH)
                    }
                }

                VStack(spacing: gap) {
                    backBtn.frame(width: btnW, height: btnH)
                    doneBtn.frame(width: btnW)
                }
                .frame(height: gridH)
            }
            .padding(.horizontal, gap)
        }
        .frame(height: 4 * 54 + 3 * 6 + 20)
        .background(Color(.systemGray6))
    }

    private func numBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(.jakarta(label == ".000" ? 15 : 22, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.appText)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var backBtn: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard !amountDigits.isEmpty else { return }
            amountDigits = String(amountDigits.dropLast())
        }) {
            Image(systemName: "delete.left")
                .font(.jakarta(20, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.appText)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var doneBtn: some View {
        Button(action: { onDone?() }) {
            Text("Selesai")
                .font(.jakarta(16, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.white)
                .background(Color.appPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func tap(_ digit: String) {
        guard amountDigits.count < maxDigits else { return }
        if digit == "0" && (amountDigits.isEmpty || amountDigits == "0") { return }
        if amountDigits == "0" { amountDigits = digit; return }
        amountDigits += digit
    }

    private func tapThousand() {
        if amountDigits.isEmpty || amountDigits == "0" { return }
        let remaining = maxDigits - amountDigits.count
        guard remaining > 0 else { return }
        amountDigits += String(repeating: "0", count: min(3, remaining))
    }
}
