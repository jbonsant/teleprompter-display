import Foundation

public struct ASRModelWarmupResult: Codable, Sendable, Equatable {
    public let modelID: String
    public let loadSeconds: TimeInterval
    public let modelDirectory: URL
    public let initialLoadSeconds: TimeInterval?

    public init(modelID: String, loadSeconds: TimeInterval, modelDirectory: URL, initialLoadSeconds: TimeInterval? = nil) {
        self.modelID = modelID
        self.loadSeconds = loadSeconds
        self.modelDirectory = modelDirectory
        self.initialLoadSeconds = initialLoadSeconds
    }
}

public struct ASRMicrophoneSanityResult: Codable, Sendable, Equatable {
    public let prompt: String
    public let transcribedText: String
    public let overlapScore: Double
    public let looksFrench: Bool
    public let latencySeconds: TimeInterval
    public let source: String

    public init(
        prompt: String,
        transcribedText: String,
        overlapScore: Double,
        looksFrench: Bool,
        latencySeconds: TimeInterval,
        source: String
    ) {
        self.prompt = prompt
        self.transcribedText = transcribedText
        self.overlapScore = overlapScore
        self.looksFrench = looksFrench
        self.latencySeconds = latencySeconds
        self.source = source
    }
}

public protocol StreamingASRServiceControlling: AnyObject, Sendable {
    func requestMicrophonePermission() async -> Bool
    func availableInputDevices() async -> [AudioInputDeviceDescriptor]
    func selectedInputDeviceDescriptor() async -> AudioInputDeviceDescriptor?
    func selectInputDevice(id: String?) async
    func currentLatencySnapshot() async -> ASRLatencySnapshot
    func currentModelID() async -> String
    func hypothesisStream() async -> AsyncStream<ASRTranscriptionEvent>
    func confirmedStream() async -> AsyncStream<ASRTranscriptionEvent>
    func warmModel() async throws -> ASRModelWarmupResult
    func validateFrenchMicrophone(prompt: String, timeoutSeconds: TimeInterval) async throws -> ASRMicrophoneSanityResult
    func start() async throws
    func stop() async
}
