import SwiftUI

struct AmountKeyboard: View {
    @Binding var amountDigits: String
    var maxDigits: Int = 12
    var onDone: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var tappedKey: String?

    private var btnBg: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(.thickMaterial)
            : AnyShapeStyle(Color.appCardBackground)
    }

    var body: some View {
        let gap: CGFloat = 6
        let screenW = UIScreen.main.bounds.width
        let btnW = (screenW - gap * 5) / 4
        let btnH: CGFloat = 60
        let gridH = 4 * btnH + 3 * gap

        HStack(spacing: gap) {
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    numBtn("1") { tap("1") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("2") { tap("2") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("3") { tap("3") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                }
                HStack(spacing: gap) {
                    numBtn("4") { tap("4") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("5") { tap("5") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("6") { tap("6") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                }
                HStack(spacing: gap) {
                    numBtn("7") { tap("7") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("8") { tap("8") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn("9") { tap("9") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                }
                HStack(spacing: gap) {
                    Color.clear.frame(width: btnW, height: btnH)
                    numBtn("0") { tap("0") }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                    numBtn(".000") { tapThousand() }.frame(width: btnW, height: btnH).contentShape(Rectangle())
                }
            }

            VStack(spacing: gap) {
                backBtn.frame(width: btnW, height: btnH).contentShape(Rectangle())
                doneBtn.frame(width: btnW).frame(maxHeight: .infinity).contentShape(Rectangle())
            }
            .frame(height: gridH)
        }
        .padding(.horizontal, gap)
        .frame(height: gridH + 2 * gap)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
    }

    private func numBtn(_ label: String, action: @escaping () -> Void) -> some View {
        let isTapped = tappedKey == label
        return Button(action: {
            tappedKey = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.tappedKey == label { self.tappedKey = nil }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Text(label)
                        .font(.jakarta(label == ".000" ? 15 : 22, weight: .medium))
                        .foregroundColor(.appText)
                }
        }
        .buttonStyle(KeyboardBtnStyle())
        .background(btnBg.opacity(isTapped ? 0.55 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.1), value: tappedKey)
    }

    private var backBtn: some View {
        let isTapped = tappedKey == "⌫"
        return Button(action: {
            tappedKey = "⌫"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.tappedKey == "⌫" { self.tappedKey = nil }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard !amountDigits.isEmpty else { return }
            amountDigits = String(amountDigits.dropLast())
        }) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Image(systemName: "delete.left")
                        .font(.jakarta(20, weight: .medium))
                        .foregroundColor(.appText)
                }
        }
        .buttonStyle(KeyboardBtnStyle())
        .background(btnBg.opacity(isTapped ? 0.55 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.1), value: tappedKey)
    }

    private var doneBtn: some View {
        let isTapped = tappedKey == "done"
        return Button(action: {
            tappedKey = "done"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.tappedKey == "done" { self.tappedKey = nil }
            }
            onDone?()
        }) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Text("Selesai")
                        .font(.jakarta(16, weight: .semibold))
                        .foregroundColor(.white)
                }
        }
        .buttonStyle(KeyboardBtnStyle())
        .background(Color.appPrimary.opacity(isTapped ? 0.55 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.1), value: tappedKey)
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

struct KeyboardBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

import SwiftUI

struct WalletIconView: View {
    let icon: WalletIcon?
    var size: CGFloat = 36

    private var imageName: String? {
        guard let icon else { return nil }
        // Map WalletIcon id to asset name
        let map: [String: String] = [
            "mastercard": "mastercard",
            "jcb": "jcb",
            "amex": "amex",
            "visa": "visa",
        ]
        return map[icon.id]
    }

    var body: some View {
        if let imageName, UIImage(named: imageName) != nil {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let icon {
            ZStack {
                Circle()
                    .fill(icon.color)
                    .frame(width: size, height: size)
                Text(icon.shortName)
                    .font(.jakarta(size <= 28 ? 6 : 8, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

struct WalletIconBadgeView: View {
    let icon: WalletIcon?
    var size: CGFloat = 18

    var body: some View {
        WalletIconView(icon: icon, size: size)
    }
}
