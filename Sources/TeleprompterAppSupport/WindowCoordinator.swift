import AppKit
import Foundation

@MainActor
public protocol ControlWindowPresenting: AnyObject {
    var window: NSWindow? { get }
    func showControlWindow()
}

@MainActor
public protocol TeleprompterWindowPresenting: AnyObject {
    var window: NSWindow? { get }
    func showTeleprompterWindow(targetFrame: NSRect?)
}

public protocol AppRelaunching {
    func relaunchCurrentProcess() throws
}

public enum AppRelaunchError: LocalizedError {
    case executableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            return "Could not resolve an executable to relaunch at \(path)."
        }
    }
}

public struct ProcessAppRelauncher: AppRelaunching {
    public init() {}

    public func relaunchCurrentProcess() throws {
        let process = Process()
        process.executableURL = try Self.currentExecutableURL()
        process.arguments = Array(CommandLine.arguments.dropFirst())
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
    }

    private static func currentExecutableURL(fileManager: FileManager = .default) throws -> URL {
        if let executableURL = Bundle.main.executableURL,
           fileManager.isExecutableFile(atPath: executableURL.path) {
            return executableURL
        }

        guard let rawPath = CommandLine.arguments.first, !rawPath.isEmpty else {
            throw AppRelaunchError.executableNotFound("<missing>")
        }

        let candidateURL: URL
        if rawPath.hasPrefix("/") {
            candidateURL = URL(fileURLWithPath: rawPath)
        } else {
            candidateURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(rawPath)
        }

        let executableURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw AppRelaunchError.executableNotFound(executableURL.path)
        }
        return executableURL
    }
}

@MainActor
public final class WindowCoordinator: NSObject, NSWindowDelegate {
    public private(set) var isControlWindowVisible: Bool
    public private(set) var isTeleprompterWindowVisible: Bool

    public var hasVisibleWindows: Bool {
        isControlWindowVisible || isTeleprompterWindowVisible
    }

    private let controlWindowController: any ControlWindowPresenting
    private let teleprompterWindowController: any TeleprompterWindowPresenting
    private let displayFrameProvider: () -> NSRect?
    private let activationHandler: () -> Void
    private let relauncher: any AppRelaunching
    private let terminator: () -> Void
    private let errorPresenter: (String) -> Void

    public init(
        controlWindowController: any ControlWindowPresenting,
        teleprompterWindowController: any TeleprompterWindowPresenting,
        displayFrameProvider: @escaping () -> NSRect? = {
            let targetScreen = NSScreen.screens.dropFirst().first ?? NSScreen.main
            return targetScreen?.visibleFrame
        },
        activationHandler: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        relauncher: any AppRelaunching = ProcessAppRelauncher(),
        terminator: @escaping () -> Void = { NSApp.terminate(nil) },
        errorPresenter: @escaping (String) -> Void = { detail in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Restart App Failed"
            alert.informativeText = detail
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    ) {
        self.controlWindowController = controlWindowController
        self.teleprompterWindowController = teleprompterWindowController
        self.displayFrameProvider = displayFrameProvider
        self.activationHandler = activationHandler
        self.relauncher = relauncher
        self.terminator = terminator
        self.errorPresenter = errorPresenter
        self.isControlWindowVisible = controlWindowController.window?.isVisible ?? false
        self.isTeleprompterWindowVisible = teleprompterWindowController.window?.isVisible ?? false
        super.init()
        installWindowDelegates()
        updateVisibilityFromWindows()
    }

    public func showControlWindow() {
        controlWindowController.showControlWindow()
        isControlWindowVisible = true
        activationHandler()
    }

    public func showTeleprompterWindow() {
        teleprompterWindowController.showTeleprompterWindow(targetFrame: displayFrameProvider())
        isTeleprompterWindowVisible = true
        activationHandler()
    }

    public func bringAllToFront() {
        if isControlWindowVisible || controlWindowController.window?.isVisible == true {
            controlWindowController.showControlWindow()
            isControlWindowVisible = true
        }

        if isTeleprompterWindowVisible || teleprompterWindowController.window?.isVisible == true {
            teleprompterWindowController.showTeleprompterWindow(targetFrame: displayFrameProvider())
            isTeleprompterWindowVisible = true
        }

        activationHandler()
    }

    public func repositionTeleprompterWindowIfVisible() {
        guard isTeleprompterWindowVisible || teleprompterWindowController.window?.isVisible == true else {
            updateVisibilityFromWindows()
            return
        }

        teleprompterWindowController.showTeleprompterWindow(targetFrame: displayFrameProvider())
        isTeleprompterWindowVisible = true
    }

    public func restartApp() {
        do {
            try relauncher.relaunchCurrentProcess()
            terminator()
        } catch {
            errorPresenter("Could not restart the app.\n\n\(error.localizedDescription)")
        }
    }

    public func windowWillClose(_ notification: Notification) {
        updateVisibility(for: notification.object as? NSWindow, visible: false)
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        updateVisibility(for: notification.object as? NSWindow, visible: false)
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        updateVisibilityFromWindows()
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        updateVisibilityFromWindows()
    }

    private func installWindowDelegates() {
        controlWindowController.window?.delegate = self
        teleprompterWindowController.window?.delegate = self
    }

    private func updateVisibility(for window: NSWindow?, visible: Bool) {
        guard let window else { return }
        if window === controlWindowController.window {
            isControlWindowVisible = visible
        }
        if window === teleprompterWindowController.window {
            isTeleprompterWindowVisible = visible
        }
    }

    private func updateVisibilityFromWindows() {
        isControlWindowVisible = controlWindowController.window?.isVisible ?? false
        isTeleprompterWindowVisible = teleprompterWindowController.window?.isVisible ?? false
    }
}

extension ControlWindowController: ControlWindowPresenting {
    public func showControlWindow() {
        present()
    }
}

extension TeleprompterWindowController: TeleprompterWindowPresenting {
    public func showTeleprompterWindow(targetFrame: NSRect?) {
        present(on: targetFrame)
    }
}
