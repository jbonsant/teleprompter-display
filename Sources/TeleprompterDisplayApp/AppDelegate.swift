import AppKit
import TeleprompterAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppSessionStore()
    private var controlWindowController: ControlWindowController?
    private var teleprompterWindowController: TeleprompterWindowController?
    private var keyEventMonitor: Any?

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
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let base = appSupport.appendingPathComponent("TeleprompterDisplay", isDirectory: true)
        let subdirs = ["BundleCache", "Models", "Logs"]

        for subdir in subdirs {
            let url = base.appendingPathComponent(subdir, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
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
}
