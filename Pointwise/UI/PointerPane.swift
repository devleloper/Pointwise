import Charts
import PointwiseCore
import SwiftUI

struct PointerPane: View {
    @Environment(AppModel.self) private var model
    @State private var chartDeviceID: String?

    private var chartDevice: PointerDevice? {
        model.devices.first { $0.id == chartDeviceID } ?? model.devices.first { $0.isMouse } ?? model.devices.first
    }

    var body: some View {
        Form {
            Section {
                Toggle("Customize pointer tracking", isOn: Binding(
                    get: { model.settings.customizesPointer },
                    set: { model.setCustomizesPointer($0) }
                ))
            } footer: {
                SectionNote("When off, mice use System Settings › Mouse. Mice with their own settings in Devices are not affected.")
            }

            Section {
                PointerCurveChart(
                    device: chartDevice,
                    settings: model.settings.customizesPointer ? model.settings.pointer : nil,
                    systemSettings: model.systemSettings
                )
                if chartDevice?.linearScaling == true {
                    Label("Pointer acceleration is off in System Settings › Mouse › Advanced, so macOS scales movement linearly: Tracking speed works as a plain multiplier.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.devices.count > 1 {
                    Picker("Curve for", selection: Binding(
                        get: { chartDevice?.id },
                        set: { chartDeviceID = $0 }
                    )) {
                        ForEach(model.devices) { device in
                            Text(device.identity.name).tag(Optional(device.id))
                        }
                    }
                }
                Group {
                    PointerControls(settings: model.binding(\.pointer))
                }
                .disabled(!model.settings.customizesPointer)
            } header: {
                Text("Tracking")
            } footer: {
                SectionNote("macOS uses one tracking value for both speed and acceleration: higher values move faster and accelerate more. With acceleration off, the pointer moves exactly as far as the mouse reports, so its speed follows the mouse's DPI setting. macOS doesn't let apps change speed and acceleration separately.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset Pointer") {
                        model.update {
                            $0.customizesPointer = false
                            $0.pointer = PointerSettings()
                        }
                    }
                    .disabled(!model.settings.customizesPointer && model.settings.pointer == PointerSettings())
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.settings.isEnabled)
    }
}

/// Speed multiplier against mouse speed, computed the way macOS accelerates this device.
struct PointerCurveChart: View {
    /// `nil` draws a typical mouse.
    let device: PointerDevice?
    /// Pointwise settings to draw; `nil` when the pointer follows macOS.
    let settings: PointerSettings?
    let systemSettings: PointerSettings?

    private static let maximumCounts = 60.0

    private struct Point: Identifiable {
        let series: String
        let counts: Double
        let gain: Double
        var id: String { "\(series)-\(counts)" }
    }

    private var model: PointerAccelerationModel {
        device?.acceleration ?? PointerAccelerationModel(curves: [], table: nil)
    }

    private var resolution: Double { device?.resolution ?? PointerTransfer.defaultResolution }

    private var pointwiseLabel: String { String(localized: "Pointwise") }
    private var macOSLabel: String { String(localized: "macOS setting") }

    private var points: [Point] {
        var series: [(String, PointerSettings)] = []
        if let settings {
            series.append((pointwiseLabel, settings))
        }
        if let systemSettings {
            series.append((macOSLabel, systemSettings))
        }
        return series.flatMap { name, settings in
            let transfer = transfer(for: settings)
            return stride(from: 1.0, through: Self.maximumCounts, by: 0.5).map {
                Point(series: name, counts: $0, gain: transfer.gain(atCounts: $0))
            }
        }
    }

    private func transfer(for settings: PointerSettings) -> PointerTransfer {
        model.transfer(
            acceleration: HIDFixed.toDouble(settings.hidAccelerationValue),
            resolution: resolution,
            linearScaling: device?.linearScaling ?? false
        )
    }

    var body: some View {
        let points = points
        let shownSeries = [pointwiseLabel, macOSLabel].filter { name in points.contains { $0.series == name } }
        VStack(alignment: .leading, spacing: 6) {
            Chart(points) { point in
                LineMark(x: .value("Mouse speed", point.counts), y: .value("Speed multiplier", point.gain))
                    .foregroundStyle(by: .value("Curve", point.series))
                    .lineStyle(point.series == pointwiseLabel
                        ? StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        : StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
            }
            .chartForegroundStyleScale(
                domain: shownSeries,
                range: shownSeries.map { $0 == pointwiseLabel ? Color.accentColor : Color.secondary }
            )
            .chartXAxisLabel(String(localized: "Mouse speed (counts per report)"), alignment: .center)
            .chartYAxisLabel(String(localized: "Pointer points per count"))
            .chartXScale(domain: 0...Self.maximumCounts)
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 190)
            .accessibilityLabel("Pointer acceleration curve")
            .accessibilityValue(accessibilitySummary)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var caption: String {
        let name = device?.identity.name ?? String(localized: "a typical mouse")
        let kind = switch model {
        case .parametric: String(localized: "its own acceleration curves")
        case .table: String(localized: "the standard macOS curve")
        }
        return String(localized: "Curve for \(name), which uses \(kind) at \(Int(resolution)) counts per inch.")
    }

    private var accessibilitySummary: String {
        guard let settings else { return String(localized: "Showing the macOS setting.") }
        if !settings.isAccelerationEnabled {
            return String(localized: "Acceleration is off: the pointer moves one point per mouse count.")
        }
        let transfer = transfer(for: settings)
        let slow = transfer.gain(atCounts: 2).formatted(fractionDigits: 2)
        let fast = transfer.gain(atCounts: 40).formatted(fractionDigits: 2)
        return String(localized: "Slow movements move \(slow) points per count; fast movements move \(fast) points per count.")
    }
}
