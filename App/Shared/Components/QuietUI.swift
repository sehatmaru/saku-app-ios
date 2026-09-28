import SwiftUI

/// Masked value used wherever balances are hidden.
let hiddenAmount = "••••••"

/// Large light-weight amount with a small "Rp" prefix; a negative value gets "−Rp".
struct HeroAmount: View {
    /// `hero` is the Beranda total (58pt, extra light).
    enum Size { case hero, large, medium }

    let value: Double
    var size: Size = .large
    var prefix: String = "Rp"
    var color: Color = .appText
    var prefixColor: Color = .appTextSecondary
    var isVisible: Bool = true
    var weight: Font.Weight = .light

    var body: some View {
        let (number, symbol, top, tracking, spacing): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = switch size {
        case .hero: (58, 24, 9, -2.6, 4)
        case .large: (52, 22, 8, -2, 4)
        case .medium: (40, 17, 5, -1.4, 3)
        }
        HStack(alignment: .top, spacing: spacing) {
            Text(value < 0 && prefix == "Rp" && isVisible ? "−Rp" : prefix)
                .font(.app(symbol))
                .foregroundStyle(prefixColor)
                .padding(.top, top)
            Text(isVisible ? value.formattedAsDigits() : hiddenAmount)
                .font(.app(number, weight: weight))
                .tracking(tracking)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .monospacedDigit()
    }
}

/// Thin two-colour bar splitting income (green) from spending (red).
struct FlowSplitBar: View {
    let income: Double
    let expense: Double

    var body: some View {
        let total = income + expense
        let share = total > 0 ? income / total : 0.5
        GeometryReader { geo in
            HStack(spacing: 3) {
                if income > 0 || total == 0 {
                    RoundedRectangle(cornerRadius: 3).fill(Color.appPrimary)
                        .frame(width: total == 0 ? nil : max(0, (geo.size.width - 3) * share))
                }
                if expense > 0 || total == 0 {
                    RoundedRectangle(cornerRadius: 3).fill(total == 0 ? Color.appDivider : Color.appError)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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

/// Segmented progress bar in the "Kesehatan finansial" style; segments fill in one by one
/// each time the bar appears, starting after `delay`.
struct SegmentBar: View {
    let value: Double
    var color: Color = .appPrimary
    var count = 30
    var height: CGFloat = 8
    var spacing: CGFloat = 2
    var delay: Double = 0
    /// For bars that stay mounted while hidden: fills only while true.
    var isActive = true
    @State private var isShown = false

    var body: some View {
        let filled = isShown && isActive ? Int((min(max(value, 0), 1) * Double(count)).rounded()) : 0
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? color : Color.appDivider)
                    .animation(.easeOut(duration: 0.24).delay(delay + Double(i) * 0.014), value: filled)
            }
        }
        .frame(height: height)
        // Fill on the next frame so the first render is empty and the change animates.
        .task { isShown = true }
        .onDisappear {
            var reset = SwiftUI.Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { isShown = false }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) persen")
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

/// Text that counts up (or down) when `value` changes inside an animation.
struct CountingText: View, @MainActor Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// Horizontal line through the middle of its frame; stroke it with a dash for guides.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
