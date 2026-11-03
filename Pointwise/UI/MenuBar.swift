import AppKit
import SwiftUI

struct MenuBarMenu: View {
    let model: AppModel
    let windows: WindowPresenter

    var body: some View {
        Toggle("Enable Pointwise", isOn: Binding(
            get: { model.settings.isEnabled },
            set: { model.setEnabled($0) }
        ))
        .keyboardShortcut("e")

        Toggle("Smooth Scrolling", isOn: Binding(
            get: { model.settings.scroll.isSmoothScrollingEnabled },
            set: { value in model.update { $0.scroll.isSmoothScrollingEnabled = value } }
        ))
        .disabled(!model.settings.isEnabled || !model.settings.scroll.isCustomScrollingEnabled)

        Divider()

        if model.needsAttention {
            Button("Pointwise Needs Attention…") { windows.showSettings(.general) }
        }
        Button("Settings…") { windows.showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Pointwise") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
