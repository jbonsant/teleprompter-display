import Foundation
import SwiftUI
import TeleprompterDomain

@MainActor
public final class AppSessionStore: ObservableObject {
    private struct PlaceholderSegment {
        let title: String
        let blocks: [String]
        let slideCounter: String
    }

    private let placeholderSegments: [PlaceholderSegment] = [
        PlaceholderSegment(
            title: "Ouverture",
            blocks: [
                "Merci de nous recevoir. Je suis Jeremie Bonsant, fondateur de Webisoft.",
                "Le GPSN est un projet de numerisation du metier notarial.",
                "La technologie est au service de la profession, pas l'inverse.",
            ],
            slideCounter: "Slide 0/3"
        ),
        PlaceholderSegment(
            title: "Architecture",
            blocks: [
                "Architecture tri-couche: React et TypeScript, Django, PostgreSQL.",
                "Sept services conteneurises, observabilite native, portabilite reelle.",
                "La pile reste 100 % open source et transferable.",
            ],
            slideCounter: "Slide 1/3"
        ),
        PlaceholderSegment(
            title: "Workflow",
            blocks: [
                "Le moteur orchestre la demande notariale de bout en bout.",
                "Les controles manuels priment toujours sur l'alignement automatique.",
                "Le coffre-fort devient le point d'arrivee naturel de la transaction.",
            ],
            slideCounter: "Slide 2/3"
        ),
    ]

    @Published public var sessionState: SessionState
    @Published public var slideCounter: String
    @Published public var statusDetail: String
    @Published public var activeSegmentTitle: String
    @Published public var teleprompterBlocks: [String]
    @Published public var currentSegmentIndex: Int
    @Published public var isPaused: Bool
    @Published public var isEmergencyScrolling: Bool

    public let referenceDirectory: URL

    /// Currently loaded bundle (nil until a script is compiled and loaded).
    public var bundle: PresentationBundle?

    public init(
        referenceDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("references"),
        sessionState: SessionState = .idle
    ) {
        self.referenceDirectory = referenceDirectory
        self.sessionState = sessionState
        self.slideCounter = placeholderSegments[0].slideCounter
        self.statusDetail = "Scaffold ready. Begin Task 1 and Task 2 from references/plan.md."
        self.activeSegmentTitle = placeholderSegments[0].title
        self.teleprompterBlocks = placeholderSegments[0].blocks
        self.currentSegmentIndex = 0
        self.isPaused = false
        self.isEmergencyScrolling = false
    }

    // MARK: - Keyboard actions

    public func handleTogglePause() {
        isPaused.toggle()
        if isPaused {
            sessionState = .liveFrozen
            statusDetail = "Paused"
        } else {
            sessionState = .liveAuto
            statusDetail = "Resumed"
        }
    }

    public func handleEmergencyScroll() {
        isEmergencyScrolling.toggle()
        if isEmergencyScrolling {
            sessionState = .manualScroll
            statusDetail = "Emergency scroll active"
        } else {
            sessionState = .liveAuto
            statusDetail = "Emergency scroll off"
        }
    }

    public func handleNextSegment() {
        if let bundle {
            guard currentSegmentIndex < bundle.spokenSegments.count - 1 else { return }
            currentSegmentIndex += 1
            updateDisplayFromBundle()
            statusDetail = "Manual advance to segment \(currentSegmentIndex)"
            return
        }

        guard currentSegmentIndex < placeholderSegments.count - 1 else { return }
        currentSegmentIndex += 1
        applyPlaceholderSegment(at: currentSegmentIndex)
        statusDetail = "Manual advance to placeholder segment \(currentSegmentIndex + 1)"
    }

    public func handlePreviousSegment() {
        guard currentSegmentIndex > 0 else { return }
        currentSegmentIndex -= 1

        if bundle != nil {
            updateDisplayFromBundle()
            statusDetail = "Manual rewind to segment \(currentSegmentIndex)"
            return
        }

        applyPlaceholderSegment(at: currentSegmentIndex)
        statusDetail = "Manual rewind to placeholder segment \(currentSegmentIndex + 1)"
    }

    // MARK: - Bundle display

    private func updateDisplayFromBundle() {
        guard let bundle else { return }
        let segment = bundle.spokenSegments[currentSegmentIndex]

        if let section = bundle.sections.first(where: { $0.segmentIDs.contains(segment.id) }) {
            activeSegmentTitle = section.title
        }

        let currentAndUpcoming = bundle.spokenSegments[currentSegmentIndex...].prefix(4)
        let segmentIDs = Set(currentAndUpcoming.map(\.id))
        let blocks = bundle.displayBlocks.filter { segmentIDs.contains($0.segmentID) }
        teleprompterBlocks = blocks.map { $0.text }

        let totalSlides = bundle.slideMarkers.count
        let slidesPassedCount = bundle.slideMarkers.filter { marker in
            guard let markerSegmentIdx = bundle.spokenSegments.firstIndex(where: { $0.id == marker.targetSegmentID }) else {
                return false
            }
            return markerSegmentIdx <= currentSegmentIndex
        }.count
        slideCounter = "Slide \(slidesPassedCount)/\(totalSlides)"
    }

    private func applyPlaceholderSegment(at index: Int) {
        let segment = placeholderSegments[index]
        activeSegmentTitle = segment.title
        teleprompterBlocks = segment.blocks
        slideCounter = segment.slideCounter
    }
}
