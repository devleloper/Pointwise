#if DEBUG
import AppKit
import PointwiseCore
import SwiftUI

/// `Pointwise --snapshot <directory>` renders the app's windows to PNG in light and dark
/// appearance, then quits. Rendering is offscreen, so no Screen Recording permission is needed.
/// The screenshots show sample settings, which are neither saved nor applied to any device.
@MainActor
enum DebugSnapshots {
    private struct Shot {
        let name: String
        let title: String
        let view: AnyView
        let size: NSSize?
        let appearance: NSAppearance?
        let url: URL
    }

    static func runIfRequested(model: AppModel) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var sample = AppSettings()
        sample.customizesPointer = true
        sample.pointer = PointerSettings(speed: 1.25)
        sample.hasCompletedOnboarding = true
        model.preview(sample)

        var screens: [(name: String, title: String, view: AnyView, size: NSSize?)] = [
            ("welcome", "", AnyView(WelcomeView {}.environment(model)), nil)
        ]
        for pane in SettingsPane.allCases {
            screens.append((pane.rawValue, "Pointwise Settings", AnyView(SettingsView(navigation: SettingsNavigation(pane: pane)).environment(model).environment(\.isRenderingSnapshot, true)), NSSize(width: 780, height: 680)))
        }
        let appearances: [(name: String, appearance: NSAppearance?)] = [
            ("light", NSAppearance(named: .aqua)),
            ("dark", NSAppearance(named: .darkAqua)),
        ]
        let shots = screens.flatMap { screen in
            appearances.map {
                Shot(name: screen.name, title: screen.title, view: screen.view, size: screen.size, appearance: $0.appearance,
                     url: directory.appendingPathComponent("\(screen.name)-\($0.name).png"))
            }
        }

        NSApp.setActivationPolicy(.regular)
        // Controls only draw their active look in the active app.
        NSApp.activate(ignoringOtherApps: true)
        capture(shots[...])
        return true
    }

    /// One window at a time, made key, so selection and controls render in their active look.
    private static func capture(_ shots: ArraySlice<Shot>) {
        guard let shot = shots.first else {
            NSApp.terminate(nil)
            return
        }
        let controller = NSHostingController(rootView: shot.view)
        controller.sizingOptions = []
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = shot.appearance
        window.title = shot.title
        window.titleVisibility = shot.title.isEmpty ? .hidden : .visible
        window.titlebarAppearsTransparent = shot.title.isEmpty
        window.toolbarStyle = .unified
        window.contentViewController = controller
        window.setContentSize(shot.size ?? controller.view.fittingSize)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)

        // Let SwiftUI finish layout and charts finish rendering before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let frameView = window.contentView?.superview,
               let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: shot.url)
            }
            window.close()
            capture(shots.dropFirst())
        }
    }
}
#endif
