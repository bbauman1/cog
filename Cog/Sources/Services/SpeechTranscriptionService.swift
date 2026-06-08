import AVFoundation
import os
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

    private static let log = Logger(subsystem: "com.cogfordevin.ios", category: "Speech")

    var isAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    func startTranscription() async {
        guard !isTranscribing else { return }
        errorMessage = nil
        transcribedText = ""

        Self.log.info("[mic] startTranscription called")

        guard SpeechTranscriber.isAvailable else {
            Self.log.warning("[mic] SpeechTranscriber.isAvailable = false")
            errorMessage = "Speech transcription not available on this device"
            return
        }

        // Request microphone permission before accessing audio hardware
        let recordPermission = AVAudioApplication.shared.recordPermission
        Self.log.info("[mic] recordPermission = \(String(describing: recordPermission))")

        let permissionGranted: Bool
        if recordPermission == .undetermined {
            permissionGranted = await AVAudioApplication.requestRecordPermission()
            Self.log.info("[mic] permission request result = \(permissionGranted)")
        } else {
            permissionGranted = recordPermission == .granted
        }

        guard permissionGranted else {
            Self.log.warning("[mic] microphone permission denied")
            errorMessage = "Microphone access is required. Enable it in Settings > Privacy > Microphone."
            return
        }

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale.current
        ) else {
            Self.log.warning("[mic] locale not supported: \(Locale.current.identifier)")
            errorMessage = "Current language not supported for transcription"
            return
        }
        Self.log.info("[mic] using locale: \(locale.identifier)")

        // Verify audio capture hardware exists (reliable even in simulator)
        guard AVCaptureDevice.default(for: .audio) != nil else {
            Self.log.warning("[mic] AVCaptureDevice.default(for: .audio) is nil — no mic hardware")
            errorMessage = "No microphone available on this device"
            return
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            Self.log.info("[mic] audio session activated (category=playAndRecord, mode=measurement)")
        } catch {
            Self.log.error("[mic] audio session config failed: \(error.localizedDescription)")
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }

        // Double-check input availability after session activation
        guard audioSession.isInputAvailable else {
            Self.log.warning("[mic] isInputAvailable = false after activation")
            errorMessage = "No audio input available on this device"
            deactivateAudioSession()
            return
        }

        let availableInputs = audioSession.availableInputs ?? []
        Self.log.info("[mic] availableInputs = \(availableInputs.map(\.portName))")
        guard !availableInputs.isEmpty else {
            Self.log.warning("[mic] availableInputs is empty")
            errorMessage = "No audio input available on this device"
            deactivateAudioSession()
            return
        }

        // Set up audio engine — create first, validate inputNode format before
        // installing a tap, so we fail gracefully instead of crashing.
        let engine = AVAudioEngine()
        audioEngine = engine

        Self.log.info("[mic] accessing engine.inputNode")
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Self.log.info("[mic] inputNode format: sampleRate=\(format.sampleRate), channels=\(format.channelCount), interleaved=\(format.isInterleaved)")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            Self.log.warning("[mic] invalid input format — sampleRate or channelCount is 0")
            errorMessage = "Audio input format is not supported"
            audioEngine = nil
            deactivateAudioSession()
            return
        }

        // Create speech modules
        Self.log.info("[mic] creating SpeechTranscriber")
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        transcriber = module

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        Self.log.info("[mic] creating SpeechAnalyzer")
        let speechAnalyzer = SpeechAnalyzer(inputSequence: stream, modules: [module])
        analyzer = speechAnalyzer

        // Install tap with nil format — lets Core Audio pick the hardware-native
        // format, avoiding format-mismatch crashes.
        Self.log.info("[mic] installing tap on inputNode (format=nil)")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }

        engine.prepare()
        Self.log.info("[mic] engine prepared, starting…")
        do {
            try engine.start()
        } catch {
            Self.log.error("[mic] engine.start() failed: \(error.localizedDescription)")
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            cleanup()
            return
        }

        isTranscribing = true
        Self.log.info("[mic] engine running — transcription active")

        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, !Task.isCancelled else { break }
                    self.transcribedText = result.text.description
                }
                Self.log.info("[mic] results stream ended normally")
            } catch {
                Self.log.error("[mic] results stream error: \(error.localizedDescription)")
            }
        }
    }

    func stopTranscription() -> String {
        let finalText = transcribedText
        Self.log.info("[mic] stopTranscription — captured text length=\(finalText.count)")
        cleanup()
        return finalText
    }

    // MARK: - Private

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

        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
