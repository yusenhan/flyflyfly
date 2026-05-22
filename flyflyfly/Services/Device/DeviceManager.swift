import Foundation
import MapKit
import Combine

private enum SimulateLocationMode: String {
    case dvt = "developer dvt"
    case legacy = "developer"

    func clearArgs(host: String?, port: String?, udid: String?) -> [String] {
        if let udid = udid, host == nil {
            return ["developer", "simulate-location", "clear", "--udid", udid]
        }
        guard let host = host, let port = port else { return [] }
        switch self {
        case .dvt:
            return ["developer", "dvt", "simulate-location", "clear", "--rsd", host, port]
        case .legacy:
            return ["developer", "simulate-location", "clear", "--rsd", host, port]
        }
    }

    func setArgs(host: String?, port: String?, udid: String?, latitude: Double, longitude: Double) -> [String] {
        let lat = String(format: AppConstants.Formatting.coordinatePrecision, locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: AppConstants.Formatting.coordinatePrecision, locale: Locale(identifier: "en_US_POSIX"), longitude)
        
        if let udid = udid, host == nil {
            return ["developer", "simulate-location", "set", "--udid", udid, "--", lat, lon]
        }
        
        guard let host = host, let port = port else { return [] }
        switch self {
        case .dvt:
            return ["developer", "dvt", "simulate-location", "set", "--rsd", host, port, "--", lat, lon]
        case .legacy:
            return ["developer", "simulate-location", "set", "--rsd", host, port, "--", lat, lon]
        }
    }
}

private enum TunnelTransport: String, CaseIterable {
    case tcp
    case quic
}

private enum TunnelConnectionType: String {
    case usb
    case wifi
}

// A thread-safe buffer for capturing process output
private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

// A thread-safe buffer for capturing logs
private final class ThreadSafeLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []

    func append(_ text: String) {
        lock.lock()
        buffer.append(text)
        lock.unlock()
    }

    func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let current = buffer
        buffer.removeAll()
        return current
    }
}

struct TunnelOutputParser {
    nonisolated static func endpoint(in text: String) -> (host: String, port: String)? {
        if let host = firstMatch(text, pattern: "RSD\\s+Address:\\s*([^\\s\\n\\r]+)"),
           let port = firstMatch(text, pattern: "RSD\\s+Port:\\s*(\\d+)") {
            return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
        }

        if let host = firstMatch(text, pattern: "\"host\"\\s*:\\s*\"([^\"]+)\""),
           let port = firstMatch(text, pattern: "\"port\"\\s*:\\s*(\\d+)") {
            return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
        }

        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let pair = lines.compactMap(scriptModeEndpoint(from:)).last {
            return pair
        }

        if let host = firstMatch(text, pattern: "--rsd\\s+([^\\s]+)\\s+(\\d+)") {
            let all = matches(text, pattern: "--rsd\\s+([^\\s]+)\\s+(\\d+)")
            if let last = all.last, last.count == 2 {
                return (last[0].trimmingCharacters(in: .whitespacesAndNewlines), last[1])
            }
            if let port = firstMatch(text, pattern: "--rsd\\s+[^\\s]+\\s+(\\d+)") {
                return (host.trimmingCharacters(in: .whitespacesAndNewlines), port)
            }
        }

        return nil
    }

    nonisolated static func immediateFailure(in text: String) -> String? {
        let lowered = text.lowercased()
        
        if lowered.contains("requires root privileges") || lowered.contains("sudo") {
            return "This command requires root privileges. Consider retrying with \"sudo\"."
        }
        
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let isBorder = line.contains("╭") || line.contains("─") || line.contains("╰") || line.contains("╯") || line.contains("│")
                return !line.isEmpty && !isBorder
            }
        
        let fatalMarkers = [
            "error:",
            "exception",
            "traceback",
            "device is not connected",
            "no device connected",
            "connection refused",
            "timed out",
            "timeout"
        ]
        
        return lines.last(where: { line in
            let loweredLine = " " + line.lowercased() + " "
            if fatalMarkers.contains(where: { loweredLine.contains($0) }) { return true }
            if loweredLine.contains(" error ") && !line.contains("──") { return true }
            return false
        })
    }

    nonisolated private static func scriptModeEndpoint(from line: String) -> (host: String, port: String)? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let port = Int(parts[1]), port > 0 else { return nil }
        let host = String(parts[0])
        guard host == "localhost" || host.contains(".") || host.contains(":") else { return nil }
        return (host, String(port))
    }

    nonisolated private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = r.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    nonisolated private static func matches(_ text: String, pattern: String) -> [[String]] {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let result = r.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return result.map { m in
            (1..<m.numberOfRanges).compactMap { idx in
                let rg = m.range(at: idx)
                guard rg.location != NSNotFound else { return nil }
                return ns.substring(with: rg)
            }
        }
    }
}

@MainActor
final class DeviceManager: ObservableObject, DeviceControlling {
    @Published private(set) var connectionState: DeviceConnectionState = .disconnected
    @Published var systemInfo: IOSSystemInfo = IOSSystemInfo()
    @Published private(set) var deviceName: String = "未連接"
    
    private var dtxClient: DTXClient?
    @Published private(set) var lastError: String?
    @Published var manualRsdHost: String = "" {
        didSet { UserDefaults.standard.set(manualRsdHost, forKey: Self.manualRsdHostKey) }
    }
    @Published var manualRsdPort: String = "" {
        didSet { UserDefaults.standard.set(manualRsdPort, forKey: Self.manualRsdPortKey) }
    }
    @Published var tunnelUDID: String = "" {
        didSet { UserDefaults.standard.set(tunnelUDID, forKey: Self.tunnelUDIDKey) }
    }

    @Published var isWirelessMode: Bool = false {
        didSet { UserDefaults.standard.set(isWirelessMode, forKey: Self.wirelessModeKey) }
    }
    @Published var isAutoConnectEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isAutoConnectEnabled, forKey: Self.autoConnectEnabledKey) }
    }
    @Published private(set) var debugLog: [String] = []
    @Published var developerModeDisabled: Bool = false
    @Published var isRepairing: Bool = false
    @Published var repairLogs: [String] = []
    
    private let repairLogBuffer = ThreadSafeLogBuffer()
    private var repairTimer: AnyCancellable?

    var isConnected: Bool { connectionState.isConnected }
    var isConnecting: Bool { connectionState.isBusy }
    var connectionStage: String { connectionState.statusText }

    private struct Endpoint: Sendable {
        let host: String
        let port: String
    }

    private let sendQueue = DispatchQueue(label: "paperclip.gps.sender", qos: .utility)
    private var isConnectionInFlight = false
    private var inFlight = false
    private var pendingCoordinate: CLLocationCoordinate2D?
    private let dvtStream = DVTLocationStream()

    private var rsdEndpoint: Endpoint?
    private var connectedUDID: String?
    private var connectedVersion: String?
    private var autoReconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var userInitiatedDisconnect = false
    private var expectedDvtStreamExit = false
    private var sentLocationCount: Int = 0
    private let runtimeLog = DiagnosticsPaths.logFileURL(named: "device-runtime.log").path
    private let runtimeLogQueue = DispatchQueue(label: "paperclip.runtime.log", qos: .utility)
    private static let manualRsdHostKey = "paperclip.connection.manualRsdHost"
    private static let manualRsdPortKey = "paperclip.connection.manualRsdPort"
    private static let tunnelUDIDKey = "paperclip.connection.tunnelUDID"
    private static let wirelessModeKey = "paperclip.connection.wirelessMode"
    private static let autoConnectEnabledKey = "paperclip.connection.autoConnectEnabled"
    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private let usbmuxMonitor = USBMuxMonitor()
    private var monitorCancellables = Set<AnyCancellable>()

    init() {
        let defaults = UserDefaults.standard
        manualRsdHost = defaults.string(forKey: Self.manualRsdHostKey) ?? ""
        manualRsdPort = defaults.string(forKey: Self.manualRsdPortKey) ?? ""
        tunnelUDID = defaults.string(forKey: Self.tunnelUDIDKey) ?? ""
        isWirelessMode = defaults.bool(forKey: Self.wirelessModeKey)
        if defaults.object(forKey: Self.autoConnectEnabledKey) == nil {
            defaults.set(true, forKey: Self.autoConnectEnabledKey)
        }
        isAutoConnectEnabled = defaults.bool(forKey: Self.autoConnectEnabledKey)
        
        usbmuxMonitor.startMonitoring()
        
        usbmuxMonitor.$devices
            .sink { [weak self] newDevices in
                self?.handleMuxDevicesChanged(newDevices)
            }
            .store(in: &monitorCancellables)
    }

    deinit {
        let stream = dvtStream
        Task { @MainActor in
            stream.stop()
        }
    }

    func terminateAllProcesses() {
        appendLog("執行所有程序清理")
        
        expectedDvtStreamExit = true
        dvtStream.stop()
        
        rsdEndpoint = nil
        connectedUDID = nil
        connectedVersion = nil
        pendingCoordinate = nil
        inFlight = false
    }

    func cleanup() {
        cancelAutoReconnect()
        terminateAllProcesses()
    }

    func connectDevice() {
        Task {
            await connectDeviceInternal(autoTriggered: false, force: true)
        }
    }

    func connectDeviceIfAvailable() {
        guard isAutoConnectEnabled else { return }
        guard !isConnected && !isConnecting else { return }
        guard manualEndpointIfValid() != nil else { return }
        
        appendLog("啟動自動偵測：掃描已連線的 iOS 裝置...")
        let devices = usbmuxMonitor.devices
        if !devices.isEmpty {
            appendLog("啟動自動偵測：偵測到 \(devices.count) 台 iOS 裝置，自動啟動連線流程")
            Task {
                await connectDeviceInternal(autoTriggered: false, force: true)
            }
        } else {
            appendLog("啟動自動偵測：未偵測到任何連接的 iOS 裝置，跳過自動連線")
        }
    }

    func connectDeviceAsync() async throws {
        await connectDeviceInternal(autoTriggered: false, force: true)
        let timeout = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady + AppConstants.Timeouts.mountTimeout)
        while Date() < timeout {
            if isConnected { return }
            if connectionState == .failed {
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: lastError ?? "裝置連線失敗"
                ])
            }
            try await Task.sleep(nanoseconds: 200 * 1_000_000)
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "裝置連線逾時"
        ])
    }

    private func isVersionLegacy(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        guard let majorStr = parts.first, let major = Int(majorStr) else {
            return false
        }
        return major < 17
    }

    private func connectDeviceInternal(autoTriggered: Bool, force: Bool) async {
        guard force || !isConnected else { return }
        if !autoTriggered {
            cancelAutoReconnect()
            appendLog("開始連線 Apple 裝置")
            self.developerModeDisabled = false
            setConnectionState(.connecting(step: "初始化"), deviceName: "連線中…", lastError: nil)
        } else {
            setConnectionState(.connecting(step: "自動重連中"), deviceName: "重新連線中…", lastError: nil)
            appendLog("執行自動重連（第 \(reconnectAttempt) 次）")
        }

        if self.isConnectionInFlight {
            self.appendLog("已有連線流程進行中，略過重複請求")
            return
        }
        self.isConnectionInFlight = true
        defer { self.isConnectionInFlight = false }

        do {
            // 優先檢查是否有已連接的 USBMux 實體設備
            let devices = usbmuxMonitor.devices
            if let targetDevice = devices.first {
                let ver = targetDevice.productVersion ?? "15.0"
                let devName = targetDevice.deviceName ?? "iOS 裝置"
                let udid = targetDevice.id
                let devID = targetDevice.deviceID ?? 0
                
                let isLegacyDevice = isVersionLegacy(ver)
                
                if isLegacyDevice {
                    self.appendLog("偵測到已連接的 Legacy 裝置：\(devName) (系統: \(ver), UDID: \(udid))，啟動純 Swift 原生直連通道...")
                    self.setStage("啟動 Legacy 直連")
                    
                    self.connectedUDID = udid
                    self.connectedVersion = ver
                    
                    // 1. 執行 USBMux 雙穿透，啟動定位模擬服務並獲取 socketFd
                    let socketFd = try await connectLegacyDeviceLocationService(deviceID: devID)
                    
                    // 2. 啟動 dtxClient Legacy 模式
                    let client = DTXClient()
                    client.delegate = self
                    self.dtxClient = client
                    
                    try await client.startLegacy(socketFd: socketFd)
                    self.dvtStream.setClient(client)
                    
                    self.setConnectionState(.connected, deviceName: "\(devName) (iOS \(ver))", lastError: nil)
                    self.appendLog("Legacy 裝置直連成功！定位服務已準備就緒。")
                    self.cancelAutoReconnect()
                    self.reconnectAttempt = 0
                    return
                } else {
                    self.appendLog("偵測到已連接的 iOS 17+ 裝置：\(devName) (系統: \(ver))，退回 RSD 模式。")
                }
            }

            guard let manual = self.manualEndpointIfValid() else {
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "未偵測到已連線的 iOS 16 及以下設備。對於 iOS 17+ 設備，請點擊設定，並手動輸入在 Mac 終端機啟動 'pymobiledevice3 remote start-tunnel' 後獲取的 RSD Address 與 Port。"
                ])
            }
            
            self.setStage("使用手動 RSD")
            self.rsdEndpoint = manual
            
            // 嘗試啟動原生 DVT 位置流，以確認 RSD Port 連接正常
            try await self.startDvtStreamIfNeeded(host: manual.host, port: manual.port)
            
            self.setConnectionState(.connected, deviceName: "手動 iOS 裝置 (RSD: \(manual.host):\(manual.port))", lastError: nil)
            self.appendLog("手動 RSD 連線完成！")
            
            self.cancelAutoReconnect()
            self.reconnectAttempt = 0
        } catch {
            self.terminateAllProcesses()
            self.setConnectionState(.failed, deviceName: "連線失敗", lastError: error.localizedDescription)
            print("❌ connectDevice error: \(error.localizedDescription)")
            self.appendLog("連線失敗：\(error.localizedDescription)")
            if autoTriggered {
                self.scheduleAutoReconnect(reason: error.localizedDescription)
            }
        }
    }

    private func connectLegacyDeviceLocationService(deviceID: Int) async throws -> Int32 {
        let socketPath = "/var/run/usbmuxd"
        
        // -------------------------------------------------------------
        // 步驟 1: 穿透 usbmuxd 連接 lockdownd 並發送 StartService
        // -------------------------------------------------------------
        self.appendLog("正在與 Lockdownd 握手以啟動定位服務...")
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "DeviceManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "無法創建 Unix Socket"])
        }
        
        signal(SIGPIPE, SIG_IGN)
        
        var tv = timeval()
        tv.tv_sec = 4 // 4 秒超時
        tv.tv_usec = 0
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() {
                if i < 104 { rawPointer[i] = byte }
            }
        }
        
        let addrSize = MemoryLayout<sockaddr_un>.size
        let connectRes = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(addrSize))
            }
        }
        
        guard connectRes >= 0 else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -11, userInfo: [NSLocalizedDescriptionKey: "無法連接到本地 usbmuxd"])
        }
        
        let connectPlist: [String: Any] = [
            "ClientVersionString": "flyflyfly",
            "DeviceID": deviceID,
            "PortNumber": 32498, // htons(62078) = 32498
            "MessageType": "Connect",
            "ProgName": "flyflyfly"
        ]
        
        guard sendUsbmuxPlist(fd, plist: connectPlist, tag: 100) else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -12, userInfo: [NSLocalizedDescriptionKey: "發送 usbmux Connect 失敗"])
        }
        
        guard let connResult = readUsbmuxResponse(fd, timeoutSeconds: 3) else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -13, userInfo: [NSLocalizedDescriptionKey: "讀取 usbmux Connect 回應失敗"])
        }
        
        if let number = connResult["Number"] as? Int, number != 0 {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -14, userInfo: [NSLocalizedDescriptionKey: "usbmuxd 拒絕連接 Lockdownd (代碼: \(number))"])
        }
        
        let startServiceRequest: [String: Any] = [
            "Label": "flyflyfly",
            "Request": "StartService",
            "Service": "com.apple.dt.simulatelocation"
        ]
        
        guard let reqData = try? PropertyListSerialization.data(fromPropertyList: startServiceRequest, format: .xml, options: 0) else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -15, userInfo: [NSLocalizedDescriptionKey: "無法序列化 StartService 請求"])
        }
        
        var lengthHeader = CFSwapInt32HostToBig(UInt32(reqData.count))
        var sendData = Data()
        withUnsafePointer(to: &lengthHeader) { pointer in
            sendData.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
        sendData.append(reqData)
        
        let bytesWritten = sendData.withUnsafeBytes { buffer in
            write(fd, buffer.baseAddress, sendData.count)
        }
        
        guard bytesWritten == sendData.count else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -16, userInfo: [NSLocalizedDescriptionKey: "寫入 StartService 失敗"])
        }
        
        var lenBuffer = [UInt8](repeating: 0, count: 4)
        let lenRead = read(fd, &lenBuffer, 4)
        guard lenRead == 4 else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -17, userInfo: [NSLocalizedDescriptionKey: "讀取 StartService 回應長度失敗"])
        }
        
        let responseLength = lenBuffer.withUnsafeBytes { buffer in
            CFSwapInt32BigToHost(buffer.load(as: UInt32.self))
        }
        
        guard responseLength > 0 && responseLength < 1_000_000 else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -18, userInfo: [NSLocalizedDescriptionKey: "無效的 StartService 回應長度"])
        }
        
        var payloadBuffer = [UInt8](repeating: 0, count: Int(responseLength))
        var totalBytesRead = 0
        while totalBytesRead < Int(responseLength) {
            let readChunk = read(fd, &payloadBuffer[totalBytesRead], Int(responseLength) - totalBytesRead)
            if readChunk <= 0 {
                close(fd)
                throw NSError(domain: "DeviceManager", code: -19, userInfo: [NSLocalizedDescriptionKey: "讀取 StartService 數據中斷"])
            }
            totalBytesRead += readChunk
        }
        
        let payloadData = Data(payloadBuffer)
        guard let plist = try? PropertyListSerialization.propertyList(from: payloadData, options: [], format: nil) as? [String: Any] else {
            close(fd)
            throw NSError(domain: "DeviceManager", code: -20, userInfo: [NSLocalizedDescriptionKey: "解析 StartService 回應失敗"])
        }
        
        guard let servicePort = plist["Port"] as? Int else {
            close(fd)
            if let errorMsg = plist["Error"] as? String {
                throw NSError(domain: "DeviceManager", code: -21, userInfo: [NSLocalizedDescriptionKey: "啟動定位服務失敗：\(errorMsg)"])
            }
            throw NSError(domain: "DeviceManager", code: -22, userInfo: [NSLocalizedDescriptionKey: "StartService 未返回 Port 號"])
        }
        
        close(fd)
        self.appendLog("成功在設備上啟動 com.apple.dt.simulatelocation 服務 (埠號: \(servicePort))")
        
        // -------------------------------------------------------------
        // 步驟 2: 再次連接 usbmuxd，穿透到剛才啟動的定位服務 Port
        // -------------------------------------------------------------
        self.appendLog("正在建立定位服務之穿透 Socket (Port: \(servicePort))...")
        let serviceFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serviceFd >= 0 else {
            throw NSError(domain: "DeviceManager", code: -23, userInfo: [NSLocalizedDescriptionKey: "無法創建第二個 Unix Socket"])
        }
        
        setsockopt(serviceFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(serviceFd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        let serviceConnectRes = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(serviceFd, sockaddrPointer, socklen_t(addrSize))
            }
        }
        
        guard serviceConnectRes >= 0 else {
            close(serviceFd)
            throw NSError(domain: "DeviceManager", code: -24, userInfo: [NSLocalizedDescriptionKey: "無法再次連接到本地 usbmuxd"])
        }
        
        let portNumber = Int(CFSwapInt16HostToBig(UInt16(servicePort)))
        let connectServicePlist: [String: Any] = [
            "ClientVersionString": "flyflyfly",
            "DeviceID": deviceID,
            "PortNumber": portNumber,
            "MessageType": "Connect",
            "ProgName": "flyflyfly"
        ]
        
        guard sendUsbmuxPlist(serviceFd, plist: connectServicePlist, tag: 200) else {
            close(serviceFd)
            throw NSError(domain: "DeviceManager", code: -25, userInfo: [NSLocalizedDescriptionKey: "發送 usbmux Connect 定位服務失敗"])
        }
        
        guard let serviceConnResult = readUsbmuxResponse(serviceFd, timeoutSeconds: 3) else {
            close(serviceFd)
            throw NSError(domain: "DeviceManager", code: -26, userInfo: [NSLocalizedDescriptionKey: "讀取 usbmux Connect 定位服務回應失敗"])
        }
        
        if let number = serviceConnResult["Number"] as? Int, number != 0 {
            close(serviceFd)
            throw NSError(domain: "DeviceManager", code: -27, userInfo: [NSLocalizedDescriptionKey: "usbmuxd 拒絕穿透定位服務 (代碼: \(number))"])
        }
        
        self.appendLog("定位服務穿透成功！Socket 已接通。")
        return serviceFd
    }

    private struct UsbmuxHeader {
        var length: UInt32
        var version: UInt32
        var type: UInt32
        var tag: UInt32
    }
    
    private func sendUsbmuxPlist(_ socketFd: Int32, plist: [String: Any], tag: UInt32) -> Bool {
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }
        
        let headerLength = MemoryLayout<UsbmuxHeader>.size
        let totalLength = headerLength + plistData.count
        
        var header = UsbmuxHeader(
            length: UInt32(totalLength),
            version: 1,
            type: 8,
            tag: tag
        )
        
        var data = Data()
        withUnsafePointer(to: &header) { pointer in
            data.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
        data.append(plistData)
        
        let bytesWritten = data.withUnsafeBytes { buffer in
            write(socketFd, buffer.baseAddress, data.count)
        }
        
        return bytesWritten == data.count
    }
    
    private func readUsbmuxResponse(_ socketFd: Int32, timeoutSeconds: Int) -> [String: Any]? {
        let headerLength = MemoryLayout<UsbmuxHeader>.size
        var headerBuffer = [UInt8](repeating: 0, count: headerLength)
        
        let bytesRead = read(socketFd, &headerBuffer, headerLength)
        guard bytesRead == headerLength else { return nil }
        
        let header = headerBuffer.withUnsafeBytes { buffer in
            buffer.load(as: UsbmuxHeader.self)
        }
        
        let payloadLength = Int(header.length) - headerLength
        guard payloadLength > 0 else { return nil }
        
        var payloadBuffer = [UInt8](repeating: 0, count: payloadLength)
        var totalBytesRead = 0
        while totalBytesRead < payloadLength {
            let readChunk = read(socketFd, &payloadBuffer[totalBytesRead], payloadLength - totalBytesRead)
            if readChunk <= 0 {
                return nil
            }
            totalBytesRead += readChunk
        }
        
        let payloadData = Data(payloadBuffer)
        guard let plist = try? PropertyListSerialization.propertyList(from: payloadData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist
    }

    private func manualEndpointIfValid() -> Endpoint? {
        let h = manualRsdHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = manualRsdPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !p.isEmpty else { return nil }
        guard Int(p) != nil else { return nil }
        return Endpoint(host: h, port: p)
    }

    func resetDeveloperModeDisabled() {
        developerModeDisabled = false
    }



    private func handleMuxDevicesChanged(_ newDevices: [USBMuxDevice]) {
        appendLog("偵測到 USBMux 裝置變更，當前連接數量：\(newDevices.count)")
        
        // 若當前處於連線或正在連線狀態，且我們連線的 UDID 已經不在 newDevices 列表中（即已被拔出）
        if isConnected || isConnecting {
            if let activeUDID = connectedUDID {
                let stillConnected = newDevices.contains(where: { $0.identifier == activeUDID || $0.uniqueDeviceID == activeUDID })
                if !stillConnected {
                    appendLog("即插即連：偵測到當前連線的手機已被拔除，主動執行斷開連線...")
                    disconnect()
                    setConnectionState(.disconnected, deviceName: "未連接", lastError: "裝置已拔除")
                    return
                }
            }
        }
        
        // 若偵測到新設備插入，且當前未連線、未正在連線、且開啟了「自動偵測」
        guard isAutoConnectEnabled else { return }
        guard !isConnected && !isConnecting else { return }
        
        let hasLegacyDevice = newDevices.contains(where: { isVersionLegacy($0.productVersion ?? "15.0") })
        if hasLegacyDevice || manualEndpointIfValid() != nil {
            if !newDevices.isEmpty {
                appendLog("即插即連：偵測到 iOS 裝置已接入，自動啟動連線流程...")
                Task {
                    await connectDeviceInternal(autoTriggered: false, force: true)
                }
            }
        }
    }

    func disconnect() {
        userInitiatedDisconnect = true
        Task {
            try? await clearSimulatedLocationAsyncInternal()
            cleanup()
            setConnectionState(.disconnected, deviceName: "未連接", lastError: nil)
            appendLog("裝置已中斷")
        }
    }

    func disconnectAsync() async {
        disconnect()
        while isConnected || isConnecting {
            try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        }
    }

    func sendLocationToDevice(latitude: Double, longitude: Double) {
        guard isConnected else { return }
        let c = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(c) else { return }

        Task {
            self.pendingCoordinate = c
            self.flushLatestCoordinate()
        }
    }

    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws {
        guard isConnected else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "裝置尚未連線"
            ])
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "座標無效"
            ])
        }

        let wasIdle = !self.inFlight && self.pendingCoordinate == nil
        self.pendingCoordinate = coordinate

        guard wasIdle else { return }

        self.flushLatestCoordinate()
        if self.lastError?.contains("發送定位失敗") == true {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: self.lastError ?? "發送定位失敗"
            ])
        }
    }

    func startContinuousLocationStream() {
        guard isConnected else { return }
        Task {
            guard let ep = self.rsdEndpoint else { return }
            do {
                try await self.startDvtStreamIfNeeded(host: ep.host, port: ep.port)
            } catch {
                self.appendLog("啟動 DVT 即時定位流失敗：\(error.localizedDescription)")
            }
        }
    }

    func stopContinuousLocationStream() {
        Task {
            self.expectedDvtStreamExit = true
            self.dvtStream.stop()
        }
    }

    func clearSimulatedLocation() {
        Task {
            try? await clearSimulatedLocationAsync()
        }
    }

    func clearSimulatedLocationAsync() async throws {
        guard isConnected else { return }
        try await clearSimulatedLocationAsyncInternal()
    }

    private func clearSimulatedLocationAsyncInternal() async throws {
        self.dvtStream.clear()
        print("Sweep: cleared location (Native DVT)")
    }

    private func flushLatestCoordinate() {
        guard !inFlight, let next = pendingCoordinate else { return }
        pendingCoordinate = nil
        inFlight = true
        
        Task {
            defer {
                self.inFlight = false
                if self.pendingCoordinate != nil { self.flushLatestCoordinate() }
            }

            let isLegacy = self.connectedVersion.map { self.isVersionLegacy($0) } ?? false
            if !isLegacy && self.rsdEndpoint == nil {
                self.setConnectionState(.failed, deviceName: "RSD 未就緒，請重連", lastError: "RSD 未就緒")
                return
            }

            do {
                let lat = String(format: AppConstants.Formatting.coordinatePrecision, next.latitude)
                let lon = String(format: AppConstants.Formatting.coordinatePrecision, next.longitude)
                try await sendCoordinate(latitude: next.latitude, longitude: next.longitude)
                self.sentLocationCount += 1
                if self.sentLocationCount % 100 == 0 {
                    self.appendLog("定位已送出：\(lat), \(lon)")
                }
            } catch {
                let msg = error.localizedDescription
                print("❌ 發送失敗: \(msg)")
                self.appendLog("送出定位失敗：\(msg)")
                self.lastError = "發送定位失敗：\(msg)"
                if msg.lowercased().contains("timeout") || msg.lowercased().contains("broken pipe") || msg.lowercased().contains("connection") {
                    self.setConnectionState(.failed, deviceName: "Tunnel 中斷，請重連", lastError: msg)
                    self.scheduleAutoReconnect(reason: msg)
                }
            }
        }
    }

    private func handleUnexpectedConnectionLoss(reason: String) {
        guard !userInitiatedDisconnect else { return }
        guard rsdEndpoint != nil || connectionState.isConnected else { return }
        appendLog("連線中斷：\(reason)")
        terminateAllProcesses()
        setConnectionState(.failed, deviceName: "連線已中斷", lastError: reason)
        scheduleAutoReconnect(reason: reason)
    }



    private func scheduleAutoReconnect(reason: String) {
        guard !userInitiatedDisconnect else { return }
        guard autoReconnectWorkItem == nil else { return }

        reconnectAttempt += 1
        let delay = min(AppConstants.DeviceStream.reconnectBackoffCap, pow(2.0, Double(max(0, reconnectAttempt - 1))))
        setConnectionState(.connecting(step: "等待重連"), deviceName: "等待重新連線…", lastError: lastError)
        appendLog("排程自動重連（\(String(format: "%.0f", delay))s）原因：\(reason)")

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.autoReconnectWorkItem = nil
                guard !self.userInitiatedDisconnect else { return }
                await self.connectDeviceInternal(autoTriggered: true, force: true)
            }
        }
        autoReconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelAutoReconnect() {
        autoReconnectWorkItem?.cancel()
        autoReconnectWorkItem = nil
    }

    private func setStage(_ stage: String) {
        setConnectionState(.connecting(step: stage), lastError: nil)
    }

    private func setConnectionState(
        _ state: DeviceConnectionState,
        deviceName: String? = nil,
        lastError: String? = nil
    ) {
        self.connectionState = state
        if let deviceName = deviceName {
            self.deviceName = deviceName
        }
        self.lastError = lastError
        
        // Trigger system monitoring based on state
        if state.isConnected {
            startSystemMonitoring()
        } else {
            stopSystemMonitoring()
        }
    }

    private func startSystemMonitoring() {
        if let ver = connectedVersion, isVersionLegacy(ver) {
            // Legacy 裝置已經在 connectDeviceInternal 啟動好了，直接返回
            print("[DeviceManager] Legacy 效能監控與定位服務已就緒，無需重新啟動")
            return
        }
        
        stopSystemMonitoring()
        
        guard let udid = connectedUDID else { return }
        
        let client = DTXClient()
        client.delegate = self
        self.dtxClient = client
        
        print("[DeviceManager] 啟動原生 DTX 效能監控，UDID: \(udid)")
        
        Task {
            do {
                // RSD 模式 (iOS 17+)
                guard let ep = self.rsdEndpoint else {
                    throw NSError(domain: "DeviceManager", code: -71, userInfo: [NSLocalizedDescriptionKey: "找不到有效的 RSD Endpoint"])
                }
                
                guard let portInt = Int(ep.port) else {
                    throw NSError(domain: "DeviceManager", code: -72, userInfo: [NSLocalizedDescriptionKey: "RSD Port 格式無效"])
                }
                
                // 啟動 DTXClient
                try await client.startRsd(host: ep.host, rsdPort: portInt)
                
                // 啟動成功後，將當前 client 注入 dvtStream 適配器
                self.dvtStream.setClient(client)
                print("[DeviceManager] 原生 DTX 效能監控啟動成功！")
            } catch {
                print("[DeviceManager] 原生 DTX 效能監控啟動失敗: \(error.localizedDescription)")
                self.appendLog("❌ 效能監控啟動失敗: \(error.localizedDescription)")
            }
        }
    }
    
    private func stopSystemMonitoring() {
        self.dvtStream.setClient(nil)
        dtxClient?.stop()
        dtxClient = nil
        systemInfo = IOSSystemInfo()
    }

    private func appendLog(_ text: String) {
        let stamp = Self.logFormatter.string(from: Date())
        let line = "[\(stamp)] \(text)"
        self.debugLog.append(line)
        if self.debugLog.count > 120 {
            self.debugLog.removeFirst(self.debugLog.count - 120)
        }
        
        runtimeLogQueue.async { [runtimeLog] in
            guard let data = (line + "\n").data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: runtimeLog) {
                fm.createFile(atPath: runtimeLog, contents: data)
                return
            }
            do {
                let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: runtimeLog))
                try fh.seekToEnd()
                try fh.write(contentsOf: data)
                try fh.close()
            } catch { }
        }
    }



    nonisolated private func summarizeOutput(_ text: String, maxChars: Int = 260) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(3)
            .joined(separator: " | ")
        if cleaned.count <= maxChars { return cleaned }
        return String(cleaned.prefix(maxChars)) + "..."
    }

    private func sendCoordinate(latitude: Double, longitude: Double) async throws {
        if let ver = connectedVersion, isVersionLegacy(ver) {
            if !dvtStream.isRunning {
                try dvtStream.start(
                    host: "localhost",
                    port: "0",
                    onOutput: { [weak self] text in
                        guard let self = self else { return }
                        let summarized = self.summarizeOutput(text, maxChars: 180)
                        Task { @MainActor in self.appendLog("dvt-stream: \(summarized)") }
                    },
                    onError: { [weak self] text in
                        guard let self = self else { return }
                        let summarized = self.summarizeOutput(text, maxChars: 180)
                        Task { @MainActor in self.appendLog("dvt-stream err: \(summarized)") }
                    },
                    onExit: { [weak self] status in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.appendLog("dvt-stream exited: \(status)")
                            if self.expectedDvtStreamExit {
                                self.expectedDvtStreamExit = false
                                return
                            }
                            self.handleUnexpectedConnectionLoss(reason: "定位串流已中斷（code: \(status)）")
                        }
                    }
                )
            }
            try dvtStream.send(latitude: latitude, longitude: longitude)
            return
        }

        guard let ep = rsdEndpoint else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "RSD 未就緒"
            ])
        }

        try await startDvtStreamIfNeeded(host: ep.host, port: ep.port)
        try dvtStream.send(latitude: latitude, longitude: longitude)
    }

    private func startDvtStreamIfNeeded(host: String, port: String) async throws {
        if dvtStream.isRunning {
            return
        }

        expectedDvtStreamExit = false

        try dvtStream.start(
            host: host,
            port: port,
            onOutput: { [weak self] text in
                guard let self = self else { return }
                let summarized = self.summarizeOutput(text, maxChars: 180)
                Task { @MainActor in self.appendLog("dvt-stream: \(summarized)") }
            },
            onError: { [weak self] text in
                guard let self = self else { return }
                let summarized = self.summarizeOutput(text, maxChars: 180)
                Task { @MainActor in self.appendLog("dvt-stream err: \(summarized)") }
            },
            onExit: { [weak self] status in
                guard let self = self else { return }
                Task { @MainActor in
                    self.appendLog("dvt-stream exited: \(status)")
                    if self.expectedDvtStreamExit {
                        self.expectedDvtStreamExit = false
                        return
                    }
                    self.handleUnexpectedConnectionLoss(reason: "定位串流已中斷（code: \(status)）")
                }
            }
        )
    }



    func repairEnvironment() async {
        guard !isRepairing else { return }
        isRepairing = true
        repairLogs = []
        
        // 啟動 80ms 刷新定時器，將修復日誌批量寫入，避免高頻 UI 渲染造成卡頓
        repairTimer = Timer.publish(every: 0.08, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.flushPendingRepairLogs()
            }
            
        appendRepairLog("[START] 開始執行一鍵修復環境...")
        
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            appendRepairLog("[INFO] 正在重置本地 USBMux 監聽服務...")
            
            // 安全重啟內部的 USBMuxMonitor 連接
            usbmuxMonitor.stopMonitoring()
            try await Task.sleep(nanoseconds: 400_000_000)
            usbmuxMonitor.startMonitoring()
            
            appendRepairLog("[SUCCESS] 本地 USBMux 監聽轉發器已成功重啟！")
            try await Task.sleep(nanoseconds: 200_000_000)
            
            appendRepairLog("[INFO] 指引：若設備仍未被識別，請手動確認以下事項：")
            appendRepairLog("  1. 請拔掉 iPhone 的 USB 數據線，等待 3 秒後重新插入。")
            appendRepairLog("  2. 請解鎖 iPhone，並在「信任此電腦」對話框中點選「信任」並輸入密碼。")
            appendRepairLog("  3. 確保使用支援數據傳輸的原廠或優質傳輸線。")
            appendRepairLog("  4. 由於 macOS 沙盒與安全限制，App 無法透過管理員權限強行重啟系統 usbmuxd。")
            appendRepairLog("  5. 若問題依舊，請嘗試重啟 iPhone 或重啟 Mac 電腦。")
            
            try await Task.sleep(nanoseconds: 200_000_000)
            appendRepairLog("[SUCCESS] 一鍵修復環境程序執行完畢！")
        } catch {
            appendRepairLog("[ERROR] 修復過程遭遇非預期錯誤：\(error.localizedDescription)")
        }
        
        // 確保把剩餘的日誌都刷出來
        flushPendingRepairLogs()
        repairTimer?.cancel()
        repairTimer = nil
        isRepairing = false
    }
    
    nonisolated private func appendRepairLog(_ text: String) {
        repairLogBuffer.append(text)
    }
    
    @MainActor
    private func flushPendingRepairLogs() {
        let logsToFlush = repairLogBuffer.flush()
        guard !logsToFlush.isEmpty else { return }
        
        // 批量寫入 repairLogs
        self.repairLogs.append(contentsOf: logsToFlush)
        
        // 批量寫入 debugLog 並寫入文件以節省 I/O 與 UI 重繪開銷
        let stamp = Self.logFormatter.string(from: Date())
        var newDebugLines: [String] = []
        var fileContent = ""
        for text in logsToFlush {
            let line = "[\(stamp)] [修復環境] \(text)"
            newDebugLines.append(line)
            fileContent += line + "\n"
        }
        
        self.debugLog.append(contentsOf: newDebugLines)
        if self.debugLog.count > 120 {
            self.debugLog.removeFirst(self.debugLog.count - 120)
        }
        
        // 將批量文件寫入丟到背景佇列，避免阻塞 UI
        runtimeLogQueue.async { [runtimeLog, fileContent] in
            guard let data = fileContent.data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: runtimeLog) {
                fm.createFile(atPath: runtimeLog, contents: data)
                return
            }
            do {
                let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: runtimeLog))
                try fh.seekToEnd()
                try fh.write(contentsOf: data)
                try fh.close()
            } catch { }
        }
    }


}

// ==============================================================================
// DTXClientDelegate 實作
// ==============================================================================

extension DeviceManager: DTXClientDelegate {
    @MainActor
    public func dtxClient(_ client: DTXClient, didReceiveCPU cpu: Double, ramUsedGB ram: Double) {
        guard client === self.dtxClient else { return }
        
        self.systemInfo.cpuUsage = cpu
        self.systemInfo.ramUsed = ram
        self.systemInfo.ramTotal = 8.0 // 估計的實體記憶體總量
    }
    
    @MainActor
    public func dtxClient(_ client: DTXClient, didDisconnectWithError error: Error?) {
        guard client === self.dtxClient else { return }
        
        let errorMsg = error?.localizedDescription ?? "正常中斷"
        print("[DeviceManager] 原生 DTX 監控連線中斷: \(errorMsg)")
        self.appendLog("⚠️ 原生 DTX 監控連線中斷: \(errorMsg)")
        
        self.dtxClient = nil
        self.systemInfo = IOSSystemInfo()
    }
}