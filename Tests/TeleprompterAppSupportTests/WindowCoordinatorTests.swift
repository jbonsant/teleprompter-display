import AppKit
import XCTest
@testable import TeleprompterAppSupport

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    func testShowCommandsUpdateVisibilityAndUseTargetFrame() {
        let controlPresenter = TestControlWindowPresenter()
        let teleprompterPresenter = TestTeleprompterWindowPresenter()
        let targetFrame = NSRect(x: 120, y: 80, width: 1440, height: 900)
        let coordinator = makeCoordinator(
            controlPresenter: controlPresenter,
            teleprompterPresenter: teleprompterPresenter,
            displayFrameProvider: { targetFrame }
        )

        XCTAssertFalse(coordinator.hasVisibleWindows)

        coordinator.showTeleprompterWindow()
        XCTAssertTrue(coordinator.isTeleprompterWindowVisible)
        XCTAssertEqual(teleprompterPresenter.showCount, 1)
        XCTAssertEqual(teleprompterPresenter.lastTargetFrame, targetFrame)

        coordinator.showControlWindow()
        XCTAssertTrue(coordinator.isControlWindowVisible)
        XCTAssertEqual(controlPresenter.showCount, 1)
    }

    func testBringAllToFrontRefreshesVisibleWindowsOnly() {
        let controlPresenter = TestControlWindowPresenter()
        let teleprompterPresenter = TestTeleprompterWindowPresenter()
        let coordinator = makeCoordinator(
            controlPresenter: controlPresenter,
            teleprompterPresenter: teleprompterPresenter
        )

        coordinator.showControlWindow()
        coordinator.showTeleprompterWindow()
        controlPresenter.showCount = 0
        teleprompterPresenter.showCount = 0

        coordinator.bringAllToFront()

        XCTAssertEqual(controlPresenter.showCount, 1)
        XCTAssertEqual(teleprompterPresenter.showCount, 1)
        XCTAssertTrue(coordinator.hasVisibleWindows)
    }

    func testRestartAppTerminatesAfterSuccessfulRelaunch() {
        let controlPresenter = TestControlWindowPresenter()
        let teleprompterPresenter = TestTeleprompterWindowPresenter()
        let relauncher = TestRelauncher()
        var terminateCount = 0
        let coordinator = makeCoordinator(
            controlPresenter: controlPresenter,
            teleprompterPresenter: teleprompterPresenter,
            relauncher: relauncher,
            terminator: { terminateCount += 1 }
        )

        coordinator.restartApp()

        XCTAssertEqual(relauncher.runCount, 1)
        XCTAssertEqual(terminateCount, 1)
    }

    func testRestartAppFailureKeepsCurrentProcessAlive() {
        let controlPresenter = TestControlWindowPresenter()
        let teleprompterPresenter = TestTeleprompterWindowPresenter()
        let relauncher = TestRelauncher()
        relauncher.error = AppRelaunchError.executableNotFound("/tmp/teleprompter-display")
        var terminateCount = 0
        var reportedError: String?
        let coordinator = makeCoordinator(
            controlPresenter: controlPresenter,
            teleprompterPresenter: teleprompterPresenter,
            relauncher: relauncher,
            terminator: { terminateCount += 1 },
            errorPresenter: { reportedError = $0 }
        )

        coordinator.restartApp()

        XCTAssertEqual(relauncher.runCount, 1)
        XCTAssertEqual(terminateCount, 0)
        XCTAssertNotNil(reportedError)
        XCTAssertTrue(reportedError?.contains("Could not restart the app.") == true)
    }

    func testWindowCloseUpdatesVisibilityFlags() {
        let controlPresenter = TestControlWindowPresenter()
        let teleprompterPresenter = TestTeleprompterWindowPresenter()
        let coordinator = makeCoordinator(
            controlPresenter: controlPresenter,
            teleprompterPresenter: teleprompterPresenter
        )

        coordinator.showControlWindow()
        coordinator.showTeleprompterWindow()
        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: teleprompterPresenter.window))

        XCTAssertTrue(coordinator.isControlWindowVisible)
        XCTAssertFalse(coordinator.isTeleprompterWindowVisible)
    }

    private func makeCoordinator(
        controlPresenter: TestControlWindowPresenter,
        teleprompterPresenter: TestTeleprompterWindowPresenter,
        displayFrameProvider: @escaping () -> NSRect? = { nil },
        relauncher: TestRelauncher = TestRelauncher(),
        terminator: @escaping () -> Void = {},
        errorPresenter: @escaping (String) -> Void = { _ in }
    ) -> WindowCoordinator {
        WindowCoordinator(
            controlWindowController: controlPresenter,
            teleprompterWindowController: teleprompterPresenter,
            displayFrameProvider: displayFrameProvider,
            activationHandler: {},
            relauncher: relauncher,
            terminator: terminator,
            errorPresenter: errorPresenter
        )
    }
}

@MainActor
private final class TestControlWindowPresenter: ControlWindowPresenting {
    let window: NSWindow?
    var showCount = 0

    init(window: NSWindow = NSWindow()) {
        self.window = window
    }

    func showControlWindow() {
        showCount += 1
    }
}

@MainActor
private final class TestTeleprompterWindowPresenter: TeleprompterWindowPresenting {
    let window: NSWindow?
    var showCount = 0
    var lastTargetFrame: NSRect?

    init(window: NSWindow = NSWindow()) {
        self.window = window
    }

    func showTeleprompterWindow(targetFrame: NSRect?) {
        showCount += 1
        lastTargetFrame = targetFrame
    }
}

private final class TestRelauncher: AppRelaunching {
    var runCount = 0
    var error: Error?

    func relaunchCurrentProcess() throws {
        runCount += 1
        if let error {
            throw error
        }
    }
}
