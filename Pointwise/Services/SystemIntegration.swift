import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement

/// Access to modify input events, shown to users as Accessibility in System Settings.
/// Needed only for the scroll event tap.
enum Accessibility {
    /// Cheap, but can stay `true` for a while after the user revokes access.
    static var isGranted: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    /// Asks tccd directly, which also notices revocation. Blocking IPC: call it off the main thread.
    nonisolated static func checkWithSystem() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted || AXIsProcessTrusted()
    }

    /// Adds Pointwise to the Accessibility list and prompts once; afterwards macOS only reports.
    @discardableResult
    static func request() -> Bool {
        CGRequestPostEventAccess()
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

@MainActor
enum AppRelauncher {
    /// Set while quitting for a relaunch, so this instance leaves the devices to the next one.
    private(set) static var isRelaunching = false

    /// macOS applies a newly granted permission to an existing event tap only after a relaunch.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        isRelaunching = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    isRelaunching = false
                    Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Login items registered from a disk image or Downloads (App Translocation) can break.
    static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.deletingLastPathComponent().path
        return path == "/Applications" || path == NSHomeDirectory() + "/Applications"
    }
}

enum MouseSettings {
    static func open() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension")!)
    }

    /// The macOS "Natural scrolling" choice, which applies to mice and trackpads alike.
    static var isNaturalScrollingEnabled: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }
}
