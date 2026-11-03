import PointwiseCore
import SwiftUI

struct DevicesPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.devices.isEmpty {
                    ContentUnavailableView {
                        Label("No Mouse Connected", systemImage: "computermouse")
                    } description: {
                        Text("Connect a USB, Bluetooth or wireless mouse. It appears here automatically.")
                    }
                } else {
                    ForEach(model.devices) { device in
                        DeviceRow(identity: device.identity, transport: device.transport, isMouse: device.isMouse, isConnected: true)
                    }
                }
            } header: {
                Text("Connected")
            } footer: {
                SectionNote("Give a mouse its own pointer speed, or leave it to macOS. Wheel scrolling settings apply to every mouse, because macOS doesn't tell apps which mouse scrolled without Input Monitoring access.")
            }

            if !model.rememberedDevices.isEmpty {
                Section("Not Connected") {
                    ForEach(model.rememberedDevices, id: \.self) { identity in
                        DeviceRow(identity: identity, transport: nil, isMouse: true, isConnected: false)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.settings.isEnabled)
    }
}

private struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let identity: DeviceIdentity
    let transport: String?
    let isMouse: Bool
    let isConnected: Bool

    private enum Choice: Hashable {
        case global, custom, system
    }

    private var rule: DeviceRule { model.settings.rule(for: identity) }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                switch rule {
                case .followGlobal: .global
                case .custom: .custom
                case .system: .system
                }
            },
            set: { choice in
                switch choice {
                case .global: model.setRule(.followGlobal, for: identity)
                case .system: model.setRule(.system, for: identity)
                case .custom:
                    // Start from what the device uses now, so nothing jumps.
                    let start = model.settings.pointerSettings(for: identity) ?? model.systemSettings ?? PointerSettings()
                    model.setRule(.custom(start), for: identity)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent {
                HStack(spacing: 8) {
                    Picker("Pointer", selection: choice) {
                        Text("Shared settings").tag(Choice.global)
                        Text("Custom").tag(Choice.custom)
                        Text("macOS settings").tag(Choice.system)
                    }
                    .labelsHidden()
                    .fixedSize()
                    if !isConnected {
                        Button {
                            model.setRule(.followGlobal, for: identity)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Forget this mouse")
                        .accessibilityLabel("Forget \(identity.name)")
                    }
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(identity.name)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: isMouse ? "computermouse" : "keyboard")
                        .foregroundStyle(isConnected ? Color.accentColor : .secondary)
                }
            }

            if case .custom(let settings) = rule {
                PointerControls(settings: Binding(
                    get: { settings },
                    set: { model.setRule(.custom($0), for: identity) }
                ))
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard let transport else { return String(localized: "Not connected") }
        let connection = transport.isEmpty ? String(localized: "Unknown connection") : transport
        return isMouse ? connection : String(localized: "\(connection) · Pointer built into another device")
    }
}
