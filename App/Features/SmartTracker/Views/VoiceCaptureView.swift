import SwiftUI

/// "Mendengarkan" (design 1b, now a sheet): the sentence appears as it is spoken, with what Saku has caught so far
/// (amount, wallet, date) as chips. Stop to see the result; the keyboard button goes back to typing.
struct VoiceCaptureView: View {
    var onFinish: (String) -> Void
    var onKeyboard: () -> Void
    @StateObject private var voice = SpeechDictation()
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Nothing was heard for a few seconds (design 3b): listening stopped and the mic button offers another try.
    @State private var heardNothing = false

    private var chips: [(String, String)] {
        let text = voice.transcript.lowercased()
        guard !text.isEmpty else { return [] }
        var result: [(String, String)] = []
        if let amount = SmartParser.amount(in: text) { result.append(("banknote", amount.value.formattedAsCurrency())) }
        if let wallet = SmartParser.findWallets(in: text, accounts: store.accounts).first { result.append(("wallet.bifold", wallet.account.name)) }
        for (word, label) in [("kemarin", L("Kemarin")), ("tadi", L("Hari ini")), ("hari ini", L("Hari ini")), ("lusa", L("2 hari lalu"))] where text.contains(word) {
            result.append(("calendar", label))
            break
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(heardNothing ? Color.appTextTertiary.opacity(0.6) : Color.appError).frame(width: 9, height: 9)
                    .scaleEffect(voice.isListening ? 1.25 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(), value: voice.isListening)
                Text(heardNothing ? L("Belum terdengar apa-apa") : L("Mendengarkan"))
                    .font(.app(22, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(heardNothing ? Color.appTextTertiary : Color.appText)
            }
            // one fixed-height area: the prompt and the spoken sentence swap in place, so nothing moves or animates when words arrive
            VStack(alignment: .leading, spacing: 0) {
                if heardNothing {
                    Text(L("Coba bicara lebih dekat ke mikrofon, atau ketik saja kalimatnya."))
                        .font(.app(15)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                } else if voice.transcript.isEmpty {
                    Text(L("Sebutkan apa, berapa, dan pakai apa"))
                        .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                } else {
                    Text(voice.transcript)
                        .font(.app(26, weight: .medium)).tracking(-0.5).lineSpacing(3)
                        .foregroundStyle(Color.appText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(.top, 8)
            .transaction { $0.animation = nil }

            FlowLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 6) {
                        Image(systemName: chip.0).font(.system(size: 13, weight: .bold))
                        Text(L(chip.1)).font(.app(14, weight: .semibold))
                    }
                    .foregroundStyle(Color.stSuccessText)
                    .padding(.leading, 9).padding(.trailing, 12).frame(height: 30)
                    .background(Color.stSuccessBg, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            .padding(.top, 6)
            .transaction { $0.animation = nil }

            if let message = voice.message {
                Text(L(message)).font(.app(14)).foregroundStyle(Color.appError).padding(.top, 12)
            }

            WaveformView(isActive: voice.isListening, isFlat: heardNothing)
                .frame(height: 56).frame(maxWidth: .infinity)
                .padding(.top, 22)
            if !heardNothing, voice.transcript.isEmpty {
                Text(L("Contoh: “makan siang 45rb pakai BCA”"))
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary)
                    .frame(maxWidth: .infinity).padding(.top, 6)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filterSheet {
            SmartSheetFooter(primary: heardNothing ? L("Coba lagi") : L("Berhenti"),
                             primaryIcon: heardNothing ? "mic.fill" : "stop.fill",
                             destructive: !heardNothing,
                             secondary: L("Ketik saja"),
                             onPrimary: { if heardNothing { Task { await listen() } } else { finish() } },
                             onSecondary: { voice.stop(); onKeyboard() })
        }
        .presentationDetents([.medium, .large])
        .task { await listen() }
        .onDisappear { voice.stop() }
    }

    /// Starts the microphone; after 6 seconds without a word it stops and shows the "nothing heard" state.
    private func listen() async {
        heardNothing = false
        await voice.start()
        try? await Task.sleep(for: .seconds(6))
        if voice.isListening, voice.transcript.isEmpty, !Task.isCancelled {
            voice.stop()
            heardNothing = true
        }
    }

    private func finish() {
        let spoken = voice.transcript
        voice.stop()
        dismiss()
        if !spoken.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onFinish(spoken) }
        }
    }
}

/// Thirty bars that breathe while listening.
private struct WaveformView: View {
    let isActive: Bool
    var isFlat = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<30, id: \.self) { i in
                    let base = 0.35 + 0.65 * sin(Double(i) / 29 * .pi)
                    let wobble = isActive ? 0.5 + 0.5 * sin(t * (2 + Double(i * 37 % 7) / 3) + Double(i)) : 0.4
                    Capsule().fill(isFlat ? Color.stChip : Color.stGreen).frame(width: 4, height: isFlat ? 6 : max(6, 72 * base * wobble))
                }
            }
        }
    }
}
