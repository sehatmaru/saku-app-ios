import SwiftUI

/// Every sheet behaves like the transaction filter: as tall as its content, drag up to full, system corners and grabber.
/// The content scrolls when the sheet is shorter than it (a long list is capped at full height).
/// The action buttons go in `footer`: they stay at the bottom of the sheet and never scroll away with the content.
extension View {
    /// The gap from the buttons to the bottom edge of the screen is the same 24 pt as on their sides. The home
    /// indicator's safe area is already part of that gap, so the difference is taken off (the buttons reach into it).
    static var footerBottomPadding: CGFloat {
        let safe = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.bottom ?? 0
        return 24 - safe
    }

    /// `detent` is for sheets that also open or jump to full height from code: `.large` is full, anything else means "fits the content".
    func filterSheet(detent: Binding<PresentationDetent>? = nil) -> some View {
        ScrollView { self.reportHeight(SheetContentHeight.self) }
            .background(Color.appBackground)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .modifier(AdaptiveDetents(selection: detent))
    }

    /// `showsMoreCue` adds a fade and a down arrow above the footer while there is more content below.
    func filterSheet<Footer: View>(showsMoreCue: Bool = false, detent: Binding<PresentationDetent>? = nil, @ViewBuilder footer: () -> Footer) -> some View {
        let bar = footer()
        return ScrollView { self.reportHeight(SheetContentHeight.self) }
            .background(Color.appBackground)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .modifier(MoreCue(enabled: showsMoreCue))
            .pinnedFooter { bar }
            .modifier(AdaptiveDetents(selection: detent))
    }

    /// The footer pinned at the bottom of a sheet, 24 pt from the screen edge and from the sides.
    func pinnedFooter<Footer: View>(separator: Bool = false, @ViewBuilder _ footer: () -> Footer) -> some View {
        modifier(PinnedFooter(bar: footer(), separator: separator, initial: Self.footerBottomPadding))
    }
}

/// The home indicator's safe area counts toward the 24 pt gap, so it is read from the sheet's own geometry: reading
/// the window instead left the buttons off the screen whenever the sheet's inset differed from the window's.
private struct PinnedFooter<Bar: View>: ViewModifier {
    let bar: Bar
    let separator: Bool
    @State private var padding: CGFloat

    init(bar: Bar, separator: Bool, initial: CGFloat) {
        self.bar = bar
        self.separator = separator
        _padding = State(initialValue: initial)
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bar
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, padding)
                    .frame(maxWidth: .infinity)
                    .background(Color.appBackground)
                    .reportHeight(SheetFooterHeight.self)
                    .overlay(alignment: .top) { if separator { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { padding = 24 - proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.safeAreaInsets.bottom) { _, bottom in padding = 24 - bottom }
                }
            }
    }
}

private struct MoreCue: ViewModifier {
    let enabled: Bool
    @State private var hasMore = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height < g.contentSize.height - 1
                } action: { _, more in hasMore = more }
                .overlay(alignment: .bottom) {
                    if hasMore {
                        LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .center)
                            .frame(height: 56).allowsHitTesting(false)
                            .overlay(alignment: .bottom) {
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.appTextSecondary)
                                    .frame(width: 28, height: 28).background(Color.appFill, in: Circle()).padding(.bottom, 4)
                            }
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: hasMore)
        } else {
            content
        }
    }
}

private struct SheetContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SheetFooterHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension View {
    func reportHeight<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
        background(GeometryReader { Color.clear.preference(key: K.self, value: $0.size.height) })
    }
}

/// While the keyboard is up the sheet's content shrinks; measuring then and resizing the detent feeds back into the layout
/// and loops ("presentation preference is rapidly switching"). Measurements are ignored until the keyboard is gone.
private struct KeyboardUp: ViewModifier {
    @Binding var up: Bool
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in up = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in up = false }
    }
}

/// Detents are "fits the content" and full. The content and footer heights are measured inside the sheet; until the first
/// measurement the system's half height stands in. A sheet taller than the screen is capped at full height by the system.
private struct AdaptiveDetents: ViewModifier {
    let selection: Binding<PresentationDetent>?
    @State private var content: CGFloat = 0
    @State private var footer: CGFloat = 0
    @State private var keyboard = false

    private var adaptive: PresentationDetent? {
        guard content > 0 else { return nil }
        let safe = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.bottom ?? 0
        return .height(max(ceil(content + footer + safe), 200))
    }

    func body(content view: Content) -> some View {
        view
            .modifier(KeyboardUp(up: $keyboard))
            .onPreferenceChange(SheetContentHeight.self) { if !keyboard { content = $0 } }
            .onPreferenceChange(SheetFooterHeight.self) { if !keyboard { footer = $0 } }
            .modifier(FitDetents(fit: adaptive, selection: selection))
    }
}

/// The sheet always has a selected detent that exists in the set: while nothing is measured it is half height, then the fit
/// height replaces it in the same update. Removing the selected detent from the set made the system jump to full height.
private struct FitDetents: ViewModifier {
    let fit: PresentationDetent?
    let selection: Binding<PresentationDetent>?
    @State private var local: PresentationDetent = .medium

    func body(content: Content) -> some View {
        let wantsFull = (selection?.wrappedValue ?? local) == .large
        let current: PresentationDetent = wantsFull ? .large : (fit ?? .medium)
        content.presentationDetents([fit ?? .medium, .large], selection: Binding(
            get: { current },
            set: { new in
                let value: PresentationDetent = new == .large ? .large : .medium
                if let selection { selection.wrappedValue = value } else { local = value }
            }))
    }
}

private struct SheetClipKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// How much of the scroll content is cut off (positive) or spare (negative) at the sheet's current height.
private struct SheetScrollSlack: ViewModifier {
    @State private var clip: CGFloat?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height - $0.containerSize.height } action: { _, new in
                if clip == nil || abs((clip ?? 0) - new) >= 1 { clip = new }
            }
            .preference(key: SheetClipKey.self, value: clip)
    }
}

private struct FixedSheetDetentsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True: `adaptiveSheet` does not measure anything and the sheet simply opens at half height, one drag from full.
    var fixedSheetDetents: Bool {
        get { self[FixedSheetDetentsKey.self] }
        set { self[FixedSheetDetentsKey.self] = newValue }
    }
}

/// Fits the sheet to its content for layouts that are not built with `filterSheet`: the sheet's height now plus whatever
/// the scroll view cuts off (or has spare) is the height that fits. Until the first measurement the half height stands in.
private struct SlackDetents: ViewModifier {
    let selection: Binding<PresentationDetent>?
    @State private var total: CGFloat = 0
    @State private var clip: CGFloat?
    @State private var keyboard = false
    @Environment(\.fixedSheetDetents) private var fixed

    private var adaptive: PresentationDetent? {
        guard total > 0, let clip else { return nil }
        return .height(max(ceil(total + clip), 200))
    }

    @ViewBuilder func body(content view: Content) -> some View {
        if fixed {
            view.presentationDetents([.medium, .large])
        } else {
        view
            .modifier(KeyboardUp(up: $keyboard))
            .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: { if !keyboard { total = $0 } }
            .onPreferenceChange(SheetClipKey.self) { if !keyboard { clip = $0 } }
            .modifier(FitDetents(fit: adaptive, selection: selection))
        }
    }
}

extension View {
    /// Put on the sheet's ScrollView, together with `adaptiveSheet` on the sheet's root.
    func sheetScrollSlack() -> some View { modifier(SheetScrollSlack()) }

    /// Replaces `.presentationDetents([.medium, .large])`: as tall as the content, full height one drag away.
    /// `detent` works like in `filterSheet`: `.large` is full, anything else means "fits the content".
    func adaptiveSheet(detent: Binding<PresentationDetent>? = nil) -> some View { modifier(SlackDetents(selection: detent)) }
}
