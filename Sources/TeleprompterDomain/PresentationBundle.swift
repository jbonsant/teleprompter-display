import CryptoKit
import Foundation

public struct PresentationBundle: Codable, Sendable, Equatable {
    public var bundleID: UUID
    public var compilerVersion: String
    public var sourceHash: String
    public var generatedAt: Date
    public var sections: [PresentationSection]
    public var displayBlocks: [DisplayBlock]
    public var spokenSegments: [SpokenSegment]
    public var slideMarkers: [SlideMarker]
    public var bookmarks: [Bookmark]
    public var anchorPhrases: [AnchorPhrase]

    public init(
        bundleID: UUID = UUID(),
        compilerVersion: String,
        sourceHash: String,
        generatedAt: Date = .now,
        sections: [PresentationSection],
        displayBlocks: [DisplayBlock],
        spokenSegments: [SpokenSegment],
        slideMarkers: [SlideMarker],
        bookmarks: [Bookmark],
        anchorPhrases: [AnchorPhrase]
    ) {
        self.bundleID = bundleID
        self.compilerVersion = compilerVersion
        self.sourceHash = sourceHash
        self.generatedAt = generatedAt
        self.sections = sections
        self.displayBlocks = displayBlocks
        self.spokenSegments = spokenSegments
        self.slideMarkers = slideMarkers
        self.bookmarks = bookmarks
        self.anchorPhrases = anchorPhrases
    }
}

public extension PresentationBundle {
    static func stub(source: String, rawScript: String, compilerVersion: String = "0.1.0") -> PresentationBundle {
        let section = PresentationSection(id: "section-1", title: source, segmentIDs: ["segment-1"])
        let block = DisplayBlock(id: "display-1", text: "Scaffolded teleprompter content for \(source)", segmentID: "segment-1")
        let segment = SpokenSegment(id: "segment-1", text: String(rawScript.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines), sectionID: section.id)
        let bookmark = Bookmark(id: "bookmark-start", title: "Start", targetSegmentID: segment.id)
        let marker = SlideMarker(id: "slide-1", index: 1, targetSegmentID: segment.id, label: "SLIDE")
        let anchor = AnchorPhrase(id: "anchor-1", segmentID: segment.id, text: "GPSN")

        return PresentationBundle(
            compilerVersion: compilerVersion,
            sourceHash: Self.hash(rawScript),
            sections: [section],
            displayBlocks: [block],
            spokenSegments: [segment],
            slideMarkers: [marker],
            bookmarks: [bookmark],
            anchorPhrases: [anchor]
        )
    }

    private static func hash(_ rawScript: String) -> String {
        let digest = SHA256.hash(data: Data(rawScript.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct PresentationSection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var segmentIDs: [String]

    public init(id: String, title: String, segmentIDs: [String]) {
        self.id = id
        self.title = title
        self.segmentIDs = segmentIDs
    }
}

public struct DisplayBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var segmentID: String

    public init(id: String, text: String, segmentID: String) {
        self.id = id
        self.text = text
        self.segmentID = segmentID
    }
}

public struct SpokenSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var sectionID: String

    public init(id: String, text: String, sectionID: String) {
        self.id = id
        self.text = text
        self.sectionID = sectionID
    }
}

public struct SlideMarker: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var index: Int
    public var targetSegmentID: String
    public var label: String

    public init(id: String, index: Int, targetSegmentID: String, label: String = "SLIDE") {
        self.id = id
        self.index = index
        self.targetSegmentID = targetSegmentID
        self.label = label
    }
}

public struct Bookmark: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var targetSegmentID: String

    public init(id: String, title: String, targetSegmentID: String) {
        self.id = id
        self.title = title
        self.targetSegmentID = targetSegmentID
    }
}

public struct AnchorPhrase: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var segmentID: String
    public var text: String

    public init(id: String, segmentID: String, text: String) {
        self.id = id
        self.segmentID = segmentID
        self.text = text
    }
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle
    case preflight
    case ready
    case countdown
    case liveAuto
    case liveFrozen
    case manualScroll
    case recoveringLocal
    case recoveringCloud
    case error
}

public struct ASROutput: Codable, Sendable, Equatable {
    public var hypothesisText: String
    public var confirmedText: String
    public var audioStartSeconds: TimeInterval
    public var audioEndSeconds: TimeInterval

    public init(hypothesisText: String, confirmedText: String, audioStartSeconds: TimeInterval, audioEndSeconds: TimeInterval) {
        self.hypothesisText = hypothesisText
        self.confirmedText = confirmedText
        self.audioStartSeconds = audioStartSeconds
        self.audioEndSeconds = audioEndSeconds
    }
}

public struct AlignmentCandidateScore: Codable, Sendable, Equatable {
    public var segmentID: String
    public var score: Double

    public init(segmentID: String, score: Double) {
        self.segmentID = segmentID
        self.score = score
    }
}

public struct AlignmentFrame: Codable, Sendable, Equatable {
    public var confirmedContext: [String]
    public var candidateScores: [AlignmentCandidateScore]
    public var chosenSegmentID: String?
    public var confidence: Double
    public var debounceCount: Int

    public init(
        confirmedContext: [String],
        candidateScores: [AlignmentCandidateScore],
        chosenSegmentID: String?,
        confidence: Double,
        debounceCount: Int
    ) {
        self.confirmedContext = confirmedContext
        self.candidateScores = candidateScores
        self.chosenSegmentID = chosenSegmentID
        self.confidence = confidence
        self.debounceCount = debounceCount
    }
}
