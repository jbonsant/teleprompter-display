import Foundation
import ScriptCompiler
import SpeechAlignment
import SwiftUI
import TeleprompterDomain

public struct TeleprompterSegmentSnapshot: Identifiable, Equatable {
    public let id: String
    public let segmentIndex: Int
    public let sectionTitle: String
    public let text: String

    public init(id: String, segmentIndex: Int, sectionTitle: String, text: String) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.sectionTitle = sectionTitle
        self.text = text
    }
}

public struct TeleprompterSlideSnapshot: Equatable {
    public let index: Int
    public let label: String

    public init(index: Int, label: String) {
        self.index = index
        self.label = label
    }
}

@MainActor
public final class AppSessionStore: ObservableObject {
    public struct ControlBookmarkSummary: Identifiable, Hashable, Sendable {
        public enum Kind: String, Sendable {
            case section
            case question
        }

        public let id: String
        public let title: String
        public let targetSegmentID: String
        public let sectionID: String
        public let segmentIndex: Int
        public let slideIndex: Int?
        public let kind: Kind
    }

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

    private let allowedTransitions: [SessionState: Set<SessionState>] = [
        .idle: [.preflight, .error],
        .preflight: [.idle, .ready, .error],
        .ready: [.preflight, .countdown, .recoveringLocal, .manualScroll, .error],
        .countdown: [.ready, .liveAuto, .manualScroll, .error],
        .liveAuto: [.liveFrozen, .manualScroll, .recoveringLocal, .recoveringCloud, .error],
        .liveFrozen: [.liveAuto, .manualScroll, .recoveringLocal, .recoveringCloud, .error],
        .manualScroll: [.liveAuto, .liveFrozen, .recoveringLocal, .recoveringCloud, .error],
        .recoveringLocal: [.liveAuto, .liveFrozen, .manualScroll, .recoveringCloud, .error],
        .recoveringCloud: [.liveAuto, .liveFrozen, .manualScroll, .recoveringLocal, .error],
        .error: [.idle, .preflight],
    ]

    @Published public var sessionState: SessionState
    @Published public var slideCounter: String
    @Published public var statusDetail: String
    @Published public var activeSegmentTitle: String
    @Published public var teleprompterBlocks: [String]
    @Published public var currentSegmentIndex: Int
    @Published public var isPaused: Bool
    @Published public var isEmergencyScrolling: Bool
    @Published public private(set) var diagnosticEvents: [DiagnosticEvent]
    @Published public private(set) var preflightResults: [PreflightResult]
    @Published public private(set) var availableAudioInputs: [AudioInputDeviceDescriptor]
    @Published public private(set) var selectedAudioInputID: String?
    @Published public private(set) var selectedAudioInputName: String
    @Published public private(set) var latestHypothesis: ASRTranscriptionEvent?
    @Published public private(set) var latestConfirmed: ASRTranscriptionEvent?
    @Published public private(set) var latencySnapshot: ASRLatencySnapshot
    @Published public private(set) var activeModelID: String
    @Published public private(set) var sessionStartedAt: Date?
    @Published public private(set) var countdownTargetDate: Date?
    @Published public private(set) var currentSegmentPreview: String
    @Published public private(set) var nextSegmentPreview: String
    @Published public private(set) var alignmentConfidence: Double
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isMirrorModeEnabled: Bool
    @Published public private(set) var teleprompterFontSize: CGFloat

    public let referenceDirectory: URL
    public private(set) var bundle: PresentationBundle?

    private let asrService: WhisperStreamingASRService
    private let modelDirectory: URL
    private var hypothesisTask: Task<Void, Never>?
    private var confirmedTask: Task<Void, Never>?
    private var sessionLog: SessionLog

    public init(
        referenceDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("references"),
        sessionState: SessionState = .idle,
        asrConfiguration: ASRConfiguration = ASRConfiguration()
    ) {
        self.referenceDirectory = referenceDirectory
        self.sessionState = sessionState
        self.slideCounter = placeholderSegments[0].slideCounter
        self.statusDetail = "Transport idle. Run preflight before going live."
        self.activeSegmentTitle = placeholderSegments[0].title
        self.teleprompterBlocks = placeholderSegments[0].blocks
        self.currentSegmentIndex = 0
        self.isPaused = false
        self.isEmergencyScrolling = false
        self.diagnosticEvents = []
        self.preflightResults = []
        self.availableAudioInputs = []
        self.selectedAudioInputID = nil
        self.selectedAudioInputName = "System Default"
        self.latestHypothesis = nil
        self.latestConfirmed = nil
        self.latencySnapshot = ASRLatencySnapshot(
            hypothesisTargetSeconds: asrConfiguration.hypothesisLatencyTargetSeconds,
            confirmedTargetSeconds: asrConfiguration.confirmedLatencyTargetSeconds
        )
        self.activeModelID = asrConfiguration.modelID
        self.sessionStartedAt = nil
        self.countdownTargetDate = nil
        self.currentSegmentPreview = placeholderSegments[0].blocks.first ?? ""
        self.nextSegmentPreview = placeholderSegments.dropFirst().first?.blocks.first ?? ""
        self.alignmentConfidence = 0
        self.lastErrorMessage = nil
        self.isMirrorModeEnabled = false
        self.teleprompterFontSize = 56
        self.sessionLog = SessionLog()
        self.asrService = WhisperStreamingASRService(configuration: asrConfiguration)
        self.modelDirectory = RehearsalTranscriptionService.defaultModelDirectory

        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .stateTransition,
                payload: [
                    "from": "uninitialized",
                    "to": sessionState.rawValue,
                    "reason": "storeInit",
                ]
            )
        )

        _ = loadReferenceBundleIfAvailable()

        Task { [weak self] in
            await self?.refreshAudioInputs()
        }
    }

    deinit {
        let asrService = asrService
        hypothesisTask?.cancel()
        confirmedTask?.cancel()
        Task {
            await asrService.stop()
        }
    }

    public var stateDisplayName: String {
        switch sessionState {
        case .idle:
            return "Idle"
        case .preflight:
            return "Preflight"
        case .ready:
            return "Ready"
        case .countdown:
            return "Countdown"
        case .liveAuto:
            return "Live Auto"
        case .liveFrozen:
            return "Frozen"
        case .manualScroll:
            return "Manual Scroll"
        case .recoveringLocal:
            return "Recovering Local"
        case .recoveringCloud:
            return "Recovering Cloud"
        case .error:
            return "Error"
        }
    }

    public var canMoveToPreviousSegment: Bool {
        currentSegmentIndex > 0
    }

    public var canMoveToNextSegment: Bool {
        currentSegmentIndex < segmentCount - 1
    }

    public var currentSegmentNumber: Int {
        guard segmentCount > 0 else { return 0 }
        return min(currentSegmentIndex + 1, segmentCount)
    }

    public var segmentPositionText: String {
        "\(currentSegmentNumber)/\(segmentCount)"
    }

    public var currentSlideNumber: Int {
        slideMetrics.current
    }

    public var totalSlideCount: Int {
        slideMetrics.total
    }

    public var attentionBorderRequired: Bool {
        sessionState == .error || sessionState == .manualScroll
    }

    public var playPauseButtonLabel: String {
        switch sessionState {
        case .ready, .countdown:
            return "Play"
        case .liveAuto, .recoveringLocal, .recoveringCloud, .manualScroll:
            return "Pause"
        case .liveFrozen:
            return "Play"
        case .idle, .preflight, .error:
            return "Play"
        }
    }

    public var freezeButtonLabel: String {
        sessionState == .liveFrozen ? "Unfreeze" : "Freeze"
    }

    public var canTriggerPlayPause: Bool {
        switch sessionState {
        case .ready, .countdown, .liveAuto, .liveFrozen, .manualScroll, .recoveringLocal, .recoveringCloud:
            return true
        case .idle, .preflight, .error:
            return false
        }
    }

    public var canTriggerFreeze: Bool {
        switch sessionState {
        case .liveAuto, .liveFrozen, .manualScroll, .recoveringLocal, .recoveringCloud:
            return true
        case .idle, .preflight, .ready, .countdown, .error:
            return false
        }
    }

    public var activeTimerDate: Date? {
        switch sessionState {
        case .countdown:
            return countdownTargetDate
        default:
            return sessionStartedAt
        }
    }

    public var bookmarkSummaries: [ControlBookmarkSummary] {
        guard let bundle else {
            return placeholderBookmarkSummaries()
        }

        let segmentIndexes = Dictionary(uniqueKeysWithValues: bundle.spokenSegments.enumerated().map { ($0.element.id, $0.offset) })
        let slideIndexBySegment = Dictionary(uniqueKeysWithValues: bundle.slideMarkers.map { ($0.targetSegmentID, $0.index) })

        return bundle.bookmarks.compactMap { bookmark in
            guard let segmentIndex = segmentIndexes[bookmark.targetSegmentID] else { return nil }
            let kind: ControlBookmarkSummary.Kind = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Q") ? .question : .section
            return ControlBookmarkSummary(
                id: bookmark.id,
                title: bookmark.title,
                targetSegmentID: bookmark.targetSegmentID,
                sectionID: bookmark.sectionID,
                segmentIndex: segmentIndex,
                slideIndex: slideIndexBySegment[bookmark.targetSegmentID],
                kind: kind
            )
        }
    }

    public var sectionBookmarks: [ControlBookmarkSummary] {
        bookmarkSummaries.filter { $0.kind == .section }
    }

    public var questionBookmarks: [ControlBookmarkSummary] {
        bookmarkSummaries.filter { $0.kind == .question }
    }

    public func isCurrentBookmark(_ bookmark: ControlBookmarkSummary) -> Bool {
        bookmark.segmentIndex == currentSegmentIndex
    }

    public func jumpToBookmark(_ bookmark: ControlBookmarkSummary) {
        jumpToSegment(index: bookmark.segmentIndex, reason: "bookmark:\(bookmark.id)")
    }

    public func reloadReferenceBundle() {
        if loadReferenceBundleIfAvailable() {
            statusDetail = "Loaded reference presentation bundle."
        } else {
            statusDetail = "No reference presentation script found."
        }
    }

    public func runPreflight() async {
        beginPreflight()
        await refreshAudioInputs()

        let microphoneGranted = await requestMicrophonePermission()
        let bundleLoaded = loadReferenceBundleIfAvailable()
        let micSelected = selectedAudioInputID != nil || !availableAudioInputs.isEmpty
        let modelCached = locateCachedModelFolder(named: activeModelID) != nil
        let promptsReady = !sectionBookmarks.isEmpty

        let results = [
            PreflightResult(
                checkName: "Presentation bundle",
                passed: bundleLoaded,
                detail: bundleLoaded ? "Reference script compiled and loaded." : "Missing presentation script in references/."
            ),
            PreflightResult(
                checkName: "Microphone permission",
                passed: microphoneGranted,
                detail: microphoneGranted ? "Capture access granted." : "Grant microphone access in System Settings."
            ),
            PreflightResult(
                checkName: "Microphone selection",
                passed: micSelected,
                detail: micSelected ? selectedAudioInputName : "No capture device detected."
            ),
            PreflightResult(
                checkName: "Pinned model cache",
                passed: modelCached,
                detail: modelCached ? activeModelID : "Pinned ASR model is not cached locally."
            ),
            PreflightResult(
                checkName: "Jump lists",
                passed: promptsReady,
                detail: promptsReady ? "\(bookmarkSummaries.count) bookmarks ready." : "Compile the reference script before going live."
            ),
        ]

        completePreflight(results)
    }

    public func handlePlayPause() {
        switch sessionState {
        case .ready:
            startCountdown()
        case .countdown:
            beginLiveAuto()
        case .liveAuto, .liveFrozen, .manualScroll, .recoveringLocal, .recoveringCloud:
            handleTogglePause()
        case .idle, .preflight, .error:
            statusDetail = "Run preflight before starting playback."
        }
    }

    public func handleFreeze() {
        switch sessionState {
        case .liveFrozen:
            transition(to: .liveAuto, reason: "Freeze released", override: true)
        case .liveAuto, .manualScroll, .recoveringLocal, .recoveringCloud:
            isEmergencyScrolling = false
            transition(to: .liveFrozen, reason: "Transport frozen", override: true)
        case .idle, .preflight, .ready, .countdown, .error:
            statusDetail = "Freeze is available after the live session starts."
        }
    }

    // MARK: - Transport state machine

    public func beginPreflight() {
        transition(to: .preflight, reason: "Preflight started")
    }

    public func completePreflight(_ results: [PreflightResult]) {
        preflightResults = results
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .preflightCheck,
                payload: [
                    "passed": String(results.allSatisfy(\.passed)),
                    "checks": String(results.count),
                ]
            )
        )

        if results.allSatisfy(\.passed) {
            transition(to: .ready, reason: "Preflight passed")
        } else {
            fail(with: "Preflight failed")
        }
    }

    public func startCountdown(seconds: TimeInterval = 3) {
        countdownTargetDate = Date().addingTimeInterval(seconds)
        transition(to: .countdown, reason: "Countdown started")
    }

    public func beginLiveAuto() {
        if sessionStartedAt == nil {
            sessionStartedAt = Date()
        }
        transition(to: .liveAuto, reason: "Automatic tracking live")
    }

    public func beginLocalRecovery(reason: String = "Local recovery requested") {
        transition(to: .recoveringLocal, reason: reason, override: true)
    }

    public func beginCloudRecovery(reason: String = "Cloud recovery requested") {
        transition(to: .recoveringCloud, reason: reason, override: true)
    }

    public func resetToIdle() {
        transition(to: .idle, reason: "Transport reset")
        sessionStartedAt = nil
        countdownTargetDate = nil
        isPaused = false
        isEmergencyScrolling = false
    }

    public func fail(with message: String) {
        lastErrorMessage = message
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .error,
                payload: ["message": message]
            )
        )
        transition(to: .error, reason: message, override: true)
    }

    // MARK: - Manual commands

    public func handleTogglePause() {
        isPaused.toggle()
        if isPaused {
            transition(to: .liveFrozen, reason: "Manual pause", override: true)
        } else if isEmergencyScrolling {
            transition(to: .manualScroll, reason: "Resume emergency scroll", override: true)
        } else {
            transition(to: .liveAuto, reason: "Manual resume", override: true)
        }
    }

    public func handleEmergencyScroll() {
        isEmergencyScrolling.toggle()
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .emergencyScroll,
                payload: ["enabled": String(isEmergencyScrolling)]
            )
        )

        if isEmergencyScrolling {
            transition(to: .manualScroll, reason: "Emergency scroll active", override: true)
        } else if isPaused {
            transition(to: .liveFrozen, reason: "Emergency scroll off", override: true)
        } else {
            transition(to: .liveAuto, reason: "Emergency scroll off", override: true)
        }
    }

    public func handleNextSegment() {
        guard canMoveToNextSegment else { return }
        currentSegmentIndex += 1
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: "nextSegment")
        transition(to: .recoveringLocal, reason: "Manual advance to segment \(currentSegmentIndex + 1)", override: true)
    }

    public func handlePreviousSegment() {
        guard canMoveToPreviousSegment else { return }
        currentSegmentIndex -= 1
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: "previousSegment")
        transition(to: .recoveringLocal, reason: "Manual rewind to segment \(currentSegmentIndex + 1)", override: true)
    }

    public func jumpToSegment(index: Int, reason: String = "manualJump") {
        guard index >= 0, index < segmentCount else { return }
        currentSegmentIndex = index
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: reason)
        transition(to: .recoveringLocal, reason: "Manual jump to segment \(index + 1)", override: true)
    }

    public func toggleMirrorMode() {
        isMirrorModeEnabled.toggle()
    }

    public func increaseTeleprompterFontSize() {
        teleprompterFontSize = min(teleprompterFontSize + 4, 96)
    }

    public func decreaseTeleprompterFontSize() {
        teleprompterFontSize = max(teleprompterFontSize - 4, 36)
    }

    // MARK: - ASR service integration

    public func refreshAudioInputs() async {
        let devices = await asrService.availableInputDevices()
        availableAudioInputs = devices

        if selectedAudioInputID == nil {
            selectedAudioInputID = devices.first?.id
            selectedAudioInputName = devices.first?.name ?? "System Default"
            await asrService.selectInputDevice(id: selectedAudioInputID)
        } else if let selected = devices.first(where: { $0.id == selectedAudioInputID }) {
            selectedAudioInputName = selected.name
        }
    }

    public func selectMicrophone(id: String?) async {
        await asrService.selectInputDevice(id: id)
        selectedAudioInputID = id
        selectedAudioInputName = availableAudioInputs.first(where: { $0.id == id })?.name ?? "System Default"
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .preflightCheck,
                payload: [
                    "selectedMicID": id ?? "default",
                    "selectedMicName": selectedAudioInputName,
                ]
            )
        )
    }

    public func requestMicrophonePermission() async -> Bool {
        let granted = await asrService.requestMicrophonePermission()
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .preflightCheck,
                payload: [
                    "check": "microphonePermission",
                    "granted": String(granted),
                ]
            )
        )
        return granted
    }

    public func startASR() async {
        bindASRStreamsIfNeeded()

        do {
            try await asrService.start()
            latencySnapshot = await asrService.currentLatencySnapshot()
            activeModelID = await asrService.currentModelID()
            statusDetail = "ASR streaming with \(activeModelID)"
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    public func stopASR() async {
        await asrService.stop()
        hypothesisTask?.cancel()
        confirmedTask?.cancel()
        hypothesisTask = nil
        confirmedTask = nil
    }

    // MARK: - Display content

    public func loadBundle(_ bundle: PresentationBundle) {
        self.bundle = bundle
        currentSegmentIndex = 0
        updateDisplayForCurrentSegment()
    }

    public var teleprompterCurrentSegmentNumber: Int {
        min(currentSegmentIndex + 1, segmentCount)
    }

    public var teleprompterSegmentCount: Int {
        segmentCount
    }

    public var teleprompterProgressFraction: Double {
        guard segmentCount > 0 else { return 0 }
        return Double(teleprompterCurrentSegmentNumber) / Double(segmentCount)
    }

    public var emergencyScrollWordsPerMinute: Double {
        145
    }

    public var emergencyScrollSegmentDuration: TimeInterval {
        guard let activeSegment = teleprompterSegment(at: currentSegmentIndex) else {
            return 2.5
        }

        let wordCount = max(activeSegment.text.split(whereSeparator: \.isWhitespace).count, 6)
        return max((Double(wordCount) / emergencyScrollWordsPerMinute) * 60.0, 2.0)
    }

    public var previousTeleprompterSegment: TeleprompterSegmentSnapshot? {
        teleprompterSegment(at: currentSegmentIndex - 1)
    }

    public var activeTeleprompterSegment: TeleprompterSegmentSnapshot? {
        teleprompterSegment(at: currentSegmentIndex)
    }

    public var upcomingTeleprompterSegments: [TeleprompterSegmentSnapshot] {
        (1...3).compactMap { teleprompterSegment(at: currentSegmentIndex + $0) }
    }

    public func teleprompterSegment(at index: Int) -> TeleprompterSegmentSnapshot? {
        guard index >= 0 else { return nil }

        if let bundle {
            guard let segment = bundle.spokenSegments[safe: index] else { return nil }
            let sectionTitle = bundle.sections.first(where: { $0.id == segment.sectionID })?.title ?? activeSegmentTitle
            let displayText = bundle.displayBlocks.first(where: { $0.segmentID == segment.id })?.text ?? segment.text
            return TeleprompterSegmentSnapshot(
                id: segment.id,
                segmentIndex: index,
                sectionTitle: sectionTitle,
                text: displayText
            )
        }

        guard let segment = placeholderSegments[safe: index] else { return nil }
        return TeleprompterSegmentSnapshot(
            id: "placeholder-\(index)",
            segmentIndex: index,
            sectionTitle: segment.title,
            text: segment.blocks.joined(separator: " ")
        )
    }

    public func slideMarker(beforeSegmentIndex index: Int) -> TeleprompterSlideSnapshot? {
        guard index >= 0 else { return nil }

        if let bundle {
            guard
                let marker = bundle.slideMarkers.first(where: { marker in
                    bundle.spokenSegments.firstIndex(where: { $0.id == marker.targetSegmentID }) == index
                })
            else {
                return nil
            }

            return TeleprompterSlideSnapshot(index: marker.index, label: marker.label)
        }

        guard index > 0 else { return nil }
        return TeleprompterSlideSnapshot(index: index, label: "SLIDE")
    }

    public var hypothesisHighlightTerms: Set<String> {
        let terms = latestHypothesis?.text ?? latestConfirmed?.text ?? ""
        return Set(Self.normalizedSearchTerms(from: terms))
    }

    // MARK: - Internal helpers

    private var segmentCount: Int {
        bundle?.spokenSegments.count ?? placeholderSegments.count
    }

    private var slideMetrics: (current: Int, total: Int) {
        if let bundle {
            let totalSlides = bundle.slideMarkers.count
            let slidesPassedCount = bundle.slideMarkers.filter { marker in
                guard let markerSegmentIdx = bundle.spokenSegments.firstIndex(where: { $0.id == marker.targetSegmentID }) else {
                    return false
                }
                return markerSegmentIdx <= currentSegmentIndex
            }.count
            return (slidesPassedCount, totalSlides)
        }

        let components = slideCounter.split(separator: " ").last?.split(separator: "/") ?? []
        if components.count == 2,
           let current = Int(components[0]),
           let total = Int(components[1]) {
            return (current, total)
        }
        return (0, 0)
    }

    private func placeholderBookmarkSummaries() -> [ControlBookmarkSummary] {
        placeholderSegments.enumerated().map { index, segment in
            ControlBookmarkSummary(
                id: "placeholder-bookmark-\(index)",
                title: segment.title,
                targetSegmentID: "placeholder-segment-\(index)",
                sectionID: "placeholder-section-\(index)",
                segmentIndex: index,
                slideIndex: index,
                kind: .section
            )
        }
    }

    @discardableResult
    private func loadReferenceBundleIfAvailable() -> Bool {
        for name in ["presentation-script.md", "presentation-script-opus.md"] {
            let url = referenceDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let compiledBundle = ScriptCompiler().compile(markdown: markdown, source: name)
            loadBundle(compiledBundle)
            return true
        }

        return false
    }

    private func locateCachedModelFolder(named modelName: String) -> URL? {
        let fileManager = FileManager.default
        let baseDirectory = modelDirectory
        let candidates = [
            baseDirectory.appendingPathComponent(modelName, isDirectory: true),
            baseDirectory
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(modelName, isDirectory: true),
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
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

    private func bindASRStreamsIfNeeded() {
        guard hypothesisTask == nil, confirmedTask == nil else { return }

        hypothesisTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.hypothesisTask = nil
                }
            }
            let stream = await asrService.hypothesisStream()
            for await event in stream {
                await MainActor.run {
                    self.ingestHypothesis(event)
                }
            }
        }

        confirmedTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.confirmedTask = nil
                }
            }
            let stream = await asrService.confirmedStream()
            for await event in stream {
                await MainActor.run {
                    self.ingestConfirmed(event)
                }
            }
        }
    }

    private func ingestHypothesis(_ event: ASRTranscriptionEvent) {
        latestHypothesis = event
        statusDetail = "Hypothesis: \(event.text)"
        latencySnapshot.latestHypothesisLatencySeconds = event.latencySeconds
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .asrChunk,
                payload: [
                    "stream": "hypothesis",
                    "latencySeconds": String(format: "%.3f", event.latencySeconds),
                    "text": event.text,
                ]
            )
        )
    }

    private func ingestConfirmed(_ event: ASRTranscriptionEvent) {
        latestConfirmed = event
        statusDetail = "Confirmed: \(event.text)"
        latencySnapshot.latestConfirmedLatencySeconds = event.latencySeconds
        alignmentConfidence = max(0.15, min(1, 1 - (event.latencySeconds / max(latencySnapshot.confirmedTargetSeconds, 0.1))))
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .asrChunk,
                payload: [
                    "stream": "confirmed",
                    "latencySeconds": String(format: "%.3f", event.latencySeconds),
                    "text": event.text,
                ]
            )
        )
    }

    private func transition(to newState: SessionState, reason: String, override: Bool = false) {
        guard newState != sessionState else {
            statusDetail = reason
            return
        }

        let oldState = sessionState
        let isAllowed = override || allowedTransitions[oldState, default: []].contains(newState)

        guard isAllowed else {
            lastErrorMessage = "Invalid transition \(oldState.rawValue) -> \(newState.rawValue)"
            appendDiagnosticEvent(
                DiagnosticEvent(
                    eventType: .error,
                    payload: [
                        "message": lastErrorMessage ?? "",
                        "reason": reason,
                    ]
                )
            )
            sessionState = .error
            applyStateSideEffects(for: .error)
            statusDetail = lastErrorMessage ?? reason
            appendDiagnosticEvent(
                DiagnosticEvent(
                    eventType: .stateTransition,
                    payload: [
                        "from": oldState.rawValue,
                        "to": SessionState.error.rawValue,
                        "reason": "invalidTransition",
                        "override": "false",
                    ]
                )
            )
            return
        }

        sessionState = newState
        statusDetail = reason
        applyStateSideEffects(for: newState)
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .stateTransition,
                payload: [
                    "from": oldState.rawValue,
                    "to": newState.rawValue,
                    "reason": reason,
                    "override": String(override),
                ]
            )
        )
    }

    private func applyStateSideEffects(for state: SessionState) {
        switch state {
        case .liveAuto:
            isPaused = false
            if !isEmergencyScrolling {
                countdownTargetDate = nil
            }
        case .liveFrozen:
            isPaused = true
            isEmergencyScrolling = false
        case .manualScroll:
            isEmergencyScrolling = true
        case .recoveringLocal, .recoveringCloud:
            isPaused = false
        case .ready, .countdown:
            isEmergencyScrolling = false
        case .idle:
            isPaused = false
            isEmergencyScrolling = false
        case .preflight, .error:
            break
        }
    }

    private func appendManualJumpEvent(reason: String) {
        appendDiagnosticEvent(
            DiagnosticEvent(
                eventType: .manualJump,
                payload: [
                    "segmentIndex": String(currentSegmentIndex),
                    "segmentID": currentSegmentID ?? "placeholder-\(currentSegmentIndex)",
                    "reason": reason,
                ]
            )
        )
    }

    private var currentSegmentID: String? {
        bundle?.spokenSegments[safe: currentSegmentIndex]?.id
    }

    private func updateDisplayForCurrentSegment() {
        if bundle != nil {
            updateDisplayFromBundle()
        } else {
            applyPlaceholderSegment(at: currentSegmentIndex)
        }
        updateSegmentPreviews()
    }

    private func updateSegmentPreviews() {
        if let bundle {
            currentSegmentPreview = bundle.spokenSegments[safe: currentSegmentIndex]?.text ?? ""
            nextSegmentPreview = bundle.spokenSegments[safe: currentSegmentIndex + 1]?.text ?? ""
        } else {
            currentSegmentPreview = placeholderSegments[safe: currentSegmentIndex]?.blocks.first ?? ""
            nextSegmentPreview = placeholderSegments[safe: currentSegmentIndex + 1]?.blocks.first ?? ""
        }
    }

    private func updateDisplayFromBundle() {
        guard let bundle, let segment = bundle.spokenSegments[safe: currentSegmentIndex] else { return }

        if let section = bundle.sections.first(where: { $0.segmentIDs.contains(segment.id) }) {
            activeSegmentTitle = section.title
        }

        let currentAndUpcoming = bundle.spokenSegments[currentSegmentIndex...].prefix(4)
        let segmentIDs = Set(currentAndUpcoming.map(\.id))
        teleprompterBlocks = bundle.displayBlocks
            .filter { segmentIDs.contains($0.segmentID) }
            .map(\.text)

        let metrics = slideMetrics
        slideCounter = "Slide \(metrics.current)/\(metrics.total)"
    }

    private func applyPlaceholderSegment(at index: Int) {
        guard let segment = placeholderSegments[safe: index] else { return }
        activeSegmentTitle = segment.title
        teleprompterBlocks = segment.blocks
        slideCounter = segment.slideCounter
    }

    private func appendDiagnosticEvent(_ event: DiagnosticEvent) {
        diagnosticEvents.append(event)
        sessionLog.append(event)
    }

    private static func normalizedSearchTerms(from text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
