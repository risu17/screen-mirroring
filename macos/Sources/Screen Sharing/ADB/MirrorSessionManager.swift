import Foundation
import Combine
import AppKit

public enum MirrorMode: String, CaseIterable, Identifiable, Sendable {
    case mirror = "Mirror Mode"
    case independent = "Independent Mode"

    public var id: String { rawValue }
}

public final class MirrorSessionManager: ObservableObject {
    public static let shared = MirrorSessionManager()

    @Published public var isRunning: Bool = false
    @Published public var currentDevice: DiscoveredDevice?
    @Published public var currentMode: MirrorMode = .mirror
    @Published public var connectionQuality: String = "Good (Wi-Fi)"
    @Published public var warningMessage: String?
    @Published public var fps: Int = 60

    // Display power & stream resilience states
    @Published public var isPhoneScreenDark: Bool = false
    @Published public var isPhoneAsleep: Bool = false
    @Published public var isReconnecting: Bool = false
    @Published public var reconnectAttempt: Int = 0

    private var scrcpyProcess: Process?
    public var scrcpyProcessInstance: Process? { scrcpyProcess }

    private var userInitiatedDisconnect: Bool = false
    private var wakefulnessTimer: Timer?

    private init() {}

    public func startSession(
        device: DiscoveredDevice,
        mode: MirrorMode = .mirror,
        turnScreenOff: Bool = false,
        isRetry: Bool = false
    ) async -> Bool {
        if !isRetry {
            await stopSession(isUserInitiated: false)
            self.userInitiatedDisconnect = false
            self.reconnectAttempt = 0
            self.isReconnecting = false
            self.isPhoneAsleep = false
            self.isPhoneScreenDark = turnScreenOff
        } else {
            // Clean up old process before retry
            if let proc = scrcpyProcess, proc.isRunning {
                proc.terminate()
                scrcpyProcess = nil
            }
        }

        self.currentDevice = device
        self.currentMode = mode
        self.warningMessage = nil

        var args: [String] = [
            "--serial", device.id,
            "--max-size", "1920",
            "--max-fps", "60",
            "--video-bit-rate", "8M",
            "--window-title", "Phone Mirroring - \(device.name)"
        ]

        // Only apply screen-off if explicitly requested
        if turnScreenOff {
            args.append("--turn-screen-off")
        }

        if mode == .independent {
            // Android 11+ / 14+ virtual display
            args.append(contentsOf: ["--new-display=1920x1080/420"])
        }

        let scrcpyBin = ADBManager.shared.scrcpyPath
        guard FileManager.default.isExecutableFile(atPath: scrcpyBin) else {
            DispatchQueue.main.async {
                self.warningMessage = "scrcpy binary not found at \(scrcpyBin)"
            }
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyBin)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        let binDir = (scrcpyBin as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
        env["SCRCPY_SERVER_PATH"] = ADBManager.shared.scrcpyServerPath
        process.environment = env

        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            self.scrcpyProcess = process

            DispatchQueue.main.async {
                self.isRunning = true
                self.isReconnecting = false
                self.startWakefulnessPolling(serial: device.id)
            }

            // Monitor termination in background
            DispatchQueue.global(qos: .utility).async { [weak self] in
                process.waitUntilExit()
                let exitStatus = process.terminationStatus
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    if self.userInitiatedDisconnect {
                        self.isRunning = false
                        self.currentDevice = nil
                        self.isReconnecting = false
                        self.reconnectAttempt = 0
                        await ADBManager.shared.cleanupPhone(serial: device.id)
                        await ADBManager.shared.killServerIfNoDevices()
                        return
                    }

                    // Check if phone went to sleep
                    let wakeState = await ADBManager.shared.checkWakefulness(serial: device.id)
                    if wakeState == .asleep {
                        self.isRunning = false
                        self.isPhoneAsleep = true
                        NSLog("[MirrorSession] Phone screen went to sleep. Pausing stream and showing wake overlay.")
                        return
                    }

                    // Handle Independent Mode fallback
                    if exitStatus != 0 && mode == .independent && (errStr.contains("display") || errStr.contains("unsupported")) {
                        self.warningMessage = "Independent Mode is not supported by your phone. Falling back to Mirror Mode."
                        Task { _ = await self.startSession(device: device, mode: .mirror) }
                        return
                    }

                    // Stream dropped unexpectedly (e.g. phone screen turned on, video encoder stopped, Wi-Fi glitch)
                    if self.reconnectAttempt < 3 {
                        self.reconnectAttempt += 1
                        self.isReconnecting = true
                        NSLog("[MirrorSession] Stream dropped unexpectedly (exit: %d). Auto-reconnecting attempt %d/3...", exitStatus, self.reconnectAttempt)
                        
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        
                        // Ensure screen backlight is awake
                        _ = await ADBManager.shared.runADB(args: ["-s", device.id, "shell", "input", "keyevent", "224"])
                        
                        let ok = await self.startSession(
                            device: device,
                            mode: mode,
                            turnScreenOff: self.isPhoneScreenDark,
                            isRetry: true
                        )
                        if ok {
                            self.isReconnecting = false
                            self.reconnectAttempt = 0
                        }
                    } else {
                        // Max retries exceeded
                        self.isRunning = false
                        self.isReconnecting = false
                        self.reconnectAttempt = 0
                        self.warningMessage = "Mirror connection lost. Tap 'Connect Devices' to reconnect."
                        await ADBManager.shared.cleanupPhone(serial: device.id)
                        await ADBManager.shared.killServerIfNoDevices()
                    }
                }
            }

            return true
        } catch {
            DispatchQueue.main.async {
                self.warningMessage = "Failed to launch mirror: \(error.localizedDescription)"
            }
            return false
        }
    }

    public func stopSession(isUserInitiated: Bool = true) async {
        self.userInitiatedDisconnect = isUserInitiated
        self.isReconnecting = false
        self.reconnectAttempt = 0

        wakefulnessTimer?.invalidate()
        wakefulnessTimer = nil

        if let proc = scrcpyProcess, proc.isRunning {
            proc.terminate()
            scrcpyProcess = nil
        }

        if let dev = currentDevice {
            // Restore physical display power on session exit
            _ = await ADBManager.shared.setDisplayPower(serial: dev.id, turnOff: false)
            await ADBManager.shared.cleanupPhone(serial: dev.id)
            await ADBManager.shared.killServerIfNoDevices()
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.currentDevice = nil
            self.isPhoneScreenDark = false
            self.isPhoneAsleep = false
        }
    }

    /// Wake up the phone from sleep and restore mirroring stream
    public func wakePhone() async {
        guard let dev = currentDevice else { return }
        NSLog("[MirrorSession] Waking phone via KEYCODE_WAKEUP (224)...")
        _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "shell", "input", "keyevent", "224"])
        
        DispatchQueue.main.async {
            self.isPhoneAsleep = false
        }

        // If scrcpy stream exited due to encoder pausing on sleep, restart it
        if !isRunning {
            _ = await startSession(
                device: dev,
                mode: currentMode,
                turnScreenOff: isPhoneScreenDark,
                isRetry: true
            )
        }
    }

    /// Toggle device physical screen on or off using DisplayManager
    public func togglePhysicalDisplayPower() async {
        guard let dev = currentDevice else { return }
        let turnOff = !isPhoneScreenDark
        let ok = await ADBManager.shared.setDisplayPower(serial: dev.id, turnOff: turnOff)
        
        if ok {
            DispatchQueue.main.async {
                self.isPhoneScreenDark = turnOff
            }
        } else {
            DispatchQueue.main.async {
                self.warningMessage = "Your phone OEM ignored physical display power control. You can switch to Independent Mode for an isolated display."
            }
        }
    }

    private func startWakefulnessPolling(serial: String) {
        wakefulnessTimer?.invalidate()
        wakefulnessTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                let state = await ADBManager.shared.checkWakefulness(serial: serial)
                if state == .asleep && !self.isPhoneAsleep {
                    self.isPhoneAsleep = true
                } else if state == .awake && self.isPhoneAsleep {
                    self.isPhoneAsleep = false
                }
            }
        }
    }

    public func sendControlAction(action: ControlAction) async {
        guard let dev = currentDevice else { return }
        let keycode: String
        switch action {
        case .back:
            keycode = "4"
        case .home:
            keycode = "3"
        case .recents:
            keycode = "187"
        case .rotate:
            _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "shell", "settings", "put", "system", "user_rotation", "1"])
            return
        case .screenshot:
            let remotePath = "/sdcard/screenshot_\(Int(Date().timeIntervalSince1970)).png"
            _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "shell", "screencap", "-p", remotePath])
            let home = FileManager.default.homeDirectoryForCurrentUser
            let localPath = home.appendingPathComponent("Desktop/\((remotePath as NSString).lastPathComponent)").path
            _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "pull", remotePath, localPath])
            _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "shell", "rm", remotePath])
            return
        }

        _ = await ADBManager.shared.runADB(args: ["-s", dev.id, "shell", "input", "keyevent", keycode])
    }
}

public enum ControlAction {
    case back
    case home
    case recents
    case rotate
    case screenshot
}
