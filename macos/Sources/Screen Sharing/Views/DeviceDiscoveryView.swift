import SwiftUI

public struct DeviceDiscoveryView: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var discovery: DeviceDiscoveryManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button(action: {
                    appState.navigate(to: .home)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Available Devices")
                    .font(.headline)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        appState.openPairingSheet(for: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode")
                            Text("Pair New Phone")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Pair a new Android phone via QR code or pairing code")

                    Button(action: {
                        appState.showSetupSheet = true
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Phone Setup Guide")

                    Button(action: {
                        appState.showSettingsSheet = true
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Status Banners
            if !discovery.isWiFiConnected {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                    Text("Wi-Fi is disconnected. Connect your Mac and phone to the same Wi-Fi network for Wireless Debugging.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
            } else if discovery.localNetworkPermissionDenied {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Local Network permission is required to discover Wireless Debugging devices. Please grant access in System Settings > Privacy & Security > Local Network.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
            }

            if let error = appState.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.footnote)
                    Spacer()
                    Button("Dismiss") {
                        appState.errorMessage = nil
                    }
                    .font(.footnote)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
            }

            // Device List
            if discovery.devices.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.1)

                    VStack(spacing: 6) {
                        Text("Searching for Android Devices...")
                            .font(.headline)
                        Text("Plug in via USB or turn on Wireless Debugging on your phone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            appState.openPairingSheet(for: nil)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "qrcode")
                                Text("Pair with QR Code or Code")
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Phone Setup Guide") {
                            appState.showSetupSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(discovery.devices) { device in
                            DeviceRowView(device: device) {
                                Task {
                                    await appState.connect(to: device)
                                }
                            } onForget: {
                                appState.forgetDevice(device)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Nearby & Connected Devices")
                            Spacer()
                            if discovery.isScanning {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $appState.showSetupSheet) {
            SetupGuideSheet(isPresented: $appState.showSetupSheet)
        }
        .sheet(isPresented: $appState.showPairingSheet) {
            PairingPromptView(device: appState.pairingTargetDevice, isPresented: $appState.showPairingSheet)
        }
        .sheet(isPresented: $appState.showSettingsSheet) {
            SettingsSheetView(isPresented: $appState.showSettingsSheet)
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}

private struct DeviceRowView: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(device.connectionType == .usb ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: device.connectionType == .usb ? "cable.connector" : "wifi")
                    .foregroundColor(device.connectionType == .usb ? .purple : .blue)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))

                    // Connection Type Badge
                    Text(device.connectionType.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(device.connectionType == .usb ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundColor(device.connectionType == .usb ? .purple : .blue)
                        .cornerRadius(4)

                    // Paired Before Badge
                    if device.isPairedBefore {
                        Text("Paired before")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                Text(device.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if device.isPairedBefore {
                Button(action: onForget) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Forget this device")
                .padding(.trailing, 6)
            }

            Button(action: onConnect) {
                Text(device.isPairedBefore || device.isConnected ? "Connect" : "Pair")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(device.isPairedBefore || device.isConnected ? .blue : .green)
        }
        .padding(.vertical, 6)
    }
}

public struct SetupGuideSheet: View {
    @Binding var isPresented: Bool

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("How to Enable Wireless Debugging")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 14) {
                GuideStepRow(
                    step: 1,
                    title: "Enable Developer Options",
                    desc: "On your phone, open Settings > About phone. Tap 'Build number' 7 times until you see 'You are now a developer!'."
                )

                GuideStepRow(
                    step: 2,
                    title: "Turn on Wireless Debugging",
                    desc: "Go to Settings > System > Developer options. Scroll to Debugging, tap 'Wireless debugging' and toggle it ON."
                )

                GuideStepRow(
                    step: 3,
                    title: "Pair using QR Code (Recommended) or Code",
                    desc: "• Option A (Fastest): Tap 'Pair device with QR code' on your phone and scan the QR code on Phone Mirroring.\n• Option B: Tap 'Pair device with pairing code' and enter the 6-digit code and pairing port."
                )

                GuideStepRow(
                    step: 4,
                    title: "Automatic Reconnect",
                    desc: "Once paired, your phone is remembered securely in your Keychain and will reconnect automatically whenever on the same Wi-Fi."
                )
            }

            Spacer()

            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.green)
                Text("Zero phone install required. Encrypted local Wi-Fi link.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
    }
}

private struct GuideStepRow: View {
    let step: Int
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 24, height: 24)
                Text("\(step)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
