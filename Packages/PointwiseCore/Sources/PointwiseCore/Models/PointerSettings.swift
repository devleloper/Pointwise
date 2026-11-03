/// Pointer tracking for a mouse, applied through the macOS HID event system.
///
/// macOS couples speed and acceleration in a single "tracking" value that selects one of the
/// device's acceleration curves: higher values are both faster and more accelerated. Public APIs
/// cannot change pointer resolution, so speed cannot be decoupled from acceleration.
public struct PointerSettings: Codable, Equatable, Sendable {
    /// The range macOS itself offers in System Settings › Mouse › Tracking speed.
    public static let speedRange: ClosedRange<Double> = 0...3
    /// macOS default for mice.
    public static let defaultSpeed = 0.6875

    /// Tracking value; see `speedRange`.
    public var speed = PointerSettings.defaultSpeed
    /// When off, macOS moves the pointer by exactly the distance the mouse reports.
    public var isAccelerationEnabled = true

    public init(speed: Double = PointerSettings.defaultSpeed, isAccelerationEnabled: Bool = true) {
        self.speed = speed.finite(or: Self.defaultSpeed).clamped(to: Self.speedRange)
        self.isAccelerationEnabled = isAccelerationEnabled
    }

    /// Value for the `HIDMouseAcceleration` service property, in 16.16 fixed point.
    /// A negative value disables acceleration.
    public var hidAccelerationValue: Int {
        isAccelerationEnabled ? HIDFixed.from(speed) : HIDFixed.accelerationDisabled
    }
}

extension PointerSettings {
    private enum CodingKeys: String, CodingKey {
        case speed, isAccelerationEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            speed: container.value(.speed) ?? Self.defaultSpeed,
            isAccelerationEnabled: container.value(.isAccelerationEnabled) ?? true
        )
    }
}

/// IOKit's 16.16 fixed-point numbers (`IOFixed`).
public enum HIDFixed {
    public static let one = 65536
    /// `-1.0`, the value macOS uses for "no acceleration".
    public static let accelerationDisabled = -65536

    public static func from(_ value: Double) -> Int {
        Int((value * Double(one)).rounded())
    }

    public static func toDouble(_ value: Int) -> Double {
        Double(value) / Double(one)
    }
}
