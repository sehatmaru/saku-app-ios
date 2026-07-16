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
            "unionpay": "unionpay",
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
