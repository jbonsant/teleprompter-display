import Foundation

public struct ASRPerformanceMetrics: Codable, Equatable, Sendable {
    public var modelLoadSeconds: TimeInterval
    public var encoderLoadSeconds: TimeInterval
    public var decoderLoadSeconds: TimeInterval
    public var tokenizerLoadSeconds: TimeInterval
    public var transcriptionLatencySeconds: TimeInterval
    public var audioDurationSeconds: TimeInterval
    public var realTimeFactor: Double
    public var speedFactor: Double

    public init(
        modelLoadSeconds: TimeInterval,
        encoderLoadSeconds: TimeInterval,
        decoderLoadSeconds: TimeInterval,
        tokenizerLoadSeconds: TimeInterval,
        transcriptionLatencySeconds: TimeInterval,
        audioDurationSeconds: TimeInterval,
        realTimeFactor: Double,
        speedFactor: Double
    ) {
        self.modelLoadSeconds = modelLoadSeconds
        self.encoderLoadSeconds = encoderLoadSeconds
        self.decoderLoadSeconds = decoderLoadSeconds
        self.tokenizerLoadSeconds = tokenizerLoadSeconds
        self.transcriptionLatencySeconds = transcriptionLatencySeconds
        self.audioDurationSeconds = audioDurationSeconds
        self.realTimeFactor = realTimeFactor
        self.speedFactor = speedFactor
    }
}
