import Foundation
import TeleprompterDomain
#if canImport(WhisperKit)
import WhisperKit
#endif

public struct RehearsalTranscriptionResult: Sendable {
    public let chunks: [ASROutput]
    public let modelName: String
    public let modelDirectory: URL

    public init(chunks: [ASROutput], modelName: String, modelDirectory: URL) {
        self.chunks = chunks
        self.modelName = modelName
        self.modelDirectory = modelDirectory
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
        #if canImport(WhisperKit)
        WhisperKit.recommendedModels().default
        #else
        "openai_whisper-large-v3"
        #endif
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
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: modelDirectory,
            voiceActivityDetector: configuration.useVoiceActivityDetection ? EnergyVAD() : nil,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: allowDownload
        )
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
            modelDirectory: whisperKit.modelFolder ?? modelDirectory
        )
        #else
        throw RehearsalTranscriptionError.whisperKitUnavailable
        #endif
    }
}
