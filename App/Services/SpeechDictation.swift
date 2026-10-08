import Foundation
import Speech
import AVFoundation

/// Mic to text for "Catat cepat" (Speech framework, language follows the app). The text can be edited
/// before it is read; when permission or the language is missing, `message` says so and typing still works.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published var message: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        message = nil
        guard await Self.authorized() else {
            message = L("Izin mikrofon atau pengenalan suara belum diberikan. Aktifkan di Pengaturan, atau ketik saja.")
            return
        }
        let locale = Locale(identifier: AppLanguage.code == "en" ? "en-US" : "id-ID")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            message = L("Pengenalan suara untuk bahasa ini belum tersedia di perangkat. Ketik saja.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            Self.installTap(on: engine.inputNode, request: request)
            engine.prepare()
            try engine.start()
            transcript = ""
            isListening = true
            task = Self.recognize(with: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            message = L("Mikrofon tidak bisa dipakai sekarang. Ketik saja.")
            stop()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    // These callbacks arrive on audio and system queues. They are built in nonisolated functions on
    // purpose: a closure made inside this @MainActor class would assert main-queue isolation and crash.
    private nonisolated static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || result?.isFinal == true)
        }
    }

    private nonisolated static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
