import AppKit
import SwiftUI

@MainActor
public final class ControlWindowController: NSWindowController {
    public init(
        store: AppSessionStore,
        onShowDisplay: @escaping () -> Void = {},
        onRestartApp: @escaping () -> Void = {}
    ) {
        let rootView = ControlRootView(
            store: store,
            onShowDisplay: onShowDisplay,
            onRestartApp: onRestartApp
        )
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

    public func present() {
        super.showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        window.styleMask.insert(.fullSizeContentView)
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func showWindow(_ sender: Any?) {
        present(on: window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
    }

    public func present(on targetFrame: NSRect?) {
        super.showWindow(nil)
        guard let window else { return }
        if let targetFrame {
            window.setFrame(targetFrame, display: true, animate: true)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
