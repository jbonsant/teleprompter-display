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
    public init(store: AppSessionStore) {
        let rootView = TeleprompterRootView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Teleprompter Display"
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.backgroundColor = .black
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
