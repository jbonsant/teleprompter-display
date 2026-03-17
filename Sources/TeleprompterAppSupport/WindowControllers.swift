import AppKit
import SwiftUI

@MainActor
public final class ControlWindowController: NSWindowController {
    public init(store: AppSessionStore) {
        let rootView = ControlRootView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Teleprompter Control"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

@MainActor
public final class TeleprompterWindowController: NSWindowController {
    private let store: AppSessionStore

    public init(store: AppSessionStore) {
        self.store = store
        let rootView = TeleprompterRootView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = TeleprompterWindow(contentViewController: hostingController)
        window.title = "Teleprompter Display"
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.backgroundColor = .black
        super.init(window: window)
        let teleWindow = window as TeleprompterWindow
        teleWindow.keyHandler = { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 49: // Space — toggle pause
            store.handleTogglePause()
        case 53: // Escape — emergency scroll
            store.handleEmergencyScroll()
        case 123: // Left arrow — previous segment
            store.handlePreviousSegment()
        case 124: // Right arrow — next segment
            store.handleNextSegment()
        default:
            break
        }
    }
}

/// Custom NSWindow subclass that captures key events for the teleprompter.
private class TeleprompterWindow: NSWindow {
    var keyHandler: (@MainActor (NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        keyHandler?(event)
    }
}
