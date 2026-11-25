import Foundation

public enum DeviceConnectionType: String, Codable, Sendable {
    case wifi = "Wi-Fi"
    case usb = "USB"
}

public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    public let id: String              // Serial number or IP:port
    public var name: String            // Model or user-defined name
    public var model: String           // e.g. "Pixel 8", "Galaxy S24"
    public var connectionType: DeviceConnectionType
    public var host: String?           // IP address for Wi-Fi
    public var port: Int?              // Connect port
    public var pairingPort: Int?       // Pairing port if advertised
    public var isPairedBefore: Bool    // Found in trusted keychain
    public var isConnected: Bool       // Currently attached in adb devices
    public var androidVersion: String? // Android release version (e.g. "14")
    public var lastSeen: Date

    public init(
        id: String,
        name: String,
        model: String = "Android Device",
        connectionType: DeviceConnectionType,
        host: String? = nil,
        port: Int? = nil,
        pairingPort: Int? = nil,
        isPairedBefore: Bool = false,
        isConnected: Bool = false,
        androidVersion: String? = nil,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.connectionType = connectionType
        self.host = host
        self.port = port
        self.pairingPort = pairingPort
        self.isPairedBefore = isPairedBefore
        self.isConnected = isConnected
        self.androidVersion = androidVersion
        self.lastSeen = lastSeen
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}
