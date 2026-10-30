import SwiftUI

/// The tones of a Beranda notice (design "Saku Notices"). Only the colour changes between them.
enum NoticeTone {
    case critical, warning, neutral

    var color: Color {
        switch self {
        case .critical: .appError
        case .warning: .appWarning
        case .neutral: .appPrimary
        }
    }
}

/// The one card the notices on Beranda share: a round badge, a title, an optional message, up to two actions and an
/// optional close. Radius 24, no border or shadow, the tone as a 9% tint. It rises in once when it shows up.
struct NoticeCard<Actions: View>: View {
    let icon: String
    var tone: NoticeTone = .neutral
    let title: String
    var message: String?
    var onClose: (() -> Void)?
    @ViewBuilder var actions: Actions
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appBackground)
                    .frame(width: 36, height: 36)
                    .background(tone.color, in: Circle())
                Text(title)
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.trailing, -10)
                    .padding(.vertical, -8)
                    .accessibilityLabel(L("Tutup"))
                }
            }
            if let message {
                Text(message)
                    .font(.app(14))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .rise(shown, y: 10, delay: 0, fade: 0.32, move: 0.32)
        .onAppear { shown = true }
    }
}

extension NoticeCard where Actions == EmptyView {
    init(icon: String, tone: NoticeTone = .neutral, title: String, message: String? = nil, onClose: (() -> Void)? = nil) {
        self.init(icon: icon, tone: tone, title: title, message: message, onClose: onClose) { EmptyView() }
    }
}

/// A 44 pt pill sized to its text: green for the main action, ink for Apple, a thin outline for the second one.
struct NoticeButton: View {
    enum Style { case primary, secondary, ink }

    let title: String
    var icon: String?
    var style: Style = .primary
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                    Text(title)
                }
            }
            .font(.app(15, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(background, in: Capsule())
            .overlay { if style == .secondary { Capsule().strokeBorder(Color.appBorder, lineWidth: 1) } }
        }
        .buttonStyle(PressScaleStyle())
    }

    private var foreground: Color {
        switch style {
        case .primary: .white
        case .secondary: .appText
        case .ink: .appBackground
        }
    }

    private var background: Color {
        switch style {
        case .primary: .appPrimary
        case .secondary: .appBackground
        case .ink: .appText
        }
    }
}

/// The one-line form of a notice (a load error): a glyph in the tone, a short text, no badge.
struct NoticeLine: View {
    let icon: String
    var tone: NoticeTone = .critical
    let text: String
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tone.color)
            Text(text)
                .font(.app(13))
                .foregroundStyle(Color.appText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(tone.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .rise(shown, y: 10, delay: 0, fade: 0.32, move: 0.32)
        .onAppear { shown = true }
    }
}
