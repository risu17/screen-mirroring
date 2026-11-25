import SwiftUI

public struct PairingPromptView: View {
    let device: DiscoveredDevice?
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var discovery: DeviceDiscoveryManager = .shared

    public init(device: DiscoveredDevice? = nil, isPresented: Binding<Bool>) {
        self.device = device
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "lock.shield")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device != nil ? "Pair with \(device!.name)" : "Pair Android Device")
                        .font(.headline)
                    Text("Wireless Debugging Authentication")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    appState.dismissPairingSheet()
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            // Local Network Warning (if denied)
            if discovery.localNetworkPermissionDenied {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local Network Permission Denied")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red)
                        Text("macOS requires Local Network access to discover your phone on Wi-Fi.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button("Open Local Network Settings") {
                            appState.openLocalNetworkSettings()
                        }
                        .font(.caption2)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            // Method Picker (Segmented Control)
            Picker("Pairing Method", selection: $appState.selectedPairingMethod) {
                Text("Pair with QR code").tag(PairingMethod.qr)
                Text("Pair with pairing code").tag(PairingMethod.code)
            }
            .pickerStyle(.segmented)

            Divider()

            ScrollView {
                if appState.selectedPairingMethod == .qr {
                    qrView
                } else {
                    codeView
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(width: 460, height: 570)
    }

    // MARK: - QR Code View
    private var qrView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("On your phone, go to:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Settings > Developer options > Wireless debugging")
                    .font(.system(size: 12, weight: .semibold))
                Text("Tap 'Pair device with QR code' and scan:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)

            // High-contrast QR Display
            if let img = appState.qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            } else {
                ProgressView()
                    .frame(width: 190, height: 190)
            }

            // Live status badge
            HStack(spacing: 8) {
                if appState.qrStatusText.contains("scan") || appState.qrStatusText.contains("finding") || appState.qrStatusText.contains("Pairing") || appState.qrStatusText.contains("Connecting") {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                } else if appState.qrStatusText.contains("Paired") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }

                Text(appState.qrStatusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // Expiration countdown
            let minutes = appState.qrTimeRemaining / 60
            let seconds = appState.qrTimeRemaining % 60
            Text(appState.isQRExpired ? "QR code expired" : String(format: "Expires in %d:%02d", minutes, seconds))
                .font(.caption2)
                .foregroundColor(appState.isQRExpired ? .red : .secondary)

            // 30-Second Inactivity Hint Card
            if appState.qrTimeRemaining <= 90 && appState.qrStatusText.contains("Waiting") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("Not connecting yet? Try these tips:")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("• Tap 'Pair device with QR code' inside Wireless debugging (do not use camera app).")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("• Ensure phone and Mac are connected to the exact same Wi-Fi.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("• Turn off any VPN or proxy on either device.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("• Check if router 'AP/Client Isolation' is enabled.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Button(action: {
                        appState.selectedPairingMethod = .code
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                            Text("Use pairing code instead")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            }

            // Method 5: Manual IP Fallback Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Phone IP address fallback")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("If mDNS is blocked by router")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone IP")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("192.168.1.13", text: $appState.qrManualHostInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pairing Port")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("e.g. 37891", text: $appState.qrManualPortInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 80)
                    }

                    VStack {
                        Spacer()
                        Button(action: {
                            Task {
                                _ = await appState.qrPairWithManualIP()
                            }
                        }) {
                            if appState.isQRManualPairing {
                                ProgressView().scaleEffect(0.6).frame(width: 50)
                            } else {
                                Text("Pair IP")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.qrManualHostInput.isEmpty || appState.qrManualPortInput.isEmpty || appState.isQRManualPairing)
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // "Show details" Diagnostic Log
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    appState.showQRDetails.toggle()
                }) {
                    HStack(spacing: 4) {
                        Text(appState.showQRDetails ? "Hide details" : "Show details")
                        Image(systemName: appState.showQRDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                if appState.showQRDetails {
                    ScrollView {
                        Text(appState.qrLogDetails.isEmpty ? "No resolution logs yet." : appState.qrLogDetails)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(height: 65)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(4)
                }
            }

            // QR Actions
            HStack {
                Button(action: {
                    appState.generateNewQRCode()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("Generate new QR")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    appState.dismissPairingSheet()
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Pairing Code View
    private var codeView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("On your phone, go to:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Settings > Developer options > Wireless debugging")
                    .font(.system(size: 12, weight: .semibold))
                Text("Tap 'Pair device with pairing code' and enter the info shown:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone IP Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. 192.168.1.13", text: $appState.pairingHostInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Pairing Port (from the pairing popup)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Different from connect port")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    TextField("e.g. 37891", text: $appState.pairingPortInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wi-Fi Pairing Code (6 digits)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. 123456", text: $appState.pairingCodeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
            }

            // Error Display with Details toggle
            if let err = appState.pairingErrorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let details = appState.pairingRawDetails, !details.isEmpty {
                        Button(action: {
                            appState.showPairingDetails.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Text(appState.showPairingDetails ? "Hide details" : "Show details")
                                Image(systemName: appState.showPairingDetails ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)

                        if appState.showPairingDetails {
                            ScrollView {
                                Text(details)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(4)
                            }
                            .frame(height: 50)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }

            Spacer()

            // Code Actions
            HStack {
                Button("Cancel") {
                    appState.dismissPairingSheet()
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    Task {
                        _ = await appState.pairWithCode()
                    }
                }) {
                    if appState.isPairingInProgress {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 80)
                    } else {
                        Text("Pair & Connect")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.pairingHostInput.isEmpty || appState.pairingPortInput.isEmpty || appState.pairingCodeInput.isEmpty || appState.isPairingInProgress)
            }
        }
    }
}
