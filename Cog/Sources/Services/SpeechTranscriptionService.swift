import AVFoundation
import Speech
import SwiftUI

@MainActor @Observable
final class SpeechTranscriptionService {
    var transcribedText = ""
    var isTranscribing = false
    var errorMessage: String?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    var isAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    func startTranscription() async {
        guard !isTranscribing else { return }
        errorMessage = nil
        transcribedText = ""

        guard SpeechTranscriber.isAvailable else {
            errorMessage = "Speech transcription not available on this device"
            return
        }

        // Request microphone permission before accessing audio hardware
        let permissionGranted: Bool
        if AVAudioApplication.shared.recordPermission == .undetermined {
            permissionGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            permissionGranted = AVAudioApplication.shared.recordPermission == .granted
        }

        guard permissionGranted else {
            errorMessage = "Microphone access is required. Enable it in Settings > Privacy > Microphone."
            return
        }

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale.current
        ) else {
            errorMessage = "Current language not supported for transcription"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session"
            return
        }

        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        transcriber = module

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let speechAnalyzer = SpeechAnalyzer(inputSequence: stream, modules: [module])
        analyzer = speechAnalyzer

        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "Failed to start audio engine"
            cleanup()
            return
        }

        isTranscribing = true

        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, !Task.isCancelled else { break }
                    self.transcribedText = result.text.description
                }
            } catch {
                // Results stream ended or was cancelled
            }
        }
    }

    func stopTranscription() -> String {
        let finalText = transcribedText
        cleanup()
        return finalText
    }

    private func cleanup() {
        resultsTask?.cancel()
        resultsTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            let ref = analyzer
            Task { await ref.cancelAndFinishNow() }
        }
        analyzer = nil
        transcriber = nil

        isTranscribing = false
        transcribedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
