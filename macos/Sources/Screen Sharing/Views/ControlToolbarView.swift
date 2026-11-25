import SwiftUI

public struct ControlToolbarView: View {
    let onBack: () -> Void
    let onHome: () -> Void
    let onRecents: () -> Void
    let onRotate: () -> Void
    let onScreenshot: () -> Void
    let onToggleScreenOff: () -> Void
    let onOpenSettings: () -> Void
    let onDisconnect: () -> Void

    @ObservedObject var appState: AppState = .shared
    @ObservedObject var session: MirrorSessionManager = .shared

    public init(
        onBack: @escaping () -> Void,
        onHome: @escaping () -> Void,
        onRecents: @escaping () -> Void,
        onRotate: @escaping () -> Void,
        onScreenshot: @escaping () -> Void,
        onToggleScreenOff: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.onBack = onBack
        self.onHome = onHome
        self.onRecents = onRecents
        self.onRotate = onRotate
        self.onScreenshot = onScreenshot
        self.onToggleScreenOff = onToggleScreenOff
        self.onOpenSettings = onOpenSettings
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        HStack(spacing: 12) {
            ToolbarButton(icon: "chevron.left", label: "Back", action: onBack)
            ToolbarButton(icon: "circle", label: "Home", action: onHome)
            ToolbarButton(icon: "square.stack", label: "Recents", action: onRecents)

            Divider()
                .frame(height: 18)

            ToolbarButton(icon: "rotate.right", label: "Rotate", action: onRotate)
            ToolbarButton(icon: "camera", label: "Screenshot", action: onScreenshot)

            Divider()
                .frame(height: 18)

            // Screen Off / On Toggle
            Button(action: onToggleScreenOff) {
                HStack(spacing: 5) {
                    Image(systemName: session.isPhoneScreenDark ? "display.slash.fill" : "display")
                        .font(.system(size: 13, weight: .medium))
                    Text(session.isPhoneScreenDark ? "Phone Screen Dark" : "Turn Phone Screen Off")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(session.isPhoneScreenDark ? .blue : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(session.isPhoneScreenDark ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Toggle phone physical display on/off while mirroring")

            Spacer()

            // Settings Button
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Disconnect Button
            Button(action: onDisconnect) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Disconnect")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
    }
}

private struct ToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 30, height: 26)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
