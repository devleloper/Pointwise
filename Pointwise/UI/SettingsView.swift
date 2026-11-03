import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case pointer
    case scrolling
    case devices
    case general

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .pointer: "Pointer"
        case .scrolling: "Scrolling"
        case .devices: "Devices"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .pointer: "cursorarrow.motionlines"
        case .scrolling: "scroll"
        case .devices: "computermouse"
        case .general: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .pointer: .blue
        case .scrolling: .indigo
        case .devices: .teal
        case .general: .gray
        }
    }
}

extension EnvironmentValues {
    /// Offscreen screenshots can't capture vibrancy, so the sidebar draws its selection itself.
    @Entry var isRenderingSnapshot = false
}

/// The selected pane, owned by the window so "Settings…" can switch panes without rebuilding it.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane? = .pointer

    init(pane: SettingsPane = .pointer) {
        self.pane = pane
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    @Bindable var navigation: SettingsNavigation

    private var selection: SettingsPane? { navigation.pane }

    var body: some View {
        NavigationSplitView {
            Group {
                if isRenderingSnapshot {
                    List(SettingsPane.allCases) { pane in
                        sidebarRow(pane)
                            .listRowBackground(pane == selection
                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor).padding(.horizontal, 10)
                                : nil)
                            .foregroundStyle(pane == selection ? Color.white : Color.primary)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .underPageBackgroundColor))
                } else {
                    List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                        sidebarRow(pane)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection ?? .pointer {
                case .pointer: PointerPane()
                case .scrolling: ScrollingPane()
                case .devices: DevicesPane()
                case .general: GeneralPane()
                }
            }
            .navigationTitle(selection?.title ?? SettingsPane.pointer.title)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 480, idealHeight: 640)
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            SettingsIcon(symbol: pane.symbol, tint: pane.tint)
        }
        .badge(badge(for: pane))
    }

    private func badge(for pane: SettingsPane) -> Text? {
        switch pane {
        case .scrolling where model.scrollState == .needsPermission || model.scrollState == .failed:
            Text("!")
        default:
            nil
        }
    }
}

/// White SF Symbol on a colored rounded square, like the System Settings sidebar.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: .rect(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}
