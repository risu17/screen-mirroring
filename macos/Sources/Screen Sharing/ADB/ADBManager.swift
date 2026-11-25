import Foundation
import Network

public struct PairingResult: Sendable {
    public let success: Bool
    public let friendlyMessage: String
    public let rawDetails: String

    public init(success: Bool, friendlyMessage: String, rawDetails: String) {
        self.success = success
        self.friendlyMessage = friendlyMessage
        self.rawDetails = rawDetails
    }
}

public final class ADBManager {
    public static let shared = ADBManager()

    public private(set) var adbPath: String
    public private(set) var scrcpyPath: String
    public private(set) var scrcpyServerPath: String

    private init() {
        let bundleResources = Bundle.main.resourcePath ?? ""
        let bundledAdb = (bundleResources as NSString).appendingPathComponent("bin/adb")
        let bundledScrcpy = (bundleResources as NSString).appendingPathComponent("bin/scrcpy")
        let bundledServer = (bundleResources as NSString).appendingPathComponent("bin/scrcpy-server")

        if FileManager.default.isExecutableFile(atPath: bundledAdb) {
            self.adbPath = bundledAdb
        } else {
            let localFallback = "/Users/risu1712/screen share/macos/Resources/bin/adb"
            if FileManager.default.isExecutableFile(atPath: localFallback) {
                self.adbPath = localFallback
            } else {
                self.adbPath = "/usr/local/bin/adb"
            }
        }

        if FileManager.default.isExecutableFile(atPath: bundledScrcpy) {
            self.scrcpyPath = bundledScrcpy
        } else {
            let localFallback = "/Users/risu1712/screen share/macos/Resources/bin/scrcpy"
            if FileManager.default.isExecutableFile(atPath: localFallback) {
                self.scrcpyPath = localFallback
            } else {
                self.scrcpyPath = "/usr/local/bin/scrcpy"
            }
        }

        if FileManager.default.fileExists(atPath: bundledServer) {
            self.scrcpyServerPath = bundledServer
        } else {
            self.scrcpyServerPath = "/Users/risu1712/screen share/macos/Resources/bin/scrcpy-server"
        }
    }

    public func runCommand(executable: String, args: [String], timeout: TimeInterval = 12) async -> (output: String, error: String, exitCode: Int32) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let binDir = (executable as NSString).deletingLastPathComponent
                env["PATH"] = "\(binDir):/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
                env["SCRCPY_SERVER_PATH"] = self.scrcpyServerPath
                env["ADB_MDNS_OPENSCREEN"] = "1"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (outStr, errStr, process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription, -1))
                }
            }
        }
    }

    public func runADB(args: [String], timeout: TimeInterval = 12) async -> (output: String, error: String, exitCode: Int32) {
        return await runCommand(executable: adbPath, args: args, timeout: timeout)
    }

    /// List USB & Wi-Fi connected devices via `adb devices -l`
    public func fetchConnectedDevices() async -> [DiscoveredDevice] {
        let (output, _, code) = await runADB(args: ["devices", "-l"])
        guard code == 0 else { return [] }

        var devices: [DiscoveredDevice] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices") || trimmed.hasPrefix("* daemon") {
                continue
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }

            let serial = String(parts[0])
            let status = String(parts[1])

            guard status == "device" else { continue }

            let isNetwork = serial.contains(":") || serial.contains(".")
            let connectionType: DeviceConnectionType = isNetwork ? .wifi : .usb

            var model = "Android Phone"
            var product = ""

            for part in parts.dropFirst(2) {
                let pair = part.split(separator: ":", maxSplits: 1)
                if pair.count == 2 {
                    let key = pair[0]
                    let val = pair[1].replacingOccurrences(of: "_", with: " ")
                    if key == "model" { model = String(val) }
                    if key == "product" { product = String(val) }
                }
            }

            let name = model.isEmpty ? (product.isEmpty ? serial : product) : model
            let isPaired = KeychainManager.shared.isTrustedDevice(id: serial)

            var host: String? = nil
            var port: Int? = nil
            if isNetwork {
                let hostParts = serial.split(separator: ":")
                if hostParts.count == 2 {
                    host = String(hostParts[0])
                    port = Int(hostParts[1])
                } else {
                    host = serial
                }
            }

            devices.append(DiscoveredDevice(
                id: serial,
                name: name,
                model: model,
                connectionType: connectionType,
                host: host,
                port: port,
                isPairedBefore: isPaired,
                isConnected: true
            ))
        }

        return devices
    }

    /// Pair a wireless Android device using `adb pair <host>:<port> <code>`
    /// Automatically kills/restarts adb server and retries once if a protocol fault occurs.
    public func pairWirelessDevice(host: String, port: Int, code: String) async -> PairingResult {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = "\(cleanHost):\(port)"

        func executePair() async -> (success: Bool, rawOutput: String, exitCode: Int32) {
            let (out, err, exitCode) = await runADB(args: ["pair", target, cleanCode], timeout: 12)
            let combined = "\(out)\n\(err)".trimmingCharacters(in: .whitespacesAndNewlines)
            let isSuccess = combined.lowercased().contains("successfully paired")
            return (isSuccess, combined, exitCode)
        }

        var (success, rawOutput, exitCode) = await executePair()

        // If it failed with protocol fault or smartsocket error, restart adb daemon and retry once
        let lowerRaw = rawOutput.lowercased()
        if !success && (lowerRaw.contains("protocol fault") || lowerRaw.contains("status message") || lowerRaw.contains("smartsocket") || exitCode != 0) {
            _ = await runADB(args: ["kill-server"])
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
            _ = await runADB(args: ["start-server"])
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

            let retry = await executePair()
            success = retry.success
            rawOutput = retry.rawOutput
            exitCode = retry.exitCode
        }

        if success {
            KeychainManager.shared.saveTrustedDevice(id: cleanHost, name: cleanHost, host: cleanHost)
            KeychainManager.shared.saveTrustedDevice(id: target, name: cleanHost, host: cleanHost)
            return PairingResult(
                success: true,
                friendlyMessage: "Successfully paired with \(cleanHost)!",
                rawDetails: rawOutput
            )
        } else {
            let friendly = humanizePairingError(rawOutput: rawOutput, host: cleanHost, port: port)
            return PairingResult(
                success: false,
                friendlyMessage: friendly,
                rawDetails: rawOutput.isEmpty ? "Exit code \(exitCode)" : rawOutput
            )
        }
    }

    private func humanizePairingError(rawOutput: String, host: String, port: Int) -> String {
        let lower = rawOutput.lowercased()
        if lower.contains("wrong password") || lower.contains("wrong code") || lower.contains("bad password") {
            return "Wrong pairing code. Please double-check the 6-digit code shown on your phone and try again."
        } else if lower.contains("protocol fault") || lower.contains("status message") {
            return "The pairing session expired or closed on your phone. Tap 'Pair device with pairing code' again on your phone to get a fresh code and port, then re-enter them."
        } else if lower.contains("connection refused") || lower.contains("no route to host") || lower.contains("timed out") || lower.contains("cannot connect") {
            return "Could not reach \(host):\(port). Please ensure both your Mac and phone are on the exact same Wi-Fi network and the pairing dialog is still visible on your phone."
        } else {
            return "Pairing failed. Please make sure Wireless debugging is ON, tap 'Pair device with pairing code' on your phone, and enter the updated port and code."
        }
    }

    /// Run `adb connect <host>:<port>`
    public func connectWirelessDevice(host: String, port: Int) async -> (success: Bool, message: String) {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = "\(cleanHost):\(port)"
        let (out, err, _) = await runADB(args: ["connect", target], timeout: 10)
        let combined = "\(out)\n\(err)".trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = combined.lowercased()
        let isSuccess = lower.contains("connected to") && !lower.contains("cannot connect") && !lower.contains("failed to connect")

        if isSuccess {
            KeychainManager.shared.saveTrustedDevice(id: cleanHost, name: cleanHost, host: cleanHost)
            KeychainManager.shared.saveTrustedDevice(id: target, name: cleanHost, host: cleanHost)
            return (true, combined)
        } else {
            return (false, combined)
        }
    }

    /// Verify if a device is recognized as online "device" in `adb devices`
    public func verifyDeviceConnected(host: String) async -> Bool {
        let (output, _, code) = await runADB(args: ["devices"])
        guard code == 0 else { return false }
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(host) && trimmed.hasSuffix("device") {
                return true
            }
        }
        return false
    }

    /// Disconnect a wireless device
    public func disconnectDevice(serial: String) async {
        if serial.contains(":") {
            _ = await runADB(args: ["disconnect", serial])
        }
    }

    /// Clean up temp scrcpy server files from the phone
    public func cleanupPhone(serial: String) async {
        _ = await runADB(args: ["-s", serial, "shell", "rm", "-f", "/data/local/tmp/scrcpy-server*"])
    }

    /// Start adb server
    public func startServer() async {
        _ = await runADB(args: ["start-server"])
    }

    /// Kill adb server
    public func killServer() async {
        _ = await runADB(args: ["kill-server"])
    }

    /// Fetch mdns services discovered by adb daemon
    public func fetchMDNSServices() async -> [(name: String, type: String, host: String, port: Int)] {
        let (out, _, code) = await runADB(args: ["mdns", "services"])
        guard code == 0 else { return [] }
        var list: [(name: String, type: String, host: String, port: Int)] = []

        for line in out.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of") { continue }
            let parts = trimmed.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3 {
                let name = parts[0]
                let type = parts[1]
                let addr = parts[2]
                let addrParts = addr.split(separator: ":")
                if addrParts.count == 2, let port = Int(addrParts[1]) {
                    let host = String(addrParts[0])
                    list.append((name, type, host, port))
                }
            }
        }
        return list
    }

    /// Ask adb mdns for a pairing service matching the QR service name
    public func findMDNSPairingService(serviceName: String) async -> (host: String, port: Int)? {
        let cleanName = serviceName.lowercased()
        let services = await fetchMDNSServices()
        for svc in services {
            if svc.type.contains("pairing") && (svc.name.lowercased().contains(cleanName) || cleanName.contains(svc.name.lowercased())) {
                return (svc.host, svc.port)
            }
        }
        return nil
    }

    /// Ask adb mdns for the connect port of a host
    public func findMDNSConnectService(host: String) async -> Int? {
        let services = await fetchMDNSServices()
        for svc in services {
            if svc.type.contains("connect") && (svc.host == host || svc.name.contains(host)) {
                return svc.port
            }
        }
        return nil
    }

    /// Check if other devices are still connected before stopping adb daemon
    public func killServerIfNoDevices() async {
        let devices = await fetchConnectedDevices()
        if devices.isEmpty {
            _ = await runADB(args: ["kill-server"])
        }
    }

    public enum WakefulnessState: Sendable {
        case awake
        case asleep
        case unknown
    }

    /// Check if phone screen is awake or asleep
    public func checkWakefulness(serial: String) async -> WakefulnessState {
        let (out, _, code) = await runADB(args: ["-s", serial, "shell", "dumpsys", "power"])
        guard code == 0 else { return .unknown }
        if out.contains("mWakefulness=Awake") {
            return .awake
        } else if out.contains("mWakefulness=Asleep") || out.contains("mWakefulness=Dozing") {
            return .asleep
        }
        return .unknown
    }

    /// Control physical display power via Android DisplayManager
    public func setDisplayPower(serial: String, turnOff: Bool) async -> Bool {
        if turnOff {
            let res = await runADB(args: ["-s", serial, "shell", "cmd", "display", "power-off", "0"])
            return res.exitCode == 0
        } else {
            _ = await runADB(args: ["-s", serial, "shell", "cmd", "display", "power-reset", "0"])
            _ = await runADB(args: ["-s", serial, "shell", "input", "keyevent", "224"])
            return true
        }
    }
}
