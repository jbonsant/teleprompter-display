import Foundation
import TeleprompterDomain
#if canImport(WhisperKit)
import WhisperKit
#endif

public struct ASRConfiguration: Sendable, Equatable {
    public var languageCode: String
    public var useVoiceActivityDetection: Bool
    public var conditionOnPreviousText: Bool
    public var usesConfirmedStreamForAlignment: Bool

    public init(
        languageCode: String = "fr",
        useVoiceActivityDetection: Bool = true,
        conditionOnPreviousText: Bool = false,
        usesConfirmedStreamForAlignment: Bool = true
    ) {
        self.languageCode = languageCode
        self.useVoiceActivityDetection = useVoiceActivityDetection
        self.conditionOnPreviousText = conditionOnPreviousText
        self.usesConfirmedStreamForAlignment = usesConfirmedStreamForAlignment
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
    public static let guidance = "Use confirmed WhisperKit output for advancement, keep alignment forward-only, and preserve manual override paths."
}
