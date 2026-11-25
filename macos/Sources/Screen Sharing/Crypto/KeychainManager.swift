import Foundation
import Security

public final class KeychainManager {
    public static let shared = KeychainManager()
    private let service = "com.screensharing.macos.trusted-devices"
    private let defaultsKey = "ScreenSharing.TrustedDevices"

    private init() {}

    public func saveTrustedDevice(id: String, name: String, host: String? = nil) {
        // Save to Keychain
        let key = "device.\(id)"
        if let data = name.data(using: .utf8) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        }

        // Also track ID in UserDefaults for fast synchronous listing
        var devices = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        if !devices.contains(id) {
            devices.append(id)
            UserDefaults.standard.set(devices, forKey: defaultsKey)
        }
    }

    public func isTrustedDevice(id: String) -> Bool {
        let devices = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        if devices.contains(id) { return true }

        let key = "device.\(id)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func removeTrustedDevice(id: String) {
        let key = "device.\(id)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var devices = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        devices.removeAll { $0 == id }
        UserDefaults.standard.set(devices, forKey: defaultsKey)
    }

    public func listTrustedDeviceIDs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }
}
