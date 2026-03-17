import Foundation
import TeleprompterDomain
#if canImport(WhisperKit)
import WhisperKit
#endif

public struct RehearsalTranscriptionResult: Sendable {
    public let chunks: [ASROutput]
    public let modelName: String
    public let modelDirectory: URL
    public let performance: ASRPerformanceMetrics

    public init(
        chunks: [ASROutput],
        modelName: String,
        modelDirectory: URL,
        performance: ASRPerformanceMetrics
    ) {
        self.chunks = chunks
        self.modelName = modelName
        self.modelDirectory = modelDirectory
        self.performance = performance
    }
}

public enum RehearsalTranscriptionError: LocalizedError {
    case whisperKitUnavailable

    public var errorDescription: String? {
        switch self {
        case .whisperKitUnavailable:
            return "WhisperKit is unavailable in this build."
        }
    }
}

public struct RehearsalTranscriptionService: Sendable {
    public let configuration: ASRConfiguration
    public let modelName: String
    public let modelDirectory: URL

    public init(
        configuration: ASRConfiguration = ASRConfiguration(),
        modelName: String? = nil,
        modelDirectory: URL? = nil
    ) {
        self.configuration = configuration
        self.modelName = modelName ?? Self.defaultModelName
        self.modelDirectory = modelDirectory ?? Self.defaultModelDirectory
    }

    public static var defaultModelDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (appSupport ?? URL(fileURLWithPath: fileManager.currentDirectoryPath))
            .appendingPathComponent("TeleprompterDisplay", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    public static var defaultModelName: String {
        ASRModelCatalog.primaryModelID
    }

    public func downloadModel() async throws -> URL {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true, attributes: nil)
        #if canImport(WhisperKit)
        return try await WhisperKit.download(variant: modelName, downloadBase: modelDirectory)
        #else
        throw RehearsalTranscriptionError.whisperKitUnavailable
        #endif
    }

    public func transcribe(audioFileAt audioURL: URL, allowDownload: Bool = true) async throws -> RehearsalTranscriptionResult {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true, attributes: nil)
        #if canImport(WhisperKit)
        let config: WhisperKitConfig
        if allowDownload {
            config = WhisperKitConfig(
                model: modelName,
                downloadBase: modelDirectory,
                voiceActivityDetector: configuration.useVoiceActivityDetection ? EnergyVAD() : nil,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: true
            )
        } else if let cachedModelFolder = cachedModelFolder() {
            config = WhisperKitConfig(
                modelFolder: cachedModelFolder.path,
                tokenizerFolder: modelDirectory,
                voiceActivityDetector: configuration.useVoiceActivityDetection ? EnergyVAD() : nil,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
        } else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: modelDirectory.path,
                NSLocalizedDescriptionKey: "Cached model \(modelName) was not found at \(modelDirectory.path).",
            ])
        }
        let whisperKit = try await WhisperKit(config)
        // Leave prompt and prefix tokens unset so chunk decoding stays independent.
        let options = DecodingOptions(
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
        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let mergedResult = TranscriptionUtilities.mergeTranscriptionResults(results)
        let chunks = results
            .flatMap { $0.segments }
            .sorted { $0.start < $1.start }
            .map { segment in
                let confirmedText = segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                return ASROutput(
                    hypothesisText: confirmedText,
                    confirmedText: confirmedText,
                    audioStartSeconds: TimeInterval(segment.start),
                    audioEndSeconds: TimeInterval(segment.end)
                )
            }
            .filter { !$0.confirmedText.isEmpty }

        return RehearsalTranscriptionResult(
            chunks: chunks,
            modelName: modelName,
            modelDirectory: whisperKit.modelFolder ?? modelDirectory,
            performance: ASRPerformanceMetrics(
                modelLoadSeconds: whisperKit.currentTimings.modelLoading,
                encoderLoadSeconds: whisperKit.currentTimings.encoderLoadTime,
                decoderLoadSeconds: whisperKit.currentTimings.decoderLoadTime,
                tokenizerLoadSeconds: whisperKit.currentTimings.tokenizerLoadTime,
                transcriptionLatencySeconds: mergedResult.timings.fullPipeline,
                audioDurationSeconds: mergedResult.timings.inputAudioSeconds,
                realTimeFactor: mergedResult.timings.realTimeFactor,
                speedFactor: mergedResult.timings.speedFactor
            )
        )
        #else
        throw RehearsalTranscriptionError.whisperKitUnavailable
        #endif
    }

    private func cachedModelFolder() -> URL? {
        let fileManager = FileManager.default
        let knownCandidates = [
            modelDirectory.appendingPathComponent(modelName, isDirectory: true),
            modelDirectory
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(modelName, isDirectory: true),
        ]

        for candidate in knownCandidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        guard let enumerator = fileManager.enumerator(
            at: modelDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let candidate as URL in enumerator where candidate.lastPathComponent == modelName {
            if (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return candidate
            }
        }

        return nil
    }
}
