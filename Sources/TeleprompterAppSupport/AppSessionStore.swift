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

    public let referenceDirectory: URL

    public init(
        referenceDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("references"),
        sessionState: SessionState = .idle
    ) {
        self.referenceDirectory = referenceDirectory
        self.sessionState = sessionState
        self.slideCounter = "Slide 1/1"
        self.statusDetail = "Scaffold ready. Begin Task 1 and Task 2 from references/plan.md."
        self.activeSegmentTitle = "Ouverture"
        self.teleprompterBlocks = [
            "Merci de nous recevoir. Je suis Jeremie Bonsant, fondateur de Webisoft.",
            "Le GPSN est un projet de numerisation du metier notarial.",
            "Les controles manuels priment toujours sur l'alignement automatique.",
        ]
    }
}
