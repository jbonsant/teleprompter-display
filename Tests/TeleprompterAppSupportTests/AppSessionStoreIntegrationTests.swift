import Foundation
import XCTest
@testable import SpeechAlignment
@testable import TeleprompterAppSupport
@testable import TeleprompterDomain

@MainActor
final class AppSessionStoreIntegrationTests: XCTestCase {
    func testRunPreflightPersistsPassingReportAndUnlocksStart() async throws {
        let sandbox = try TestSandbox()
        try sandbox.createModel(named: ASRModelCatalog.primaryModelID)

        let asrService = MockASRService(
            devices: [AudioInputDeviceDescriptor(id: "mic-1", name: "French Desk Mic")],
            warmupResult: ASRModelWarmupResult(
                modelID: ASRModelCatalog.primaryModelID,
                loadSeconds: 2.4,
                modelDirectory: sandbox.modelsDirectory
            ),
            microphoneSanityResult: ASRMicrophoneSanityResult(
                prompt: SessionConfiguration.microphonePrompt,
                transcribedText: "Bonjour GPSN, nous validons la transcription francaise en direct.",
                overlapScore: 0.93,
                looksFrench: true,
                latencySeconds: 1.1
            )
        )

        let store = AppSessionStore(
            referenceDirectory: referencesURL,
            modelDirectory: sandbox.modelsDirectory,
            reportsDirectory: sandbox.reportsDirectory,
            asrService: asrService,
            cloudRecoveryClient: MockCloudRecoveryClient(),
            nowProvider: { Date(timeIntervalSince1970: 1_710_000_000) }
        )
        store.updateConnectedDisplayCount(2)
        store.installKeyboardShortcutProbe {
            .pass("Space, Left, Right, and Escape responded.")
        }

        await store.runPreflight()

        XCTAssertEqual(store.sessionState, .ready)
        XCTAssertTrue(store.isPreflightReady)
        XCTAssertTrue(store.canStartSession)
        XCTAssertEqual(store.preflightResults.count, PreflightCheckKind.allCases.count)
        XCTAssertTrue(store.preflightResults.allSatisfy(\.passed))

        let reportURL = try XCTUnwrap(store.lastPreflightReportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))

        let reportData = try Data(contentsOf: reportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(PreflightReport.self, from: reportData)

        XCTAssertEqual(report.activeModelID, ASRModelCatalog.primaryModelID)
        XCTAssertEqual(report.displayCount, 2)
        XCTAssertEqual(report.selectedMicrophoneName, "French Desk Mic")
        XCTAssertEqual(report.results.count, PreflightCheckKind.allCases.count)
        XCTAssertTrue(report.results.allSatisfy(\.passed))
    }

    func testCloudRecoveryWaitsThirtySecondsBeforeJumpingWithinCandidateWindow() async throws {
        let sandbox = try TestSandbox()
        let asrService = MockASRService()
        let cloudRecoveryClient = MockCloudRecoveryClient(
            resolution: CloudRecoveryResolution(targetSegmentID: "segment-3", confidence: 0.91)
        )

        var now = Date(timeIntervalSince1970: 1_710_100_000)
        let store = AppSessionStore(
            referenceDirectory: referencesURL,
            alignmentPolicy: AlignmentPolicy(confidenceThreshold: 0.7, debounceFrames: 3),
            cloudRecoveryPolicy: CloudRecoveryPolicy(
                enabledByDefault: false,
                lowConfidenceThreshold: 0.55,
                lowConfidenceWindowSeconds: 30,
                maxRetryCount: 1,
                modelName: "llama-3.3-70b-versatile"
            ),
            modelDirectory: sandbox.modelsDirectory,
            reportsDirectory: sandbox.reportsDirectory,
            asrService: asrService,
            cloudRecoveryClient: cloudRecoveryClient,
            groqAPIKeyProvider: { "test-groq-key" },
            nowProvider: { now }
        )
        store.loadBundle(makeRecoveryBundle())
        store.setCloudRecoveryEnabled(true)

        await prepareLiveSession(store)

        await asrService.emitConfirmed(text: "phrase hors scenario sans ancrage local", latencySeconds: 1.0)
        try await waitUntil { store.sessionState == .recoveringLocal }
        XCTAssertEqual(store.currentSegmentIndex, 0)

        now.addTimeInterval(31)
        await asrService.emitConfirmed(text: "encore une phrase hors script pour forcer la recuperation", latencySeconds: 1.0)

        try await waitUntil { store.currentSegmentIndex == 2 && store.sessionState == .liveAuto }
        XCTAssertEqual(store.currentSegmentIndex, 2)
        XCTAssertTrue(store.lastCloudRecoveryDetail.contains("Recovered to segment 3"))

        let requests = await cloudRecoveryClient.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertLessThanOrEqual(requests[0].recentConfirmedWords.count, 20)
        XCTAssertEqual(requests[0].candidates.map(\.segmentID), ["segment-1", "segment-2", "segment-3"])
    }

    func testManualControlsRemainDeterministicAcrossBookmarkFreezeScrollAndSlideUpdates() async throws {
        let sandbox = try TestSandbox()
        let store = AppSessionStore(
            referenceDirectory: referencesURL,
            modelDirectory: sandbox.modelsDirectory,
            reportsDirectory: sandbox.reportsDirectory,
            asrService: MockASRService(),
            cloudRecoveryClient: MockCloudRecoveryClient()
        )
        store.loadBundle(try loadGoldenBundle())

        await prepareLiveSession(store)

        let startingSlide = store.currentSlideNumber
        let targetBookmark = try XCTUnwrap(store.sectionBookmarks.last)
        store.jumpToBookmark(targetBookmark)

        XCTAssertEqual(store.currentSegmentIndex, targetBookmark.segmentIndex)
        XCTAssertEqual(store.sessionState, .recoveringLocal)
        XCTAssertGreaterThan(store.currentSlideNumber, startingSlide)
        XCTAssertTrue(store.slideCounter.contains("/"))

        store.handleFreeze()
        XCTAssertEqual(store.sessionState, .liveFrozen)

        store.handleFreeze()
        XCTAssertEqual(store.sessionState, .liveAuto)

        store.handleEmergencyScroll()
        XCTAssertTrue(store.isEmergencyScrolling)
        XCTAssertEqual(store.sessionState, .manualScroll)

        store.handleEmergencyScroll()
        XCTAssertFalse(store.isEmergencyScrolling)
        XCTAssertEqual(store.sessionState, .liveAuto)

        let advancedIndex = store.currentSegmentIndex
        store.handleNextSegment()
        XCTAssertEqual(store.currentSegmentIndex, advancedIndex + 1)
    }

    func testRefreshAudioInputsPrefersWirelessMicReceiverWhenAvailable() async throws {
        let sandbox = try TestSandbox()
        let asrService = MockASRService(
            devices: [
                AudioInputDeviceDescriptor(id: "usb", name: "USB Audio Codec"),
                AudioInputDeviceDescriptor(id: "macbook", name: "MacBook Pro Microphone"),
                AudioInputDeviceDescriptor(id: "wireless", name: "Wireless Mic Rx"),
            ]
        )
        let store = AppSessionStore(
            referenceDirectory: referencesURL,
            modelDirectory: sandbox.modelsDirectory,
            reportsDirectory: sandbox.reportsDirectory,
            asrService: asrService,
            cloudRecoveryClient: MockCloudRecoveryClient()
        )

        await store.refreshAudioInputs()

        XCTAssertEqual(store.selectedAudioInputName, "Wireless Mic Rx")
        let selectedDevice = await asrService.selectedInputDeviceDescriptor()
        XCTAssertEqual(selectedDevice?.name, "Wireless Mic Rx")
    }

    func testRefreshAudioInputsFallsBackToMacBookMicrophoneWhenWirelessReceiverIsMissing() async throws {
        let sandbox = try TestSandbox()
        let asrService = MockASRService(
            devices: [
                AudioInputDeviceDescriptor(id: "usb", name: "USB Audio Codec"),
                AudioInputDeviceDescriptor(id: "macbook", name: "MacBook Pro Microphone"),
            ]
        )
        let store = AppSessionStore(
            referenceDirectory: referencesURL,
            modelDirectory: sandbox.modelsDirectory,
            reportsDirectory: sandbox.reportsDirectory,
            asrService: asrService,
            cloudRecoveryClient: MockCloudRecoveryClient()
        )

        await store.refreshAudioInputs()

        XCTAssertEqual(store.selectedAudioInputName, "MacBook Pro Microphone")
        let selectedDevice = await asrService.selectedInputDeviceDescriptor()
        XCTAssertEqual(selectedDevice?.name, "MacBook Pro Microphone")
    }
}

private extension AppSessionStoreIntegrationTests {
    var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    var referencesURL: URL {
        repoRootURL.appendingPathComponent("references", isDirectory: true)
    }

    var goldenBundleURL: URL {
        repoRootURL.appendingPathComponent("Tests/Fixtures/golden-bundle.json")
    }

    func loadGoldenBundle() throws -> PresentationBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PresentationBundle.self, from: Data(contentsOf: goldenBundleURL))
    }

    func prepareLiveSession(_ store: AppSessionStore) async {
        store.beginPreflight()
        store.completePreflight(
            PreflightCheckKind.allCases.map {
                PreflightResult(kind: $0, status: .pass, detail: "Prepared for integration test.")
            }
        )
        await store.startASR()
        store.startCountdown(seconds: 0)
        store.beginLiveAuto()
    }

    func waitUntil(
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Timed out waiting for condition.")
    }

    func makeRecoveryBundle() -> PresentationBundle {
        let segments = [
            "ouverture et cadrage general",
            "architecture react django postgresql",
            "moteur de workflow et coffre fort numerique",
        ]

        let spokenSegments = segments.enumerated().map { index, text in
            SpokenSegment(id: "segment-\(index + 1)", text: text, sectionID: "section-1")
        }
        let displayBlocks = segments.enumerated().map { index, text in
            DisplayBlock(id: "display-\(index + 1)", text: text, segmentID: "segment-\(index + 1)", sectionID: "section-1")
        }
        let anchors = [
            AnchorPhrase(id: "anchor-1", segmentID: "segment-1", sectionID: "section-1", text: "cadrage general"),
            AnchorPhrase(id: "anchor-2", segmentID: "segment-2", sectionID: "section-1", text: "django postgresql"),
            AnchorPhrase(id: "anchor-3", segmentID: "segment-3", sectionID: "section-1", text: "coffre fort numerique"),
        ]

        return PresentationBundle(
            compilerVersion: "test",
            sourceHash: "hash",
            sections: [
                PresentationSection(id: "section-1", title: "Test", segmentIDs: spokenSegments.map(\.id))
            ],
            displayBlocks: displayBlocks,
            spokenSegments: spokenSegments,
            slideMarkers: [
                SlideMarker(id: "slide-1", index: 1, targetSegmentID: "segment-2", sectionID: "section-1"),
                SlideMarker(id: "slide-2", index: 2, targetSegmentID: "segment-3", sectionID: "section-1"),
            ],
            bookmarks: [],
            anchorPhrases: anchors
        )
    }
}

private struct TestSandbox {
    let rootDirectory: URL
    let modelsDirectory: URL
    let reportsDirectory: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        modelsDirectory = rootDirectory.appendingPathComponent("Models", isDirectory: true)
        reportsDirectory = rootDirectory.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }

    func createModel(named name: String) throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
}

private actor MockASRService: StreamingASRServiceControlling {
    private let devices: [AudioInputDeviceDescriptor]
    private let warmupResult: ASRModelWarmupResult
    private let microphoneSanityResult: ASRMicrophoneSanityResult
    private let latencySnapshot: ASRLatencySnapshot
    private let modelID: String
    private var selectedDeviceID: String?
    private var hypothesisContinuations: [AsyncStream<ASRTranscriptionEvent>.Continuation] = []
    private var confirmedContinuations: [AsyncStream<ASRTranscriptionEvent>.Continuation] = []

    init(
        devices: [AudioInputDeviceDescriptor] = [AudioInputDeviceDescriptor(id: "default", name: "Default Mic")],
        warmupResult: ASRModelWarmupResult = ASRModelWarmupResult(
            modelID: ASRModelCatalog.primaryModelID,
            loadSeconds: 1.2,
            modelDirectory: FileManager.default.temporaryDirectory
        ),
        microphoneSanityResult: ASRMicrophoneSanityResult = ASRMicrophoneSanityResult(
            prompt: SessionConfiguration.microphonePrompt,
            transcribedText: "Bonjour GPSN",
            overlapScore: 0.9,
            looksFrench: true,
            latencySeconds: 1.0
        ),
        latencySnapshot: ASRLatencySnapshot = ASRLatencySnapshot(
            hypothesisTargetSeconds: 0.45,
            confirmedTargetSeconds: 1.7
        ),
        modelID: String = ASRModelCatalog.primaryModelID
    ) {
        self.devices = devices
        self.warmupResult = warmupResult
        self.microphoneSanityResult = microphoneSanityResult
        self.latencySnapshot = latencySnapshot
        self.modelID = modelID
        self.selectedDeviceID = devices.first?.id
    }

    func requestMicrophonePermission() async -> Bool { true }

    func availableInputDevices() async -> [AudioInputDeviceDescriptor] {
        devices
    }

    func selectedInputDeviceDescriptor() async -> AudioInputDeviceDescriptor? {
        devices.first(where: { $0.id == selectedDeviceID }) ?? devices.first
    }

    func selectInputDevice(id: String?) async {
        selectedDeviceID = id
    }

    func currentLatencySnapshot() async -> ASRLatencySnapshot {
        latencySnapshot
    }

    func currentModelID() async -> String {
        modelID
    }

    func hypothesisStream() async -> AsyncStream<ASRTranscriptionEvent> {
        AsyncStream { continuation in
            hypothesisContinuations.append(continuation)
        }
    }

    func confirmedStream() async -> AsyncStream<ASRTranscriptionEvent> {
        AsyncStream { continuation in
            confirmedContinuations.append(continuation)
        }
    }

    func warmModel() async throws -> ASRModelWarmupResult {
        warmupResult
    }

    func validateFrenchMicrophone(prompt: String, timeoutSeconds: TimeInterval) async throws -> ASRMicrophoneSanityResult {
        microphoneSanityResult
    }

    func start() async throws {}

    func stop() async {
        for continuation in hypothesisContinuations {
            continuation.finish()
        }
        for continuation in confirmedContinuations {
            continuation.finish()
        }
        hypothesisContinuations.removeAll()
        confirmedContinuations.removeAll()
    }

    func emitConfirmed(text: String, latencySeconds: TimeInterval) {
        let event = ASRTranscriptionEvent(
            text: text,
            audioStartSeconds: 0,
            audioEndSeconds: 1.5,
            emittedAt: Date(),
            latencySeconds: latencySeconds,
            modelID: modelID
        )
        for continuation in confirmedContinuations {
            continuation.yield(event)
        }
    }
}

private actor MockCloudRecoveryClient: CloudRecoveryClientProtocol {
    private let resolution: CloudRecoveryResolution
    private var recordedRequests: [CloudRecoveryRequest] = []

    init(resolution: CloudRecoveryResolution = CloudRecoveryResolution(targetSegmentID: nil, confidence: 0)) {
        self.resolution = resolution
    }

    func resolveTarget(apiKey: String, request: CloudRecoveryRequest) async throws -> CloudRecoveryResolution {
        recordedRequests.append(request)
        return resolution
    }

    func requests() -> [CloudRecoveryRequest] {
        recordedRequests
    }
}
