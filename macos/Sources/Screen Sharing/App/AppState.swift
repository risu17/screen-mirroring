import Foundation
import Combine
import SwiftUI
import CoreImage
import AppKit

public enum NavigationScreen {
    case home
    case devices
    case mirror
}

public enum PairingMethod: String, CaseIterable, Identifiable {
    case code = "Pair with pairing code"
    case qr = "Pair with QR code"
    public var id: String { rawValue }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var currentScreen: NavigationScreen = .home
    @Published public var activeDevice: DiscoveredDevice?
    @Published public var showPairingSheet: Bool = false
    @Published public var pairingTargetDevice: DiscoveredDevice?
    @Published public var showSetupGuide: Bool = false
    @Published public var showSetupSheet: Bool = false
    @Published public var statusMessage: String?
    @Published public var isConnecting: Bool = false
    @Published public var errorMessage: String?

    // Pairing Method Choice (remembered in UserDefaults)
    @Published public var selectedPairingMethod: PairingMethod = {
        if let saved = UserDefaults.standard.string(forKey: "lastPairingMethod"),
           let method = PairingMethod(rawValue: saved) {
            return method
        }
        return .qr
    }() {
        didSet {
            UserDefaults.standard.set(selectedPairingMethod.rawValue, forKey: "lastPairingMethod")
            if selectedPairingMethod == .qr {
                generateNewQRCode()
            } else {
                stopQRPairingTimer()
                discoveryManager.stopListeningForQRPairing()
            }
        }
    }

    // "Pair with pairing code" state
    @Published public var pairingHostInput: String = ""
    @Published public var pairingPortInput: String = ""
    @Published public var pairingCodeInput: String = ""
    @Published public var isPairingInProgress: Bool = false
    @Published public var pairingErrorMessage: String?
    @Published public var pairingRawDetails: String?
    @Published public var showPairingDetails: Bool = false

    // "Pair with QR code" state
    @Published public var qrServiceName: String = ""
    @Published public var qrPassword: String = ""
    @Published public var qrImage: NSImage?
    @Published public var qrStatusText: String = "Waiting for phone to scan..."
    @Published public var qrTimeRemaining: Int = 120
    @Published public var isQRExpired: Bool = false
    @Published public var qrLogDetails: String = ""
    @Published public var showQRDetails: Bool = false

    // Manual IP fallback inside QR tab
    @Published public var qrManualHostInput: String = ""
    @Published public var qrManualPortInput: String = ""
    @Published public var isQRManualPairing: Bool = false

    private var qrCountdownTimer: Timer?

    // Mirror window view state
    @Published public var selectedMode: MirrorMode = .mirror
    @Published public var screenshotBanner: String?

    // Settings & Lock UI State
    @Published public var showSettingsSheet: Bool = false
    @Published public var showResetConfirmation: Bool = false
    @Published public var showChangePasswordSection: Bool = false
    @Published public var changeCurrentPassInput: String = ""
    @Published public var changeNewPassInput: String = ""
    @Published public var changeConfirmPassInput: String = ""
    @Published public var changePasswordMessage: String? = nil

    @Published public var turnPhoneScreenOff: Bool = {
        let saved = UserDefaults.standard.object(forKey: "PhoneMirroring.turnPhoneScreenOff") as? Bool
        return saved ?? false
    }() {
        didSet {
            UserDefaults.standard.set(turnPhoneScreenOff, forKey: "PhoneMirroring.turnPhoneScreenOff")
        }
    }

    public let discoveryManager = DeviceDiscoveryManager.shared
    public let mirrorManager = MirrorSessionManager.shared
    public let adbManager = ADBManager.shared

    private init() {}

    public func navigate(to screen: NavigationScreen) {
        self.currentScreen = screen
        if screen == .devices {
            discoveryManager.startDiscovery()
        } else if screen == .home {
            discoveryManager.stopDiscovery()
            dismissPairingSheet()
        }
    }

    public func openPairingSheet(for device: DiscoveredDevice? = nil) {
        self.pairingTargetDevice = device

        // Best effort to discover host: target device -> any discovered device -> default
        let detectedHost: String = device?.host ?? (discoveryManager.devices.first(where: { $0.host != nil && $0.host != "127.0.0.1" })?.host ?? "192.168.1.13")

        self.pairingHostInput = detectedHost
        self.qrManualHostInput = detectedHost

        if let p = device?.pairingPort {
            self.pairingPortInput = String(p)
            self.qrManualPortInput = String(p)
        } else if let p = device?.port {
            self.pairingPortInput = String(p)
            self.qrManualPortInput = ""
        } else {
            self.pairingPortInput = ""
            self.qrManualPortInput = ""
        }

        self.pairingCodeInput = ""
        self.pairingErrorMessage = nil
        self.pairingRawDetails = nil
        self.showPairingDetails = false
        self.showQRDetails = false
        self.showPairingSheet = true

        if selectedPairingMethod == .qr {
            generateNewQRCode()
        }
    }

    public func dismissPairingSheet() {
        stopQRPairingTimer()
        discoveryManager.stopListeningForQRPairing()
        self.showPairingSheet = false
    }

    public func generateNewQRCode() {
        stopQRPairingTimer()

        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomSuffix = String((0..<8).map { _ in chars.randomElement()! })
        let serviceName = "studio-\(randomSuffix)"
        let password = String(format: "%06d", Int.random(in: 100000...999999))

        self.qrServiceName = serviceName
        self.qrPassword = password
        self.qrTimeRemaining = 120
        self.isQRExpired = false
        self.qrStatusText = "Waiting for phone to scan..."

        let timeStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.qrLogDetails = "[\(timeStr)] New QR session started (service: \(serviceName))\n"

        // QR format: WIFI:T:ADB;S:<serviceName>;P:<password>;;
        let qrString = "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
        self.qrImage = generateQRImage(from: qrString)

        self.qrCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.qrTimeRemaining > 1 {
                    self.qrTimeRemaining -= 1
                } else {
                    self.qrTimeRemaining = 0
                    self.isQRExpired = true
                    self.qrStatusText = "QR code expired. Generate a new QR code."
                    self.stopQRPairingTimer()
                    self.discoveryManager.stopListeningForQRPairing()
                }
            }
        }

        discoveryManager.startListeningForQRPairing(
            serviceName: serviceName,
            password: password,
            onStatus: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.qrStatusText = status
                }
            },
            onLog: { [weak self] logMsg in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let nowStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    self.qrLogDetails += "[\(nowStr)] \(logMsg)\n"
                }
            },
            completion: { [weak self] success, errorMsg, device in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if success, let dev = device {
                        self.stopQRPairingTimer()
                        self.showPairingSheet = false
                        Task {
                            await self.connect(to: dev)
                        }
                    } else if let err = errorMsg {
                        self.qrStatusText = err
                    }
                }
            }
        )
    }

    public func stopQRPairingTimer() {
        qrCountdownTimer?.invalidate()
        qrCountdownTimer = nil
    }

    /// Fallback manual pairing using the current QR password and entered IP/port
    public func qrPairWithManualIP() async -> Bool {
        let cleanHost = qrManualHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPortStr = qrManualPortInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty else {
            self.qrStatusText = "Please enter the phone's IP address."
            return false
        }
        guard let port = Int(cleanPortStr), port > 0, port <= 65535 else {
            self.qrStatusText = "Please enter a valid numeric pairing port (e.g. 37891)."
            return false
        }

        self.isQRManualPairing = true
        self.qrStatusText = "Pairing with \(cleanHost):\(port)..."
        let nowStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.qrLogDetails += "[\(nowStr)] [Manual IP Fallback] Running adb pair \(cleanHost):\(port)...\n"

        let result = await adbManager.pairWirelessDevice(host: cleanHost, port: port, code: qrPassword)

        if !result.success {
            self.isQRManualPairing = false
            self.qrStatusText = result.friendlyMessage
            self.qrLogDetails += "[\(nowStr)] [Manual IP Failed] \(result.rawDetails)\n"
            return false
        }

        self.qrStatusText = "Paired! Connecting..."
        self.qrLogDetails += "[\(nowStr)] [Manual IP] Successfully paired! Auto-connecting...\n"

        var connectPort = 5555
        if let cp = await adbManager.findMDNSConnectService(host: cleanHost) {
            connectPort = cp
        } else if let known = discoveryManager.devices.first(where: { $0.host == cleanHost }), let p = known.port {
            connectPort = p
        }

        let (connected, connMsg) = await adbManager.connectWirelessDevice(host: cleanHost, port: connectPort)
        let isOnline = await adbManager.verifyDeviceConnected(host: cleanHost)

        self.isQRManualPairing = false

        if connected || isOnline {
            self.qrStatusText = "Paired!"
            self.qrLogDetails += "[\(nowStr)] [Success] Device is connected to port \(connectPort)!\n"
            self.stopQRPairingTimer()
            self.discoveryManager.stopListeningForQRPairing()
            self.showPairingSheet = false
            let device = DiscoveredDevice(
                id: "\(cleanHost):\(connectPort)",
                name: "Android Device",
                model: "Wi-Fi Android Device",
                connectionType: .wifi,
                host: cleanHost,
                port: connectPort,
                isPairedBefore: true,
                isConnected: true
            )
            await connect(to: device)
            return true
        } else {
            self.qrStatusText = "Paired, but could not connect to port \(connectPort)"
            self.qrLogDetails += "[\(nowStr)] [Connect Failed] \(connMsg)\n"
            return false
        }
    }

    public func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    public func pairWithCode() async -> Bool {
        let cleanHost = pairingHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPortStr = pairingPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanHost.isEmpty else {
            self.pairingErrorMessage = "Please enter the phone's IP address."
            return false
        }

        guard let port = Int(cleanPortStr), port > 0, port <= 65535 else {
            self.pairingErrorMessage = "Please enter a valid numeric port (e.g. 37891)."
            return false
        }

        guard cleanCode.count >= 4 else {
            self.pairingErrorMessage = "Pairing code must be at least 4-6 digits."
            return false
        }

        self.isPairingInProgress = true
        self.pairingErrorMessage = nil
        self.pairingRawDetails = nil

        let result = await adbManager.pairWirelessDevice(host: cleanHost, port: port, code: cleanCode)

        guard result.success else {
            self.isPairingInProgress = false
            self.pairingErrorMessage = result.friendlyMessage
            self.pairingRawDetails = result.rawDetails
            return false
        }

        // Successfully paired! Auto-connect to connect service
        var connectPort = pairingTargetDevice?.port ?? 5555
        if let found = discoveryManager.devices.first(where: { $0.host == cleanHost }), let p = found.port {
            connectPort = p
        }

        let (connected, connMsg) = await adbManager.connectWirelessDevice(host: cleanHost, port: connectPort)
        let isOnline = await adbManager.verifyDeviceConnected(host: cleanHost)

        self.isPairingInProgress = false

        if connected || isOnline {
            self.showPairingSheet = false
            let device = DiscoveredDevice(
                id: "\(cleanHost):\(connectPort)",
                name: pairingTargetDevice?.name ?? "Android Device",
                model: pairingTargetDevice?.model ?? "Wi-Fi Android Device",
                connectionType: .wifi,
                host: cleanHost,
                port: connectPort,
                isPairedBefore: true,
                isConnected: true
            )
            await connect(to: device)
            return true
        } else {
            self.pairingErrorMessage = "Paired successfully, but could not connect to port \(connectPort): \(connMsg)"
            self.pairingRawDetails = connMsg
            return false
        }
    }

    public func connect(to device: DiscoveredDevice) async {
        self.isConnecting = true
        self.errorMessage = nil

        // If it's a Wi-Fi device that hasn't been paired yet, show pairing prompt
        if device.connectionType == .wifi && !device.isPairedBefore && !device.isConnected {
            self.openPairingSheet(for: device)
            self.isConnecting = false
            return
        }

        // If it's Wi-Fi and has host & port, run `adb connect`
        if device.connectionType == .wifi, let host = device.host, let port = device.port {
            let (success, msg) = await adbManager.connectWirelessDevice(host: host, port: port)
            if !success {
                self.errorMessage = "Failed to connect to \(device.name): \(msg)"
                self.isConnecting = false
                return
            }
        }

        // Start mirroring session
        self.activeDevice = device
        let started = await mirrorManager.startSession(device: device, mode: self.selectedMode, turnScreenOff: self.turnPhoneScreenOff)
        self.isConnecting = false

        if started {
            self.navigate(to: .mirror)
        } else {
            self.errorMessage = mirrorManager.warningMessage ?? "Could not start screen mirror session."
        }
    }

    public func disconnect() async {
        await mirrorManager.stopSession()
        if let dev = activeDevice {
            await adbManager.disconnectDevice(serial: dev.id)
        }
        self.activeDevice = nil
        self.navigate(to: .devices)
    }

    public func forgetDevice(_ device: DiscoveredDevice) {
        KeychainManager.shared.removeTrustedDevice(id: device.id)
        if let host = device.host {
            KeychainManager.shared.removeTrustedDevice(id: host)
        }
        Task {
            await adbManager.disconnectDevice(serial: device.id)
            await discoveryManager.refreshDevices()
        }
    }
}

public func generateQRImage(from string: String) -> NSImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    guard let data = string.data(using: .utf8) else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")

    guard let outputImage = filter.outputImage else { return nil }
    let transform = CGAffineTransform(scaleX: 10, y: 10)
    let scaledImage = outputImage.transformed(by: transform)

    let rep = NSCIImageRep(ciImage: scaledImage)
    let nsImage = NSImage(size: rep.size)
    nsImage.addRepresentation(rep)
    return nsImage
}
