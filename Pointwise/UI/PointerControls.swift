import PointwiseCore
import SwiftUI

/// Tracking speed and acceleration, shared by the Pointer pane and per-device settings.
struct PointerControls: View {
    @Binding var settings: PointerSettings

    var body: some View {
        Toggle("Pointer acceleration", isOn: $settings.isAccelerationEnabled)
        SettingSlider(
            title: "Tracking speed",
            value: Binding(
                get: { settings.speed },
                set: { settings = PointerSettings(speed: $0, isAccelerationEnabled: settings.isAccelerationEnabled) }
            ),
            range: PointerSettings.speedRange,
            minimumLabel: "Slow",
            maximumLabel: "Fast",
            valueText: settings.speed.formatted(fractionDigits: 2)
        )
        .disabled(!settings.isAccelerationEnabled)
    }
}
