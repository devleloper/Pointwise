import Foundation

/// Spreads each notch's distance over a short ease-out glide.
///
/// Every notch adds an independent segment and overlapping segments add up, so the total
/// distance is exactly the sum of the notches regardless of frame timing. Progress follows
/// `1 - (1 - t)^exponent`: it starts at full speed (no added latency) and decelerates to rest.
public struct GlideAnimator: Sendable {
    /// Bounds memory and work if events arrive faster than glides finish.
    static let maximumSegments = 64

    private struct Segment {
        let distance: Double
        let start: Double
        let duration: Double
        let exponent: Double
        var progress = 0.0
    }

    private var segments: [Segment] = []

    public init() {}

    public var isActive: Bool { !segments.isEmpty }

    /// Distance the active glides still have to travel.
    public var remainingDistance: Double {
        segments.reduce(0) { $0 + $1.distance * (1 - $1.progress) }
    }

    /// Starts a glide of `distance` at `time`. A notch in the opposite direction cancels the
    /// remaining glide first, so reversing the wheel stops the content immediately.
    public mutating func add(distance: Double, at time: Double, duration: Double, exponent: Double) {
        guard distance != 0, distance.isFinite else { return }
        if let current = segments.first, current.distance.sign != distance.sign {
            segments.removeAll()
        }
        if segments.count >= Self.maximumSegments {
            // Merge the remainder of the oldest glide into the new one instead of dropping it.
            let oldest = segments.removeFirst()
            let carried = oldest.distance * (1 - oldest.progress)
            segments.append(Segment(distance: distance + carried, start: time, duration: max(duration, 0), exponent: max(exponent, 1)))
            return
        }
        segments.append(Segment(distance: distance, start: time, duration: max(duration, 0), exponent: max(exponent, 1)))
    }

    /// Distance to move between the previous call and `time`.
    public mutating func advance(to time: Double) -> Double {
        var delta = 0.0
        for index in segments.indices {
            let segment = segments[index]
            let progress = Self.progress(elapsed: time - segment.start, duration: segment.duration, exponent: segment.exponent)
            guard progress > segment.progress else { continue }
            delta += segment.distance * (progress - segment.progress)
            segments[index].progress = progress
        }
        segments.removeAll { $0.progress >= 1 }
        return delta
    }

    public mutating func stop() {
        segments.removeAll()
    }

    /// Eased progress in 0...1.
    public static func progress(elapsed: Double, duration: Double, exponent: Double) -> Double {
        guard duration > 0 else { return elapsed >= 0 ? 1 : 0 }
        let t = (elapsed / duration).clamped(to: 0...1)
        return 1 - pow(1 - t, exponent)
    }
}
