import Foundation
import Network
import Combine

public func resolveHostnameIPv4(_ hostname: String) -> String? {
    var clean = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasSuffix(".") {
        clean.removeLast()
    }
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM

    var res: UnsafeMutablePointer<addrinfo>?
    let status = getaddrinfo(clean, nil, &hints, &res)
    guard status == 0, let info = res else { return nil }
    defer { freeaddrinfo(res) }

    var p: UnsafeMutablePointer<addrinfo>? = info
    while p != nil {
        if let current = p {
            if current.pointee.ai_family == AF_INET {
                let sinPtr = current.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = sinPtr.sin_addr
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    return String(cString: buffer)
                }
            }
            p = current.pointee.ai_next
        }
    }
    return nil
}

private final class MainRunLoopNetServiceResolver: NSObject, NetServiceDelegate {
    private let netService: NetService
    private var completion: ((String?, Int) -> Void)?
    private var isDone = false

    init(domain: String, type: String, name: String) {
        self.netService = NetService(domain: domain, type: type, name: name)
        super.init()
        self.netService.delegate = self
    }

    func resolve(timeout: TimeInterval = 10.0, completion: @escaping (String?, Int) -> Void) {
        self.completion = completion
        self.netService.schedule(in: .main, forMode: .common)
        self.netService.resolve(withTimeout: timeout)
    }

    func cancel() {
        if !isDone {
            isDone = true
            netService.stop()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !isDone else { return }
        isDone = true
        var resolvedIP: String?
        let port = sender.port

        if let addresses = sender.addresses {
            for data in addresses {
                data.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: sockaddr.self)
                    if ptr.baseAddress?.pointee.sa_family == sa_family_t(AF_INET) {
                        let sinPtr = raw.bindMemory(to: sockaddr_in.self)
                        if let sin = sinPtr.baseAddress {
                            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                            var saddr = sin.pointee.sin_addr
                            if inet_ntop(AF_INET, &saddr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                                resolvedIP = String(cString: buf)
                            }
                        }
                    }
                }
                if resolvedIP != nil { break }
            }
        }

        if resolvedIP == nil, let hostName = sender.hostName {
            resolvedIP = resolveHostnameIPv4(hostName)
        }

        completion?(resolvedIP, port)
        sender.stop()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        guard !isDone else { return }
        isDone = true
        var resolvedIP: String? = nil
        if let hostName = sender.hostName {
            resolvedIP = resolveHostnameIPv4(hostName)
        }
        completion?(resolvedIP, sender.port)
    }
}

public final class DeviceDiscoveryManager: ObservableObject {
    public static let shared = DeviceDiscoveryManager()

    @Published public var devices: [DiscoveredDevice] = []
    @Published public var isScanning: Bool = false
    @Published public var isWiFiConnected: Bool = true
    @Published public var localNetworkPermissionDenied: Bool = false

    private var connectBrowser: NWBrowser?
    private var pairingBrowser: NWBrowser?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.screensharing.network.monitor")
    private var pollTimer: Timer?

    // QR pairing active session
    private var qrTargetServiceName: String?
    private var qrTargetPassword: String?
    private var onQRStatusChanged: ((String) -> Void)?
    private var onQRLog: ((String) -> Void)?
    private var onQRPairingCompleted: ((Bool, String?, DiscoveredDevice?) -> Void)?
    private var isQRPairingInProgress: Bool = false

    private init() {
        setupPathMonitor()
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isWiFiConnected = path.usesInterfaceType(.wifi) || path.status == .satisfied
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    public func startDiscovery() {
        guard !isScanning else { return }
        isScanning = true

        startBonjourBrowsers()

        // Poll USB and connected devices immediately and every 2.5 seconds
        Task { await refreshDevices() }

        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshDevices()
                }
            }
        }
    }

    public func stopDiscovery() {
        isScanning = false
        pollTimer?.invalidate()
        pollTimer = nil
        connectBrowser?.cancel()
        pairingBrowser?.cancel()
        connectBrowser = nil
        pairingBrowser = nil
    }

    public func startListeningForQRPairing(
        serviceName: String,
        password: String,
        onStatus: @escaping (String) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping (Bool, String?, DiscoveredDevice?) -> Void
    ) {
        self.qrTargetServiceName = serviceName
        self.qrTargetPassword = password
        self.onQRStatusChanged = onStatus
        self.onQRLog = onLog
        self.onQRPairingCompleted = completion
        self.isQRPairingInProgress = false

        onLog("[Discovery] Browsing _adb-tls-pairing._tcp for service '\(serviceName)'...")

        if !isScanning {
            startDiscovery()
        }
    }

    public func stopListeningForQRPairing() {
        self.qrTargetServiceName = nil
        self.qrTargetPassword = nil
        self.onQRStatusChanged = nil
        self.onQRLog = nil
        self.onQRPairingCompleted = nil
        self.isQRPairingInProgress = false
    }

    private func startBonjourBrowsers() {
        let connectParams = NWParameters()
        connectParams.includePeerToPeer = true

        // 1. Browse _adb-tls-connect._tcp
        let connectDescriptor = NWBrowser.Descriptor.bonjour(type: "_adb-tls-connect._tcp", domain: "local.")
        connectBrowser = NWBrowser(for: connectDescriptor, using: connectParams)

        connectBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleBonjourResults(results, isPairing: false)
        }

        connectBrowser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .failed(let error):
                    if case .dns(let dnsError) = error {
                        if dnsError == kDNSServiceErr_PolicyDenied || dnsError == kDNSServiceErr_NoAuth {
                            self?.localNetworkPermissionDenied = true
                        }
                    }
                default:
                    break
                }
            }
        }

        connectBrowser?.start(queue: monitorQueue)

        // 2. Browse _adb-tls-pairing._tcp
        let pairingDescriptor = NWBrowser.Descriptor.bonjour(type: "_adb-tls-pairing._tcp", domain: "local.")
        pairingBrowser = NWBrowser(for: pairingDescriptor, using: connectParams)

        pairingBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleBonjourResults(results, isPairing: true)
        }

        pairingBrowser?.start(queue: monitorQueue)
    }

    private func handleBonjourResults(_ results: Set<NWBrowser.Result>, isPairing: Bool) {
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                // Check for QR pairing match
                if isPairing, let targetQR = qrTargetServiceName, !targetQR.isEmpty {
                    let matches = name.caseInsensitiveCompare(targetQR) == .orderedSame || name.lowercased().contains(targetQR.lowercased())
                    if matches && !isQRPairingInProgress {
                        isQRPairingInProgress = true
                        Task {
                            await handleQRPairingMatch(endpoint: result.endpoint, name: name, type: type, domain: domain)
                        }
                        continue
                    }
                }

                // Standard device discovery resolution
                Task {
                    if let (host, port) = await resolveEndpointMultiMethod(endpoint: result.endpoint, domain: domain, type: type, name: name) {
                        await MainActor.run {
                            self.updateOrAddBonjourDevice(
                                serviceName: name,
                                host: host,
                                port: port,
                                isPairing: isPairing
                            )
                        }
                    }
                }
            }
        }
    }

    private func handleQRPairingMatch(endpoint: NWEndpoint, name: String, type: String, domain: String) async {
        guard let password = qrTargetPassword, let targetQR = qrTargetServiceName else {
            isQRPairingInProgress = false
            return
        }

        await MainActor.run {
            self.onQRStatusChanged?("Phone scanned, finding its address...")
            self.onQRLog?("[Discovery] Phone advertisement detected: '\(name)'")
        }

        var resolvedHost: String? = nil
        var resolvedPort: Int = 0

        // Step 1: NWConnection with IPv4 required
        await MainActor.run { self.onQRLog?("[Method 1] Probing NWConnection (IPv4 required) to \(name)...") }
        let m1 = await resolveViaNWConnection(endpoint: endpoint)
        if let (h, p) = m1 {
            resolvedHost = h
            resolvedPort = p
            await MainActor.run { self.onQRLog?("[Method 1 Success] NWConnection resolved \(h):\(p)") }
        } else {
            await MainActor.run { self.onQRLog?("[Method 1 Failed] NWConnection did not resolve IPv4.") }
        }

        // Step 2: NetService resolve on RunLoop.main (10s timeout)
        if resolvedHost == nil || resolvedPort == 0 {
            await MainActor.run { self.onQRLog?("[Method 2] Trying NetService.resolve() on RunLoop.main (10s)...") }
            let m2 = await resolveViaNetService(domain: domain, type: type, name: name)
            if let (h, p) = m2 {
                resolvedHost = h
                resolvedPort = p
                await MainActor.run { self.onQRLog?("[Method 2 Success] NetService resolved \(h):\(p)") }
            } else {
                await MainActor.run { self.onQRLog?("[Method 2 Failed] NetService did not resolve address.") }
            }
        }

        // Step 3: Ask bundled adb mdns services
        if resolvedHost == nil || resolvedPort == 0 {
            await MainActor.run { self.onQRLog?("[Method 3] Querying 'adb mdns services' for '\(targetQR)'...") }
            if let (h, p) = await ADBManager.shared.findMDNSPairingService(serviceName: targetQR) {
                resolvedHost = h
                resolvedPort = p
                await MainActor.run { self.onQRLog?("[Method 3 Success] adb mdns found \(h):\(p)") }
            } else {
                await MainActor.run { self.onQRLog?("[Method 3 Failed] adb mdns did not find matching pairing service.") }
            }
        }

        // Step 4: Fallback to known device host
        if resolvedHost == nil || resolvedPort == 0 {
            if let known = devices.first(where: { $0.host != nil && $0.host != "127.0.0.1" }), let kh = known.host {
                resolvedHost = kh
                await MainActor.run { self.onQRLog?("[Method 4 Fallback] Using known phone host \(kh)...") }
            }
        }

        guard let host = resolvedHost, resolvedPort > 0 else {
            await MainActor.run {
                self.onQRLog?("[Resolution Note] Could not resolve host/port on this attempt. Continuing to browse...")
                self.onQRStatusChanged?("Phone scanned, waiting for address resolution...")
                // Method 4: Keep browsing for the full 2 minutes, do not abort!
                self.isQRPairingInProgress = false
            }
            return
        }

        // Host and port acquired! Proceed with pairing
        await MainActor.run {
            self.onQRStatusChanged?("Pairing...")
            self.onQRLog?("[adb pair] Pairing with \(host):\(resolvedPort)...")
        }

        let result = await ADBManager.shared.pairWirelessDevice(host: host, port: resolvedPort, code: password)

        if result.success {
            await MainActor.run {
                self.onQRStatusChanged?("Paired! Connecting...")
                self.onQRLog?("[adb pair] Successfully paired to \(host):\(resolvedPort)!")
            }

            // Short delay for the connect service to start advertising
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            // Determine connect port
            var connectPort = 5555
            if let cp = await ADBManager.shared.findMDNSConnectService(host: host) {
                connectPort = cp
            } else if let known = self.devices.first(where: { $0.host == host }), let p = known.port {
                connectPort = p
            }

            await MainActor.run {
                self.onQRLog?("[adb connect] Connecting to \(host):\(connectPort)...")
            }

            let (connSuccess, connMsg) = await ADBManager.shared.connectWirelessDevice(host: host, port: connectPort)
            let isOnline = await ADBManager.shared.verifyDeviceConnected(host: host)

            await MainActor.run {
                self.isQRPairingInProgress = false
                if connSuccess || isOnline {
                    self.onQRStatusChanged?("Paired!")
                    self.onQRLog?("[Success] Connected to \(host):\(connectPort) as device!")
                    let device = DiscoveredDevice(
                        id: "\(host):\(connectPort)",
                        name: "Android Device",
                        model: "Wi-Fi Android Device",
                        connectionType: .wifi,
                        host: host,
                        port: connectPort,
                        isPairedBefore: true,
                        isConnected: true
                    )
                    self.onQRPairingCompleted?(true, nil, device)
                } else {
                    self.onQRStatusChanged?("Connection failed: \(connMsg)")
                    self.onQRLog?("[adb connect error] \(connMsg)")
                    self.onQRPairingCompleted?(false, "Paired, but could not connect to port \(connectPort): \(connMsg)", nil)
                }
            }
        } else {
            await MainActor.run {
                self.isQRPairingInProgress = false
                self.onQRStatusChanged?(result.friendlyMessage)
                self.onQRLog?("[adb pair error] \(result.rawDetails)")
                // Keep browsing so subsequent scans can proceed
            }
        }
    }

    private func resolveViaNWConnection(endpoint: NWEndpoint) async -> (String, Int)? {
        return await withCheckedContinuation { continuation in
            let params = NWParameters.tcp
            if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOptions.version = .v4
            }
            let conn = NWConnection(to: endpoint, using: params)
            var resumed = false

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 3.0)
            timer.setEventHandler {
                if !resumed {
                    resumed = true
                    conn.cancel()
                    continuation.resume(returning: nil)
                }
            }
            timer.resume()

            conn.stateUpdateHandler = { state in
                if case .ready = state, !resumed {
                    resumed = true
                    timer.cancel()
                    var resolvedHost: String? = nil
                    var resolvedPort: Int = 0

                    if let remote = conn.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = remote {
                        var hStr = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                        if hStr.contains(":") {
                            if let v4 = resolveHostnameIPv4("Android.local") {
                                resolvedHost = v4
                            } else {
                                resolvedHost = hStr
                            }
                        } else {
                            resolvedHost = hStr
                        }
                        resolvedPort = Int(port.rawValue)
                    }
                    conn.cancel()
                    if let h = resolvedHost, resolvedPort > 0 {
                        continuation.resume(returning: (h, resolvedPort))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else if case .failed(_) = state, !resumed {
                    resumed = true
                    timer.cancel()
                    conn.cancel()
                    continuation.resume(returning: nil)
                }
            }
            conn.start(queue: .global())
        }
    }

    private func resolveViaNetService(domain: String, type: String, name: String) async -> (String, Int)? {
        return await withCheckedContinuation { continuation in
            var resumed = false
            let resolver = MainRunLoopNetServiceResolver(domain: domain, type: type, name: name)

            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 10.0)
            timer.setEventHandler {
                if !resumed {
                    resumed = true
                    resolver.cancel()
                    continuation.resume(returning: nil)
                }
            }
            timer.resume()

            resolver.resolve(timeout: 10.0) { ip, port in
                if !resumed {
                    resumed = true
                    timer.cancel()
                    if let ip = ip, port > 0 {
                        continuation.resume(returning: (ip, port))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private func resolveEndpointMultiMethod(endpoint: NWEndpoint, domain: String, type: String, name: String) async -> (String, Int)? {
        if let (h, p) = await resolveViaNWConnection(endpoint: endpoint) {
            return (h, p)
        }
        if let (h, p) = await resolveViaNetService(domain: domain, type: type, name: name) {
            return (h, p)
        }
        return nil
    }

    private func updateOrAddBonjourDevice(serviceName: String, host: String, port: Int, isPairing: Bool) {
        let deviceId = "\(host):\(port)"
        let isPaired = KeychainManager.shared.isTrustedDevice(id: host) || KeychainManager.shared.isTrustedDevice(id: deviceId)

        if let index = devices.firstIndex(where: { $0.host == host || $0.id == deviceId }) {
            var existing = devices[index]
            if isPairing {
                existing.pairingPort = port
            } else {
                existing.port = port
            }
            existing.lastSeen = Date()
            existing.isPairedBefore = isPaired
            devices[index] = existing
        } else {
            let cleanName = serviceName.replacingOccurrences(of: "adb-", with: "Android-")
            let newDev = DiscoveredDevice(
                id: deviceId,
                name: cleanName,
                model: "Wi-Fi Android Device",
                connectionType: .wifi,
                host: host,
                port: isPairing ? nil : port,
                pairingPort: isPairing ? port : nil,
                isPairedBefore: isPaired,
                isConnected: false,
                lastSeen: Date()
            )
            devices.append(newDev)
        }
    }

    public func refreshDevices() async {
        let usbDevices = await ADBManager.shared.fetchConnectedDevices()

        DispatchQueue.main.async {
            var updated = self.devices

            for usbDev in usbDevices {
                if let index = updated.firstIndex(where: { $0.id == usbDev.id || ($0.host != nil && $0.host == usbDev.host) }) {
                    updated[index].isConnected = true
                    updated[index].name = usbDev.name
                    updated[index].model = usbDev.model
                    updated[index].connectionType = usbDev.connectionType
                    if let h = usbDev.host { updated[index].host = h }
                    if let p = usbDev.port { updated[index].port = p }
                    updated[index].lastSeen = Date()
                } else {
                    updated.append(usbDev)
                }
            }

            // Prune stale un-connected devices older than 30s
            let cutoff = Date().addingTimeInterval(-30)
            updated.removeAll { !$0.isConnected && $0.lastSeen < cutoff }

            self.devices = updated
        }
    }
}
