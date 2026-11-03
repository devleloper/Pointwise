/// Mouse-wheel behaviour. Trackpads and Magic Mouse are never affected.
public struct ScrollSettings: Codable, Equatable, Sendable {
    public static let linesPerNotchRange: ClosedRange<Double> = 1...12
    /// Quartz converts one scroll line to ten points.
    public static let pointsPerLine = 10.0

    /// Pointwise's own speed curve and glide for notched wheels.
    /// When off, macOS scrolls as usual; reversing still applies.
    public var isCustomScrollingEnabled = true
    /// Distance of a single slow notch.
    public var linesPerNotch = 4.0
    /// 0 keeps every notch the same length; 1 makes fast spins travel furthest.
    public var acceleration = 0.5
    public var isSmoothScrollingEnabled = true
    /// 0 is a short glide, 1 a long one.
    public var smoothness = 0.5
    /// 0 eases into motion gently, 1 moves most of the way at once.
    public var responsiveness = 0.5
    public var reverseVertical = false
    public var reverseHorizontal = false

    public init() {}

    public var pointsPerNotch: Double { linesPerNotch * Self.pointsPerLine }

    public var glideDuration: Double {
        Self.glideDurationRange.lowerBound + smoothness * (Self.glideDurationRange.upperBound - Self.glideDurationRange.lowerBound)
    }

    /// Exponent of the ease-out curve `1 - (1 - t)^k`; larger values front-load the motion.
    public var glideExponent: Double {
        Self.glideExponentRange.lowerBound + responsiveness * (Self.glideExponentRange.upperBound - Self.glideExponentRange.lowerBound)
    }

    static let glideDurationRange: ClosedRange<Double> = 0.08...0.6
    static let glideExponentRange: ClosedRange<Double> = 1.5...6

    /// Brings every value into its valid range, e.g. after decoding edited preferences.
    public func clamped() -> ScrollSettings {
        let defaults = ScrollSettings()
        var result = self
        result.linesPerNotch = linesPerNotch.finite(or: defaults.linesPerNotch).clamped(to: Self.linesPerNotchRange)
        result.acceleration = acceleration.finite(or: defaults.acceleration).clamped(to: 0...1)
        result.smoothness = smoothness.finite(or: defaults.smoothness).clamped(to: 0...1)
        result.responsiveness = responsiveness.finite(or: defaults.responsiveness).clamped(to: 0...1)
        return result
    }
}

extension ScrollSettings {
    private enum CodingKeys: String, CodingKey {
        case isCustomScrollingEnabled, linesPerNotch, acceleration, isSmoothScrollingEnabled
        case smoothness, responsiveness, reverseVertical, reverseHorizontal
    }

    /// Tolerates missing or unknown values so settings survive app upgrades and downgrades.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        let defaults = ScrollSettings()
        isCustomScrollingEnabled = container.value(.isCustomScrollingEnabled) ?? defaults.isCustomScrollingEnabled
        linesPerNotch = container.value(.linesPerNotch) ?? defaults.linesPerNotch
        acceleration = container.value(.acceleration) ?? defaults.acceleration
        isSmoothScrollingEnabled = container.value(.isSmoothScrollingEnabled) ?? defaults.isSmoothScrollingEnabled
        smoothness = container.value(.smoothness) ?? defaults.smoothness
        responsiveness = container.value(.responsiveness) ?? defaults.responsiveness
        reverseVertical = container.value(.reverseVertical) ?? defaults.reverseVertical
        reverseHorizontal = container.value(.reverseHorizontal) ?? defaults.reverseHorizontal
        self = clamped()
    }
}
