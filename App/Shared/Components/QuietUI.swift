import SwiftUI

/// Masked value used wherever balances are hidden.
let hiddenAmount = "••••••"

/// Large light-weight amount with a small "Rp" prefix.
struct HeroAmount: View {
    enum Size { case large, medium }

    let value: Double
    var size: Size = .large
    var prefix: String = "Rp"
    var color: Color = .appText
    var prefixColor: Color = .appTextSecondary
    var isVisible: Bool = true

    var body: some View {
        let big = size == .large
        HStack(alignment: .top, spacing: big ? 4 : 3) {
            Text(prefix)
                .font(.app(big ? 22 : 17))
                .foregroundStyle(prefixColor)
                .padding(.top, big ? 8 : 5)
            Text(isVisible ? value.formattedAsDigits() : hiddenAmount)
                .font(.app(big ? 52 : 40, weight: .light))
                .tracking(big ? -2 : -1.4)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .monospacedDigit()
    }
}

/// 20pt section title with an optional trailing label or link.
struct SectionHeader: View {
    let title: String
    var trailing: String?
    var trailingColor: Color = .appTextSecondary
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.app(20, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.appText)
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(.app(15))
                        .foregroundStyle(trailingColor)
                } else {
                    Text(trailing)
                        .font(.app(15))
                        .foregroundStyle(trailingColor)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// Segmented progress bar in the "Kesehatan finansial" style; segments fill in one by one on appear.
struct SegmentBar: View {
    let value: Double
    var color: Color = .appPrimary
    var count = 30
    var height: CGFloat = 8
    var spacing: CGFloat = 2
    @State private var isShown = false

    var body: some View {
        let filled = isShown ? Int((min(max(value, 0), 1) * Double(count)).rounded()) : 0
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? color : Color.appDivider)
                    .animation(.easeOut(duration: 0.24).delay(Double(i) * 0.014), value: filled)
            }
        }
        .frame(height: height)
        .onAppear { isShown = true }
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) persen")
    }
}

/// 3pt progress bar.
struct ThinProgress: View {
    let value: Double
    var color: Color = .appText

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.appDivider)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
        }
        .frame(height: 3)
    }
}

/// Large 34pt screen title with trailing controls, replacing the nav bar title.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.app(34, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(Color.appText)
            Spacer()
            HStack(spacing: 18) { trailing }
                .font(.system(size: 20))
                .foregroundStyle(Color.appText)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }
}

extension View {
    /// Row bottom hairline used by every list in the Quiet Minimal style.
    func rowSeparator() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Color.appSeparator).frame(height: 1)
        }
    }
}

/// 1pt divider between home sections.
struct SectionDivider: View {
    var body: some View {
        Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 24)
    }
}
