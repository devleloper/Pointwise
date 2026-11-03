import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Pointwise", isOn: Binding(
                    get: { model.settings.isEnabled },
                    set: { model.setEnabled($0) }
                ))
            } footer: {
                SectionNote("When off, every mouse goes back to its macOS settings and scroll events pass through unchanged.")
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLoginStatus == .enabled || model.launchAtLoginStatus == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLoginStatus == .requiresApproval {
                    LabeledContent("macOS needs your approval in Login Items.") {
                        Button("Open Login Items…", action: LaunchAtLogin.openSystemSettings)
                    }
                    .foregroundStyle(.secondary)
                }
                if !LaunchAtLogin.isInstalledInApplications {
                    Label("Move Pointwise to the Applications folder so it can open at login reliably.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: model.binding(\.showsMenuBarIcon))
            } footer: {
                if !model.settings.showsMenuBarIcon {
                    SectionNote("To open Settings while the icon is hidden, open Pointwise again from Finder or Spotlight.")
                }
            }

            Section("Permissions") {
                LabeledContent {
                    switch model.scrollState {
                    case .needsPermission:
                        Button("Grant Access…") { model.requestAccessibility() }
                    case .failed:
                        Button("Relaunch Pointwise") { AppRelauncher.relaunch() }
                    case .running:
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .off:
                        Text(model.isAccessibilityGranted ? "Granted" : "Not needed")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                        Text("Used only to adjust mouse-wheel scroll events.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.pointerFailures > 0 {
                    Label("macOS refused to change the tracking speed of \(model.pointerFailures) device(s).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section {
                LabeledContent("Restore every mouse and scrolling option to its default.") {
                    Button("Restore Defaults…") { isConfirmingReset = true }
                }
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.versionDescription)
                LabeledContent("Mouse settings in macOS") {
                    Button("Open Mouse Settings…", action: MouseSettings.open)
                }
            } footer: {
                SectionNote("Pointwise works offline. It has no network access, analytics or telemetry.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) { model.restoreDefaults() }
        } message: {
            Text("Every mouse goes back to its macOS tracking speed, per-device settings are removed, and scrolling returns to the default settings.")
        }
    }
}

extension Bundle {
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
