import Foundation

public struct EnvironmentValueResolver: Sendable {
    private let environment: [String: String]
    private let dotenvValues: [String: String]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dotenvURL: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
    ) {
        self.environment = environment
        self.dotenvValues = Self.loadDotEnvValues(from: dotenvURL)
    }

    public func value(for keys: [String]) -> String? {
        let normalizedKeys = Set(keys.map(Self.normalize))

        if let match = environment.first(where: { normalizedKeys.contains(Self.normalize($0.key)) }), !match.value.isEmpty {
            return match.value
        }

        if let match = dotenvValues.first(where: { normalizedKeys.contains(Self.normalize($0.key)) }), !match.value.isEmpty {
            return match.value
        }

        return nil
    }

    public func isConfigured(for keys: [String]) -> Bool {
        value(for: keys) != nil
    }

    private static func normalize(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: #"[^A-Za-z0-9_]+"#, with: "", options: .regularExpression)
            .uppercased()
    }

    private static func loadDotEnvValues(from url: URL?) -> [String: String] {
        guard let url, let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else {
                continue
            }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }
        return values
    }
}
