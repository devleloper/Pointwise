import AppKit
import os
import PointwiseCore

/// Rewrites mouse-wheel events with a Quartz event tap on a dedicated thread.
///
/// The tap sees scroll-wheel events only: keyboard, clicks and pointer motion never reach it,
/// so a stalled or revoked tap can never block them. Gesture-phase events from trackpads and
/// Magic Mouse pass through untouched.
final class ScrollEventTap: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var settings: ScrollSettings
        var frameInterval: Double
    }

    /// Marks events Pointwise synthesized so the tap passes them through instead of processing them again.
    private static let marker: Int64 = 0x506F_696E_7477 // "Pointw"
    /// Modifiers that change what a scroll does in apps (zoom, horizontal, …).
    private static let relevantModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
    private static let eventMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
    /// `kCGScrollPhaseBegan` and `kCGScrollPhaseMayBegin`: a finger touched the trackpad.
    private static let touchPhases: Set<Int64> = [1, 128]

    /// Written on the main thread, read by the tap thread.
    private let pendingConfiguration = OSAllocatedUnfairLock<Configuration?>(initialState: nil)

    // Owned by the main thread.
    private var thread: Thread?
    private var controlRunLoop: CFRunLoop?
    private var controlTap: CFMachPort?
    private var finished: DispatchSemaphore?
    /// A thread that didn't stop in time; no new one may start until it has.
    private var lingering: DispatchSemaphore?

    // Confined to the tap thread while it runs.
    private var tap: CFMachPort?
    private var configuration: Configuration
    private var scroller: WheelScroller
    private var frameTimer: CFRunLoopTimer?
    private var glideFlags: CGEventFlags = []
    private let clock = ContinuousClock()
    /// Source of every synthesized event. By default macOS suppresses local mouse and keyboard
    /// input for 0.25 s after each posted event; with glide frames every few milliseconds the
    /// pointer would barely move while scrolling.
    private let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        let permitAll: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source?.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateSuppressionInterval)
        source?.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateRemoteMouseDrag)
        return source
    }()
    private let origin = ContinuousClock.now

    init(configuration: Configuration) {
        self.configuration = configuration
        scroller = WheelScroller(settings: configuration.settings)
    }

    var isRunning: Bool { thread != nil }

    /// `false` when macOS disabled or invalidated the tap and it needs to be recreated.
    @MainActor
    var isHealthy: Bool {
        guard let controlTap else { return false }
        return CFMachPortIsValid(controlTap) && CGEvent.tapIsEnabled(tap: controlTap)
    }

    /// Creates the tap on its own thread. Fails without Accessibility access.
    @MainActor
    func start() -> Bool {
        guard thread == nil else { return true }
        if let lingering {
            guard lingering.wait(timeout: .now()) == .success else { return false }
            self.lingering = nil
        }
        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            defer { finished.signal() }
            guard let tap = createTap() else {
                ready.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            self.tap = tap
            controlRunLoop = runLoop
            controlTap = tap
            ready.signal()

            CFRunLoopRun()

            stopGlide()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        thread.name = "io.github.devleloper.Pointwise.scroll"
        // Scroll latency matters more than throughput.
        thread.qualityOfService = .userInteractive
        thread.start()
        // The semaphore orders the tap thread's writes before these reads.
        ready.wait()
        guard controlTap != nil else {
            finished.wait()
            Log.scroll.error("Could not create the scroll event tap")
            return false
        }
        self.thread = thread
        self.finished = finished
        Log.scroll.notice("Scroll event tap started")
        return true
    }

    /// Stops the tap and waits for its thread, so a following `start()` never overlaps it.
    @MainActor
    func stop() {
        guard thread != nil, let controlRunLoop else { return }
        performOnTapThread(controlRunLoop) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(controlRunLoop)
        if let finished, finished.wait(timeout: .now() + 2) == .timedOut {
            Log.scroll.error("Scroll event tap thread did not stop in time")
            lingering = finished
        }
        thread = nil
        finished = nil
        self.controlRunLoop = nil
        controlTap = nil
        Log.scroll.notice("Scroll event tap stopped")
    }

    /// Takes effect with the next event.
    func update(_ configuration: Configuration) {
        pendingConfiguration.withLock { $0 = configuration }
    }

    /// Stops a running glide, e.g. because the user clicked: content still moving would make
    /// the click land somewhere else.
    @MainActor
    func cancelGlide() {
        guard let controlRunLoop else { return }
        performOnTapThread(controlRunLoop) { [self] in
            stopGlide()
        }
        CFRunLoopWakeUp(controlRunLoop)
    }

    /// Runs `block` on the tap thread's run loop. The block must be `@Sendable`: a plain closure
    /// written in a main-actor method inherits main-actor isolation, and Swift traps when it then
    /// runs on another thread.
    private nonisolated func performOnTapThread(_ runLoop: CFRunLoop, _ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
    }

    // MARK: Tap thread

    private func createTap() -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ScrollEventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .scrollWheel:
            return handleScroll(event)
        case .tapDisabledByTimeout:
            // macOS disables taps that delay events; a glide may have been cut short.
            stopGlide()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .tapDisabledByUserInput:
            // Deliberate; the app's health check recreates the tap later.
            stopGlide()
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            return Unmanaged.passUnretained(event)
        }
        applyPendingConfiguration()

        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let kind = ScrollEventKind(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: scrollPhase,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )
        switch kind {
        case .gesture:
            if Self.touchPhases.contains(scrollPhase) {
                // The trackpad takes over; don't let the wheel's glide fight it.
                stopGlide()
            }
            return Unmanaged.passUnretained(event)
        case .preciseWheel:
            reverseInPlace(event)
            return Unmanaged.passUnretained(event)
        case .notchedWheel:
            guard configuration.settings.isCustomScrollingEnabled else {
                reverseInPlace(event)
                return Unmanaged.passUnretained(event)
            }
            return replaceNotches(event)
        }
    }

    private func replaceNotches(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let vertical = notchDirection(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
        let horizontal = notchDirection(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        guard vertical != 0 || horizontal != 0 else { return Unmanaged.passUnretained(event) }

        let flags = event.flags.intersection(Self.relevantModifiers)
        if scroller.isGliding, flags != glideFlags {
            // A glide that started as scrolling must not turn into zooming halfway.
            stopGlide()
        }
        glideFlags = flags

        let time = now
        let lead = configuration.frameInterval
        let verticalDelivery = scroller.notch(on: .vertical, direction: vertical, at: time, leadTime: lead)
        let horizontalDelivery = scroller.notch(on: .horizontal, direction: horizontal, at: time, leadTime: lead)
        if scroller.isGliding {
            startFrames()
        }

        var lines = WheelScroller.Output.zero
        var points = WheelScroller.Output.zero
        for delivery in [verticalDelivery, horizontalDelivery] {
            switch delivery {
            case .lines(let output):
                lines.vertical += output.vertical
                lines.horizontal += output.horizontal
            case .points(let output):
                points.vertical += output.vertical
                points.horizontal += output.horizontal
            case .none:
                break
            }
        }

        if !lines.isZero {
            setLines(event, lines)
            return Unmanaged.passUnretained(event)
        }
        // The first chunk replaces the original event in place, so nothing is delayed or duplicated.
        guard !points.isZero, let replacement = makeEvent(points, flags: event.flags) else { return nil }
        return Unmanaged.passRetained(replacement)
    }

    /// The sign of a discrete event's notch; the line delta is ±1 or more, never fractional.
    private func notchDirection(_ event: CGEvent, _ lines: CGEventField, _ fixed: CGEventField) -> Int {
        let delta = event.getIntegerValueField(lines)
        if delta != 0 { return Int(delta.signum()) }
        let fraction = event.getDoubleValueField(fixed)
        return fraction > 0 ? 1 : fraction < 0 ? -1 : 0
    }

    /// Writes whole lines into a classic wheel event. The line setter also overwrites the
    /// other two fields, so the order matters.
    private func setLines(_ event: CGEvent, _ lines: WheelScroller.Output) {
        let pointsPerLine = ScrollSettings.pointsPerLine
        for (value, fields) in [
            (lines.vertical, (CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1)),
            (lines.horizontal, (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)),
        ] {
            // The line field is 16-bit inside the event.
            let clamped = Int64(min(max(value, Int(Int16.min)), Int(Int16.max)))
            event.setIntegerValueField(fields.0, value: clamped)
            event.setDoubleValueField(fields.1, value: Double(clamped))
            event.setIntegerValueField(fields.2, value: Int64((Double(clamped) * pointsPerLine).rounded()))
        }
    }

    private func reverseInPlace(_ event: CGEvent) {
        let settings = configuration.settings
        if settings.reverseVertical {
            negate(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        }
        if settings.reverseHorizontal {
            negate(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        }
    }

    /// Reads all three representations first: setting the line delta overwrites the others.
    private func negate(_ event: CGEvent, _ lines: CGEventField, _ fixed: CGEventField, _ points: CGEventField) {
        let lineValue = event.getIntegerValueField(lines)
        let fixedValue = event.getDoubleValueField(fixed)
        let pointValue = event.getIntegerValueField(points)
        event.setIntegerValueField(lines, value: -lineValue)
        event.setDoubleValueField(fixed, value: -fixedValue)
        event.setIntegerValueField(points, value: -pointValue)
    }

    /// The event keeps the location it is created with, the pointer's current one, so a frame
    /// never points at a spot the pointer has already left.
    private func makeEvent(_ output: WheelScroller.Output, flags: CGEventFlags) -> CGEvent? {
        var vertical = output.vertical
        var horizontal = output.horizontal
        // AppKit turns Shift + wheel into horizontal scrolling only for classic wheel events,
        // not for the pixel-precise ones Pointwise sends, so do it here.
        if flags.contains(.maskShift), horizontal == 0 {
            swap(&vertical, &horizontal)
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: vertical),
            wheel2: Int32(clamping: horizontal),
            wheel3: 0
        ) else { return nil }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        return event
    }

    // MARK: Glide frames

    private func startFrames() {
        guard frameTimer == nil else { return }
        let interval = configuration.frameInterval
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0) { [weak self] _ in
            self?.deliverFrame()
        }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        frameTimer = timer
    }

    private func deliverFrame() {
        let modifiers = CGEventSource.flagsState(.combinedSessionState).intersection(Self.relevantModifiers)
        guard modifiers == glideFlags else {
            stopGlide()
            return
        }
        let output = scroller.frame(at: now)
        if !output.isZero, let event = makeEvent(output, flags: glideFlags) {
            event.post(tap: .cgSessionEventTap)
        }
        if !scroller.isGliding {
            stopFrames()
        }
    }

    private func stopGlide() {
        scroller.stop()
        stopFrames()
    }

    private func stopFrames() {
        guard let frameTimer else { return }
        CFRunLoopTimerInvalidate(frameTimer)
        self.frameTimer = nil
    }

    private func applyPendingConfiguration() {
        guard let new = pendingConfiguration.withLock({ value -> Configuration? in
            defer { value = nil }
            return value
        }) else { return }
        configuration = new
        scroller.update(settings: new.settings)
        if !scroller.isGliding { stopFrames() }
    }

    /// Seconds on a monotonic clock.
    private var now: Double {
        let elapsed = clock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }
}
