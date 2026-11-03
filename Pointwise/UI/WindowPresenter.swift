import AppKit
import SwiftUI

/// Owns the single Welcome or Settings window and releases it on close,
/// so an idle menu bar app keeps no view hierarchy in memory.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var isShowingWelcome = false
    private let navigation = SettingsNavigation()

    init(model: AppModel) {
        self.model = model
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane {
            navigation.pane = pane
        }
        if let window, !isShowingWelcome {
            // Already open: keep its size and state, just bring it forward.
            bringToFront(window)
            return
        }
        if isShowingWelcome {
            model.completeOnboarding()
            isShowingWelcome = false
        }
        present(SettingsView(navigation: navigation), title: String(localized: "Pointwise Settings"), resizable: true)
    }

    func showWelcome() {
        isShowingWelcome = true
        present(WelcomeView { [weak self] in
            self?.model.completeOnboarding()
            self?.showSettings()
        }, title: String(localized: "Welcome to Pointwise"), resizable: false)
    }

    func windowWillClose(_ notification: Notification) {
        if isShowingWelcome {
            model.completeOnboarding()
        }
        window?.contentViewController = nil
        window = nil
        // Back to a menu bar-only app once the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }

    private func present(_ content: some View, title: String, resizable: Bool) {
        let controller = NSHostingController(rootView: content.environment(model))
        // Size the window once; letting the hosting controller resize it continuously
        // can send Auto Layout into a loop.
        controller.sizingOptions = []

        let isNew = window == nil
        let window = window ?? makeWindow()
        window.contentViewController = controller
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = !resizable
        window.titleVisibility = resizable ? .visible : .hidden
        window.toolbarStyle = .unified
        window.setContentSize(controller.view.fittingSize)
        window.contentMinSize = resizable ? NSSize(width: 680, height: 480) : window.contentLayoutRect.size
        if isNew {
            window.center()
            window.setFrameAutosaveName(resizable ? "Settings" : "Welcome")
            self.window = window
        }

        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        // A menu bar-only app cannot reliably bring a window to the front; while a window is
        // open, Pointwise behaves like a regular app with a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
