import SwiftUI

/// One frame for every Smart Tracker sheet: a badge beside the title, an optional message, a timeline of promises,
/// an optional note. Only the badge colour changes: green = agreement, red = destructive, neutral = info or a plain confirm.
enum SmartSheetTone {
    case consent, destructive, neutral

    var tint: Color {
        switch self {
        case .consent: return Color.stSuccessBg
        case .destructive: return Color(light: 0xFDECEC, dark: 0x3A1D1F)
        case .neutral: return Color.appFill
        }
    }

    var ink: Color {
        switch self {
        case .consent: return Color.stGreen
        case .destructive: return Color(light: 0xD1343A, dark: 0xFF6B6B)
        case .neutral: return Color.appTextSecondary
        }
    }
}

struct SmartPromise: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct SmartSheet<Extra: View, Footer: View>: View {
    let tone: SmartSheetTone
    let icon: String
    let title: String
    var message: String?
    var promises: [SmartPromise] = []
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var footer: () -> Footer

    /// Sheets without promises (confirm, info) centre a large badge and the message, as in the design.
    private var isHero: Bool { promises.isEmpty }

    var body: some View {
        Group {
            if isHero { hero } else { list }
        }
        .foregroundStyle(Color.appText)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
        .filterSheet(showsMoreCue: !promises.isEmpty) { footer() }
        .background(Color.appBackground)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Text(title).font(.app(22, weight: .bold)).tracking(-0.3).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            Spacer(minLength: 16)
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(tone.ink)
                .frame(width: 88, height: 88).background(tone.tint, in: Circle())
            if let message {
                Text(message).font(.app(16)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 24)
            }
            extra()
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .top) { height, _ in height - 58 }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tone.ink)
                    .frame(width: 36, height: 36).background(tone.tint, in: Circle())
                Text(title).font(.app(22, weight: .bold)).tracking(-0.3).fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary).padding(.top, 10)
            }
            if !promises.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(promises) { p in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: p.icon).font(.system(size: 17)).foregroundStyle(tone.ink)
                                .frame(width: 24, height: 24).background(Color.appBackground)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.title).font(.app(15, weight: .semibold))
                                Text(p.detail).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                }
                .background(alignment: .topLeading) {
                    Rectangle().fill(Color.appDivider).frame(width: 1).padding(.leading, 11).padding(.vertical, 12)
                }
                .padding(.top, 12)
            }
            extra()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SmartSheet where Extra == EmptyView {
    init(tone: SmartSheetTone, icon: String, title: String, message: String? = nil, promises: [SmartPromise] = [],
         @ViewBuilder footer: @escaping () -> Footer) {
        self.init(tone: tone, icon: icon, title: title, message: message, promises: promises, extra: { EmptyView() }, footer: footer)
    }
}

/// Two children on one row, 1 : 3 (Batal : the action).
private struct RatioRow: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 320, height: 50)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let unit = (bounds.width - spacing) / 4
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: unit, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + unit + spacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: unit * 3, height: bounds.height))
    }
}

/// Footer for every sheet with a choice: one row, a plain text button (1) and the pill (3). Without `primary` it is one
/// text button across the width; without `secondary` it is one pill across the width.
struct SmartSheetFooter: View {
    var primary: String?
    var destructive = false
    /// Black pill (white in dark mode) for a calm action that is not the main green one.
    var ink = false
    var isBusy = false
    var isEnabled = true
    var secondary: String?
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        Group {
            if let primary, let secondary {
                RatioRow {
                    Button(action: onSecondary) {
                        Text(secondary).font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .opacity(isBusy ? 0.35 : 1)
                    Button(action: onPrimary) {
                        ZStack {
                            Text(primary).opacity(isBusy ? 0 : 1)
                            if isBusy { ProgressView().tint(.white) }
                        }
                        .font(.app(17, weight: .semibold)).foregroundStyle(ink ? Color.appBackground : .white)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(destructive ? Color(hex: "D93636") : ink ? Color.appText : Color.appPrimary, in: Capsule())
                        .opacity(isEnabled ? 1 : 0.4)
                    }
                    .disabled(!isEnabled)
                }
                .frame(height: 50)
            } else if let primary {
                Button(action: onPrimary) {
                    ZStack {
                        Text(primary).opacity(isBusy ? 0 : 1)
                        if isBusy { ProgressView().tint(.white) }
                    }
                    .font(.app(17, weight: .semibold)).foregroundStyle(ink ? Color.appBackground : .white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(destructive ? Color(hex: "D93636") : ink ? Color.appText : Color.appPrimary, in: Capsule())
                    .opacity(isEnabled ? 1 : 0.4)
                }
                .disabled(!isEnabled)
            } else if let secondary {
                Button(action: onSecondary) {
                    Text(secondary).font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity).frame(height: 38)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isBusy)
    }
}
