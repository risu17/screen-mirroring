import SwiftUI
import AppKit

public struct MirrorWindowView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var session: MirrorSessionManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Control Bar
            HStack(spacing: 14) {
                // Device Info
                if let dev = session.currentDevice ?? appState.activeDevice {
                    HStack(spacing: 6) {
                        Image(systemName: dev.connectionType == .usb ? "cable.connector" : "wifi")
                            .foregroundColor(dev.connectionType == .usb ? .purple : .blue)
                            .font(.system(size: 13))

                        Text(dev.name)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Spacer()

                // Mode Switch: Mirror Mode vs Independent Mode
                Picker("Mode", selection: $appState.selectedMode) {
                    ForEach(MirrorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: appState.selectedMode) { newMode in
                    if let dev = session.currentDevice ?? appState.activeDevice {
                        Task {
                            _ = await session.startSession(device: dev, mode: newMode, turnScreenOff: session.isPhoneScreenDark)
                        }
                    }
                }

                Spacer()

                // Connection Quality Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text("\(session.fps) FPS • \(session.connectionQuality)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Native macOS Fullscreen Button
                Button(action: {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Fullscreen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Mode & Status Notices
            if session.isReconnecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Reconnecting to phone (attempt \(session.reconnectAttempt)/3)...")
                        .font(.footnote)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(10)
                .background(Color.blue.opacity(0.85))
            } else if let warning = session.warningMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.footnote)
                    Spacer()
                    Button("Dismiss") {
                        session.warningMessage = nil
                    }
                    .font(.footnote)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
            }

            if let banner = appState.screenshotBanner {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.green)
                    Text(banner)
                        .font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.12))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        appState.screenshotBanner = nil
                    }
                }
            }

            // Mirror Stream View Area
            ZStack {
                Color.black

                VStack(spacing: 16) {
                    if session.isRunning {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                                    .frame(width: 280, height: 520)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )

                                VStack(spacing: 14) {
                                    Image(systemName: appState.selectedMode == .independent ? "display.2" : "iphone")
                                        .font(.system(size: 48))
                                        .foregroundColor(.blue)

                                    Text(appState.selectedMode == .independent ? "Independent Display Active" : "Phone Mirror Active")
                                        .font(.headline)
                                        .foregroundColor(.white)

                                    Text(appState.selectedMode == .independent
                                         ? "Actions performed in this window run in an isolated virtual display and do not affect your phone's physical screen."
                                         : "Real phone screen mirroring. Mouse clicks = taps, drags = swipes, and keyboard typing are active.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)

                                    if session.isPhoneScreenDark {
                                        HStack(spacing: 6) {
                                            Image(systemName: "display.slash")
                                                .foregroundColor(.blue)
                                            Text("Phone Display Darkened for Privacy")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.blue)
                                        }
                                        .padding(.top, 4)
                                    }

                                    if appState.selectedMode == .mirror {
                                        HStack(spacing: 6) {
                                            Image(systemName: "lock.shield")
                                                .foregroundColor(.green)
                                            Text("Lock Screen PIN/Password Supported")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.green)
                                        }
                                        .padding(.top, 2)
                                    }

                                    HStack(spacing: 6) {
                                        Image(systemName: "shield.slash")
                                            .foregroundColor(.yellow)
                                        Text("FLAG_SECURE Apps Blanked by Android OS")
                                            .font(.system(size: 10))
                                            .foregroundColor(.yellow.opacity(0.8))
                                    }
                                }
                            }
                        }
                    } else if session.isPhoneAsleep {
                        // Phone is asleep overlay
                        VStack(spacing: 16) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 52))
                                .foregroundColor(.yellow)

                            Text("Phone screen is asleep")
                                .font(.title3.bold())
                                .foregroundColor(.white)

                            Text("Click anywhere or press any key to wake it")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.75))

                            Button("Wake Phone") {
                                Task {
                                    SecurityLockManager.shared.registerUserActivity()
                                    await session.wakePhone()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                        }
                        .padding(32)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(radius: 20)
                    } else {
                        ProgressView("Starting hardware video stream...")
                            .foregroundColor(.white)
                    }
                }

                // Invisible overlay to capture clicks when phone is asleep
                if session.isPhoneAsleep {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                SecurityLockManager.shared.registerUserActivity()
                                await session.wakePhone()
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Control Toolbar
            ControlToolbarView(
                onBack: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task { await session.sendControlAction(action: .back) }
                },
                onHome: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task { await session.sendControlAction(action: .home) }
                },
                onRecents: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task { await session.sendControlAction(action: .recents) }
                },
                onRotate: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task { await session.sendControlAction(action: .rotate) }
                },
                onScreenshot: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task {
                        await session.sendControlAction(action: .screenshot)
                        appState.screenshotBanner = "Screenshot saved to your Desktop!"
                    }
                },
                onToggleScreenOff: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task {
                        await session.togglePhysicalDisplayPower()
                    }
                },
                onOpenSettings: {
                    SecurityLockManager.shared.registerUserActivity()
                    appState.showSettingsSheet = true
                },
                onDisconnect: {
                    SecurityLockManager.shared.registerUserActivity()
                    Task {
                        await appState.disconnect()
                    }
                }
            )
        }
        .frame(minWidth: 540, minHeight: 640)
        .onAppear {
            appState.selectedMode = session.currentMode
        }
        .sheet(isPresented: $appState.showSettingsSheet) {
            SettingsSheetView(isPresented: $appState.showSettingsSheet)
        }
    }
}
