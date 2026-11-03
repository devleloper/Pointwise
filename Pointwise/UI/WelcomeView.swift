import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to Pointwise")
                    .font(.largeTitle.weight(.semibold))
                Text("Fine-tune your mouse without touching the trackpad.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("cursorarrow.motionlines", "Pointer speed and acceleration", "Per mouse, through the same system the macOS setting uses. No permission needed.")
                feature("scroll", "Smooth, accelerated wheel scrolling", "Your own speed curve, glide and direction for each axis. Needs Accessibility access.")
                feature("hand.raised", "Private and offline", "No network access, no analytics. Trackpad gestures and the keyboard are never touched.")
            }
            .frame(maxWidth: 380)

            HStack(spacing: 12) {
                if !model.isAccessibilityGranted {
                    Button("Grant Accessibility Access…") { model.requestAccessibility() }
                        .controlSize(.large)
                }
                Button("Open Settings", action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 36)
        .padding(.bottom, 30)
        .frame(width: 520)
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
