import Foundation
import TeleprompterDomain
#if canImport(WhisperKit)
import WhisperKit
#endif

public struct ASRConfiguration: Sendable, Equatable {
    public var modelID: String
    public var backupModelID: String
    public var languageCode: String
    public var useVoiceActivityDetection: Bool
    public var conditionOnPreviousText: Bool
    public var usesConfirmedStreamForAlignment: Bool
    public var allowModelDownloadIfMissing: Bool
    public var hypothesisLatencyTargetSeconds: TimeInterval
    public var confirmedLatencyTargetSeconds: TimeInterval
    public var requiredSegmentsForConfirmation: Int
    public var silenceThreshold: Float
    public var compressionCheckWindow: Int

    public init(
        modelID: String = ASRModelCatalog.primaryModelID,
        backupModelID: String = ASRModelCatalog.backupModelID,
        languageCode: String = "fr",
        useVoiceActivityDetection: Bool = true,
        conditionOnPreviousText: Bool = false,
        usesConfirmedStreamForAlignment: Bool = true,
        allowModelDownloadIfMissing: Bool = false,
        hypothesisLatencyTargetSeconds: TimeInterval = 0.45,
        confirmedLatencyTargetSeconds: TimeInterval = 1.7,
        requiredSegmentsForConfirmation: Int = 2,
        silenceThreshold: Float = 0.3,
        compressionCheckWindow: Int = 60
    ) {
        self.modelID = modelID
        self.backupModelID = backupModelID
        self.languageCode = languageCode
        self.useVoiceActivityDetection = useVoiceActivityDetection
        self.conditionOnPreviousText = conditionOnPreviousText
        self.usesConfirmedStreamForAlignment = usesConfirmedStreamForAlignment
        self.allowModelDownloadIfMissing = allowModelDownloadIfMissing
        self.hypothesisLatencyTargetSeconds = hypothesisLatencyTargetSeconds
        self.confirmedLatencyTargetSeconds = confirmedLatencyTargetSeconds
        self.requiredSegmentsForConfirmation = requiredSegmentsForConfirmation
        self.silenceThreshold = silenceThreshold
        self.compressionCheckWindow = compressionCheckWindow
    }
}

public struct AlignmentPolicy: Sendable, Equatable {
    public var minimumForwardWindowWords: Int
    public var maximumForwardWindowWords: Int
    public var confidenceThreshold: Double
    public var debounceFrames: Int

    public init(
        minimumForwardWindowWords: Int = 100,
        maximumForwardWindowWords: Int = 300,
        confidenceThreshold: Double = 0.7,
        debounceFrames: Int = 3
    ) {
        self.minimumForwardWindowWords = minimumForwardWindowWords
        self.maximumForwardWindowWords = maximumForwardWindowWords
        self.confidenceThreshold = confidenceThreshold
        self.debounceFrames = debounceFrames
    }
}

public enum SpeechAlignmentBootstrap {
    public static let guidance = "Use confirmed WhisperKit output for advancement, keep alignment forward-only, preserve manual override paths, and warm the pinned model before the presenter starts."
}
