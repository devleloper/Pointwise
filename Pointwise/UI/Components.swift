import PointwiseCore
import SwiftUI

extension AppModel {
    /// A binding that writes through `update`, so every change is saved and applied at once.
    func binding<Value: Equatable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// A labeled slider with end labels and the current value, as in System Settings.
struct SettingSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let minimumLabel: LocalizedStringKey
    let maximumLabel: LocalizedStringKey
    let valueText: String

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                slider
                    .labelsHidden()
                HStack {
                    Text(minimumLabel)
                    Spacer()
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(maximumLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 300)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(valueText)
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step) { Text(title) }
        } else {
            Slider(value: $value, in: range) { Text(title) }
        }
    }
}

/// Footnote under a form section.
struct SectionNote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Explains why scrolling is inactive and offers the fix.
struct AccessibilityBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isFailed = model.scrollState == .failed
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(isFailed ? "Restart required" : "Accessibility access required")
                    .fontWeight(.semibold)
                Text(isFailed
                    ? "Access is granted, but macOS applies it after Pointwise restarts."
                    : "Pointwise needs it to adjust mouse-wheel scrolling. It only changes scroll events and never reads what you type. Pointer settings work without it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if isFailed {
                        Button("Relaunch Pointwise") { AppRelauncher.relaunch() }
                    } else {
                        Button("Grant Access…") { model.requestAccessibility() }
                    }
                }
                .padding(.top, 2)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .padding(.vertical, 4)
    }
}

extension Double {
    func formatted(fractionDigits: Int) -> String {
        formatted(.number.precision(.fractionLength(fractionDigits)))
    }
}
