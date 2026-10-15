import SwiftUI

/// "Mendengarkan" (design 1b): the sentence appears as it is spoken, with what Saku has caught so far
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
        VStack(spacing: 0) {
            HStack {
                Button { voice.stop(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.appText)
                        .frame(width: 38, height: 38).background(Color.stChip, in: Circle())
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(heardNothing ? Color.appTextTertiary.opacity(0.6) : Color.appError).frame(width: 8, height: 8)
                        .scaleEffect(voice.isListening ? 1.25 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(), value: voice.isListening)
                    Text(heardNothing ? L("Berhenti mendengarkan") : L("Mendengarkan")).font(.app(15, weight: .semibold))
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 20).padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                if heardNothing {
                    Text(L("Belum terdengar apa-apa")).foregroundStyle(Color.appTextTertiary)
                    Text(L("Coba bicara lebih dekat ke mikrofon, atau ketik saja kalimatnya."))
                        .font(.app(16, weight: .regular)).tracking(0).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
                } else if voice.transcript.isEmpty {
                    Text(L("Sebutkan apa, berapa, dan pakai apa"))
                        .foregroundStyle(Color.appTextTertiary)
                } else {
                    Text(voice.transcript)
                }
            }
            .font(.app(30, weight: .medium))
            .tracking(-0.6)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 72)
            .frame(minHeight: 220, alignment: .topLeading)

            FlowLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 6) {
                        Image(systemName: chip.0).font(.system(size: 13, weight: .bold))
                        Text(L(chip.1)).font(.app(14, weight: .semibold))
                    }
                    .foregroundStyle(Color.stSuccessText)
                    .padding(.leading, 9).padding(.trailing, 12).frame(height: 30)
                    .background(Color.stSuccessBg, in: Capsule())
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 28).padding(.top, 24).frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: chips.count)

            if let message = voice.message {
                Text(L(message)).font(.app(14)).foregroundStyle(Color.appError).padding(.horizontal, 28).padding(.top, 12)
            }
            Spacer()

            WaveformView(isActive: voice.isListening, isFlat: heardNothing)
                .frame(height: 72)
                .padding(.bottom, 24)
            Text(heardNothing ? L("Ketuk mikrofon untuk coba lagi") : L("Contoh: “makan siang 45rb pakai BCA”"))
                .font(.app(14)).foregroundStyle(Color.appTextTertiary).padding(.bottom, 40)

            HStack(spacing: 44) {
                Button { voice.stop(); onKeyboard() } label: {
                    Image(systemName: "keyboard").font(.system(size: 21)).foregroundStyle(Color.appText)
                        .frame(width: 52, height: 52).background(Color.stChip, in: Circle())
                }
                .accessibilityLabel(L("Ketik saja"))
                if heardNothing {
                    Button { Task { await listen() } } label: {
                        Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Color.stGreen, in: Circle())
                            .overlay(Circle().strokeBorder(Color.stSuccessBg, lineWidth: 6).padding(-6))
                    }
                    .accessibilityLabel(L("Coba lagi"))
                } else {
                    Button { finish() } label: {
                        RoundedRectangle(cornerRadius: 7).fill(.white).frame(width: 26, height: 26)
                            .frame(width: 76, height: 76)
                            .background(Color.appError, in: Circle())
                            .overlay(Circle().strokeBorder(Color.stDangerBg, lineWidth: 6).padding(-6))
                    }
                    .accessibilityLabel(L("Berhenti merekam"))
                }
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.bottom, 44)
        }
        .background(Color.appBackground)
        .animation(.settle(0.4), value: heardNothing)
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
