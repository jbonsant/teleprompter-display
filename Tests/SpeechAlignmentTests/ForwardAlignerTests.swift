import XCTest
@testable import SpeechAlignment
@testable import TeleprompterDomain

final class ForwardAlignerTests: XCTestCase {
    func testExactMatchAdvancesAfterThreeAgreements() {
        let bundle = makeBundle(
            segments: [
                "bonjour et merci de nous recevoir aujourd hui",
                "react typescript django et postgresql structurent l architecture",
                "le moteur de workflow orchestre chaque demande notariale",
            ]
        )
        var aligner = ForwardAligner(bundle: bundle)

        let chunk = chunk("react typescript django et postgresql structurent l architecture")
        _ = aligner.ingestConfirmedChunk(chunk)
        _ = aligner.ingestConfirmedChunk(chunk)
        let update = aligner.ingestConfirmedChunk(chunk)

        XCTAssertEqual(update.segmentIndex, 1)
        XCTAssertEqual(update.segmentID, "segment-2")
        XCTAssertGreaterThan(update.confidence, 0.7)
    }

    func testParaphraseStillAdvancesWithinForwardWindow() {
        let bundle = makeBundle(
            segments: [
                "merci de nous recevoir aujourd hui",
                "la technologie est au service de la profession et du notaire",
                "le coffre fort devient le point d arrivee naturel",
            ]
        )
        var aligner = ForwardAligner(bundle: bundle)

        let paraphraseChunk = chunk("la technologie reste au service de la profession et du notaire")
        _ = aligner.ingestConfirmedChunk(paraphraseChunk)
        _ = aligner.ingestConfirmedChunk(paraphraseChunk)
        let update = aligner.ingestConfirmedChunk(paraphraseChunk)

        XCTAssertEqual(update.segmentIndex, 1)
        XCTAssertEqual(update.segmentID, "segment-2")
        XCTAssertGreaterThan(update.confidence, 0.7)
    }

    func testSkippedSectionCanJumpForwardWithoutMovingBackward() {
        let bundle = makeBundle(
            segments: [
                "ouverture et cadrage initial",
                "section sur l architecture logicielle modulaire",
                "le moteur de workflow orchestre une demande notariale de bout en bout",
                "les notifications suivent chaque changement etape",
            ]
        )
        var aligner = ForwardAligner(bundle: bundle)

        let skippedChunk = chunk("le moteur de workflow orchestre une demande notariale de bout en bout")
        _ = aligner.ingestConfirmedChunk(skippedChunk)
        _ = aligner.ingestConfirmedChunk(skippedChunk)
        let update = aligner.ingestConfirmedChunk(skippedChunk)

        XCTAssertEqual(update.segmentIndex, 2)
        XCTAssertEqual(update.segmentID, "segment-3")
    }

    func testRepeatedPhrasePrefersNearestForwardCandidate() {
        let bundle = makeBundle(
            segments: [
                "ouverture generale du dossier",
                "le coffre fort numerique centralise chaque transaction",
                "les notifications suivent l etat du dossier",
                "audit et supervision de la plateforme",
                "le coffre fort numerique archive les pieces finales",
            ]
        )
        var aligner = ForwardAligner(bundle: bundle)
        _ = aligner.manualJump(to: 1)

        let repeatedChunk = chunk("le coffre fort numerique centralise chaque transaction")
        _ = aligner.ingestConfirmedChunk(repeatedChunk)
        _ = aligner.ingestConfirmedChunk(repeatedChunk)
        let update = aligner.ingestConfirmedChunk(repeatedChunk)

        XCTAssertEqual(update.segmentIndex, 1)
        XCTAssertEqual(update.frame.chosenSegmentID, "segment-2")
    }

    func testManualJumpResetsDebounceAndWindow() {
        let bundle = makeBundle(
            segments: [
                "ouverture generale du dossier",
                "architecture react django postgresql",
                "workflow et orchestration de la demande",
                "coffre fort numerique et archivage final",
                "questions et reponses de cloture",
            ]
        )
        var aligner = ForwardAligner(bundle: bundle)

        let architectureChunk = chunk("architecture react django postgresql")
        _ = aligner.ingestConfirmedChunk(architectureChunk)
        _ = aligner.ingestConfirmedChunk(architectureChunk)

        let jumpUpdate = aligner.manualJump(to: 3)
        XCTAssertEqual(jumpUpdate.segmentIndex, 3)
        XCTAssertEqual(jumpUpdate.frame.debounceCount, 0)

        let qnaChunk = chunk("questions et reponses de cloture")
        let firstUpdate = aligner.ingestConfirmedChunk(qnaChunk)
        XCTAssertEqual(firstUpdate.segmentIndex, 3)
        XCTAssertEqual(firstUpdate.frame.debounceCount, 1)
    }
}

private extension ForwardAlignerTests {
    func makeBundle(segments: [String]) -> PresentationBundle {
        let spokenSegments = segments.enumerated().map { index, text in
            SpokenSegment(
                id: "segment-\(index + 1)",
                text: text,
                sectionID: "section-1"
            )
        }
        let displayBlocks = segments.enumerated().map { index, text in
            DisplayBlock(
                id: "display-\(index + 1)",
                text: text,
                segmentID: "segment-\(index + 1)",
                sectionID: "section-1"
            )
        }
        let anchors = segments.enumerated().flatMap { index, text in
            let words = text.split(separator: " ").map(String.init)
            let anchorText = words.suffix(min(3, words.count)).joined(separator: " ")
            return [
                AnchorPhrase(
                    id: "anchor-\(index + 1)",
                    segmentID: "segment-\(index + 1)",
                    sectionID: "section-1",
                    text: anchorText
                )
            ]
        }

        return PresentationBundle(
            compilerVersion: "test",
            sourceHash: "hash",
            sections: [
                PresentationSection(
                    id: "section-1",
                    title: "Test",
                    segmentIDs: spokenSegments.map(\.id)
                )
            ],
            displayBlocks: displayBlocks,
            spokenSegments: spokenSegments,
            slideMarkers: [],
            bookmarks: [],
            anchorPhrases: anchors
        )
    }

    func chunk(_ text: String) -> ASROutput {
        ASROutput(
            hypothesisText: text,
            confirmedText: text,
            audioStartSeconds: 0,
            audioEndSeconds: 1.5
        )
    }
}
