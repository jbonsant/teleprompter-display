import Foundation
import XCTest
@testable import TeleprompterDomain

final class PresentationBundleTests: XCTestCase {
    func testStubBundleRoundTripsThroughJSON() throws {
        var bundle = PresentationBundle.stub(source: "presentation-script.md", rawScript: "# GPSN\nBonjour")
        bundle.generatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try assertJSONRoundTrip(bundle)
    }

    func testGoldenFixtureBundleRoundTripsThroughJSON() throws {
        let bundle = try loadGoldenBundle()
        try assertJSONRoundTrip(bundle)
    }

    func testStandaloneDomainTypesRoundTripThroughJSON() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let fixedUUID = try XCTUnwrap(UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF"))

        let section = PresentationSection(
            id: "section-intro",
            title: "Introduction",
            segmentIDs: ["segment-intro"]
        )
        let block = DisplayBlock(
            id: "display-intro",
            text: "Bonjour a toutes et a tous.",
            segmentID: "segment-intro",
            sectionID: "section-intro"
        )
        let segment = SpokenSegment(
            id: "segment-intro",
            text: "Bonjour a toutes et a tous et merci de votre accueil.",
            sectionID: "section-intro"
        )
        let marker = SlideMarker(
            id: "slide-intro",
            index: 1,
            targetSegmentID: "segment-intro",
            sectionID: "section-intro"
        )
        let bookmark = Bookmark(
            id: "bookmark-intro",
            title: "Introduction",
            targetSegmentID: "segment-intro",
            sectionID: "section-intro"
        )
        let anchor = AnchorPhrase(
            id: "anchor-intro",
            segmentID: "segment-intro",
            sectionID: "section-intro",
            text: "merci de votre accueil"
        )
        let asrOutput = ASROutput(
            hypothesisText: "bonjour a toutes",
            confirmedText: "bonjour a toutes et a tous",
            audioStartSeconds: 0.0,
            audioEndSeconds: 2.5
        )
        let candidate = AlignmentCandidateScore(segmentID: "segment-intro", score: 0.92)
        let frame = AlignmentFrame(
            confirmedContext: ["bonjour", "accueil"],
            candidateScores: [candidate],
            chosenSegmentID: "segment-intro",
            confidence: 0.92,
            debounceCount: 2
        )
        let event = DiagnosticEvent(
            timestamp: fixedDate,
            eventType: .manualJump,
            payload: ["segmentID": "segment-intro"]
        )
        let preflight = PreflightResult(
            checkName: "audio-input",
            passed: true,
            detail: "Microphone detected."
        )
        let log = SessionLog(
            sessionID: fixedUUID,
            startedAt: fixedDate,
            events: [event]
        )

        try assertJSONRoundTrip(section)
        try assertJSONRoundTrip(block)
        try assertJSONRoundTrip(segment)
        try assertJSONRoundTrip(marker)
        try assertJSONRoundTrip(bookmark)
        try assertJSONRoundTrip(anchor)
        try assertJSONRoundTrip(SessionState.liveAuto)
        try assertJSONRoundTrip(asrOutput)
        try assertJSONRoundTrip(candidate)
        try assertJSONRoundTrip(frame)
        try assertJSONRoundTrip(DiagnosticEventType.manualJump)
        try assertJSONRoundTrip(event)
        try assertJSONRoundTrip(preflight)
        try assertJSONRoundTrip(log)
    }

    func testGoldenFixtureHasStableUniqueIDsAndValidCrossReferences() throws {
        let bundle = try loadGoldenBundle()
        let sectionsByID = Dictionary(uniqueKeysWithValues: bundle.sections.map { ($0.id, $0) })
        let segmentsByID = Dictionary(uniqueKeysWithValues: bundle.spokenSegments.map { ($0.id, $0) })

        XCTAssertTrue((5...10).contains(bundle.sections.count))

        assertUnique(bundle.sections.map(\.id), label: "section")
        assertUnique(bundle.displayBlocks.map(\.id), label: "display block")
        assertUnique(bundle.spokenSegments.map(\.id), label: "spoken segment")
        assertUnique(bundle.slideMarkers.map(\.id), label: "slide marker")
        assertUnique(bundle.bookmarks.map(\.id), label: "bookmark")
        assertUnique(bundle.anchorPhrases.map(\.id), label: "anchor phrase")

        let allEntityIDs = bundle.sections.map(\.id)
            + bundle.displayBlocks.map(\.id)
            + bundle.spokenSegments.map(\.id)
            + bundle.slideMarkers.map(\.id)
            + bundle.bookmarks.map(\.id)
            + bundle.anchorPhrases.map(\.id)
        assertUnique(allEntityIDs, label: "bundle-wide entity")

        for section in bundle.sections {
            XCTAssertFalse(section.segmentIDs.isEmpty)

            for segmentID in section.segmentIDs {
                let segment = try XCTUnwrap(segmentsByID[segmentID])
                XCTAssertEqual(segment.sectionID, section.id)
            }
        }

        for block in bundle.displayBlocks {
            let segment = try XCTUnwrap(segmentsByID[block.segmentID])
            XCTAssertNotNil(sectionsByID[block.sectionID])
            XCTAssertEqual(block.sectionID, segment.sectionID)
            XCTAssertFalse(block.text.isEmpty)
        }

        for marker in bundle.slideMarkers {
            let segment = try XCTUnwrap(segmentsByID[marker.targetSegmentID])
            XCTAssertNotNil(sectionsByID[marker.sectionID])
            XCTAssertEqual(marker.sectionID, segment.sectionID)
        }

        for bookmark in bundle.bookmarks {
            let segment = try XCTUnwrap(segmentsByID[bookmark.targetSegmentID])
            XCTAssertNotNil(sectionsByID[bookmark.sectionID])
            XCTAssertEqual(bookmark.sectionID, segment.sectionID)
        }

        for anchor in bundle.anchorPhrases {
            let segment = try XCTUnwrap(segmentsByID[anchor.segmentID])
            XCTAssertNotNil(sectionsByID[anchor.sectionID])
            XCTAssertEqual(anchor.sectionID, segment.sectionID)
            XCTAssertFalse(anchor.text.isEmpty)
        }

        let script = try String(contentsOf: presentationScriptURL, encoding: .utf8)
        XCTAssertEqual(bundle.sourceHash, PresentationBundle.hash(script))
    }

    func testSessionLogAppendsEvents() {
        var log = SessionLog()
        XCTAssertTrue(log.events.isEmpty)

        log.append(DiagnosticEvent(eventType: .stateTransition, payload: ["to": SessionState.ready.rawValue]))
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.events[0].eventType, .stateTransition)
    }

    func testSessionStateIncludesLiveModes() {
        XCTAssertTrue(SessionState.allCases.contains(.liveAuto))
        XCTAssertTrue(SessionState.allCases.contains(.manualScroll))
        XCTAssertTrue(SessionState.allCases.contains(.recoveringLocal))
    }
}

private extension PresentationBundleTests {
    var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    var presentationScriptURL: URL {
        repoRootURL.appendingPathComponent("references/presentation-script.md")
    }

    var goldenFixtureURL: URL {
        repoRootURL.appendingPathComponent("Tests/Fixtures/golden-bundle.json")
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func loadGoldenBundle() throws -> PresentationBundle {
        let data = try Data(contentsOf: goldenFixtureURL)
        return try decoder.decode(PresentationBundle.self, from: data)
    }

    func assertJSONRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    func assertUnique(
        _ ids: [String],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(ids).count, ids.count, "\(label) IDs must be unique", file: file, line: line)
    }
}
