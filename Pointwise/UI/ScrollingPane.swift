import Charts
import PointwiseCore
import SwiftUI

struct ScrollingPane: View {
    @Environment(AppModel.self) private var model

    private var scroll: ScrollSettings { model.settings.scroll }

    var body: some View {
        Form {
            if model.scrollState == .needsPermission || model.scrollState == .failed {
                Section { AccessibilityBanner() }
            }

            Section {
                Toggle("Custom wheel scrolling", isOn: model.binding(\.scroll.isCustomScrollingEnabled))
            } footer: {
                SectionNote("Applies to mice with a notched scroll wheel. Trackpads and Magic Mouse keep their own scrolling, gestures and momentum.")
            }

            Section("Speed") {
                ScrollCurveChart(settings: scroll)
                SettingSlider(
                    title: "Distance per notch",
                    value: model.binding(\.scroll.linesPerNotch),
                    range: ScrollSettings.linesPerNotchRange,
                    step: 0.5,
                    minimumLabel: "Short",
                    maximumLabel: "Long",
                    valueText: String(localized: "\(scroll.linesPerNotch.formatted(fractionDigits: 1)) lines")
                )
                SettingSlider(
                    title: "Acceleration",
                    value: model.binding(\.scroll.acceleration),
                    range: 0...1,
                    minimumLabel: "Off",
                    maximumLabel: "High",
                    valueText: scroll.acceleration.formatted(.percent.precision(.fractionLength(0)))
                )
            }
            .disabled(!scroll.isCustomScrollingEnabled)

            Section {
                Toggle("Smooth scrolling", isOn: model.binding(\.scroll.isSmoothScrollingEnabled))
                Group {
                    GlideChart(settings: scroll)
                    SettingSlider(
                        title: "Smoothness",
                        value: model.binding(\.scroll.smoothness),
                        range: 0...1,
                        minimumLabel: "Brief",
                        maximumLabel: "Long glide",
                        valueText: String(localized: "\(Int((scroll.glideDuration * 1000).rounded())) ms")
                    )
                    SettingSlider(
                        title: "Responsiveness",
                        value: model.binding(\.scroll.responsiveness),
                        range: 0...1,
                        minimumLabel: "Gentle",
                        maximumLabel: "Immediate",
                        valueText: scroll.responsiveness.formatted(.percent.precision(.fractionLength(0)))
                    )
                }
                .disabled(!scroll.isSmoothScrollingEnabled)
            } header: {
                Text("Smoothness")
            } footer: {
                SectionNote("Each notch glides to a stop. Responsiveness controls how much of the distance is covered right away; clicking or touching the trackpad stops the glide.")
            }
            .disabled(!scroll.isCustomScrollingEnabled)

            Section {
                Toggle("Reverse vertical scrolling", isOn: model.binding(\.scroll.reverseVertical))
                Toggle("Reverse horizontal scrolling", isOn: model.binding(\.scroll.reverseHorizontal))
            } header: {
                Text("Direction")
            } footer: {
                SectionNote(MouseSettings.isNaturalScrollingEnabled
                    ? "Reverses the mouse wheel relative to macOS Natural scrolling, which is on. The trackpad keeps the macOS direction."
                    : "Reverses the mouse wheel relative to macOS Natural scrolling, which is off. The trackpad keeps the macOS direction.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset Scrolling") {
                        model.update { $0.scroll = ScrollSettings() }
                    }
                    .disabled(scroll == ScrollSettings())
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.settings.isEnabled)
    }
}

/// Distance of one notch against wheel speed.
private struct ScrollCurveChart: View {
    let settings: ScrollSettings

    private struct Point: Identifiable {
        let speed: Double
        let distance: Double
        var id: Double { speed }
    }

    private var points: [Point] {
        let curve = ScrollAccelerationCurve(acceleration: settings.acceleration)
        return stride(from: 0.0, through: ScrollAccelerationCurve.maximumInput, by: 0.5).map {
            Point(speed: $0, distance: settings.pointsPerNotch * curve.multiplier(notchesPerSecond: $0))
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Wheel speed", point.speed), y: .value("Distance", point.distance))
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.25), .accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Wheel speed", point.speed), y: .value("Distance", point.distance))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            RuleMark(y: .value("Without acceleration", settings.pointsPerNotch))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXAxisLabel(String(localized: "Wheel speed (notches per second)"), alignment: .center)
        .chartYAxisLabel(String(localized: "Points per notch"))
        .chartXScale(domain: 0...ScrollAccelerationCurve.maximumInput)
        .frame(height: 170)
        .padding(.vertical, 6)
        .accessibilityLabel("Scroll acceleration curve")
        .accessibilityValue(String(localized: "A slow notch scrolls \(Int(settings.pointsPerNotch)) points; the fastest spin scrolls \(Int(settings.pointsPerNotch * ScrollAccelerationCurve(acceleration: settings.acceleration).maximumMultiplier)) points per notch."))
    }
}

/// Position over time for a single notch.
private struct GlideChart: View {
    let settings: ScrollSettings

    private struct Point: Identifiable {
        let time: Double
        let progress: Double
        var id: Double { time }
    }

    private var points: [Point] {
        let duration = settings.glideDuration
        return stride(from: 0.0, through: 0.6, by: 0.005).map {
            Point(time: $0 * 1000, progress: GlideAnimator.progress(elapsed: $0, duration: duration, exponent: settings.glideExponent))
        }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Time", point.time), y: .value("Distance", point.progress))
                .foregroundStyle(Color.indigo)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartXAxisLabel(String(localized: "Milliseconds after a notch"), alignment: .center)
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.percent)) }
            }
        }
        .chartYScale(domain: 0...1)
        .frame(height: 110)
        .padding(.vertical, 6)
        .accessibilityLabel("Glide curve")
        .accessibilityValue(String(localized: "Each notch takes \(Int((settings.glideDuration * 1000).rounded())) milliseconds to come to rest."))
    }
}
