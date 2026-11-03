import AppKit
import SwiftUI

@main
struct PointwiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let model = appDelegate.model
        MenuBarExtra(isInserted: Binding(
            get: { model.settings.showsMenuBarIcon },
            // macOS removes the item when the user ⌘-drags it out of the menu bar.
            set: { shown in if !shown { model.update { $0.showsMenuBarIcon = false } } }
        )) {
            MenuBarMenu(model: model, windows: appDelegate.windows)
        } label: {
            Image(systemName: model.settings.isEnabled ? "cursorarrow.motionlines" : "cursorarrow")
                .accessibilityLabel(model.settings.isEnabled ? Text("Pointwise") : Text("Pointwise (paused)"))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private(set) lazy var windows = WindowPresenter(model: model)
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugSnapshots.runIfRequested(model: model) { return }
        #endif
        terminateCleanlyOnSignals()
        model.start()
        if !model.settings.hasCompletedOnboarding {
            windows.showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    /// Reopening the app from Finder or Spotlight shows Settings,
    /// the way back in when the menu bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshSystemState()
    }

    /// `kill`, `launchctl` and Ctrl-C quit through `NSApp.terminate`, so devices are always
    /// handed back to macOS.
    private func terminateCleanlyOnSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}
