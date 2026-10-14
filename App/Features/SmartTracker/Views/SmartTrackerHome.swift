import PhotosUI
import SwiftUI

/// Smart Tracker on Beranda (design 1a): a sparkle button with the number of drafts that opens a floating
/// bar over the tab bar: one sentence, microphone, and the "Konfirmasi transaksi" tray.
struct SmartTrackerHomeOverlay: View {
    let userId: String
    /// Nothing recorded yet (design 3a): the button pulses and a tip points at it.
    var isFresh = false
    var onOpenQueue: () -> Void
    var onToast: (String) -> Void
    @ObservedObject private var store = DraftStore.shared
    @AppStorage(SmartTrackerConsent.key) private var consented = false
    /// The tip over the button is shown until the button is first tapped, then never again.
    @AppStorage("smartTrackerTipSeen") private var tipSeen = false
    @State private var isOpen = false
    @State private var text = ""
    @State private var showsConsent = false
    @State private var showsMemoryConsent = false
    @State private var showsVoice = false
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsImageConsent = false
    /// The picture being read, shown small in the bar. Memory only; dropped when reading ends.
    @State private var thumbnail: UIImage?
    @State private var notice: ImageNotice?
    @State private var result: QuickInput?
    /// "Ulang": the sentence is back in the bar, waiting to be retyped.
    @State private var retryHint = false
    @State private var isThinking = false
    @FocusState private var focused: Bool
    /// What to do after the agreement: open the bar, or start listening.
    @State private var afterConsent: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            if isOpen { Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { close() } }
            if isFresh && !tipSeen { tip }
            fab
            bar
        }
        // fill the screen so the button and bar sit at the bottom; empty areas let touches through
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.settle(0.42), value: isOpen)
        .onReceive(NotificationCenter.default.publisher(for: .openSmartTrackerBar)) { _ in open() }
        .onAppear {
            if SmartButtonGate.shared.opensBarOnShow {
                SmartButtonGate.shared.opensBarOnShow = false
                open()
            }
        }
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: UUID(uuidString: userId)) {
                showsConsent = false
                afterConsent?()
                afterConsent = nil
            }
        }
        .sheet(isPresented: $showsMemoryConsent) { MemorySyncConsentSheet(profileId: UUID(uuidString: userId)) }
        .sheet(isPresented: $showsImageConsent) { ImageConsentSheet { afterConsent?(); afterConsent = nil } }
        .fullScreenCover(isPresented: $showsCamera) { CameraPicker { read(imageData: $0) }.ignoresSafeArea() }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { if let data = try? await item.loadTransferable(type: Data.self) { read(imageData: data) } }
        }
        .fullScreenCover(isPresented: $showsVoice) {
            VoiceCaptureView(onFinish: { spoken in submit(spoken, source: .voice) },
                             onKeyboard: { showsVoice = false; isOpen = true; focused = true })
        }
        .sheet(item: $result) { input in
            QuickResultSheet(sentence: input.sentence, source: input.source, drafts: input.drafts, userId: userId,
                             onSaved: { onToast($0) }, onSaveLater: { store.add($0) },
                             onRedo: { sentence in
                                 text = sentence
                                 retryHint = true
                                 isOpen = true
                                 focused = true
                             })
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
                .background(Color.stGreen, in: Circle())
                .shadow(color: Color.stGreen.opacity(0.35), radius: 10, y: 8)
                .background { if isFresh && !isOpen { STPulse(color: .stGreen) } }
                .overlay(alignment: .topTrailing) {
                    if !store.drafts.isEmpty {
                        Text("\(store.drafts.count)")
                            .font(.app(11, weight: .heavy))
                            .foregroundStyle(Color.stGreen)
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

    /// The speech bubble over the button in the empty Beranda (design 3a).
    private var tip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Catat pakai satu kalimat")).font(.app(15, weight: .semibold))
            Text(L("Ketuk ✦ lalu tulis “kopi 25rb gopay”. Saku yang menyusun transaksinya."))
                .font(.app(13)).lineSpacing(2).opacity(0.75)
        }
        .foregroundStyle(Color.stInkText)
        .padding(.horizontal, 16).padding(.vertical, 14).frame(width: 240, alignment: .leading)
        .background(Color.stInk, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 2).fill(Color.stInk).frame(width: 12, height: 12)
                .rotationEffect(.degrees(45)).offset(x: -22, y: 5)
        }
        .stFloat()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20).padding(.bottom, 62 + 56 + 14)
        .opacity(isOpen ? 0 : 1)
        .scaleEffect(isOpen ? 0.94 : 1, anchor: .bottomTrailing)
        .allowsHitTesting(false)
        .stEnter(2)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appText)
                    .frame(width: 50, height: 50)
            }
            .accessibilityLabel(L("Tutup"))
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Color.stGreen)
                if isThinking {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            .padding(.leading, -9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Membaca gambar…").font(.app(15, weight: .medium)).foregroundStyle(Color.stGreen)
                            Text("Gambar tidak disimpan").font(.app(12)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(text).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                            Text("Smart Tracker sedang membaca…").font(.app(12, weight: .medium)).foregroundStyle(Color.stGreen)
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    TextField(L("kopi 25rb gopay"), text: $text)
                        .font(.app(16))
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit { submit(text, source: .typed) }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { retryHint = false }
                }
                if isThinking {
                    ProgressView().frame(width: 40, height: 40)
                } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Menu {
                        Button { startImage(camera: true) } label: { Label("Kamera", systemImage: "camera") }
                        Button { startImage(camera: false) } label: { Label("Galeri", systemImage: "photo.on.rectangle") }
                    } label: {
                        Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(Color.appText)
                            .frame(width: 40, height: 40)
                            .background(Color.stRaised, in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                    }
                    .accessibilityLabel(L("Catat dari gambar"))
                    Button { startVoice() } label: {
                        Image(systemName: "mic").font(.system(size: 19)).foregroundStyle(Color.appText)
                            .frame(width: 40, height: 40)
                            .background(Color.stRaised, in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                    }
                    .accessibilityLabel(L("Catat dengan suara"))
                } else {
                    Button { submit(text, source: .typed) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Color.stGreen, in: Circle())
                    }
                    .accessibilityLabel(L("Buat draf"))
                }
            }
            .padding(.leading, 14).padding(.trailing, 5).frame(height: 50)
            .background(Color.stChip, in: Capsule())
        }
        .padding(.horizontal, 7).frame(height: 64)
        .background(Color.stBar.opacity(0.97), in: Capsule())
        .overlay(Capsule().strokeBorder(retryHint ? Color.stGreen : Color.primary.opacity(0.06), lineWidth: retryHint ? 1.5 : 1))
        .overlay(alignment: .topLeading) {
            if retryHint {
                Text("Ketik ulang kalimatmu, lalu kirim").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .padding(.leading, 8).offset(y: -26)
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 14, y: 4)
        .overlay(alignment: .bottom) {
            if let notice { noticeCard(notice).offset(y: -76).transition(.opacity.combined(with: .offset(y: 8))) }
        }
        .animation(.settle(0.3), value: notice)
        .padding(.horizontal, 20)
        // sits exactly over the system tab bar, which it replaces while open
        // over the tab bar while it rests; a little above the keyboard while typing
        .offset(y: isOpen ? (focused ? -10 : 12) : 90)
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
    }

    /// What went wrong with a picture, above the bar with the next step.
    private func noticeCard(_ n: ImageNotice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: n.icon).font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 22)
                Text(L(n.message)).font(.app(15)).lineSpacing(2).foregroundStyle(Color.appBody)
            }
            HStack(spacing: 8) {
                Button { notice = nil; n.primary { startImage(camera: $0) } } label: {
                    Text(L(n.primaryTitle)).font(.app(15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 36).background(Color.stGreen, in: Capsule())
                }
                Button { notice = nil; focused = true } label: {
                    Text("Ketik saja").font(.app(15, weight: .medium)).foregroundStyle(Color.appText)
                        .padding(.horizontal, 16).frame(height: 36)
                        .overlay(Capsule().strokeBorder(Color(light: 0xD2D2D7, dark: 0x48484A), lineWidth: 1))
                }
            }
            .padding(.leading, 34)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stBar, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 4)
    }

    // MARK: Actions

    private func open() {
        tipSeen = true
        guard consented else { afterConsent = { isOpen = true; focused = true }; showsConsent = true; return }
        isOpen = true
        focused = true
        // agreed to Smart Tracker before Ingatan could live on the server: ask about that once
        if SmartTrackerMemorySync.shouldAsk, !store.isGuest { showsMemoryConsent = true }
    }

    private func close() {
        retryHint = false
        focused = false
        isOpen = false
    }

    private func startVoice() {
        tipSeen = true
        guard consented else { afterConsent = { showsVoice = true }; showsConsent = true; return }
        focused = false
        showsVoice = true
    }

    /// Camera or gallery. Needs the Smart Tracker agreement and the short one for pictures (asked once).
    private func startImage(camera: Bool) {
        tipSeen = true
        let go = {
            guard !camera || CameraPicker.isAllowed else {
                notice = .cameraOff
                return
            }
            focused = false
            if camera { showsCamera = true } else { showsLibrary = true }
        }
        guard consented else { afterConsent = { startImage(camera: camera) }; showsConsent = true; return }
        guard SmartTrackerImageConsent.isGranted else { afterConsent = go; showsImageConsent = true; return }
        go()
    }

    /// Reads the picture on the device, then lands in the same result sheet as a sentence. The picture is dropped afterwards.
    private func read(imageData data: Data) {
        text = ""
        focused = false
        notice = nil
        thumbnail = ImageReader.downscaled(data, maxSide: 120).map { UIImage(cgImage: $0) }
        isThinking = true
        Task {
            defer { thumbnail = nil }
            let lines = ImageReader.downscaled(data) == nil ? [] : await ImageReader.lines(in: ImageReader.downscaled(data)!)
            var reading = ImageParser.parse(lines: lines, context: store.context)
            // hard case: only the text goes to the language model, when agreed, online and available
            if reading.drafts.isEmpty, !lines.isEmpty, let remote = await store.refined(lines.joined(separator: "\n"), source: .photo) {
                reading.drafts = remote
            }
            isThinking = false
            guard !reading.drafts.isEmpty else {
                notice = .unreadable
                return
            }
            close()
            result = QuickInput(sentence: "", source: .photo, drafts: reading.drafts)
            if reading.truncated {
                onToast(L("Hanya %lld transaksi pertama yang dibaca. Bagi screenshot-nya agar sisanya ikut terbaca.", ImageParser.limit))
            }
        }
    }

    /// Every sentence ends in the quick result sheet: one transaction, several, or one that could not be read.
    private func submit(_ raw: String, source: Draft.Source) {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        guard consented else { afterConsent = { submit(sentence, source: source) }; showsConsent = true; return }
        text = sentence
        retryHint = false
        focused = false
        Haptics.add()
        isThinking = true
        Task {
            let drafts = SmartTrackerHomeOverlay.parse(sentence, source: source, store: store)
            let refined = drafts.count == 1 && (drafts[0].isUnreadable || drafts[0].amount == nil)
                ? await store.refined(sentence, source: source) : nil
            isThinking = false
            let final = refined ?? drafts
            text = ""
            guard !final.isEmpty else { return }
            close()
            result = QuickInput(sentence: sentence, source: source, drafts: final)
        }
    }

    private static func parse(_ text: String, source: Draft.Source, store: DraftStore) -> [Draft] {
        SmartParser.parse(text, source: source, context: store.context)
    }
}

/// A picture that could not be used, with what to do next.
enum ImageNotice: Equatable {
    case unreadable, cameraOff

    var icon: String { self == .unreadable ? "photo.badge.exclamationmark" : "camera.fill" }
    var message: String {
        self == .unreadable ? "Gambarnya tidak terbaca. Coba foto ulang atau pilih gambar yang lebih jelas."
            : "Saku belum boleh memakai kamera. Kamu masih bisa pilih gambar dari Galeri atau ketik transaksinya."
    }
    var primaryTitle: String { self == .unreadable ? "Foto ulang" : "Pilih dari galeri" }
    func primary(_ start: (Bool) -> Void) { start(self == .unreadable) }
}

/// What the quick result sheet shows: the sentence and the drafts read from it.
struct QuickInput: Identifiable {
    let id = UUID()
    let sentence: String
    let source: Draft.Source
    let drafts: [Draft]
}

extension Notification.Name {
    /// Asks the Beranda button to open the Catat cepat bar ("Catat sekarang" in an empty Konfirmasi transaksi).
    static let openSmartTrackerBar = Notification.Name("openSmartTrackerBar")
}

/// Pages that cover the bottom of the screen (Konfirmasi transaksi, its sheets, Smart Tracker settings) hide the
/// floating sparkle button while they are open, so it never sits on top of their buttons.
@MainActor
final class SmartButtonGate: ObservableObject {
    static let shared = SmartButtonGate()
    @Published private(set) var hiders = 0
    /// Set by "Buka Smart Tracker" on an empty queue: the bar opens as soon as the button is back on Beranda.
    var opensBarOnShow = false
    func hide() { hiders += 1 }
    func show() { hiders = max(0, hiders - 1) }
}

extension View {
    func hidesSmartButton() -> some View {
        onAppear { SmartButtonGate.shared.hide() }.onDisappear { SmartButtonGate.shared.show() }
    }
}
