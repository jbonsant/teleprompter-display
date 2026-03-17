import Foundation

public struct ASRModelWarmupResult: Codable, Sendable, Equatable {
    public let modelID: String
    public let loadSeconds: TimeInterval
    public let modelDirectory: URL

    public init(modelID: String, loadSeconds: TimeInterval, modelDirectory: URL) {
        self.modelID = modelID
        self.loadSeconds = loadSeconds
        self.modelDirectory = modelDirectory
    }
}

public struct ASRMicrophoneSanityResult: Codable, Sendable, Equatable {
    public let prompt: String
    public let transcribedText: String
    public let overlapScore: Double
    public let looksFrench: Bool
    public let latencySeconds: TimeInterval

    public init(
        prompt: String,
        transcribedText: String,
        overlapScore: Double,
        looksFrench: Bool,
        latencySeconds: TimeInterval
    ) {
        self.prompt = prompt
        self.transcribedText = transcribedText
        self.overlapScore = overlapScore
        self.looksFrench = looksFrench
        self.latencySeconds = latencySeconds
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
