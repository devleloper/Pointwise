/// Identifies a model of pointing device across reconnects.
///
/// macOS exposes no stable public serial number for most mice, so two identical mice share
/// their settings. The name is part of the key because some receivers reuse product IDs.
public struct DeviceIdentity: Codable, Hashable, Sendable, Comparable {
    public var vendorID: Int
    public var productID: Int
    public var name: String

    public init(vendorID: Int, productID: Int, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
    }

    public var key: String { "\(vendorID):\(productID):\(name)" }

    public static func < (lhs: DeviceIdentity, rhs: DeviceIdentity) -> Bool {
        (lhs.name.localizedLowercase, lhs.vendorID, lhs.productID) < (rhs.name.localizedLowercase, rhs.vendorID, rhs.productID)
    }
}

/// How a specific device's pointer is configured.
public enum DeviceRule: Codable, Equatable, Sendable {
    /// Uses the Pointer settings shared by all mice.
    case followGlobal
    /// Uses its own speed and acceleration.
    case custom(PointerSettings)
    /// Pointwise leaves the device to macOS.
    case system
}

public struct DeviceConfiguration: Codable, Equatable, Sendable {
    public var identity: DeviceIdentity
    public var rule: DeviceRule

    public init(identity: DeviceIdentity, rule: DeviceRule) {
        self.identity = identity
        self.rule = rule
    }
}
