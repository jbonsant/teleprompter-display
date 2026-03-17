import Foundation
import TeleprompterDomain

public struct AlignmentCandidateContext: Sendable, Equatable, Identifiable {
    public let segmentID: String
    public let segmentIndex: Int
    public let text: String
    public let score: Double

    public var id: String {
        segmentID
    }

    public init(segmentID: String, segmentIndex: Int, text: String, score: Double) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.text = text
        self.score = score
    }
}

public struct ForwardAlignmentUpdate: Sendable, Equatable {
    public let segmentID: String?
    public let segmentIndex: Int
    public let confidence: Double
    public let frame: AlignmentFrame
    public let anchorRecoveryAttempted: Bool
    public let anchorRecoverySucceeded: Bool
    public let candidateWindow: [AlignmentCandidateContext]
    public let recentConfirmedWords: [String]

    public init(
        segmentID: String?,
        segmentIndex: Int,
        confidence: Double,
        frame: AlignmentFrame,
        anchorRecoveryAttempted: Bool,
        anchorRecoverySucceeded: Bool,
        candidateWindow: [AlignmentCandidateContext],
        recentConfirmedWords: [String]
    ) {
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.confidence = confidence
        self.frame = frame
        self.anchorRecoveryAttempted = anchorRecoveryAttempted
        self.anchorRecoverySucceeded = anchorRecoverySucceeded
        self.candidateWindow = candidateWindow
        self.recentConfirmedWords = recentConfirmedWords
    }
}

public struct ForwardAligner: Sendable {
    private let bundle: PresentationBundle
    private let policy: AlignmentPolicy
    private let segmentWords: [[String]]
    private let anchorsBySegmentID: [String: [[String]]]

    private var cursorIndex: Int = 0
    private var pendingCandidateIndex: Int?
    private var debounceCount: Int = 0
    private var recentConfirmedWords: [String] = []

    public init(bundle: PresentationBundle, policy: AlignmentPolicy = AlignmentPolicy()) {
        self.bundle = bundle
        self.policy = policy
        self.segmentWords = bundle.spokenSegments.map { Self.tokenize($0.text) }
        self.anchorsBySegmentID = Dictionary(grouping: bundle.anchorPhrases, by: \.segmentID)
            .mapValues { phrases in
                phrases.map { Self.tokenize($0.text) }.filter { !$0.isEmpty }
            }
    }

    public var currentSegmentIndex: Int {
        cursorIndex
    }

    public var currentSegmentID: String? {
        bundle.spokenSegments[safe: cursorIndex]?.id
    }

    public mutating func ingestConfirmedChunk(_ chunk: ASROutput) -> ForwardAlignmentUpdate {
        let confirmedWords = Self.tokenize(chunk.confirmedText)
        if !confirmedWords.isEmpty {
            recentConfirmedWords.append(contentsOf: confirmedWords)
            if recentConfirmedWords.count > 32 {
                recentConfirmedWords.removeFirst(recentConfirmedWords.count - 32)
            }
        }

        let contextWords = Array(recentConfirmedWords.suffix(max(3, min(5, recentConfirmedWords.count))))
        let candidateIndices = buildForwardWindow()

        var scoredCandidates = candidateIndices.map { candidateIndex in
            let score = candidateScore(
                for: contextWords,
                fullConfirmedWords: confirmedWords,
                candidateIndex: candidateIndex
            )
            return (candidateIndex, score)
        }

        let bestLexicalCandidate = scoredCandidates
            .max { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 > rhs.0
                }
                return lhs.1 < rhs.1
            }
        var bestCandidate = bestLexicalCandidate
        var anchorRecoveryAttempted = false
        var anchorRecoverySucceeded = false

        if let currentBestCandidate = bestCandidate, currentBestCandidate.1 < policy.confidenceThreshold {
            anchorRecoveryAttempted = true
            let anchoredCandidates = candidateIndices.map { candidateIndex in
                let anchorScore = anchorRecoveryScore(
                    fullConfirmedWords: confirmedWords,
                    candidateIndex: candidateIndex
                )
                return (candidateIndex, max(scoredCandidates.first(where: { $0.0 == candidateIndex })?.1 ?? 0, anchorScore))
            }
            scoredCandidates = anchoredCandidates
            bestCandidate = anchoredCandidates.max { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 > rhs.0
                }
                return lhs.1 < rhs.1
            }
            anchorRecoverySucceeded = (bestCandidate?.1 ?? 0) >= policy.confidenceThreshold
        }

        let chosenCandidateIndex = bestCandidate?.0
        let chosenConfidence = bestCandidate?.1 ?? 0
        var reportedDebounceCount = debounceCount
        let candidateWindow = scoredCandidates.map { candidateIndex, score in
            AlignmentCandidateContext(
                segmentID: bundle.spokenSegments[candidateIndex].id,
                segmentIndex: candidateIndex,
                text: bundle.spokenSegments[candidateIndex].text,
                score: score
            )
        }

        if chosenConfidence >= policy.confidenceThreshold, let chosenCandidateIndex {
            if pendingCandidateIndex == chosenCandidateIndex {
                debounceCount += 1
            } else {
                pendingCandidateIndex = chosenCandidateIndex
                debounceCount = 1
            }
            reportedDebounceCount = debounceCount

            if chosenCandidateIndex > cursorIndex, debounceCount >= policy.debounceFrames {
                cursorIndex = chosenCandidateIndex
                pendingCandidateIndex = nil
                debounceCount = 0
            }
        } else {
            pendingCandidateIndex = nil
            debounceCount = 0
            reportedDebounceCount = 0
        }

        let frame = AlignmentFrame(
            confirmedContext: contextWords,
            candidateScores: scoredCandidates.map { candidateIndex, score in
                AlignmentCandidateScore(
                    segmentID: bundle.spokenSegments[candidateIndex].id,
                    score: score
                )
            },
            chosenSegmentID: chosenCandidateIndex.flatMap { bundle.spokenSegments[safe: $0]?.id },
            confidence: chosenConfidence,
            debounceCount: reportedDebounceCount
        )

        return ForwardAlignmentUpdate(
            segmentID: currentSegmentID,
            segmentIndex: cursorIndex,
            confidence: chosenConfidence,
            frame: frame,
            anchorRecoveryAttempted: anchorRecoveryAttempted,
            anchorRecoverySucceeded: anchorRecoverySucceeded,
            candidateWindow: candidateWindow,
            recentConfirmedWords: recentConfirmedWords
        )
    }

    public mutating func ingestConfirmedEvent(_ event: ASRTranscriptionEvent) -> ForwardAlignmentUpdate {
        ingestConfirmedChunk(
            ASROutput(
                hypothesisText: "",
                confirmedText: event.text,
                audioStartSeconds: event.audioStartSeconds,
                audioEndSeconds: event.audioEndSeconds
            )
        )
    }

    @discardableResult
    public mutating func manualJump(to index: Int) -> ForwardAlignmentUpdate {
        cursorIndex = min(max(index, 0), max(bundle.spokenSegments.count - 1, 0))
        pendingCandidateIndex = nil
        debounceCount = 0
        recentConfirmedWords.removeAll()

        let frame = AlignmentFrame(
            confirmedContext: [],
            candidateScores: [],
            chosenSegmentID: currentSegmentID,
            confidence: 1,
            debounceCount: 0
        )
        return ForwardAlignmentUpdate(
            segmentID: currentSegmentID,
            segmentIndex: cursorIndex,
            confidence: 1,
            frame: frame,
            anchorRecoveryAttempted: false,
            anchorRecoverySucceeded: false,
            candidateWindow: [],
            recentConfirmedWords: recentConfirmedWords
        )
    }

    private func buildForwardWindow() -> [Int] {
        guard !bundle.spokenSegments.isEmpty else { return [] }

        var indices: [Int] = []
        var totalWords = 0
        var candidateIndex = cursorIndex

        while candidateIndex < bundle.spokenSegments.count && indices.count < 4 {
            indices.append(candidateIndex)
            totalWords += segmentWords[candidateIndex].count
            candidateIndex += 1

            if totalWords >= policy.maximumForwardWindowWords {
                break
            }

            if indices.count >= 2 && totalWords >= policy.minimumForwardWindowWords {
                break
            }
        }

        return indices
    }

    private func candidateScore(
        for contextWords: [String],
        fullConfirmedWords: [String],
        candidateIndex: Int
    ) -> Double {
        let candidateWords = segmentWords[candidateIndex]
        let queryWords = contextWords.isEmpty ? fullConfirmedWords : contextWords
        guard !queryWords.isEmpty, !candidateWords.isEmpty else {
            return 0
        }

        let bigramScore = ngramScore(queryWords: queryWords, candidateWords: candidateWords, n: 2)
        let trigramScore = ngramScore(queryWords: queryWords, candidateWords: candidateWords, n: 3)
        return max(bigramScore, trigramScore, (bigramScore + trigramScore) / 2)
    }

    private func anchorRecoveryScore(fullConfirmedWords: [String], candidateIndex: Int) -> Double {
        guard
            let segmentID = bundle.spokenSegments[safe: candidateIndex]?.id,
            let anchors = anchorsBySegmentID[segmentID],
            !fullConfirmedWords.isEmpty
        else {
            return 0
        }

        return anchors.reduce(0) { best, anchorWords in
            let score = max(
                ngramScore(queryWords: fullConfirmedWords, candidateWords: anchorWords, n: 2),
                ngramScore(queryWords: fullConfirmedWords, candidateWords: anchorWords, n: 3)
            )
            return max(best, score)
        }
    }

    private func ngramScore(queryWords: [String], candidateWords: [String], n: Int) -> Double {
        let queryNgrams = Self.ngrams(from: queryWords, n: n)
        let candidateNgrams = Self.ngrams(from: candidateWords, n: n)

        guard !queryNgrams.isEmpty, !candidateNgrams.isEmpty else {
            return 0
        }

        let windows = Self.slidingWindows(source: candidateNgrams, length: queryNgrams.count)
        let bestDistance = windows.reduce(Int.max) { best, window in
            min(best, Self.levenshteinDistance(queryNgrams, window))
        }

        let normalizer = max(queryNgrams.count, windows.first?.count ?? 0, 1)
        return max(0, 1 - (Double(bestDistance) / Double(normalizer)))
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func ngrams(from words: [String], n: Int) -> [String] {
        guard words.count >= n else { return [] }
        return (0...(words.count - n)).map { offset in
            words[offset..<(offset + n)].joined(separator: " ")
        }
    }

    private static func slidingWindows(source: [String], length: Int) -> [[String]] {
        guard !source.isEmpty else { return [] }
        if source.count <= length || length <= 1 {
            return [source]
        }
        return (0...(source.count - length)).map { offset in
            Array(source[offset..<(offset + length)])
        }
    }

    private static func levenshteinDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        let lhsCount = lhs.count
        let rhsCount = rhs.count

        if lhsCount == 0 { return rhsCount }
        if rhsCount == 0 { return lhsCount }

        var previousRow = Array(0...rhsCount)
        for (lhsIndex, lhsToken) in lhs.enumerated() {
            var currentRow = [lhsIndex + 1]
            for (rhsIndex, rhsToken) in rhs.enumerated() {
                let insertion = currentRow[rhsIndex] + 1
                let deletion = previousRow[rhsIndex + 1] + 1
                let substitution = previousRow[rhsIndex] + (lhsToken == rhsToken ? 0 : 1)
                currentRow.append(min(insertion, deletion, substitution))
            }
            previousRow = currentRow
        }
        return previousRow[rhsCount]
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
