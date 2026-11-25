import SwiftUI

public struct HomeView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var lockManager: SecurityLockManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar with Lock & Settings buttons
            HStack {
                Button(action: {
                    lockManager.lockApp()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                        Text("Lock")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Lock Phone Mirroring (Cmd+L)")

                Spacer()

                Button(action: {
                    appState.showSettingsSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preferences (Cmd+,)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            VStack(spacing: 28) {
                Spacer()

                // Minimalist Modern Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.85, green: 0.25, blue: 0.55), Color(red: 0.98, green: 0.45, blue: 0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: Color.pink.opacity(0.35), radius: 20, x: 0, y: 10)

                    Image(systemName: "iphone.and.arrow.forward")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("Phone Mirroring")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Mirror and control your Android phone directly from macOS.\nNothing installed on your phone.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                // Screen 1: ONE button: "Connect Devices"
                Button(action: {
                    appState.navigate(to: .devices)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Connect Devices")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(minWidth: 220)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(Color.blue)
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 48)
            }
        }
        .frame(minWidth: 540, minHeight: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $appState.showSettingsSheet) {
            SettingsSheetView(isPresented: $appState.showSettingsSheet)
        }
    }
}
