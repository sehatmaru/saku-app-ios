import SwiftUI

/// Three stacked credit cards (gold, purple, navy) with a green wallet pocket.
/// Matches the "SakuQ Logo — final" design spec.
struct SakuQLogoIcon: View {
    var walletColor: Color = Color(hex: "16875A")
    var dashColor: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100

            // Gold card
            ctx.fill(Path(roundedRect: CGRect(x: 26*s, y: 10*s, width: 48*s, height: 30*s), cornerRadius: 5*s), with: .color(Color(hex: "D9A93A")))
            ctx.fill(Path(roundedRect: CGRect(x: 32*s, y: 15*s, width: 9*s, height: 6*s), cornerRadius: 1.5*s), with: .color(Color(hex: "F3D48A")))
            ctx.fill(Path(roundedRect: CGRect(x: 56*s, y: 17*s, width: 12*s, height: 2.5*s), cornerRadius: 1.25*s), with: .color(.white.opacity(0.4)))

            // Purple card
            ctx.fill(Path(roundedRect: CGRect(x: 22*s, y: 18*s, width: 56*s, height: 30*s), cornerRadius: 5*s), with: .color(Color(hex: "472B91")))
            ctx.fill(Path(roundedRect: CGRect(x: 28*s, y: 23*s, width: 9*s, height: 6*s), cornerRadius: 1.5*s), with: .color(Color(hex: "F3D48A")))
            ctx.fill(Path(roundedRect: CGRect(x: 60*s, y: 25*s, width: 12*s, height: 2.5*s), cornerRadius: 1.25*s), with: .color(.white.opacity(0.4)))

            // Navy card
            ctx.fill(Path(roundedRect: CGRect(x: 18*s, y: 26*s, width: 64*s, height: 30*s), cornerRadius: 5*s), with: .color(Color(hex: "1A1F71")))
            ctx.fill(Path(roundedRect: CGRect(x: 24*s, y: 31*s, width: 9*s, height: 6*s), cornerRadius: 1.5*s), with: .color(Color(hex: "F3D48A")))
            ctx.fill(Path(roundedRect: CGRect(x: 64*s, y: 33*s, width: 12*s, height: 2.5*s), cornerRadius: 1.25*s), with: .color(.white.opacity(0.4)))

            // Wallet pocket — flat top at y=40, elliptical bottom (rx=34, ry=30, center at 50,62)
            let k: CGFloat = 0.5523
            var wallet = Path()
            wallet.move(to: CGPoint(x: 16*s, y: 40*s))
            wallet.addLine(to: CGPoint(x: 84*s, y: 40*s))
            wallet.addLine(to: CGPoint(x: 84*s, y: 62*s))
            wallet.addCurve(
                to: CGPoint(x: 50*s, y: 92*s),
                control1: CGPoint(x: 84*s, y: (62 + 30*k)*s),
                control2: CGPoint(x: (50 + 34*k)*s, y: 92*s)
            )
            wallet.addCurve(
                to: CGPoint(x: 16*s, y: 62*s),
                control1: CGPoint(x: (50 - 34*k)*s, y: 92*s),
                control2: CGPoint(x: 16*s, y: (62 + 30*k)*s)
            )
            wallet.closeSubpath()
            ctx.fill(wallet, with: .color(walletColor))

            // Dashed line across wallet
            var dash = Path()
            dash.move(to: CGPoint(x: 25*s, y: 50*s))
            dash.addLine(to: CGPoint(x: 75*s, y: 50*s))
            ctx.stroke(dash, with: .color(dashColor.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 3*s, lineCap: .round, dash: [5*s, 4.5*s]))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
