import AppKit
import TeleprompterAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppSessionStore()
    private var controlWindowController: ControlWindowController?
    private var teleprompterWindowController: TeleprompterWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlWindowController = ControlWindowController(store: store)
        teleprompterWindowController = TeleprompterWindowController(store: store)

        controlWindowController?.showWindow(nil)
        teleprompterWindowController?.showWindow(nil)
        positionTeleprompterWindow()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func positionTeleprompterWindow() {
        guard let window = teleprompterWindowController?.window else {
            return
        }

        let candidateScreen = NSScreen.screens.dropFirst().first ?? NSScreen.main
        guard let frame = candidateScreen?.visibleFrame else {
            return
        }

        let size = window.frame.size
        let origin = NSPoint(
            x: frame.minX + max(0, frame.width - size.width) / 2,
            y: frame.minY + max(0, frame.height - size.height) / 2
        )
        window.setFrameOrigin(origin)
    }
}
