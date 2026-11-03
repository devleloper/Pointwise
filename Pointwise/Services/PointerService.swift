import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import PointwiseCore

/// A connected mouse. One physical device can expose several HID services.
struct PointerDevice: Identifiable, Equatable {
    let identity: DeviceIdentity
    let transport: String
    /// `false` for composite devices whose main function is something else,
    /// such as a keyboard with a built-in pointer interface.
    let isMouse: Bool
    /// How macOS accelerates this device, for drawing its curve.
    let acceleration: PointerAccelerationModel
    /// Counts per inch.
    let resolution: Double
    /// macOS's own "Pointer acceleration" switch is off: tracking scales movement linearly.
    let linearScaling: Bool

    var id: String { identity.key }
}

/// Applies pointer tracking per device through the public HID event system client.
///
/// Only `HIDMouseAcceleration` is written; it is the one tracking property a non-privileged
/// client may change. Devices Pointwise does not manage keep whatever macOS set.
@MainActor
final class PointerService {
    nonisolated private static let accelerationKey: String = kIOHIDMouseAccelerationType
    nonisolated private static let accelerationTypeKey: String = kIOHIDPointerAccelerationTypeKey

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    /// Values Pointwise wrote, by service registry ID.
    private var applied: [UInt64: Int] = [:]
    /// Each service's value before Pointwise first changed it; the fallback for restoring.
    private var originals: [UInt64: Int] = [:]

    var managesAnyDevice: Bool { !applied.isEmpty }

    func devices() -> [PointerDevice] {
        var seen = Set<String>()
        return mouseServices()
            .map(\.device)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.identity < $1.identity }
    }

    /// Applies `settings(identity)` to every mouse; `nil` hands the device back to macOS.
    /// Returns the number of services whose value could not be written.
    @discardableResult
    func apply(_ settings: (DeviceIdentity) -> PointerSettings?) -> Int {
        var failures = 0
        var present = Set<UInt64>()
        for service in mouseServices() {
            present.insert(service.registryID)
            if let value = settings(service.device.identity)?.hidAccelerationValue {
                if !write(value, to: service) { failures += 1 }
            } else if applied[service.registryID] != nil {
                restore(service)
            }
        }
        // Forget services that disappeared; reconnecting creates new ones.
        applied = applied.filter { present.contains($0.key) }
        originals = originals.filter { present.contains($0.key) }
        return failures
    }

    /// Hands every device back to macOS.
    func restoreAll() {
        for service in mouseServices() where applied[service.registryID] != nil {
            restore(service)
        }
        applied.removeAll()
        originals.removeAll()
    }

    /// Re-applies values that something else changed, such as System Settings or a device reconnecting.
    /// Returns `true` if anything had drifted.
    func reapplyDrifted() -> Bool {
        var drifted = false
        for service in mouseServices() {
            guard let expected = applied[service.registryID] else { continue }
            if service.currentValue != expected {
                drifted = true
                if let current = service.currentValue {
                    // The user changed the macOS setting; restore that one later.
                    originals[service.registryID] = current
                }
                _ = write(expected, to: service)
            }
        }
        return drifted
    }

    /// The macOS tracking setting for mice, shown while Pointwise leaves the pointer alone and
    /// used as the starting point when the user begins customizing.
    var systemSettings: PointerSettings? {
        guard let value = IOHIDEventSystemClientCopyProperty(client, Self.accelerationKey as CFString) as? Int else { return nil }
        return value < 0 ? PointerSettings(isAccelerationEnabled: false) : PointerSettings(speed: HIDFixed.toDouble(value))
    }

    // MARK: Services

    private struct Service {
        let client: IOHIDServiceClient
        let registryID: UInt64
        let device: PointerDevice

        var currentValue: Int? {
            IOHIDServiceClientCopyProperty(client, PointerService.accelerationKey as CFString) as? Int
        }
    }

    private func mouseServices() -> [Service] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.compactMap { service in
            // Trackpads use HIDTrackpadAcceleration and are left to macOS.
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0,
                  IOHIDServiceClientCopyProperty(service, Self.accelerationTypeKey as CFString) as? String == kIOHIDMouseAccelerationType,
                  let registryID = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { return nil }

            func property<T>(_ key: String) -> T? {
                IOHIDServiceClientCopyProperty(service, key as CFString) as? T
            }
            let usagePage: Int = property(kIOHIDPrimaryUsagePageKey) ?? 0
            let usage: Int = property(kIOHIDPrimaryUsageKey) ?? 0
            let identity = DeviceIdentity(
                vendorID: property(kIOHIDVendorIDKey) ?? 0,
                productID: property(kIOHIDProductIDKey) ?? 0,
                name: (property(kIOHIDProductKey) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? String(localized: "Unnamed Mouse")
            )
            let isMouse = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
            let registry = Self.registryAcceleration(registryID)
            return Service(
                client: service,
                registryID: registryID,
                device: PointerDevice(
                    identity: identity,
                    transport: property(kIOHIDTransportKey) ?? "",
                    isMouse: isMouse,
                    acceleration: registry.model,
                    resolution: registry.resolution,
                    linearScaling: registry.linearScaling
                )
            )
        }
    }

    /// Curves, table and resolution are hidden from the HID client but readable in IORegistry.
    private static func registryAcceleration(_ registryID: UInt64) -> (model: PointerAccelerationModel, resolution: Double, linearScaling: Bool) {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard entry != IO_OBJECT_NULL else { return (PointerAccelerationModel(curves: [], table: nil), PointerTransfer.defaultResolution, false) }
        defer { IOObjectRelease(entry) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let curves = (property("HIDAccelCurves") as? [[String: Any]])?.map(ParametricCurve.init(registryEntry:)) ?? []
        let table = (property(kIOHIDPointerAccelerationTableKey) as? Data).flatMap(AccelerationTable.init(data:))
        let resolution = (property(kIOHIDPointerResolutionKey) as? Int).map(HIDFixed.toDouble) ?? 0
        // WindowServer publishes the user's preferences for the service in this dictionary.
        let preferences = property("HIDEventServiceProperties") as? [String: Any]
        let linearScaling = (preferences?[kIOHIDUseLinearScalingMouseAccelerationKey] as? Int ?? 0) != 0
        return (
            PointerAccelerationModel(curves: curves, table: table),
            resolution > 0 ? resolution : PointerTransfer.defaultResolution,
            linearScaling
        )
    }

    private func write(_ value: Int, to service: Service) -> Bool {
        if applied[service.registryID] == nil, originals[service.registryID] == nil, let current = service.currentValue {
            originals[service.registryID] = current
        }
        guard service.currentValue != value else {
            applied[service.registryID] = value
            return true
        }
        guard IOHIDServiceClientSetProperty(service.client, Self.accelerationKey as CFString, value as CFNumber) else {
            Log.pointer.error("Could not set tracking for \(service.device.identity.name, privacy: .public)")
            return false
        }
        applied[service.registryID] = value
        return true
    }

    private func restore(_ service: Service) {
        // Prefer the current macOS setting: the user may have changed it while Pointwise managed the device.
        let systemValue = IOHIDEventSystemClientCopyProperty(client, Self.accelerationKey as CFString) as? Int
        if let value = systemValue ?? originals[service.registryID] {
            if !IOHIDServiceClientSetProperty(service.client, Self.accelerationKey as CFString, value as CFNumber) {
                Log.pointer.error("Could not restore tracking for \(service.device.identity.name, privacy: .public)")
            }
        }
        applied[service.registryID] = nil
        originals[service.registryID] = nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
