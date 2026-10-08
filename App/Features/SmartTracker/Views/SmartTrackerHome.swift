import SwiftUI

/// Smart Tracker on Beranda (design 1a): a sparkle button with the number of drafts that opens a floating
/// bar over the tab bar: one sentence, microphone, and the "Perlu dicek" tray.
struct SmartTrackerHomeOverlay: View {
    let userId: String
    var onOpenQueue: () -> Void
    var onToast: (String) -> Void
    @ObservedObject private var store = DraftStore.shared
    @AppStorage(SmartTrackerConsent.key) private var consented = false
    @State private var isOpen = false
    @State private var text = ""
    @State private var showsConsent = false
    @State private var showsVoice = false
    @State private var result: Draft?
    @State private var isThinking = false
    @FocusState private var focused: Bool
    /// What to do after the agreement: open the bar, or start listening.
    @State private var afterConsent: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            if isOpen { Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { close() } }
            fab
            bar
        }
        .animation(.settle(0.42), value: isOpen)
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: UUID(uuidString: userId)) {
                showsConsent = false
                afterConsent?()
                afterConsent = nil
            }
        }
        .fullScreenCover(isPresented: $showsVoice) {
            VoiceCaptureView(onFinish: { spoken in submit(spoken, source: .voice) },
                             onKeyboard: { showsVoice = false; isOpen = true; focused = true })
        }
        .sheet(item: $result) { draft in
            QuickResultSheet(draft: draft, userId: userId, onSaved: { onToast($0) },
                             onSaveLater: { saved in store.add([saved]); onToast(L("Masuk ke Perlu dicek")) },
                             onRedo: { isOpen = true; focused = true })
        }
        .task {
            await NotificationManager.shared.requestPermissionIfNeeded()
            await store.refreshReferenceData(userId: userId)
        }
    }

    // MARK: Button and bar

    private var fab: some View {
        Button { open() } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.appPrimary, in: Circle())
                .shadow(color: Color.appPrimary.opacity(0.35), radius: 10, y: 8)
                .overlay(alignment: .topTrailing) {
                    if !store.drafts.isEmpty {
                        Text("\(store.drafts.count)")
                            .font(.app(11, weight: .heavy))
                            .foregroundStyle(Color.appPrimary)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 2)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Catat cepat"))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20)
        .padding(.bottom, 62)
        .opacity(isOpen ? 0 : 1)
        .scaleEffect(isOpen ? 0.6 : 1)
        .allowsHitTesting(!isOpen)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appText)
                    .frame(width: 50, height: 50)
            }
            .accessibilityLabel(L("Tutup"))
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Color.appPrimary)
                TextField(L("kopi 25rb gopay"), text: $text)
                    .font(.app(16))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { submit(text, source: .typed) }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isThinking {
                    ProgressView().frame(width: 40, height: 40)
                } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { startVoice() } label: {
                        Image(systemName: "mic").font(.system(size: 19)).foregroundStyle(Color.appText)
                            .frame(width: 40, height: 40)
                            .background(Color.appBackground, in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                    }
                    .accessibilityLabel(L("Catat dengan suara"))
                } else {
                    Button { submit(text, source: .typed) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Color.appPrimary, in: Circle())
                    }
                    .accessibilityLabel(L("Buat draf"))
                }
            }
            .padding(.leading, 14).padding(.trailing, 5).frame(height: 50)
            .background(Color.appFill, in: Capsule())
            Button { close(); onOpenQueue() } label: {
                Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Color.appText)
                    .frame(width: 50, height: 50)
                    .overlay(alignment: .topTrailing) {
                        if !store.drafts.isEmpty {
                            Text("\(store.drafts.count)")
                                .font(.app(11, weight: .bold)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 2)
                                .background(Color.appPrimary, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.appBackground, lineWidth: 2))
                                .offset(x: -2, y: 2)
                        }
                    }
            }
            .accessibilityLabel(L("Perlu dicek"))
        }
        .padding(.horizontal, 7).frame(height: 64)
        .background(Color.appBackground.opacity(0.97), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.04)))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 4)
        .padding(.horizontal, 20)
        // sits exactly over the system tab bar, which it replaces while open
        .offset(y: isOpen ? 12 : 90)
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
    }

    // MARK: Actions

    private func open() {
        guard consented else { afterConsent = { isOpen = true; focused = true }; showsConsent = true; return }
        isOpen = true
        focused = true
    }

    private func close() {
        focused = false
        isOpen = false
    }

    private func startVoice() {
        guard consented else { afterConsent = { showsVoice = true }; showsConsent = true; return }
        focused = false
        showsVoice = true
    }

    /// One complete expense or income goes to the quick result sheet; anything else (several transactions,
    /// a transfer, something unreadable) goes to Perlu dicek where it can be completed.
    private func submit(_ raw: String, source: Draft.Source) {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        guard consented else { afterConsent = { submit(sentence, source: source) }; showsConsent = true; return }
        text = ""
        focused = false
        Haptics.add()
        isThinking = true
        Task {
            let drafts = SmartTrackerHomeOverlay.parse(sentence, source: source, store: store)
            let refined = drafts.count == 1 && (drafts[0].isUnreadable || drafts[0].amount == nil)
                ? await store.refined(sentence, source: source) : nil
            isThinking = false
            let final = refined ?? drafts
            if final.count == 1, let one = final.first, one.amount != nil, !one.isUnreadable,
               one.kind == .expense || one.kind == .income {
                close()
                result = one
            } else {
                store.add(final)
                close()
                onOpenQueue()
            }
        }
    }

    private static func parse(_ text: String, source: Draft.Source, store: DraftStore) -> [Draft] {
        SmartParser.parse(text, source: source, context: store.context)
    }
}
