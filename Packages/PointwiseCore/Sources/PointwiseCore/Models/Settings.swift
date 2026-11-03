/// User configuration. Launch at login is not stored here: macOS owns that state.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Master switch. When off, every device is handed back to macOS.
    public var isEnabled = true
    /// When off, mice without their own rule keep the macOS tracking speed.
    public var customizesPointer = false
    public var pointer = PointerSettings()
    public var scroll = ScrollSettings()
    /// Per-device rules keyed by `DeviceIdentity.key`. Kept while a device is disconnected.
    public var devices: [String: DeviceConfiguration] = [:]
    public var showsMenuBarIcon = true
    public var hasCompletedOnboarding = false

    public init() {}

    /// Pointer settings to apply to `device`, or `nil` to leave it to macOS.
    public func pointerSettings(for device: DeviceIdentity) -> PointerSettings? {
        guard isEnabled else { return nil }
        switch rule(for: device) {
        case .followGlobal: return customizesPointer ? pointer : nil
        case .custom(let settings): return settings
        case .system: return nil
        }
    }

    public func rule(for device: DeviceIdentity) -> DeviceRule {
        devices[device.key]?.rule ?? .followGlobal
    }

    /// Stores `rule`; following the global settings needs no entry.
    public mutating func setRule(_ rule: DeviceRule, for device: DeviceIdentity) {
        if rule == .followGlobal {
            devices[device.key] = nil
        } else {
            devices[device.key] = DeviceConfiguration(identity: device, rule: rule)
        }
    }

    /// Safe defaults: every device back to macOS behaviour and the default scrolling.
    /// Keeps choices that are not about input behaviour, including a pause.
    public func restoringDefaults() -> AppSettings {
        var result = AppSettings()
        result.isEnabled = isEnabled
        result.showsMenuBarIcon = showsMenuBarIcon
        result.hasCompletedOnboarding = hasCompletedOnboarding
        return result
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, customizesPointer, pointer, scroll, devices, showsMenuBarIcon, hasCompletedOnboarding
    }

    /// Tolerates missing or unknown values so settings survive app upgrades and downgrades.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        isEnabled = container.value(.isEnabled) ?? isEnabled
        customizesPointer = container.value(.customizesPointer) ?? customizesPointer
        pointer = container.value(.pointer) ?? pointer
        scroll = container.value(.scroll) ?? scroll
        // Entry by entry, so one rule written by a newer version doesn't discard the others.
        if let entries = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: .devices) {
            for key in entries.allKeys {
                if let configuration = try? entries.decode(DeviceConfiguration.self, forKey: key) {
                    devices[key.stringValue] = configuration
                }
            }
        }
        showsMenuBarIcon = container.value(.showsMenuBarIcon) ?? showsMenuBarIcon
        hasCompletedOnboarding = container.value(.hasCompletedOnboarding) ?? hasCompletedOnboarding
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
