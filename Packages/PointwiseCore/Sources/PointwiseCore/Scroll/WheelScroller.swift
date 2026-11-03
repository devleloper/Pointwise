/// Pointwise scrolling for notched wheels: speed curve, reversal and optional glide.
///
/// Pure state machine driven by notches and frame ticks; the caller owns timing and event delivery.
/// Signs follow `CGEvent` scroll deltas.
public struct WheelScroller: Sendable {
    public struct Output: Equatable, Sendable {
        public var vertical: Int
        public var horizontal: Int

        public init(vertical: Int = 0, horizontal: Int = 0) {
            self.vertical = vertical
            self.horizontal = horizontal
        }

        public static let zero = Output()
        public var isZero: Bool { vertical == 0 && horizontal == 0 }
    }

    /// What to do with the wheel event that carried a notch.
    public enum Delivery: Equatable, Sendable {
        /// Rewrite the event in place with these whole lines; it stays a classic wheel event,
        /// so every app keeps its usual line handling (and AppKit its Shift-for-horizontal).
        case lines(Output)
        /// Replace the event with a pixel-precise one carrying these points; further points
        /// follow from `frame(at:)` while `isGliding`.
        case points(Output)
        /// Drop the event: the distance is too small to send yet.
        case none
    }

    private struct AxisState: Sendable {
        var speed = WheelSpeedEstimator()
        var glide = GlideAnimator()
        var remainder = FractionAccumulator()

        mutating func stop() {
            glide.stop()
            remainder.reset()
            speed.reset()
        }
    }

    public private(set) var settings: ScrollSettings
    private var curve: ScrollAccelerationCurve
    private var vertical = AxisState()
    private var horizontal = AxisState()

    public init(settings: ScrollSettings) {
        self.settings = settings.clamped()
        curve = ScrollAccelerationCurve(acceleration: self.settings.acceleration)
    }

    public var isGliding: Bool { vertical.glide.isActive || horizontal.glide.isActive }

    public mutating func update(settings newSettings: ScrollSettings) {
        let newSettings = newSettings.clamped()
        guard newSettings != settings else { return }
        let modeChanged = settings.isSmoothScrollingEnabled != newSettings.isSmoothScrollingEnabled
        settings = newSettings
        curve = ScrollAccelerationCurve(acceleration: newSettings.acceleration)
        if modeChanged {
            // Remainders are in lines in one mode and points in the other.
            stop()
        }
    }

    /// Handles one notch in `direction` (its sign) on `axis` at `time` seconds.
    /// `leadTime` lets the first chunk of a glide go out with the notch instead of a frame later.
    public mutating func notch(on axis: ScrollAxis, direction: Int, at time: Double, leadTime: Double) -> Delivery {
        guard direction != 0 else { return .none }
        let state = keyPath(for: axis)
        let speed = self[keyPath: state].speed.registerNotch(direction: direction, at: time)
        let sign = Double(direction.signum() * reversalSign(for: axis))
        let distance = sign * settings.pointsPerNotch * curve.multiplier(notchesPerSecond: speed)

        // Reversing drops the fraction left over from the old direction.
        let remainder = self[keyPath: state].remainder.remainder
        if remainder != 0, remainder.sign != distance.sign {
            self[keyPath: state].remainder.reset()
        }

        guard settings.isSmoothScrollingEnabled else {
            let lines = self[keyPath: state].remainder.take(distance / ScrollSettings.pointsPerLine)
            guard lines != 0 else { return .none }
            return .lines(axis == .vertical ? Output(vertical: lines) : Output(horizontal: lines))
        }
        self[keyPath: state].glide.add(distance: distance, at: time, duration: settings.glideDuration, exponent: settings.glideExponent)
        let points = frame(at: time + max(leadTime, 0))
        return points.isZero ? .none : .points(points)
    }

    /// Points to deliver for a display frame at `time`.
    public mutating func frame(at time: Double) -> Output {
        Output(vertical: advance(&vertical, to: time), horizontal: advance(&horizontal, to: time))
    }

    /// Cancels glides, e.g. when the user clicks or touches the trackpad.
    public mutating func stop() {
        vertical.stop()
        horizontal.stop()
    }

    /// Sign to apply to deltas that Pointwise passes through instead of generating.
    public func reversalSign(for axis: ScrollAxis) -> Int {
        let reversed = switch axis {
        case .vertical: settings.reverseVertical
        case .horizontal: settings.reverseHorizontal
        }
        return reversed ? -1 : 1
    }

    private func advance(_ state: inout AxisState, to time: Double) -> Int {
        guard state.glide.isActive else { return 0 }
        var points = state.remainder.take(state.glide.advance(to: time))
        if !state.glide.isActive {
            points += state.remainder.flush()
        }
        return points
    }

    private func keyPath(for axis: ScrollAxis) -> WritableKeyPath<WheelScroller, AxisState> {
        switch axis {
        case .vertical: \.vertical
        case .horizontal: \.horizontal
        }
    }
}
