import AppKit
import TeleprompterAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppSessionStore()
    private var controlWindowController: ControlWindowController?
    private var teleprompterWindowController: TeleprompterWindowController?
    private var windowCoordinator: WindowCoordinator?
    private var keyEventMonitor: Any?
    private var isRunningKeyboardProbe = false
    private var observedProbeKeyCodes: Set<UInt16> = []

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationSupportDirectories()

        teleprompterWindowController = TeleprompterWindowController(store: store)
        controlWindowController = ControlWindowController(
            store: store,
            onShowDisplay: { [weak self] in
                self?.windowCoordinator?.showTeleprompterWindow()
            },
            onRestartApp: { [weak self] in
                self?.windowCoordinator?.restartApp()
            }
        )

        if let controlWindowController, let teleprompterWindowController {
            windowCoordinator = WindowCoordinator(
                controlWindowController: controlWindowController,
                teleprompterWindowController: teleprompterWindowController
            )
        }

        configureMainMenu()
        windowCoordinator?.showControlWindow()
        windowCoordinator?.showTeleprompterWindow()

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
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowCoordinator?.showControlWindow()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
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

    // MARK: - Menu bar

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem(title: ProcessInfo.processInfo.processName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let restartItem = NSMenuItem(title: "Restart App", action: #selector(restartAppFromMenu(_:)), keyEquivalent: "r")
        restartItem.keyEquivalentModifierMask = [.command, .shift]
        restartItem.target = self
        appMenu.addItem(restartItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(ProcessInfo.processInfo.processName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        let showControlItem = NSMenuItem(title: "Show Control Window", action: #selector(showControlWindowFromMenu(_:)), keyEquivalent: "1")
        showControlItem.keyEquivalentModifierMask = [.command]
        showControlItem.target = self
        windowMenu.addItem(showControlItem)

        let showDisplayItem = NSMenuItem(title: "Show Teleprompter Display", action: #selector(showTeleprompterWindowFromMenu(_:)), keyEquivalent: "2")
        showDisplayItem.keyEquivalentModifierMask = [.command]
        showDisplayItem.target = self
        windowMenu.addItem(showDisplayItem)

        windowMenu.addItem(NSMenuItem.separator())

        let bringAllToFrontItem = NSMenuItem(title: "Bring All to Front", action: #selector(bringAllWindowsToFront(_:)), keyEquivalent: "")
        bringAllToFrontItem.target = self
        windowMenu.addItem(bringAllToFrontItem)

        NSApp.windowsMenu = windowMenu
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
        store.updateConnectedDisplayCount(NSScreen.screens.count)

        if NSScreen.screens.count > 1 {
            windowCoordinator?.repositionTeleprompterWindowIfVisible()
            store.statusDetail = "External display detected. Teleprompter moved."
        } else {
            windowCoordinator?.repositionTeleprompterWindowIfVisible()
            store.statusDetail = "Single display. Teleprompter on main screen."
        }
    }

    @objc private func showControlWindowFromMenu(_ sender: Any?) {
        windowCoordinator?.showControlWindow()
    }

    @objc private func showTeleprompterWindowFromMenu(_ sender: Any?) {
        windowCoordinator?.showTeleprompterWindow()
    }

    @objc private func bringAllWindowsToFront(_ sender: Any?) {
        windowCoordinator?.bringAllToFront()
    }

    @objc private func restartAppFromMenu(_ sender: Any?) {
        windowCoordinator?.restartApp()
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
