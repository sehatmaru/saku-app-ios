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
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            transcript = ""
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
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

    private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
