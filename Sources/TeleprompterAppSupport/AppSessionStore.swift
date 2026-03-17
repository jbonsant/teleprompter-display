import Foundation
import SwiftUI
import TeleprompterDomain

@MainActor
public final class AppSessionStore: ObservableObject {
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
        self.slideCounter = "Slide 0/0"
        self.statusDetail = "Scaffold ready. Begin Task 1 and Task 2 from references/plan.md."
        self.activeSegmentTitle = "Ouverture"
        self.teleprompterBlocks = [
            "Merci de nous recevoir. Je suis Jeremie Bonsant, fondateur de Webisoft.",
            "Le GPSN est un projet de numerisation du metier notarial.",
            "Les controles manuels priment toujours sur l'alignement automatique.",
        ]
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
        guard let bundle, currentSegmentIndex < bundle.spokenSegments.count - 1 else { return }
        currentSegmentIndex += 1
        updateDisplayFromBundle()
        statusDetail = "Manual advance to segment \(currentSegmentIndex)"
    }

    public func handlePreviousSegment() {
        guard bundle != nil, currentSegmentIndex > 0 else { return }
        currentSegmentIndex -= 1
        updateDisplayFromBundle()
        statusDetail = "Manual rewind to segment \(currentSegmentIndex)"
    }

    // MARK: - Bundle display

    private func updateDisplayFromBundle() {
        guard let bundle else { return }
        let segment = bundle.spokenSegments[currentSegmentIndex]

        // Find the section this segment belongs to
        if let section = bundle.sections.first(where: { $0.segmentIDs.contains(segment.id) }) {
            activeSegmentTitle = section.title
        }

        // Show current and nearby display blocks
        let currentAndUpcoming = bundle.spokenSegments[currentSegmentIndex...].prefix(4)
        let segmentIDs = Set(currentAndUpcoming.map(\.id))
        let blocks = bundle.displayBlocks.filter { segmentIDs.contains($0.segmentID) }
        teleprompterBlocks = blocks.map { $0.text }

        // Update slide counter
        let totalSlides = bundle.slideMarkers.count
        let slidesPassedCount = bundle.slideMarkers.filter { marker in
            guard let markerSegmentIdx = bundle.spokenSegments.firstIndex(where: { $0.id == marker.targetSegmentID }) else {
                return false
            }
            return markerSegmentIdx <= currentSegmentIndex
        }.count
        slideCounter = "Slide \(slidesPassedCount)/\(totalSlides)"
    }
}
