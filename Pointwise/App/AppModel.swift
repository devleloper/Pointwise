import AppKit
import Observation
import PointwiseCore
import ServiceManagement

/// Owns settings and keeps the pointer service and the scroll tap in sync with them.
@MainActor @Observable
final class AppModel {
    enum ScrollState: Equatable {
        /// Nothing to do: Pointwise is paused or every scrolling option is off.
        case off
        case running
        /// Waiting for the user to grant Accessibility.
        case needsPermission
        /// Access is granted but macOS refused the tap; a relaunch fixes it.
        case failed
    }

    /// How often Pointwise checks that macOS has not reset tracking values, that the tap is
    /// still enabled and whether Accessibility access changed. Each check is a few property reads.
    private static let maintenanceInterval: TimeInterval = 2

    private(set) var settings: AppSettings
    private(set) var devices: [PointerDevice] = []
    private(set) var scrollState: ScrollState = .off
    /// Services whose tracking value macOS refused to change.
    private(set) var pointerFailures = 0
    /// The macOS mouse tracking setting, or `nil` when macOS doesn't report one.
    private(set) var systemSettings: PointerSettings?
    private(set) var isAccessibilityGranted = Accessibility.isGranted
    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var launchAtLoginError: String?

    @ObservationIgnored private let store = SettingsStore()
    @ObservationIgnored private let pointer = PointerService()
    @ObservationIgnored private let deviceMonitor = DeviceMonitor()
    @ObservationIgnored private let scrollTap: ScrollEventTap
    @ObservationIgnored private var maintenanceTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private var delayedReapply: Task<Void, Never>?
    @ObservationIgnored private var permissionCheck: Task<Void, Never>?
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var isSessionActive = true
    /// Asleep or another user's session is active: no tap and no HID writes.
    private var isSuspended: Bool { isAsleep || !isSessionActive }

    init() {
        let settings = store.load()
        self.settings = settings
        scrollTap = ScrollEventTap(configuration: .init(settings: settings.scroll, frameInterval: Self.frameInterval()))
    }

    var needsAttention: Bool {
        scrollState == .needsPermission || scrollState == .failed || pointerFailures > 0
    }

    func start() {
        deviceMonitor.onChange = { [weak self] in self?.devicesChanged() }
        deviceMonitor.start()
        observeSystem()
        refreshSystemState()
        // Also undoes a previous instance handing devices back during a relaunch.
        scheduleDelayedReapply()
    }

    /// Hands every device back to macOS. Called when the app quits.
    func shutdown() {
        maintenanceTimer?.invalidate()
        setClickMonitor(enabled: false)
        scrollTap.stop()
        // During a relaunch the new instance takes the devices over.
        if !AppRelauncher.isRelaunching {
            pointer.restoreAll()
        }
        deviceMonitor.stop()
    }

    /// Re-reads state that the user can change outside the app. Called on launch and activation.
    func refreshSystemState() {
        readSystemState()
        apply()
    }

    private func readSystemState() {
        launchAtLoginStatus = LaunchAtLogin.status
        systemSettings = pointer.systemSettings
        isAccessibilityGranted = Accessibility.isGranted
        devices = pointer.devices()
    }

    #if DEBUG
    /// Shows `settings` without saving or applying them, for screenshots.
    func preview(_ settings: AppSettings) {
        readSystemState()
        self.settings = settings
    }
    #endif

    // MARK: Settings

    func update(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        store.save(updated)
        apply()
    }

    func setEnabled(_ enabled: Bool) {
        update { $0.isEnabled = enabled }
    }

    /// Starting to customize begins from the current macOS setting, so nothing jumps.
    func setCustomizesPointer(_ customizes: Bool) {
        update { settings in
            if customizes, !settings.customizesPointer, settings.pointer == PointerSettings(), let systemSettings {
                settings.pointer = systemSettings
            }
            settings.customizesPointer = customizes
        }
    }

    func setRule(_ rule: DeviceRule, for device: DeviceIdentity) {
        update { $0.setRule(rule, for: device) }
    }

    /// Leaves every device to macOS and resets scrolling to the defaults.
    func restoreDefaults() {
        update { $0 = $0.restoringDefaults() }
        Log.app.notice("Settings restored to defaults")
    }

    func completeOnboarding() {
        update { $0.hasCompletedOnboarding = true }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginStatus = LaunchAtLogin.status
    }

    func requestAccessibility() {
        if !Accessibility.request() {
            Accessibility.openSystemSettings()
        }
    }

    /// Devices with a stored rule that are not connected right now.
    var rememberedDevices: [DeviceIdentity] {
        let connected = Set(devices.map(\.identity))
        return settings.devices.values.map(\.identity).filter { !connected.contains($0) }.sorted()
    }

    // MARK: Applying

    private func apply() {
        applyPointer()
        updateScrollTap()
        updateMaintenance()
    }

    private func applyPointer() {
        guard !isSuspended else { return }
        let settings = settings
        let failures = pointer.apply { settings.pointerSettings(for: $0) }
        if failures != pointerFailures {
            pointerFailures = failures
        }
    }

    private func updateScrollTap(recreate: Bool = false) {
        let scroll = settings.scroll
        let wanted = settings.isEnabled && (scroll.isCustomScrollingEnabled || scroll.reverseVertical || scroll.reverseHorizontal)
        let state: ScrollState
        if !wanted {
            scrollTap.stop()
            state = .off
        } else if isSuspended {
            // Keep reporting the last state; the tap comes back on resume.
            scrollTap.stop()
            state = scrollState
        } else if !Accessibility.isGranted {
            scrollTap.stop()
            state = .needsPermission
        } else {
            if recreate { scrollTap.stop() }
            scrollTap.update(.init(settings: scroll, frameInterval: Self.frameInterval()))
            state = scrollTap.start() ? .running : .failed
        }
        setClickMonitor(enabled: scrollTap.isRunning && scroll.isCustomScrollingEnabled && scroll.isSmoothScrollingEnabled)
        if state != scrollState {
            scrollState = state
            Log.scroll.notice("Scrolling: \(String(describing: state), privacy: .public)")
        }
    }

    /// Clicking stops a glide. A passive global monitor, so clicks never pass through the tap.
    private func setClickMonitor(enabled: Bool) {
        if enabled, clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrollTap.cancelGlide() }
            }
        } else if !enabled, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func updateMaintenance() {
        let needed = pointer.managesAnyDevice || scrollState != .off
        if needed, maintenanceTimer == nil {
            let timer = Timer(timeInterval: Self.maintenanceInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.maintain() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            maintenanceTimer = timer
        } else if !needed {
            maintenanceTimer?.invalidate()
            maintenanceTimer = nil
        }
    }

    private func maintain() {
        guard !isSuspended else { return }
        if pointer.reapplyDrifted() {
            systemSettings = pointer.systemSettings
            Log.pointer.notice("Tracking was changed outside Pointwise; re-applied")
        }
        if scrollState == .running, !scrollTap.isHealthy {
            Log.scroll.notice("Scroll event tap was disabled; recreating it")
            updateScrollTap(recreate: true)
        } else if scrollState == .failed {
            // Creating a tap is cheap; it may work now (e.g. after a slow previous thread finished).
            updateScrollTap()
        }
        checkPermission()
    }

    /// Notices Accessibility being granted or revoked in System Settings without blocking the UI.
    private func checkPermission() {
        guard permissionCheck == nil, scrollState == .running || scrollState == .needsPermission else { return }
        permissionCheck = Task { [weak self] in
            let granted = await Task.detached(priority: .utility) { Accessibility.checkWithSystem() }.value
            guard let self else { return }
            permissionCheck = nil
            isAccessibilityGranted = granted
            if scrollState == .running, !granted {
                Log.scroll.notice("Accessibility access was revoked")
                scrollTap.stop()
                scrollState = .needsPermission
                setClickMonitor(enabled: false)
            } else if scrollState == .needsPermission, granted {
                updateScrollTap()
            }
            updateMaintenance()
        }
    }

    private func devicesChanged() {
        devices = pointer.devices()
        // Resuming applies everything anyway.
        guard !isSuspended else { return }
        applyPointer()
        updateMaintenance()
        // macOS applies its own tracking value to a new device shortly after it appears.
        scheduleDelayedReapply()
    }

    private func scheduleDelayedReapply() {
        delayedReapply?.cancel()
        delayedReapply = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !isSuspended else { return }
            devices = pointer.devices()
            applyPointer()
            _ = pointer.reapplyDrifted()
        }
    }

    private enum SystemTransition: Sendable {
        case sleep, wake, sessionResigned, sessionActivated
    }

    /// Sleep and session switches are tracked separately: waking up while another user's
    /// session is active must not resume Pointwise there.
    private func handle(_ transition: SystemTransition) {
        let wasSuspended = isSuspended
        switch transition {
        case .sleep: isAsleep = true
        case .wake: isAsleep = false
        case .sessionResigned: isSessionActive = false
        case .sessionActivated: isSessionActive = true
        }
        guard isSuspended != wasSuspended else { return }
        Log.app.notice("\(self.isSuspended ? "Suspended" : "Resumed", privacy: .public)")
        if !isSessionActive {
            // Tracking values are system-wide; the other user gets their own macOS settings.
            pointer.restoreAll()
        }
        // Taps are recreated after sleep and session switches rather than trusted to survive them.
        updateScrollTap(recreate: !isSuspended)
        if !isSuspended { scheduleDelayedReapply() }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let transitions: [(Notification.Name, SystemTransition)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActivated),
        ]
        for (name, transition) in transitions {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(transition) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScrollTap() }
        })
    }

    /// One glide frame per refresh of the fastest display, between 60 and 240 Hz.
    private static func frameInterval() -> Double {
        let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
        return 1 / Double(min(max(fps, 60), 240))
    }
}
