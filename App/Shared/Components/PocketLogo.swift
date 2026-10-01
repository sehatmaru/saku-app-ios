import SwiftUI

extension Animation {
    /// The revamp's shared ease-out, cubic-bezier(.2,.9,.25,1).
    static func settle(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.9, 0.25, 1, duration: duration)
    }
}

extension View {
    /// Fades in and slides up from `y` when `isShown` turns true.
    func rise(_ isShown: Bool, y: CGFloat = 18, delay: Double = 0, fade: Double = 0.5, move: Double = 0.7) -> some View {
        opacity(isShown ? 1 : 0)
            .animation(.easeInOut(duration: fade).delay(delay), value: isShown)
            .offset(y: isShown ? 0 : y)
            .animation(.settle(move).delay(delay), value: isShown)
    }
}

/// Flat top, straight sides, and a half-ellipse bottom taking `curve` of the height.
struct PocketShape: Shape {
    var curve: CGFloat

    func path(in r: CGRect) -> Path {
        let ry = r.height * curve, rx = r.width / 2, k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - ry))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - ry + ry * k),
                   control2: CGPoint(x: r.midX + rx * k, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - ry),
                   control1: CGPoint(x: r.midX - rx * k, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - ry + ry * k))
        p.closeSubpath()
        return p
    }
}

/// Row of flat segments that fill one after another as `filled` grows.
struct SegmentTrack: View {
    let count: Int
    let filled: Int
    var color: Color = .appPrimary
    var track: Color = .appDivider
    var gap: CGFloat = 2
    var delay: Double = 0
    var step: Double = 0
    var duration: Double = 0.2

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? color : track)
                    .animation(.easeOut(duration: duration).delay(delay + Double(i) * step), value: filled)
            }
        }
    }
}

/// Live logo: three cards rise out of a white pocket and fan out when `isOpen`.
/// Laid out on a 180pt grid and scaled to fit its frame.
struct PocketLogo: View {
    var isOpen: Bool
    /// Fans the two back cards out; follows `isOpen` unless set, so it can run as a later step.
    var isFanned: Bool?
    var stagger = 0.12
    var duration = 0.9
    var pocketColor: Color = .white
    /// Plain cards and pocket without chip, stripe, stitching or shadow, for small sizes.
    var isPlain = false

    private let cards: [(color: String, width: CGFloat, top: CGFloat, angle: Double, x: CGFloat)] = [
        ("D9A93A", 132, 0, -7, -10),
        ("472B91", 148, 24, 4, 7),
        ("1A1F71", 164, 47, 0, 0),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 180
            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    ForEach(cards.indices, id: \.self) { i in
                        let c = cards[i]
                        let fanned = isFanned ?? isOpen
                        card(Color(hex: c.color), s: s)
                            .frame(width: c.width * s, height: 90 * s)
                            .rotationEffect(.degrees(fanned ? c.angle : 0), anchor: .bottom)
                            .offset(x: fanned ? c.x * s : 0)
                            .animation(.settle(duration * 0.9), value: fanned)
                            .offset(y: (c.top + (isOpen ? 0 : 84)) * s)
                            .animation(.settle(duration).delay(Double(i) * stagger), value: isOpen)
                    }
                }
                .frame(width: 180 * s, height: 180 * s, alignment: .top)
                // Tucked-in cards must not peek out under the pocket's curve.
                .mask(alignment: .bottom) {
                    Rectangle().frame(width: 300 * s, height: 180 * s).padding(.bottom, 76 * s)
                }

                PocketShape(curve: 76 / 102)
                    .fill(pocketColor)
                    .shadow(color: .black.opacity(isPlain ? 0 : 0.08), radius: 7 * s, y: -4 * s)
                    .overlay(alignment: .top) {
                        if !isPlain { stitching(s) }
                    }
                    .frame(width: 180 * s, height: 102 * s)
                    .offset(y: 78 * s)
            }
            .frame(width: 180 * s, height: 180 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Saku")
    }

    private func stitching(_ s: CGFloat) -> some View {
        DashedLine()
            .stroke(Color.appBrand.opacity(0.45), style: StrokeStyle(lineWidth: 2.5 * s, dash: [6 * s, 4 * s]))
            .frame(height: 2.5 * s)
            .padding(.horizontal, 20 * s)
            .padding(.top, 21 * s)
    }

    @ViewBuilder
    private func card(_ color: Color, s: CGFloat) -> some View {
        if isPlain {
            RoundedRectangle(cornerRadius: 10 * s).fill(color)
        } else {
            detailedCard(color, s: s)
        }
    }

    private func detailedCard(_ color: Color, s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10 * s)
            .fill(color)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3.5 * s)
                    .fill(Color(hex: "F3D48A"))
                    .frame(width: 21 * s, height: 15 * s)
                    .padding(11 * s)
            }
            .overlay(alignment: .topTrailing) {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 29 * s, height: 5 * s)
                    .padding(.top, 16 * s)
                    .padding(.trailing, 11 * s)
            }
            .shadow(color: .black.opacity(0.18), radius: 6 * s, y: -3 * s)
    }
}
