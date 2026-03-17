import Foundation

public struct CloudRecoveryCandidate: Codable, Sendable, Equatable, Identifiable {
    public let segmentID: String
    public let segmentIndex: Int
    public let text: String

    public var id: String {
        segmentID
    }

    public init(segmentID: String, segmentIndex: Int, text: String) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.text = text
    }
}

public struct CloudRecoveryRequest: Codable, Sendable, Equatable {
    public let recentConfirmedWords: [String]
    public let candidates: [CloudRecoveryCandidate]

    public init(recentConfirmedWords: [String], candidates: [CloudRecoveryCandidate]) {
        self.recentConfirmedWords = recentConfirmedWords
        self.candidates = candidates
    }
}

public struct CloudRecoveryResolution: Codable, Sendable, Equatable {
    public let targetSegmentID: String?
    public let confidence: Double

    public init(targetSegmentID: String?, confidence: Double) {
        self.targetSegmentID = targetSegmentID
        self.confidence = confidence
    }
}

public protocol CloudRecoveryClientProtocol: Sendable {
    func resolveTarget(apiKey: String, request: CloudRecoveryRequest) async throws -> CloudRecoveryResolution
}

public enum CloudRecoveryClientError: LocalizedError {
    case invalidResponse
    case missingContent
    case invalidConfidence(Double)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Groq returned an invalid recovery payload."
        case .missingContent:
            return "Groq returned an empty recovery response."
        case let .invalidConfidence(confidence):
            return "Groq returned an out-of-range confidence value: \(confidence)."
        case let .transport(message):
            return message
        }
    }
}

public struct GroqCloudRecoveryClient: CloudRecoveryClientProtocol {
    public let modelName: String
    public let endpoint: URL
    public let timeoutSeconds: TimeInterval
    public let maxRetryCount: Int
    private let session: URLSession

    public init(
        modelName: String = "llama-3.3-70b-versatile",
        endpoint: URL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
        timeoutSeconds: TimeInterval = 10,
        maxRetryCount: Int = 1,
        session: URLSession = .shared
    ) {
        self.modelName = modelName
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.maxRetryCount = maxRetryCount
        self.session = session
    }

    public func resolveTarget(apiKey: String, request: CloudRecoveryRequest) async throws -> CloudRecoveryResolution {
        var lastError: Error?

        for attempt in 0...maxRetryCount {
            do {
                let payload = try await performRequest(apiKey: apiKey, request: request)
                return payload
            } catch {
                lastError = error
                guard attempt < maxRetryCount else { break }
            }
        }

        throw lastError ?? CloudRecoveryClientError.invalidResponse
    }

    private func performRequest(apiKey: String, request: CloudRecoveryRequest) async throws -> CloudRecoveryResolution {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(GroqRequest(model: modelName, request: request))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudRecoveryClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw CloudRecoveryClientError.transport("Groq request failed: \(message)")
        }

        let decoded = try JSONDecoder().decode(GroqResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw CloudRecoveryClientError.missingContent
        }

        guard let contentData = content.data(using: .utf8) else {
            throw CloudRecoveryClientError.invalidResponse
        }

        let resolution = try JSONDecoder().decode(CloudRecoveryResolution.self, from: contentData)
        guard (0...1).contains(resolution.confidence) else {
            throw CloudRecoveryClientError.invalidConfidence(resolution.confidence)
        }
        return resolution
    }
}

private struct GroqRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let temperature: Double
    let max_tokens: Int
    let response_format: ResponseFormat
    let messages: [Message]

    init(model: String, request: CloudRecoveryRequest) {
        let systemPrompt = "You recover a teleprompter cursor. Choose one candidate segment from the provided forward-only window. Return JSON only with targetSegmentID and confidence."
        let userPrompt = Self.userPrompt(for: request)

        self.model = model
        self.temperature = 0
        self.max_tokens = 80
        self.response_format = ResponseFormat(type: "json_object")
        self.messages = [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: userPrompt),
        ]
    }

    private static func userPrompt(for request: CloudRecoveryRequest) -> String {
        let recentWords = request.recentConfirmedWords.joined(separator: " ")
        let candidates = request.candidates
            .map { "- \($0.segmentID) [\($0.segmentIndex)]: \($0.text)" }
            .joined(separator: "\n")

        return """
        Recent confirmed words:
        \(recentWords)

        Candidate forward window:
        \(candidates)

        Return a JSON object like {"targetSegmentID":"segment-id","confidence":0.84}.
        If no candidate is defensible, return {"targetSegmentID":null,"confidence":0.0}.
        """
    }
}

private struct GroqResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
