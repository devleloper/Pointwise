/// Estimates how fast the wheel spins, in notches per second, from the timing of notches.
public struct WheelSpeedEstimator: Sendable {
    /// A pause longer than this starts a new gesture at rest.
    public static let resetInterval = 0.35
    /// Notches closer together than this arrived bunched (several reports delivered at once),
    /// so their spacing says nothing about the wheel's speed.
    static let maximumRate = 120.0
    /// Weight of the newest reading; damps jitter in notch timing without lagging behind real changes.
    static let smoothing = 0.5

    private var lastTime: Double?
    private var lastDirection = 0
    public private(set) var notchesPerSecond = 0.0

    public init() {}

    /// Records a notch in `direction` (its sign) at `time` seconds and returns the updated speed.
    @discardableResult
    public mutating func registerNotch(direction: Int, at time: Double) -> Double {
        let direction = direction.signum()
        guard let lastTime, direction == lastDirection, direction != 0, time - lastTime < Self.resetInterval else {
            restart(direction: direction, at: time)
            return 0
        }
        let interval = time - lastTime
        // Keep the estimate and the reference time; the next notch measures across the bunch.
        guard interval >= 1 / Self.maximumRate else { return notchesPerSecond }
        let reading = 1 / interval
        notchesPerSecond = notchesPerSecond == 0 ? reading : notchesPerSecond + Self.smoothing * (reading - notchesPerSecond)
        self.lastTime = time
        return notchesPerSecond
    }

    private mutating func restart(direction: Int, at time: Double) {
        lastTime = time
        lastDirection = direction
        notchesPerSecond = 0
    }

    public mutating func reset() {
        lastTime = nil
        lastDirection = 0
        notchesPerSecond = 0
    }
}
