import Foundation
import TeleprompterDomain
#if canImport(WhisperKit)
@preconcurrency import WhisperKit
#endif

public struct AudioInputDeviceDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ASRTranscriptionEvent: Codable, Sendable, Equatable {
    public let text: String
    public let audioStartSeconds: TimeInterval
    public let audioEndSeconds: TimeInterval
    public let emittedAt: Date
    public let latencySeconds: TimeInterval
    public let modelID: String

    public init(
        text: String,
        audioStartSeconds: TimeInterval,
        audioEndSeconds: TimeInterval,
        emittedAt: Date = .now,
        latencySeconds: TimeInterval,
        modelID: String
    ) {
        self.text = text
        self.audioStartSeconds = audioStartSeconds
        self.audioEndSeconds = audioEndSeconds
        self.emittedAt = emittedAt
        self.latencySeconds = latencySeconds
        self.modelID = modelID
    }
}

public struct ASRLatencySnapshot: Codable, Sendable, Equatable {
    public var hypothesisTargetSeconds: TimeInterval
    public var confirmedTargetSeconds: TimeInterval
    public var latestHypothesisLatencySeconds: TimeInterval?
    public var latestConfirmedLatencySeconds: TimeInterval?
    public var modelLoadSeconds: TimeInterval?

    public init(
        hypothesisTargetSeconds: TimeInterval,
        confirmedTargetSeconds: TimeInterval,
        latestHypothesisLatencySeconds: TimeInterval? = nil,
        latestConfirmedLatencySeconds: TimeInterval? = nil,
        modelLoadSeconds: TimeInterval? = nil
    ) {
        self.hypothesisTargetSeconds = hypothesisTargetSeconds
        self.confirmedTargetSeconds = confirmedTargetSeconds
        self.latestHypothesisLatencySeconds = latestHypothesisLatencySeconds
        self.latestConfirmedLatencySeconds = latestConfirmedLatencySeconds
        self.modelLoadSeconds = modelLoadSeconds
    }
}

public enum WhisperStreamingASRError: LocalizedError {
    case whisperKitUnavailable
    case microphonePermissionDenied
    case modelNotCached(String)
    case missingTokenizer
    case pipelineNotReady

    public var errorDescription: String? {
        switch self {
        case .whisperKitUnavailable:
            return "WhisperKit is unavailable in this build."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case let .modelNotCached(modelID):
            return "Model \(modelID) is not cached locally."
        case .missingTokenizer:
            return "WhisperKit tokenizer was unavailable after loading the model."
        case .pipelineNotReady:
            return "The streaming ASR pipeline is not ready."
        }
    }
}

private final class ProgressCallbackBridge: @unchecked Sendable {
    private let publishProgress: @Sendable (TranscriptionProgress) -> Void

    init(owner: WhisperStreamingASRService, audioEndSeconds: TimeInterval) {
        self.publishProgress = { progress in
            Task {
                await owner.onProgressCallback(progress, audioEndSeconds: audioEndSeconds)
            }
        }
    }

    func publish(_ progress: TranscriptionProgress) {
        publishProgress(progress)
    }
}

public actor WhisperStreamingASRService {
    private struct StreamingState {
        var currentFallbacks = 0
        var lastBufferSize = 0
        var lastConfirmedSegmentEndSeconds: Float = 0
        var currentText = ""
        var unconfirmedSegments: [TranscriptionSegment] = []
        var lastHypothesisText = ""
        var streamStartedAt: Date?
    }

    public let configuration: ASRConfiguration
    public let modelDirectory: URL

    private var selectedInputDeviceID: DeviceID?
    private var whisperKit: WhisperKit?
    private var audioProcessor: AudioProcessor?
    private var transcribeTask: TranscribeTask?
    private var streamingTask: Task<Void, Never>?
    private var state = StreamingState()
    private var latencySnapshot: ASRLatencySnapshot

    private var hypothesisContinuations: [UUID: AsyncStream<ASRTranscriptionEvent>.Continuation] = [:]
    private var confirmedContinuations: [UUID: AsyncStream<ASRTranscriptionEvent>.Continuation] = [:]

    public init(
        configuration: ASRConfiguration = ASRConfiguration(),
        modelDirectory: URL = RehearsalTranscriptionService.defaultModelDirectory
    ) {
        self.configuration = configuration
        self.modelDirectory = modelDirectory
        self.latencySnapshot = ASRLatencySnapshot(
            hypothesisTargetSeconds: configuration.hypothesisLatencyTargetSeconds,
            confirmedTargetSeconds: configuration.confirmedLatencyTargetSeconds
        )
    }

    public func requestMicrophonePermission() async -> Bool {
        #if canImport(WhisperKit)
        return await AudioProcessor.requestRecordPermission()
        #else
        return false
        #endif
    }

    public func availableInputDevices() -> [AudioInputDeviceDescriptor] {
        #if canImport(WhisperKit)
        return AudioProcessor.getAudioDevices().map {
            AudioInputDeviceDescriptor(id: String($0.id), name: $0.name)
        }
        #else
        return []
        #endif
    }

    public func selectedInputDeviceDescriptor() -> AudioInputDeviceDescriptor? {
        let devices = availableInputDevices()
        guard let selectedInputDeviceID else {
            return devices.first
        }
        return devices.first { $0.id == String(selectedInputDeviceID) }
    }

    public func selectInputDevice(id: String?) {
        guard
            let id,
            let parsedID = UInt32(id)
        else {
            selectedInputDeviceID = nil
            return
        }
        selectedInputDeviceID = parsedID
    }

    public func currentLatencySnapshot() -> ASRLatencySnapshot {
        latencySnapshot
    }

    public func currentModelID() -> String {
        configuration.modelID
    }

    public func hypothesisStream() -> AsyncStream<ASRTranscriptionEvent> {
        let streamID = UUID()
        return AsyncStream { continuation in
            hypothesisContinuations[streamID] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeHypothesisContinuation(streamID) }
            }
        }
    }

    public func confirmedStream() -> AsyncStream<ASRTranscriptionEvent> {
        let streamID = UUID()
        return AsyncStream { continuation in
            confirmedContinuations[streamID] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeConfirmedContinuation(streamID) }
            }
        }
    }

    public func start() async throws {
        #if canImport(WhisperKit)
        guard streamingTask == nil else { return }
        guard await requestMicrophonePermission() else {
            throw WhisperStreamingASRError.microphonePermissionDenied
        }

        let audioProcessor = AudioProcessor()
        let whisperKit = try await buildWhisperKit(audioProcessor: audioProcessor)
        guard let tokenizer = whisperKit.tokenizer else {
            throw WhisperStreamingASRError.missingTokenizer
        }

        let transcribeTask = TranscribeTask(
            currentTimings: TranscriptionTimings(),
            progress: whisperKit.progress,
            audioProcessor: audioProcessor,
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer
        )

        self.audioProcessor = audioProcessor
        self.whisperKit = whisperKit
        self.transcribeTask = transcribeTask
        self.state = StreamingState(streamStartedAt: Date())
        self.latencySnapshot.modelLoadSeconds = whisperKit.currentTimings.modelLoading

        try audioProcessor.startRecordingLive(inputDeviceID: selectedInputDeviceID) { _ in
            // AudioProcessor retains the rolling sample buffer for the decode loop.
        }

        streamingTask = Task { [configuration] in
            while !Task.isCancelled {
                do {
                    try await self.transcribeCurrentBuffer(configuration: configuration)
                } catch is CancellationError {
                    break
                } catch {
                    await self.finishStreams()
                    break
                }
            }
        }
        #else
        throw WhisperStreamingASRError.whisperKitUnavailable
        #endif
    }

    public func stop() async {
        streamingTask?.cancel()
        streamingTask = nil
        audioProcessor?.stopRecording()
        state.currentText = ""
        state.unconfirmedSegments = []
        state.lastHypothesisText = ""
    }

    private func removeHypothesisContinuation(_ streamID: UUID) {
        hypothesisContinuations.removeValue(forKey: streamID)
    }

    private func removeConfirmedContinuation(_ streamID: UUID) {
        confirmedContinuations.removeValue(forKey: streamID)
    }

    #if canImport(WhisperKit)
    private func buildWhisperKit(audioProcessor: AudioProcessor) async throws -> WhisperKit {
        if let cachedModelFolder = ModelArtifactLocator.locateModelFolder(named: configuration.modelID, in: modelDirectory) {
            let config = WhisperKitConfig(
                modelFolder: cachedModelFolder.path,
                tokenizerFolder: modelDirectory,
                audioProcessor: audioProcessor,
                voiceActivityDetector: configuration.useVoiceActivityDetection ? EnergyVAD() : nil,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
            return try await WhisperKit(config)
        }

        guard configuration.allowModelDownloadIfMissing else {
            throw WhisperStreamingASRError.modelNotCached(configuration.modelID)
        }

        let config = WhisperKitConfig(
            model: configuration.modelID,
            downloadBase: modelDirectory,
            audioProcessor: audioProcessor,
            voiceActivityDetector: configuration.useVoiceActivityDetection ? EnergyVAD() : nil,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: true
        )
        return try await WhisperKit(config)
    }

    private func transcribeCurrentBuffer(configuration: ASRConfiguration) async throws {
        guard let audioProcessor, let transcribeTask else {
            throw WhisperStreamingASRError.pipelineNotReady
        }

        let currentBuffer = Array(audioProcessor.audioSamples)
        let nextBufferSize = currentBuffer.count - state.lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)

        guard nextBufferSeconds > 1 else {
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }

        if configuration.useVoiceActivityDetection {
            let voiceDetected = AudioProcessor.isVoiceDetected(
                in: audioProcessor.relativeEnergy,
                nextBufferInSeconds: nextBufferSeconds,
                silenceThreshold: configuration.silenceThreshold
            )
            if !voiceDetected {
                try await Task.sleep(nanoseconds: 100_000_000)
                return
            }
        }

        state.lastBufferSize = currentBuffer.count

        let transcription = try await transcribeAudioSamples(
            currentBuffer,
            transcribeTask: transcribeTask,
            configuration: configuration
        )

        let previousConfirmedEnd = state.lastConfirmedSegmentEndSeconds
        let segments = transcription.segments
        var confirmedSegments: [TranscriptionSegment] = []
        var remainingSegments: [TranscriptionSegment] = []

        if segments.count > configuration.requiredSegmentsForConfirmation {
            let numberOfSegmentsToConfirm = segments.count - configuration.requiredSegmentsForConfirmation
            confirmedSegments = Array(segments.prefix(numberOfSegmentsToConfirm))
            remainingSegments = Array(segments.suffix(configuration.requiredSegmentsForConfirmation))
        } else {
            remainingSegments = segments
        }

        for segment in confirmedSegments where segment.end > previousConfirmedEnd {
            state.lastConfirmedSegmentEndSeconds = max(state.lastConfirmedSegmentEndSeconds, segment.end)
            await emitConfirmed(segment)
        }

        state.unconfirmedSegments = remainingSegments
        if let firstSegment = remainingSegments.first, let lastSegment = remainingSegments.last {
            let text = remainingSegments
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                await emitHypothesis(
                    text: text,
                    audioStartSeconds: TimeInterval(firstSegment.start),
                    audioEndSeconds: TimeInterval(lastSegment.end)
                )
            }
        }
    }

    private func transcribeAudioSamples(
        _ samples: [Float],
        transcribeTask: TranscribeTask,
        configuration: ASRConfiguration
    ) async throws -> TranscriptionResult {
        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: configuration.languageCode,
            usePrefillPrompt: true,
            detectLanguage: false,
            wordTimestamps: true,
            promptTokens: nil,
            prefixTokens: nil,
            chunkingStrategy: configuration.useVoiceActivityDetection ? .vad : ChunkingStrategy.none
        )
        options.clipTimestamps = [state.lastConfirmedSegmentEndSeconds]
        let audioEndSeconds = TimeInterval(samples.count) / TimeInterval(WhisperKit.sampleRate)
        let progressBridge = ProgressCallbackBridge(owner: self, audioEndSeconds: audioEndSeconds)

        return try await transcribeTask.run(audioArray: samples, decodeOptions: options) { progress in
            progressBridge.publish(progress)
            return WhisperStreamingASRService.shouldStopEarly(
                progress: progress,
                options: options,
                compressionCheckWindow: configuration.compressionCheckWindow
            )
        }
    }

    fileprivate func onProgressCallback(_ progress: TranscriptionProgress, audioEndSeconds: TimeInterval) async {
        let currentText = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.currentFallbacks = Int(progress.timings.totalDecodingFallbacks)
        state.currentText = currentText

        guard !currentText.isEmpty else { return }
        await emitHypothesis(
            text: currentText,
            audioStartSeconds: TimeInterval(state.lastConfirmedSegmentEndSeconds),
            audioEndSeconds: audioEndSeconds
        )
    }

    private func emitHypothesis(
        text: String,
        audioStartSeconds: TimeInterval,
        audioEndSeconds: TimeInterval
    ) async {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != state.lastHypothesisText else { return }
        state.lastHypothesisText = normalized

        let event = ASRTranscriptionEvent(
            text: normalized,
            audioStartSeconds: audioStartSeconds,
            audioEndSeconds: audioEndSeconds,
            latencySeconds: observedLatency(forAudioEnd: audioEndSeconds),
            modelID: configuration.modelID
        )
        latencySnapshot.latestHypothesisLatencySeconds = event.latencySeconds
        for continuation in hypothesisContinuations.values {
            continuation.yield(event)
        }
    }

    private func emitConfirmed(_ segment: TranscriptionSegment) async {
        let event = ASRTranscriptionEvent(
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
            audioStartSeconds: TimeInterval(segment.start),
            audioEndSeconds: TimeInterval(segment.end),
            latencySeconds: observedLatency(forAudioEnd: TimeInterval(segment.end)),
            modelID: configuration.modelID
        )
        latencySnapshot.latestConfirmedLatencySeconds = event.latencySeconds
        for continuation in confirmedContinuations.values {
            continuation.yield(event)
        }
    }

    private func observedLatency(forAudioEnd audioEndSeconds: TimeInterval) -> TimeInterval {
        guard let streamStartedAt = state.streamStartedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(streamStartedAt)
        return max(0, elapsed - audioEndSeconds)
    }

    private func finishStreams() async {
        streamingTask = nil
        audioProcessor?.stopRecording()
        for continuation in hypothesisContinuations.values {
            continuation.finish()
        }
        for continuation in confirmedContinuations.values {
            continuation.finish()
        }
        hypothesisContinuations.removeAll()
        confirmedContinuations.removeAll()
    }

    private static func shouldStopEarly(
        progress: TranscriptionProgress,
        options: DecodingOptions,
        compressionCheckWindow: Int
    ) -> Bool? {
        let currentTokens = progress.tokens
        if currentTokens.count > compressionCheckWindow {
            let checkTokens = Array(currentTokens.suffix(compressionCheckWindow))
            let compressionRatio = TextUtilities.compressionRatio(of: checkTokens)
            if compressionRatio > options.compressionRatioThreshold ?? 0 {
                return false
            }
        }
        if let avgLogprob = progress.avgLogprob, let logProbThreshold = options.logProbThreshold {
            if avgLogprob < logProbThreshold {
                return false
            }
        }
        return nil
    }
    #endif
}
