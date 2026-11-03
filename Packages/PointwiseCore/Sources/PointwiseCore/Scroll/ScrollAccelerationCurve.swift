import Foundation

/// Maps wheel speed to the distance a notch travels.
///
/// Slow, deliberate scrolling (below `threshold`) is never accelerated, so single notches stay
/// predictable. Above it the multiplier grows as a power curve and levels off at `maximumInput`
/// so a hard flick cannot jump arbitrarily far.
public struct ScrollAccelerationCurve: Equatable, Sendable {
    /// Notches per second that still count as precise scrolling.
    public static let threshold = 3.0
    /// A brisk spin; at full acceleration a notch travels `1 + maximumBoost` times further here.
    public static let reference = 25.0
    /// Speeds above this are treated as this speed.
    public static let maximumInput = 40.0
    static let maximumBoost = 9.0
    static let exponent = 1.5

    /// 0...1, from `ScrollSettings.acceleration`.
    public var acceleration: Double

    public init(acceleration: Double) {
        self.acceleration = acceleration.finite(or: 0).clamped(to: 0...1)
    }

    public func multiplier(notchesPerSecond speed: Double) -> Double {
        let speed = speed.finite(or: 0).clamped(to: 0...Self.maximumInput)
        let excess = max(0, speed - Self.threshold) / (Self.reference - Self.threshold)
        return 1 + acceleration * Self.maximumBoost * pow(excess, Self.exponent)
    }

    public var maximumMultiplier: Double { multiplier(notchesPerSecond: Self.maximumInput) }
}
