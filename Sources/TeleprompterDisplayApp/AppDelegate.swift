import AppKit
import TeleprompterAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppSessionStore()
    private var controlWindowController: ControlWindowController?
    private var teleprompterWindowController: TeleprompterWindowController?
    private var keyEventMonitor: Any?
    private var isRunningKeyboardProbe = false
    private var observedProbeKeyCodes: Set<UInt16> = []

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationSupportDirectories()

        controlWindowController = ControlWindowController(store: store)
        teleprompterWindowController = TeleprompterWindowController(store: store)

        controlWindowController?.showWindow(nil)
        teleprompterWindowController?.showWindow(nil)

        configureTeleprompterWindow()
        registerDisplayNotifications()
        registerKeyboardShortcuts()
        store.updateConnectedDisplayCount(NSScreen.screens.count)
        store.installKeyboardShortcutProbe { [weak self] in
            guard let self else { return .fail("Keyboard shortcut monitor is unavailable.") }
            return self.runKeyboardShortcutProbe()
        }

        NSApp.activate(ignoringOtherApps: true)
        store.statusDetail = "App shell ready. Waiting for presentation bundle."
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)

        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    // MARK: - Application Support directories

    private func setupApplicationSupportDirectories() {
        _ = try? AppSupportPaths.ensureDirectoriesExist()
    }

    // MARK: - Teleprompter window configuration

    private func configureTeleprompterWindow() {
        guard let window = teleprompterWindowController?.window else { return }

        // Float above other windows
        window.level = .floating

        // Position on external display if available
        positionWindowOnBestScreen(window)
    }

    private func positionWindowOnBestScreen(_ window: NSWindow) {
        let candidateScreen = NSScreen.screens.dropFirst().first ?? NSScreen.main
        guard let frame = candidateScreen?.visibleFrame else { return }

        // Fill the target screen
        window.setFrame(frame, display: true)
    }

    // MARK: - Display connect/disconnect

    private func registerDisplayNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func registerKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isEmpty else { return event }

        if isRunningKeyboardProbe {
            if [49, 53, 123, 124].contains(event.keyCode) {
                observedProbeKeyCodes.insert(event.keyCode)
                return nil
            }
            return event
        }

        switch event.keyCode {
        case 49:
            store.handleTogglePause()
            return nil
        case 53:
            store.handleEmergencyScroll()
            return nil
        case 123:
            store.handlePreviousSegment()
            return nil
        case 124:
            store.handleNextSegment()
            return nil
        default:
            return event
        }
    }

    @objc private func screensDidChange(_ notification: Notification) {
        guard let window = teleprompterWindowController?.window else { return }
        store.updateConnectedDisplayCount(NSScreen.screens.count)

        if NSScreen.screens.count > 1 {
            // External display connected — move teleprompter there
            positionWindowOnBestScreen(window)
            store.statusDetail = "External display detected. Teleprompter moved."
        } else {
            // Only built-in display — keep teleprompter on main
            positionWindowOnBestScreen(window)
            store.statusDetail = "Single display. Teleprompter on main screen."
        }
    }

    private func runKeyboardShortcutProbe() -> OperationalProbeResult {
        let probeEvents: [(UInt16, String)] = [
            (49, " "),
            (123, ""),
            (124, ""),
            (53, ""),
        ]

        observedProbeKeyCodes.removeAll()
        isRunningKeyboardProbe = true
        defer {
            isRunningKeyboardProbe = false
        }

        for (keyCode, characters) in probeEvents {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controlWindowController?.window?.windowNumber ?? 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else {
                return .fail("Could not synthesize keyboard shortcut probe events.")
            }

            _ = handleKeyDown(event)
        }

        let expected = Set(probeEvents.map { $0.0 })
        guard observedProbeKeyCodes == expected else {
            return .fail("Expected Space, Left, Right, and Escape to route through the control surface.")
        }

        return .pass("Space, Left, Right, and Escape routed through the keyboard monitor.")
    }
}
