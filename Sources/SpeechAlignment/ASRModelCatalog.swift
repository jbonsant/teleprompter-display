import Foundation

public enum ASRModelCatalog {
    /// Primary live model pinned after local benchmarking on the target M4 Pro machine.
    public static let primaryModelID = "openai_whisper-large-v3_turbo"

    /// Smaller recovery model kept cached in case the primary model fails to load or needs a lower-memory fallback.
    public static let backupModelID = "openai_whisper-large-v3-v20240930_turbo_632MB"

    /// Higher-quality non-turbo benchmark reference retained for comparison and future rehearsals.
    public static let qualityAlternativeModelID = "openai_whisper-large-v3"

    public static let benchmarkCandidateModelIDs = [
        primaryModelID,
        backupModelID,
        qualityAlternativeModelID,
    ]
}
