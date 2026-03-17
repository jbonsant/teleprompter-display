import Foundation

enum ModelArtifactLocator {
    static func locateModelFolder(named modelName: String, in baseDirectory: URL) -> URL? {
        let fileManager = FileManager.default
        let knownCandidates = [
            baseDirectory.appendingPathComponent(modelName, isDirectory: true),
            baseDirectory
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(modelName, isDirectory: true),
        ]

        for candidate in knownCandidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        guard let enumerator = fileManager.enumerator(
            at: baseDirectory,
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
