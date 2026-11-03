import Foundation
import Testing
@testable import PointwiseCore

private let mouse = DeviceIdentity(vendorID: 10007, productID: 20624, name: "Mi PTMS3")
private let other = DeviceIdentity(vendorID: 1133, productID: 45108, name: "MX Master 3S")

struct SettingsTests {
    @Test func pointerIsLeftToMacOSByDefault() {
        let settings = AppSettings()
        #expect(settings.pointerSettings(for: mouse) == nil)
    }

    @Test func deviceRulesOverrideGlobalSettings() {
        var settings = AppSettings()
        settings.customizesPointer = true
        settings.pointer = PointerSettings(speed: 2)
        let custom = PointerSettings(speed: 0.5, isAccelerationEnabled: false)
        settings.setRule(.custom(custom), for: mouse)
        settings.setRule(.system, for: other)

        #expect(settings.pointerSettings(for: mouse) == custom)
        #expect(settings.pointerSettings(for: other) == nil)
        #expect(settings.pointerSettings(for: DeviceIdentity(vendorID: 1, productID: 2, name: "USB Mouse"))?.speed == 2)

        settings.isEnabled = false
        #expect(settings.pointerSettings(for: mouse) == nil)
    }

    @Test func followingGlobalNeedsNoEntry() {
        var settings = AppSettings()
        settings.setRule(.system, for: mouse)
        settings.setRule(.followGlobal, for: mouse)
        #expect(settings.devices.isEmpty)
    }

    @Test func restoringDefaultsResetsInputButKeepsAppChoices() {
        var settings = AppSettings()
        settings.customizesPointer = true
        settings.scroll.reverseVertical = true
        settings.setRule(.system, for: mouse)
        settings.showsMenuBarIcon = false
        settings.hasCompletedOnboarding = true
        settings.isEnabled = false

        let restored = settings.restoringDefaults()
        #expect(!restored.isEnabled)
        #expect(!restored.customizesPointer)
        #expect(restored.scroll == ScrollSettings())
        #expect(restored.devices.isEmpty)
        #expect(!restored.showsMenuBarIcon)
        #expect(restored.hasCompletedOnboarding)
    }

    @Test func hidValues() {
        #expect(PointerSettings(speed: 0.6875).hidAccelerationValue == 45056)
        #expect(PointerSettings(speed: 3).hidAccelerationValue == 196608)
        #expect(PointerSettings(speed: 1, isAccelerationEnabled: false).hidAccelerationValue == -65536)
        #expect(PointerSettings(speed: 9).speed == PointerSettings.speedRange.upperBound)
        #expect(PointerSettings(speed: .nan).speed == PointerSettings.defaultSpeed)
    }
}

struct SettingsCodingTests {
    @Test func roundTrips() throws {
        var settings = AppSettings()
        settings.customizesPointer = true
        settings.pointer = PointerSettings(speed: 1.5, isAccelerationEnabled: false)
        settings.scroll.smoothness = 0.8
        settings.scroll.reverseHorizontal = true
        settings.setRule(.custom(PointerSettings(speed: 0.25)), for: mouse)
        settings.setRule(.system, for: other)

        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func missingKeysUseDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"scroll": {"reverseVertical": true}}"#.utf8))
        var expected = AppSettings()
        expected.scroll.reverseVertical = true
        #expect(decoded == expected)
    }

    @Test func outOfRangeAndWrongTypesAreRepaired() throws {
        let json = #"{"pointer": {"speed": 40}, "scroll": {"linesPerNotch": -3, "smoothness": "high", "acceleration": 7}, "isEnabled": "yes"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.pointer.speed == PointerSettings.speedRange.upperBound)
        #expect(decoded.scroll.linesPerNotch == ScrollSettings.linesPerNotchRange.lowerBound)
        #expect(decoded.scroll.smoothness == ScrollSettings().smoothness)
        #expect(decoded.scroll.acceleration == 1)
        #expect(decoded.isEnabled)
    }

    @Test func unknownDeviceRuleKeepsTheOthers() throws {
        let json = #"""
        {"devices": {
            "1:2:Old": {"identity": {"vendorID": 1, "productID": 2, "name": "Old"}, "rule": {"system": {}}},
            "3:4:New": {"identity": {"vendorID": 3, "productID": 4, "name": "New"}, "rule": {"futureRule": {}}}
        }}
        """#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.devices.count == 1)
        #expect(decoded.rule(for: DeviceIdentity(vendorID: 1, productID: 2, name: "Old")) == .system)
        #expect(decoded.rule(for: DeviceIdentity(vendorID: 3, productID: 4, name: "New")) == .followGlobal)
    }

    @Test func storeFallsBackToDefaultsForGarbage() {
        let suite = "PointwiseCoreTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SettingsStore(suiteName: suite)
        #expect(store.load() == AppSettings())

        UserDefaults(suiteName: suite)?.set(Data("not json".utf8), forKey: "settings")
        #expect(store.load() == AppSettings())

        var settings = AppSettings()
        settings.scroll.linesPerNotch = 7
        store.save(settings)
        #expect(store.load() == settings)
    }
}
