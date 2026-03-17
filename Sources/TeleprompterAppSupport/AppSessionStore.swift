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

public struct OperationalProbeResult: Sendable, Equatable {
    public let passed: Bool
    public let detail: String

    public static func pass(_ detail: String) -> OperationalProbeResult {
        OperationalProbeResult(passed: true, detail: detail)
    }

    public static func fail(_ detail: String) -> OperationalProbeResult {
        OperationalProbeResult(passed: false, detail: detail)
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
    @Published public private(set) var activePreflightReport: PreflightReport?
    @Published public private(set) var lastPreflightReportURL: URL?
    @Published public private(set) var isCloudRecoveryEnabled: Bool
    @Published public private(set) var lastCloudRecoveryDetail: String
    @Published public private(set) var isGroqAPIKeyConfigured: Bool
    @Published public private(set) var connectedDisplayCount: Int

    public let referenceDirectory: URL
    public private(set) var bundle: PresentationBundle?

    private let asrService: any StreamingASRServiceControlling
    private let cloudRecoveryClient: any CloudRecoveryClientProtocol
    private let cloudRecoveryPolicy: CloudRecoveryPolicy
    private let groqAPIKeyProvider: () -> String?
    private let nowProvider: () -> Date
    private let alignmentPolicy: AlignmentPolicy
    private let modelDirectory: URL
    private let reportsDirectory: URL
    private var hypothesisTask: Task<Void, Never>?
    private var confirmedTask: Task<Void, Never>?
    private var sessionLog: SessionLog
    private var aligner: ForwardAligner?
    private var lowConfidenceStartedAt: Date?
    private var hasAttemptedCloudRecoveryForCurrentIncident = false
    private var keyboardShortcutProbe: @MainActor () async -> OperationalProbeResult = {
        .fail("Keyboard shortcut probe is unavailable.")
    }

    public init(
        referenceDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("references"),
        sessionState: SessionState = .idle,
        asrConfiguration: ASRConfiguration = ASRConfiguration(),
        alignmentPolicy: AlignmentPolicy = AlignmentPolicy(),
        cloudRecoveryPolicy: CloudRecoveryPolicy = CloudRecoveryPolicy(),
        modelDirectory: URL = AppSupportPaths.modelsDirectory,
        reportsDirectory: URL = AppSupportPaths.reportsDirectory,
        asrService: (any StreamingASRServiceControlling)? = nil,
        cloudRecoveryClient: (any CloudRecoveryClientProtocol)? = nil,
        groqAPIKeyProvider: @escaping () -> String? = {
            EnvironmentValueResolver().value(for: ["GROQ_API_KEY", "groq-api-key", "groq_api_key"])
        },
        nowProvider: @escaping () -> Date = Date.init
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
        self.activePreflightReport = nil
        self.lastPreflightReportURL = nil
        self.isCloudRecoveryEnabled = cloudRecoveryPolicy.enabledByDefault
        self.lastCloudRecoveryDetail = "Cloud recovery is disabled."
        self.isGroqAPIKeyConfigured = groqAPIKeyProvider() != nil
        self.connectedDisplayCount = 1
        self.sessionLog = SessionLog()
        self.cloudRecoveryPolicy = cloudRecoveryPolicy
        self.groqAPIKeyProvider = groqAPIKeyProvider
        self.nowProvider = nowProvider
        self.alignmentPolicy = alignmentPolicy
        self.modelDirectory = modelDirectory
        self.reportsDirectory = reportsDirectory
        self.asrService = asrService ?? WhisperStreamingASRService(configuration: asrConfiguration, modelDirectory: modelDirectory)
        self.cloudRecoveryClient = cloudRecoveryClient ?? GroqCloudRecoveryClient(modelName: cloudRecoveryPolicy.modelName, maxRetryCount: cloudRecoveryPolicy.maxRetryCount)

        appendDiagnosticEvent(
            DiagnosticEvent(
                timestamp: nowProvider(),
                eventType: .stateTransition,
                payload: [
                    "from": "uninitialized",
                    "to": sessionState.rawValue,
                    "reason": "storeInit",
                ]
            )
        )

        self.preflightResults = PreflightCheckKind.allCases.map {
            PreflightResult(kind: $0, status: .pending, detail: "Not run yet.")
        }

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

    public var isPreflightReady: Bool {
        preflightResults.count == PreflightCheckKind.allCases.count && preflightResults.allSatisfy(\.passed)
    }

    public var canStartSession: Bool {
        sessionState == .ready && isPreflightReady
    }

    public var shouldShowBlockingReadinessScreen: Bool {
        sessionState == .preflight || !isPreflightReady
    }

    public var playPauseButtonLabel: String {
        switch sessionState {
        case .ready, .countdown:
            return sessionState == .ready ? "Start" : "Play"
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
        preflightResults = PreflightCheckKind.allCases.map {
            PreflightResult(kind: $0, status: .pending, detail: "Queued.")
        }

        for check in PreflightCheckKind.allCases {
            _ = await executePreflightCheck(check, finalizeAfterRun: false)
        }

        await finalizePreflightRun()
    }

    @discardableResult
    public func rerunPreflightCheck(_ check: PreflightCheckKind) async -> PreflightResult {
        await executePreflightCheck(check, finalizeAfterRun: true)
    }

    @discardableResult
    private func executePreflightCheck(_ check: PreflightCheckKind, finalizeAfterRun: Bool) async -> PreflightResult {
        beginPreflight()
        let startedAt = nowProvider()
        updatePreflightResult(PreflightResult(kind: check, status: .running, detail: "Running...", measuredAt: startedAt))

        let outcome = await runPreflightCheck(check)
        let result = PreflightResult(
            kind: check,
            status: outcome.passed ? .pass : .fail,
            detail: outcome.detail,
            measuredAt: nowProvider(),
            durationSeconds: nowProvider().timeIntervalSince(startedAt)
        )
        updatePreflightResult(result)
        appendDiagnosticEvent(
            DiagnosticEvent(
                timestamp: nowProvider(),
                eventType: .preflightCheck,
                payload: [
                    "check": check.rawValue,
                    "status": result.status.rawValue,
                    "detail": result.detail,
                ]
            )
        )
        if finalizeAfterRun {
            await finalizePreflightRun()
        }
        return result
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
        if results.allSatisfy(\.passed) {
            transition(to: .ready, reason: "Preflight passed")
        } else {
            statusDetail = "Preflight incomplete. Resolve failed checks before starting."
        }
    }

    public func startCountdown(seconds: TimeInterval = 3) {
        countdownTargetDate = nowProvider().addingTimeInterval(seconds)
        Task { [weak self] in
            await self?.startASR()
        }
        transition(to: .countdown, reason: "Countdown started")
    }

    public func beginLiveAuto() {
        if sessionStartedAt == nil {
            sessionStartedAt = nowProvider()
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
        lowConfidenceStartedAt = nil
        hasAttemptedCloudRecoveryForCurrentIncident = false
        Task { [weak self] in
            await self?.stopASR()
        }
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
        aligner?.manualJump(to: currentSegmentIndex)
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: "nextSegment")
        transition(to: .recoveringLocal, reason: "Manual advance to segment \(currentSegmentIndex + 1)", override: true)
    }

    public func handlePreviousSegment() {
        guard canMoveToPreviousSegment else { return }
        currentSegmentIndex -= 1
        aligner?.manualJump(to: currentSegmentIndex)
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: "previousSegment")
        transition(to: .recoveringLocal, reason: "Manual rewind to segment \(currentSegmentIndex + 1)", override: true)
    }

    public func jumpToSegment(index: Int, reason: String = "manualJump") {
        guard index >= 0, index < segmentCount else { return }
        currentSegmentIndex = index
        aligner?.manualJump(to: index)
        updateDisplayForCurrentSegment()
        appendManualJumpEvent(reason: reason)
        transition(to: .recoveringLocal, reason: "Manual jump to segment \(index + 1)", override: true)
    }

    public func setCloudRecoveryEnabled(_ enabled: Bool) {
        isGroqAPIKeyConfigured = groqAPIKeyProvider() != nil
        isCloudRecoveryEnabled = enabled
        lastCloudRecoveryDetail = enabled ? "Cloud recovery armed after 30 seconds of low-confidence drift." : "Cloud recovery is disabled."
    }

    public func updateConnectedDisplayCount(_ count: Int) {
        connectedDisplayCount = max(count, 0)
    }

    public func installKeyboardShortcutProbe(_ probe: @escaping @MainActor () async -> OperationalProbeResult) {
        keyboardShortcutProbe = probe
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
        self.aligner = ForwardAligner(bundle: bundle, policy: alignmentPolicy)
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

    private func runPreflightCheck(_ check: PreflightCheckKind) async -> OperationalProbeResult {
        switch check {
        case .microphonePermission:
            let granted = await requestMicrophonePermission()
            return granted
                ? .pass("Capture permission is granted.")
                : .fail("Grant microphone access in System Settings.")

        case .pinnedModelPresent:
            guard let modelURL = locateCachedModelFolder(named: activeModelID) else {
                return .fail("Pinned model \(activeModelID) is missing from \(modelDirectory.path).")
            }
            return .pass("Found \(activeModelID) at \(modelURL.lastPathComponent).")

        case .modelWarmup:
            guard locateCachedModelFolder(named: activeModelID) != nil else {
                return .fail("Warmup blocked because the pinned model is not cached locally.")
            }

            do {
                let warmup = try await asrService.warmModel()
                latencySnapshot.modelLoadSeconds = warmup.loadSeconds
                let passed = warmup.loadSeconds < SessionConfiguration.preflightWarmupThresholdSeconds
                return passed
                    ? .pass(String(format: "Warm load %.2fs (< %.0fs target).", warmup.loadSeconds, SessionConfiguration.preflightWarmupThresholdSeconds))
                    : .fail(String(format: "Warm load %.2fs exceeds %.0fs target.", warmup.loadSeconds, SessionConfiguration.preflightWarmupThresholdSeconds))
            } catch {
                return .fail(error.localizedDescription)
            }

        case .liveFrenchMicTest:
            do {
                let sanity = try await asrService.validateFrenchMicrophone(prompt: SessionConfiguration.microphonePrompt, timeoutSeconds: 12)
                return sanity.looksFrench
                    ? .pass("Confirmed French transcription: \"\(sanity.transcribedText)\"")
                    : .fail("Transcription was not confidently French: \"\(sanity.transcribedText)\"")
            } catch {
                return .fail(error.localizedDescription)
            }

        case .bundleLoaded:
            guard loadReferenceBundleIfAvailable(), let bundle else {
                return .fail("Compile and load references/presentation-script.md before going live.")
            }
            return validateBundle(bundle)

        case .secondDisplayDetected:
            return connectedDisplayCount > 1
                ? .pass("Detected \(connectedDisplayCount) displays.")
                : .fail("Only \(connectedDisplayCount) display detected. Connect the teleprompter monitor.")

        case .keyboardShortcuts:
            return await keyboardShortcutProbe()

        case .emergencyScroll:
            return probeEmergencyScroll()
        }
    }

    private func finalizePreflightRun() async {
        let report = PreflightReport(
            generatedAt: nowProvider(),
            selectedMicrophoneName: selectedAudioInputName,
            activeModelID: activeModelID,
            displayCount: connectedDisplayCount,
            bundleID: bundle?.bundleID,
            bundleSourceHash: bundle?.sourceHash,
            results: preflightResults
        )
        activePreflightReport = report
        lastPreflightReportURL = persistPreflightReport(report)
        completePreflight(preflightResults)
    }

    private func updatePreflightResult(_ result: PreflightResult) {
        if let index = preflightResults.firstIndex(where: { $0.checkID == result.checkID }) {
            preflightResults[index] = result
        } else {
            preflightResults.append(result)
        }
    }

    private func validateBundle(_ bundle: PresentationBundle) -> OperationalProbeResult {
        guard !bundle.spokenSegments.isEmpty else {
            return .fail("Compiled bundle has no spoken segments.")
        }

        let sections = Set(bundle.sections.map(\.id))
        let segments = Dictionary(uniqueKeysWithValues: bundle.spokenSegments.map { ($0.id, $0) })
        let hasInvalidDisplayBlocks = bundle.displayBlocks.contains {
            segments[$0.segmentID] == nil || !sections.contains($0.sectionID)
        }
        let hasInvalidSlideMarkers = bundle.slideMarkers.contains {
            segments[$0.targetSegmentID] == nil || !sections.contains($0.sectionID)
        }
        let hasInvalidBookmarks = bundle.bookmarks.contains {
            segments[$0.targetSegmentID] == nil || !sections.contains($0.sectionID)
        }
        let hasInvalidAnchors = bundle.anchorPhrases.contains {
            segments[$0.segmentID] == nil || !sections.contains($0.sectionID)
        }

        guard !hasInvalidDisplayBlocks, !hasInvalidSlideMarkers, !hasInvalidBookmarks, !hasInvalidAnchors else {
            return .fail("Bundle cross-references are invalid.")
        }

        return .pass("Bundle loaded with \(bundle.sections.count) sections and \(bundle.spokenSegments.count) spoken segments.")
    }

    private func probeEmergencyScroll() -> OperationalProbeResult {
        let originalState = sessionState
        let originalPaused = isPaused
        let originalEmergency = isEmergencyScrolling
        let originalStatus = statusDetail

        isEmergencyScrolling = true
        let activated = isEmergencyScrolling
        isEmergencyScrolling = false
        let deactivated = !isEmergencyScrolling

        sessionState = originalState
        isPaused = originalPaused
        isEmergencyScrolling = originalEmergency
        statusDetail = originalStatus

        return activated && deactivated
            ? .pass("Emergency scroll toggled on and off successfully.")
            : .fail("Emergency scroll did not toggle cleanly.")
    }

    private func persistPreflightReport(_ report: PreflightReport) -> URL? {
        do {
            try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let fileURL = reportsDirectory.appendingPathComponent("preflight-report-\(report.reportID.uuidString.lowercased()).json")
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
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
                timestamp: nowProvider(),
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
        appendDiagnosticEvent(
            DiagnosticEvent(
                timestamp: nowProvider(),
                eventType: .asrChunk,
                payload: [
                    "stream": "confirmed",
                    "latencySeconds": String(format: "%.3f", event.latencySeconds),
                    "text": event.text,
                ]
            )
        )

        guard shouldAdvanceAlignment else {
            alignmentConfidence = max(0.15, min(1, 1 - (event.latencySeconds / max(latencySnapshot.confirmedTargetSeconds, 0.1))))
            return
        }

        guard var aligner else { return }
        let update = aligner.ingestConfirmedEvent(event)
        self.aligner = aligner
        alignmentConfidence = update.confidence

        if update.segmentIndex > currentSegmentIndex {
            currentSegmentIndex = update.segmentIndex
            updateDisplayForCurrentSegment()
            appendDiagnosticEvent(
                DiagnosticEvent(
                    timestamp: nowProvider(),
                    eventType: .alignmentAdvance,
                    payload: [
                        "segmentIndex": String(update.segmentIndex),
                        "segmentID": update.segmentID ?? "",
                        "confidence": String(format: "%.3f", update.confidence),
                    ]
                )
            )
            lowConfidenceStartedAt = nil
            hasAttemptedCloudRecoveryForCurrentIncident = false
            if sessionState == .recoveringLocal || sessionState == .recoveringCloud {
                transition(to: .liveAuto, reason: "Alignment recovered", override: true)
            }
        }

        handlePotentialCloudRecovery(using: update)
    }

    private var shouldAdvanceAlignment: Bool {
        switch sessionState {
        case .liveAuto, .recoveringLocal, .recoveringCloud:
            return !isPaused && !isEmergencyScrolling && bundle != nil
        case .idle, .preflight, .ready, .countdown, .liveFrozen, .manualScroll, .error:
            return false
        }
    }

    private func handlePotentialCloudRecovery(using update: ForwardAlignmentUpdate) {
        let locallyStable = update.confidence >= cloudRecoveryPolicy.lowConfidenceThreshold || update.anchorRecoverySucceeded

        if locallyStable {
            lowConfidenceStartedAt = nil
            hasAttemptedCloudRecoveryForCurrentIncident = false
            if sessionState == .recoveringLocal || sessionState == .recoveringCloud {
                transition(to: .liveAuto, reason: "Local alignment stable", override: true)
            }
            return
        }

        guard isCloudRecoveryEnabled else {
            if update.anchorRecoveryAttempted {
                transition(to: .recoveringLocal, reason: "Local recovery holding position", override: true)
            }
            return
        }

        guard update.anchorRecoveryAttempted, !update.anchorRecoverySucceeded else {
            return
        }

        if lowConfidenceStartedAt == nil {
            lowConfidenceStartedAt = nowProvider()
            transition(to: .recoveringLocal, reason: "Low confidence detected. Holding local position.", override: true)
            return
        }

        let elapsed = nowProvider().timeIntervalSince(lowConfidenceStartedAt ?? nowProvider())
        guard elapsed >= cloudRecoveryPolicy.lowConfidenceWindowSeconds else { return }
        guard !hasAttemptedCloudRecoveryForCurrentIncident else { return }

        hasAttemptedCloudRecoveryForCurrentIncident = true
        Task { [weak self] in
            await self?.attemptCloudRecovery(using: update)
        }
    }

    private func attemptCloudRecovery(using update: ForwardAlignmentUpdate) async {
        transition(to: .recoveringCloud, reason: "Cloud recovery requested", override: true)

        guard let apiKey = groqAPIKeyProvider() else {
            lastCloudRecoveryDetail = "Groq API key is missing. Holding position locally."
            appendDiagnosticEvent(
                DiagnosticEvent(
                    timestamp: nowProvider(),
                    eventType: .cloudRecovery,
                    payload: ["result": "missing_api_key"]
                )
            )
            transition(to: .recoveringLocal, reason: lastCloudRecoveryDetail, override: true)
            return
        }

        let request = CloudRecoveryRequest(
            recentConfirmedWords: Array(update.recentConfirmedWords.suffix(20)),
            candidates: update.candidateWindow.map { candidate in
                CloudRecoveryCandidate(
                    segmentID: candidate.segmentID,
                    segmentIndex: candidate.segmentIndex,
                    text: candidate.text
                )
            }
        )

        do {
            let resolution = try await cloudRecoveryClient.resolveTarget(apiKey: apiKey, request: request)
            guard
                let targetSegmentID = resolution.targetSegmentID,
                let candidate = update.candidateWindow.first(where: { $0.segmentID == targetSegmentID })
            else {
                lastCloudRecoveryDetail = "Groq could not validate a target inside the candidate window. Holding position."
                appendDiagnosticEvent(
                    DiagnosticEvent(
                        timestamp: nowProvider(),
                        eventType: .cloudRecovery,
                        payload: ["result": "invalid_target"]
                    )
                )
                transition(to: .recoveringLocal, reason: lastCloudRecoveryDetail, override: true)
                return
            }

            aligner?.manualJump(to: candidate.segmentIndex)
            currentSegmentIndex = candidate.segmentIndex
            updateDisplayForCurrentSegment()
            lowConfidenceStartedAt = nil
            hasAttemptedCloudRecoveryForCurrentIncident = false
            lastCloudRecoveryDetail = String(format: "Recovered to segment %d with %.2f confidence.", candidate.segmentIndex + 1, resolution.confidence)
            appendDiagnosticEvent(
                DiagnosticEvent(
                    timestamp: nowProvider(),
                    eventType: .cloudRecovery,
                    payload: [
                        "result": "success",
                        "segmentID": candidate.segmentID,
                        "segmentIndex": String(candidate.segmentIndex),
                        "confidence": String(format: "%.3f", resolution.confidence),
                    ]
                )
            )
            transition(to: .liveAuto, reason: lastCloudRecoveryDetail, override: true)
        } catch {
            lastCloudRecoveryDetail = "Cloud recovery failed: \(error.localizedDescription)"
            appendDiagnosticEvent(
                DiagnosticEvent(
                    timestamp: nowProvider(),
                    eventType: .cloudRecovery,
                    payload: [
                        "result": "error",
                        "message": error.localizedDescription,
                    ]
                )
            )
            transition(to: .recoveringLocal, reason: lastCloudRecoveryDetail, override: true)
        }
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
