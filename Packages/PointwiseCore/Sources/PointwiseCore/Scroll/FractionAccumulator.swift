/// Turns fractional distances into the whole points or lines that scroll events carry,
/// keeping the remainder so no distance is lost or invented over many events.
public struct FractionAccumulator: Sendable {
    public private(set) var remainder = 0.0

    public init() {}

    /// Whole points to send now; the fraction is kept for later.
    public mutating func take(_ delta: Double) -> Int {
        guard delta.isFinite else { return 0 }
        let total = remainder + delta
        let whole = total.rounded(.towardZero)
        remainder = total - whole
        return Int(whole)
    }

    /// Rounds away what is left once a glide ends.
    public mutating func flush() -> Int {
        let whole = remainder.rounded()
        remainder = 0
        return Int(whole)
    }

    public mutating func reset() {
        remainder = 0
    }
}
