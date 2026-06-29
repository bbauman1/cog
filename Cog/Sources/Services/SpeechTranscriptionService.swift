@preconcurrency import AVFoundation
import os
import Speech
import SwiftUI

@MainActor @Observable
final class SpeechTranscriptionService {
    var transcribedText = ""
    var isTranscribing = false
    var errorMessage: String?
    var audioLevel: Float = 0

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var isInputTapInstalled = false
    private var audioLevelMeter: AudioLevelMeter?
    private var levelUpdateTask: Task<Void, Never>?
    private var transcriptionSegments: [TranscriptionSegment] = []

    private static let log = Logger(subsystem: "com.cogfordevin.ios", category: "Speech")

    var isAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    func startTranscription() async {
        guard !isTranscribing else { return }
        errorMessage = nil
        transcribedText = ""
        transcriptionSegments = []

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

        guard await requestSpeechRecognitionPermission() else {
            Self.log.warning("[mic] speech recognition permission denied")
            errorMessage = "Speech recognition access is required. Enable it in Settings > Privacy > Speech Recognition."
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

        Self.log.info("[mic] creating SpeechTranscriber")
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            try await prepareSpeechAssets(for: module, locale: locale)
        } catch {
            Self.log.error("[mic] speech asset setup failed: \(error.localizedDescription)")
            errorMessage = "Failed to prepare speech recognition: \(error.localizedDescription)"
            return
        }
        transcriber = module

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

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        Self.log.info("[mic] creating SpeechAnalyzer")
        let speechAnalyzer = SpeechAnalyzer(inputSequence: stream, modules: [module])
        analyzer = speechAnalyzer
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            Self.log.warning("[mic] SpeechAnalyzer.bestAvailableAudioFormat returned nil")
            errorMessage = "Audio input format is not supported"
            cleanup()
            return
        }
        let converter = AudioBufferConverter()

        Self.log.info("[mic] installing tap on inputNode")
        let levelMeter = AudioLevelMeter()
        audioLevelMeter = levelMeter
        let tapBlock = makeAnalyzerInputTap(
            converter: converter,
            analyzerFormat: analyzerFormat,
            continuation: continuation,
            levelMeter: levelMeter
        )
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: tapBlock)
        isInputTapInstalled = true

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

        levelUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let meter = self.audioLevelMeter else { break }
                self.audioLevel = meter.currentLevel
            }
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, !Task.isCancelled else { break }
                    self.applyTranscriptionResult(result)
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

    private func requestSpeechRecognitionPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        Self.log.info("[mic] speech authorizationStatus = \(String(describing: status))")

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let requestedStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            Self.log.info("[mic] speech authorization request result = \(String(describing: requestedStatus))")
            return requestedStatus == .authorized
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func prepareSpeechAssets(for module: SpeechTranscriber, locale: Locale) async throws {
        let installedLocales = await Set(SpeechTranscriber.installedLocales.map {
            $0.identifier(.bcp47)
        })
        let localeIdentifier = locale.identifier(.bcp47)

        guard !installedLocales.contains(localeIdentifier) else {
            Self.log.info("[mic] speech asset already installed for \(localeIdentifier)")
            return
        }

        Self.log.info("[mic] downloading speech asset for \(localeIdentifier)")
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            throw SpeechAssetError.unavailable
        }
        try await request.downloadAndInstall()
        Self.log.info("[mic] speech asset installed for \(localeIdentifier)")
    }

    private func cleanup() {
        levelUpdateTask?.cancel()
        levelUpdateTask = nil
        audioLevelMeter = nil
        audioLevel = 0

        resultsTask?.cancel()
        resultsTask = nil

        if let audioEngine {
            audioEngine.stop()
            if isInputTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isInputTapInstalled = false
            }
        }
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
        transcriptionSegments = []

        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func applyTranscriptionResult(_ result: SpeechTranscriber.Result) {
        let text = Self.plainText(from: result.text).trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            transcriptionSegments.removeAll { Self.rangesOverlap($0.range, result.range) }
            transcribedText = Self.joinedTranscript(transcriptionSegments.map(\.text))
            return
        }

        let segment = TranscriptionSegment(range: result.range, text: text)
        transcriptionSegments.removeAll { Self.rangesOverlap($0.range, result.range) }
        transcriptionSegments.append(segment)

        transcriptionSegments.sort { lhs, rhs in
            CMTimeCompare(lhs.range.start, rhs.range.start) < 0
        }
        transcribedText = Self.joinedTranscript(transcriptionSegments.map(\.text))
    }

    private static func plainText(from attributedText: AttributedString) -> String {
        String(attributedText.characters)
    }

    private static func rangesOverlap(_ lhs: CMTimeRange, _ rhs: CMTimeRange) -> Bool {
        let lhsEnd = CMTimeRangeGetEnd(lhs)
        let rhsEnd = CMTimeRangeGetEnd(rhs)
        return CMTimeCompare(lhs.start, rhsEnd) < 0 &&
            CMTimeCompare(rhs.start, lhsEnd) < 0
    }

    private static func joinedTranscript(_ segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct TranscriptionSegment {
    let range: CMTimeRange
    var text: String
}

private enum SpeechAssetError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Speech recognition language model is not available"
    }
}

private func makeAnalyzerInputTap(
    converter: AudioBufferConverter,
    analyzerFormat: AVAudioFormat,
    continuation: AsyncStream<AnalyzerInput>.Continuation,
    levelMeter: AudioLevelMeter
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        levelMeter.process(buffer)
        guard let convertedBuffer = try? converter.convert(buffer, to: analyzerFormat) else { return }
        continuation.yield(AnalyzerInput(buffer: convertedBuffer))
    }
}

private final class AudioBufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if formatsMatch(buffer.format, targetFormat) {
            return buffer
        }

        let converter = try converter(from: buffer.format, to: targetFormat)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AudioBufferConversionError.failed
        }

        var conversionError: NSError?
        let state = AudioConverterInputState(buffer: buffer)
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            state.didProvideInput = true
            outStatus.pointee = .haveData
            return state.buffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return convertedBuffer
        case .error:
            throw AudioBufferConversionError.failed
        @unknown default:
            return convertedBuffer
        }
    }

    private func converter(from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) throws -> AVAudioConverter {
        if let converter,
           let currentSourceFormat = self.sourceFormat,
           let currentTargetFormat = self.targetFormat,
           formatsMatch(currentSourceFormat, sourceFormat),
           formatsMatch(currentTargetFormat, targetFormat) {
            return converter
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioBufferConversionError.failed
        }

        self.converter = converter
        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        return converter
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.commonFormat == rhs.commonFormat &&
            lhs.isInterleaved == rhs.isInterleaved
    }
}

private enum AudioBufferConversionError: Error {
    case failed
}

private final class AudioConverterInputState: @unchecked Sendable {
    var didProvideInput = false
    let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

final class AudioLevelMeter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: Float(0))
    private static let smoothingUp: Float = 0.4
    private static let smoothingDown: Float = 0.15

    var currentLevel: Float {
        state.withLock { $0 }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sumOfSquares += s * s
        }
        let rms = sqrtf(sumOfSquares / Float(frames))
        let dbFS = 20 * log10f(max(rms, 1e-7))
        let minDB: Float = -50
        let normalized = max(0, min(1, (dbFS - minDB) / -minDB))

        state.withLock { previous in
            let alpha = normalized > previous ? Self.smoothingUp : Self.smoothingDown
            previous = previous + alpha * (normalized - previous)
        }
    }
}
