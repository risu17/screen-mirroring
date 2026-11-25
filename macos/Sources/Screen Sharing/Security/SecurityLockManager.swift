import Foundation
import Security
import CommonCrypto
import LocalAuthentication
import AppKit
import Combine

public enum LockState: Sendable {
    case setupRequired // Master password not yet created
    case locked        // Password set, currently locked
    case unlocked      // Authenticated and accessible
}

@MainActor
public final class SecurityLockManager: ObservableObject {
    public static let shared = SecurityLockManager()

    @Published public var lockState: LockState = .locked
    @Published public var isTouchIDEnabled: Bool
    @Published public var autoLockMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoLockMinutes, forKey: "PhoneMirroring.autoLockMinutes")
            resetInactivityTimer()
        }
    }
    @Published public var lockOnSleep: Bool {
        didSet {
            UserDefaults.standard.set(lockOnSleep, forKey: "PhoneMirroring.lockOnSleep")
        }
    }
    @Published public var keepStreamingWhenLocked: Bool {
        didSet {
            UserDefaults.standard.set(keepStreamingWhenLocked, forKey: "PhoneMirroring.keepStreamingWhenLocked")
        }
    }
    @Published public var gracePeriodEnabled: Bool {
        didSet {
            UserDefaults.standard.set(gracePeriodEnabled, forKey: "PhoneMirroring.gracePeriodEnabled")
        }
    }

    public var disconnectWhenLocked: Bool {
        get { !keepStreamingWhenLocked }
        set { keepStreamingWhenLocked = !newValue }
    }

    // Lock screen UI state
    @Published public var passwordInput: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var isAuthenticating: Bool = false
    @Published public var lockoutRemainingSeconds: Int = 0
    @Published public var lastLockedAt: Date? = nil

    // Setup UI state
    @Published public var setupPasswordInput: String = ""
    @Published public var setupConfirmInput: String = ""
    @Published public var setupTouchIDToggle: Bool = true
    @Published public var setupErrorMessage: String? = nil

    private let keychainService = "com.screensharing.macos.applock"
    private let saltAccount = "app_password_salt"
    private let hashAccount = "app_password_hash"

    private var failedAttempts: Int = 0
    private var lockoutUntil: Date?
    private var lockoutTimer: Timer?
    private var inactivityTimer: Timer?
    private var lastUserActivity: Date = Date()
    private var eventMonitor: Any?

    public var isTouchIDAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private init() {
        // Load preferences
        let savedTouchID = UserDefaults.standard.object(forKey: "PhoneMirroring.useTouchID") as? Bool
        let savedAutoLock = UserDefaults.standard.object(forKey: "PhoneMirroring.autoLockMinutes") as? Int ?? 15
        let savedLockOnSleep = UserDefaults.standard.object(forKey: "PhoneMirroring.lockOnSleep") as? Bool ?? true
        let savedKeepStreaming = UserDefaults.standard.object(forKey: "PhoneMirroring.keepStreamingWhenLocked") as? Bool ?? true
        let savedGrace = UserDefaults.standard.object(forKey: "PhoneMirroring.gracePeriodEnabled") as? Bool ?? true

        let context = LAContext()
        let hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        self.isTouchIDEnabled = savedTouchID ?? hasBiometrics
        self.autoLockMinutes = savedAutoLock
        self.lockOnSleep = savedLockOnSleep
        self.keepStreamingWhenLocked = savedKeepStreaming
        self.gracePeriodEnabled = savedGrace

        // Check if master password credentials exist
        if hasStoredCredentials() {
            self.lockState = .locked
            self.lastLockedAt = Date()
            NSLog("[SecurityLock] Initial launch: App locked (password protection active).")
        } else {
            self.lockState = .setupRequired
        }

        setupSystemNotifications()
        setupEventMonitoring()
        resetInactivityTimer()
    }

    // MARK: - Setup First Password
    public func setInitialPassword(password: String, confirm: String, enableTouchID: Bool) -> Bool {
        let cleanPass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanConfirm = confirm.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanPass.count >= 6 else {
            self.setupErrorMessage = "Password must be at least 6 characters long."
            return false
        }
        guard cleanPass == cleanConfirm else {
            self.setupErrorMessage = "Passwords do not match."
            return false
        }

        let salt = SecurityLockManager.generateSalt()
        guard let hash = SecurityLockManager.hashPassword(cleanPass, salt: salt) else {
            self.setupErrorMessage = "Failed to hash password securely."
            return false
        }

        saveCredentials(salt: salt, hash: hash)

        self.isTouchIDEnabled = enableTouchID && isTouchIDAvailable
        UserDefaults.standard.set(self.isTouchIDEnabled, forKey: "PhoneMirroring.useTouchID")

        self.setupPasswordInput = ""
        self.setupConfirmInput = ""
        self.setupErrorMessage = nil
        self.lockState = .unlocked
        resetInactivityTimer()
        return true
    }

    // MARK: - Change Password
    public func changePassword(current: String, newPass: String, confirmPass: String) -> (success: Bool, error: String?) {
        guard let (salt, expectedHash) = loadCredentials() else {
            return (false, "No existing password found.")
        }

        guard let curHash = SecurityLockManager.hashPassword(current, salt: salt), curHash == expectedHash else {
            return (false, "Current password is incorrect.")
        }

        guard newPass.count >= 6 else {
            return (false, "New password must be at least 6 characters long.")
        }

        guard newPass == confirmPass else {
            return (false, "New passwords do not match.")
        }

        let newSalt = SecurityLockManager.generateSalt()
        guard let newHash = SecurityLockManager.hashPassword(newPass, salt: newSalt) else {
            return (false, "Could not hash new password.")
        }

        saveCredentials(salt: newSalt, hash: newHash)
        return (true, nil)
    }

    // MARK: - Unlock with Password
    public func unlockWithPassword() {
        let candidate = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if currently locked out
        if let until = lockoutUntil, Date() < until {
            let rem = Int(until.timeIntervalSinceNow) + 1
            self.lockoutRemainingSeconds = rem
            self.errorMessage = "Too many wrong attempts. Try again in \(rem)s."
            return
        }

        guard let (salt, expectedHash) = loadCredentials() else {
            self.errorMessage = "Authentication configuration missing."
            return
        }

        guard let candidateHash = SecurityLockManager.hashPassword(candidate, salt: salt) else {
            self.errorMessage = "Encryption failure."
            return
        }

        if candidateHash == expectedHash {
            // Success
            failedAttempts = 0
            lockoutUntil = nil
            lockoutTimer?.invalidate()
            self.errorMessage = nil
            self.passwordInput = ""
            self.lockState = .unlocked
            resetInactivityTimer()
        } else {
            // Wrong password
            failedAttempts += 1
            if failedAttempts >= 5 {
                let waitSeconds: TimeInterval
                if failedAttempts == 5 {
                    waitSeconds = 30
                } else if failedAttempts == 6 {
                    waitSeconds = 60
                } else {
                    waitSeconds = 300
                }
                let until = Date().addingTimeInterval(waitSeconds)
                self.lockoutUntil = until
                self.lockoutRemainingSeconds = Int(waitSeconds)
                startLockoutCountdown()
                self.errorMessage = "Wrong password. Locked out for \(Int(waitSeconds)) seconds."
            } else {
                let left = 5 - failedAttempts
                self.errorMessage = "Incorrect password. (\(left) attempts remaining)"
            }
        }
    }

    // MARK: - Touch ID Authentication
    public func authenticateWithTouchID() async {
        guard isTouchIDAvailable, isTouchIDEnabled else { return }

        // If locked out by failed password attempts, do not evaluate
        if let until = lockoutUntil, Date() < until {
            return
        }

        self.isAuthenticating = true
        let context = LAContext()
        context.localizedReason = "Unlock Phone Mirroring"

        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Phone Mirroring") { ok, _ in
                continuation.resume(returning: ok)
            }
        }

        self.isAuthenticating = false
        if success {
            self.failedAttempts = 0
            self.lockoutUntil = nil
            self.lockoutTimer?.invalidate()
            self.errorMessage = nil
            self.passwordInput = ""
            self.lockState = .unlocked
            resetInactivityTimer()
        }
    }

    // MARK: - Lock App
    public func lockApp(reason: String = "Manual lock") {
        guard lockState == .unlocked else { return }

        NSLog("[SecurityLock] App locked. Reason: %@", reason)
        print("[SecurityLock] App locked. Reason: \(reason)")
        self.lastLockedAt = Date()

        if !keepStreamingWhenLocked {
            Task {
                await MirrorSessionManager.shared.stopSession()
            }
        }

        self.passwordInput = ""
        self.errorMessage = nil
        self.lockState = .locked

        // Check 1-minute grace period for Touch ID
        if gracePeriodEnabled && isTouchIDAvailable && isTouchIDEnabled {
            Task {
                await authenticateWithTouchID()
            }
        }
    }

    // MARK: - Reset App (Forgot Password)
    public func resetApp() {
        NSLog("[SecurityLock] Resetting app credentials and forgetting paired devices.")
        deleteCredentials()

        // Clear all saved paired devices
        for id in KeychainManager.shared.listTrustedDeviceIDs() {
            KeychainManager.shared.removeTrustedDevice(id: id)
        }
        UserDefaults.standard.removeObject(forKey: "ScreenSharing.TrustedDevices")

        Task {
            await MirrorSessionManager.shared.stopSession()
            await ADBManager.shared.killServer()
        }

        failedAttempts = 0
        lockoutUntil = nil
        lockoutTimer?.invalidate()
        lockState = .setupRequired
        setupPasswordInput = ""
        setupConfirmInput = ""
        setupErrorMessage = nil
        errorMessage = nil
    }

    // MARK: - Activity Monitoring
    public func registerUserActivity() {
        lastUserActivity = Date()
    }

    private func setupEventMonitoring() {
        if eventMonitor != nil { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .keyDown, .scrollWheel
        ]) { [weak self] event in
            self?.registerUserActivity()
            return event
        }
    }

    private func isScrcpyFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return true }
        if let proc = MirrorSessionManager.shared.scrcpyProcessInstance, frontApp.processIdentifier == proc.processIdentifier {
            return true
        }
        return false
    }

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        // If set to -1, "Never while a phone is mirrored"
        guard autoLockMinutes != -1 else { return }

        // interval: 0 means Immediately (10s delay to allow interaction), else minutes * 60
        let interval: TimeInterval = autoLockMinutes == 0 ? 10.0 : TimeInterval(autoLockMinutes * 60)
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.lockState == .unlocked else { return }
                
                // While a phone is connected and mirror is actively streaming and app/scrcpy is frontmost, NEVER lock
                let isMirrorActive = MirrorSessionManager.shared.isRunning
                let isFrontmost = NSApp.isActive || self.isScrcpyFrontmost()
                if isMirrorActive && isFrontmost {
                    self.lastUserActivity = Date()
                    return
                }

                if self.autoLockMinutes == -1 && isMirrorActive {
                    self.lastUserActivity = Date()
                    return
                }

                let elapsed = Date().timeIntervalSince(self.lastUserActivity)
                if elapsed >= interval {
                    let desc = self.autoLockMinutes == 0 ? "immediately upon inactivity" : "\(self.autoLockMinutes) minutes elapsed without input"
                    self.lockApp(reason: "Inactivity timeout (\(desc))")
                }
            }
        }
    }

    private func startLockoutCountdown() {
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let until = self.lockoutUntil, Date() < until {
                    self.lockoutRemainingSeconds = Int(until.timeIntervalSinceNow) + 1
                    self.errorMessage = "Locked out. Try again in \(self.lockoutRemainingSeconds)s."
                } else {
                    self.lockoutRemainingSeconds = 0
                    self.lockoutUntil = nil
                    self.errorMessage = nil
                    timer.invalidate()
                }
            }
        }
    }

    private func setupSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.lockOnSleep && self.lockState == .unlocked {
                    self.lockApp(reason: "Mac went to sleep (NSWorkspace.willSleepNotification)")
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.lockOnSleep && self.lockState == .unlocked {
                    self.lockApp(reason: "Mac screen locked (com.apple.screenIsLocked)")
                }
            }
        }
    }

    // MARK: - Secure Storage (Keychain with Application Support fallback)
    private var fallbackFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PhoneMirroring", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir.appendingPathComponent(".applock.dat")
    }

    private func hasStoredCredentials() -> Bool {
        return loadCredentials() != nil
    }

    private func saveCredentials(salt: Data, hash: Data) {
        // Try Keychain first
        let saltOk = saveToKeychain(account: saltAccount, data: salt)
        let hashOk = saveToKeychain(account: hashAccount, data: hash)

        if !saltOk || !hashOk {
            // Fallback to protected Application Support file
            let dict: [String: String] = [
                "salt": salt.base64EncodedString(),
                "hash": hash.base64EncodedString()
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                try? data.write(to: fallbackFileURL)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackFileURL.path)
            }
        }
    }

    private func loadCredentials() -> (salt: Data, hash: Data)? {
        // Check Keychain first
        if let salt = loadFromKeychain(account: saltAccount),
           let hash = loadFromKeychain(account: hashAccount) {
            return (salt, hash)
        }

        // Check fallback file
        if FileManager.default.fileExists(atPath: fallbackFileURL.path),
           let data = try? Data(contentsOf: fallbackFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let saltStr = json["salt"], let hashStr = json["hash"],
           let salt = Data(base64Encoded: saltStr),
           let hash = Data(base64Encoded: hashStr) {
            return (salt, hash)
        }

        return nil
    }

    private func deleteCredentials() {
        deleteFromKeychain(account: saltAccount)
        deleteFromKeychain(account: hashAccount)
        try? FileManager.default.removeItem(at: fallbackFileURL)
    }

    private func saveToKeychain(account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? (item as? Data) : nil
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Cryptographic Primitives (PBKDF2 SHA-256)
    public static func hashPassword(_ password: String, salt: Data) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        var derivedKey = Data(repeating: 0, count: 32)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100_000,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        return status == kCCSuccess ? derivedKey : nil
    }

    public static func generateSalt() -> Data {
        var salt = Data(repeating: 0, count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return salt
    }
}
