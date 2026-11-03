import Foundation
import IOKit.hid

/// Notices mice being connected or disconnected (USB, Bluetooth, wireless receivers).
///
/// Uses only IOHIDManager's matching callbacks. The manager is never opened, so no input is
/// read and no Input Monitoring permission is needed.
@MainActor
final class DeviceMonitor {
    /// Several interfaces of one device appear in quick succession; report them as one change.
    private static let coalescingDelay: Duration = .milliseconds(300)

    var onChange: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var isRunning = false
    private var pendingNotification: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            DeviceMonitor.callback(context)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            DeviceMonitor.callback(context)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        pendingNotification?.cancel()
    }

    private nonisolated static func callback(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        // An address is Sendable; the pointer itself is not.
        let address = UInt(bitPattern: context)
        // Scheduled on the main run loop, so this runs on the main thread.
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(pointer).takeUnretainedValue().scheduleNotification()
        }
    }

    private func scheduleNotification() {
        pendingNotification?.cancel()
        pendingNotification = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
