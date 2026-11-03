/// How Pointwise treats an incoming scroll-wheel event.
public enum ScrollEventKind: Equatable, Sendable {
    /// Carries a scroll or momentum phase: trackpads, Magic Mouse and other gesture devices.
    /// Always passed through untouched so system gestures, rubber-banding and momentum keep working.
    case gesture
    /// Pixel-precise deltas without phases, e.g. high-resolution wheels. Only reversal applies.
    case preciseWheel
    /// A classic wheel that reports whole notches.
    case notchedWheel

    public init(isContinuous: Bool, scrollPhase: Int64, momentumPhase: Int64) {
        if scrollPhase != 0 || momentumPhase != 0 {
            self = .gesture
        } else if isContinuous {
            self = .preciseWheel
        } else {
            self = .notchedWheel
        }
    }
}

public enum ScrollAxis: CaseIterable, Sendable {
    case vertical
    case horizontal
}
