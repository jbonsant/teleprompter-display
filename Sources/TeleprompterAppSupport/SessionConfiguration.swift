import Foundation

public struct CloudRecoveryPolicy: Sendable, Equatable {
    public var enabledByDefault: Bool
    public var lowConfidenceThreshold: Double
    public var lowConfidenceWindowSeconds: TimeInterval
    public var maxRetryCount: Int
    public var modelName: String

    public init(
        enabledByDefault: Bool = false,
        lowConfidenceThreshold: Double = 0.55,
        lowConfidenceWindowSeconds: TimeInterval = 30,
        maxRetryCount: Int = 1,
        modelName: String = "llama-3.3-70b-versatile"
    ) {
        self.enabledByDefault = enabledByDefault
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.lowConfidenceWindowSeconds = lowConfidenceWindowSeconds
        self.maxRetryCount = maxRetryCount
        self.modelName = modelName
    }
}

public enum SessionConfiguration {
    public static let preflightWarmupThresholdSeconds: TimeInterval = 5
    public static let speechUpdateLatencyTargetP95Seconds: TimeInterval = 2.5
    public static let peakMemoryBudgetGigabytes: Double = 2
    public static let manualJumpResponseTargetMilliseconds: Double = 100
    public static let emergencyScrollResponseTargetMilliseconds: Double = 200
    public static let microphonePrompt = "Bonjour GPSN, nous validons la transcription francaise en direct."
}
