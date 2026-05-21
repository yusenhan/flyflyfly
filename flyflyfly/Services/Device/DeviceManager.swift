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
    
    private var sysMonProcess: Process?
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

    private var tunnelProcess: Process?
    private var tunnelOutPipe: Pipe?
    private var tunnelErrPipe: Pipe?
    private var watchdogTimer: Timer?
    private var rsdEndpoint: Endpoint?
    private var isLegacyMode = false
    private var connectedUDID: String?
    private var connectedVersion: String?
    private var simulateLocationMode: SimulateLocationMode?
    private var autoReconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt: Int = 0
    private var userInitiatedDisconnect = false
    private var expectedDvtStreamExit = false
    private var sentLocationCount: Int = 0
    private var activeTunnelConnectionType: TunnelConnectionType?
    private let privilegedTunnelLog = "/tmp/opaperclip_tunnel.log"
    private let privilegedTunnelPid = "/tmp/opaperclip_tunnel.pid"
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

    private var cachedCLIPath: String?
    
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
        
        // CLI path will be resolved lazily on first use
        usbmuxMonitor.startMonitoring()
        
        usbmuxMonitor.$devices
            .sink { [weak self] newDevices in
                self?.handleMuxDevicesChanged(newDevices)
            }
            .store(in: &monitorCancellables)
    }

    deinit {
        let p = tunnelProcess
        let stream = dvtStream
        // Note: autoReconnectWorkItem is non-sendable, we cancel it in cleanup()
        // which should be called before deinit, but we can also use MainActor.run
        // or simple cancellation if we make it non-isolated.
        
        // Use nonisolated(unsafe) for deinit cleanup of non-sendable objects 
        // if we are sure about the lifecycle. 
        // But the best way is to wrap in Task.
        Task { @MainActor in
            stream.stop()
            if let p = p, p.isRunning {
                p.terminate()
            }
        }
    }

    func terminateAllProcesses() {
        appendLog("執行所有程序清理")
        
        expectedDvtStreamExit = true
        dvtStream.stop()
        
        if let p = tunnelProcess {
            if p.isRunning {
                p.terminate()
            }
            tunnelProcess = nil
        }
        tunnelOutPipe = nil
        tunnelErrPipe = nil
        
        stopPrivilegedTunnelProcessIfNeeded()
        
        rsdEndpoint = nil
        simulateLocationMode = nil
        activeTunnelConnectionType = nil
        pendingCoordinate = nil
        inFlight = false
    }

    func cleanup() {
        cancelAutoReconnect()
        stopWatchdog()
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
            self.activeTunnelConnectionType = self.isWirelessMode ? .wifi : .usb
            let cmd = try resolveCLI()
            self.appendLog("CLI: \(cmd.joined(separator: " "))")
            _ = try await self.runWithTimeoutLogged(
                cmd + ["version"],
                timeout: AppConstants.Timeouts.pymobiledeviceCheck,
                step: "檢查 pymobiledevice3"
            )

            let devices = try await self.listConnectedDevices(using: cmd)
            let picked = devices.first(where: { ($0.connectionType ?? "").uppercased() == "USB" }) ?? devices.first
            
            let osVersion = picked?.productVersion ?? "17.0"
            let udid = picked?.identifier ?? picked?.uniqueDeviceID
            self.connectedUDID = udid
            self.connectedVersion = osVersion
            
            let majorVersion = Int(osVersion.components(separatedBy: ".").first ?? "17") ?? 17
            
            if majorVersion >= 16 {
                await self.checkDeveloperMode(using: cmd, udid: udid)
            }

            if majorVersion < 17 {
                self.isLegacyMode = true
                self.simulateLocationMode = .legacy
                self.appendLog("偵測到 iOS \(osVersion)，啟用 Legacy 模式")
                
                self.setStage("掛載開發者鏡像")
                var mountArgs = cmd + ["mounter", "auto-mount"]
                if let udid = udid {
                    mountArgs += ["--udid", udid]
                }
                _ = try await self.runWithTimeoutLogged(mountArgs, timeout: AppConstants.Timeouts.mountTimeout, step: "掛載鏡像")
                
                self.setConnectionState(.connected, deviceName: await self.connectedDeviceLabel(using: cmd), lastError: nil)
                self.appendLog("Legacy 連線完成（無需 Tunnel/RSD）")
                self.startWatchdog()
            } else {
                self.isLegacyMode = false
                if let manual = self.manualEndpointIfValid() {
                    self.setStage("使用手動 RSD")
                    self.rsdEndpoint = manual
                    try await self.verifyRsdEndpoint(using: cmd, ep: manual)
                } else {
                    let tunnelUDID = try await self.preferredConnectionUDID(using: cmd)
                    self.setStage("準備建立連線")
                    do {
                        try await self.startTunnelAndResolveEndpoint(using: cmd, udid: tunnelUDID)
                    } catch {
                        let err = error.localizedDescription
                        if err.localizedCaseInsensitiveContains("requires root privileges") {
                            self.appendLog("start-tunnel 需要管理員權限，改用提示模式重試")
                            try await self.startTunnelWithAdminPrompt(using: cmd, udid: tunnelUDID)
                        }
                        else if self.shouldFallbackToAnyDevice(for: err) {
                            self.appendLog("指定 UDID 連線失敗，改為自動選擇目前已連線裝置重試")
                            try await self.startTunnelAndResolveEndpoint(using: cmd, udid: nil)
                        } else if try await self.shouldFallbackToUSBTunnel(using: cmd, errorMessage: err) {
                            self.appendLog("Wi‑Fi tunnel 不支援，改用 USB tunnel 重試")
                            self.activeTunnelConnectionType = .usb
                            let usbUDID = try await self.preferredTunnelUDID(using: cmd)
                            self.setStage("切換連線方式")
                            try await self.startTunnelAndResolveEndpoint(using: cmd, udid: usbUDID)
                        } else {
                            throw error
                        }
                    }

                    guard let ep = self.rsdEndpoint else {
                        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "無法取得 RSD host/port"
                        ])
                    }
                    try await self.verifyRsdEndpoint(using: cmd, ep: ep)
                }
                guard let ep = self.rsdEndpoint else {
                    throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "RSD endpoint 在連線完成前遺失，請重試"
                    ])
                }
                let deviceLabel = await self.connectedDeviceLabel(using: cmd)

                self.setConnectionState(.connected, deviceName: "\(deviceLabel) (RSD: \(ep.host):\(ep.port))", lastError: nil)
                self.appendLog("連線完成，模式：\(self.simulateLocationMode?.rawValue ?? "unknown")")
                self.startWatchdog()
            }
            
            self.cancelAutoReconnect()
            self.reconnectAttempt = 0
        } catch {
            self.stopTunnel()
            let lowered = error.localizedDescription.lowercased()
            self.setConnectionState(.failed, deviceName: "連線失敗", lastError: error.localizedDescription)
            print("❌ connectDevice error: \(error.localizedDescription)")
            self.appendLog("連線失敗：\(error.localizedDescription)")
            if autoTriggered || lowered.contains("bad file descriptor") {
                self.scheduleAutoReconnect(reason: error.localizedDescription)
            }
        }
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

    private func checkDeveloperMode(using cmd: [String], udid: String?) async {
        setStage("檢查開發者模式")
        var args = cmd + ["amfi", "developer-mode-status"]
        if let udid = udid {
            args += ["--udid", udid]
        }
        
        do {
            let status = try await runProcessAsync(args, timeout: 5.0)
            appendLog("開發者模式狀態：\(status.trimmingCharacters(in: .whitespacesAndNewlines))")
            if status.lowercased().contains("off") || status.lowercased().contains("false") {
                self.developerModeDisabled = true
            }
        } catch {
            appendLog("無法確認開發者模式狀態：\(error.localizedDescription)")
            // If check fails, we don't block, but if it explicitly said off, we warn.
        }
    }

    private func preferredConnectionUDID(using cmd: [String]) async throws -> String? {
        if isWirelessMode {
            setStage("搜尋可用裝置")
            let requested = effectiveTunnelUDID
            if let requested, !requested.isEmpty {
                appendLog("Wireless Mode：使用指定 UDID 建立 Wi‑Fi tunnel")
                return requested
            }
            if let connectedUDID = try await preferredActiveDeviceUDID(using: cmd) {
                appendLog("Wireless Mode：沿用目前已配對裝置建立 Wi‑Fi tunnel")
                return connectedUDID
            }
            appendLog("Wireless Mode：自動尋找可用的 Wi‑Fi 裝置")
            return nil
        }
        return try await preferredTunnelUDID(using: cmd)
    }

    private func preferredActiveDeviceUDID(using cmd: [String]) async throws -> String? {
        let devices = try await listConnectedDevices(using: cmd)
        guard !devices.isEmpty else { return nil }

        if let requested = effectiveTunnelUDID,
           let matched = devices.first(where: { matchesDevice($0, requestedUDID: requested) }) {
            return matched.identifier ?? matched.uniqueDeviceID
        }

        let preferredDevice =
            devices.first(where: { ($0.connectionType ?? "").uppercased() == "USB" }) ??
            devices.first

        return preferredDevice?.identifier ?? preferredDevice?.uniqueDeviceID
    }

    private func preferredTunnelUDID(using cmd: [String]) async throws -> String? {
        let devices = try await listConnectedDevices(using: cmd)
        guard !devices.isEmpty else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "未偵測到已連線的 iPhone/iPad。請確認裝置已用 USB 接上、已解鎖並信任這台 Mac，且 Finder 或 Xcode 能看到裝置；若你已知 RSD，也可在進階連線直接輸入 host/port。"
            ])
        }

        appendLog("偵測到裝置：" + devices.map(deviceDebugLabel(for:)).joined(separator: "、"))

        guard let requested = effectiveTunnelUDID else { return nil }
        if devices.contains(where: { matchesDevice($0, requestedUDID: requested) }) {
            return requested
        }

        appendLog("指定 UDID \(requested) 不在目前裝置列表中，改用自動選擇")
        return nil
    }

    private func verifyRsdEndpoint(using cmd: [String], ep: Endpoint) async throws {
        setStage("驗證裝置服務")
        appendLog("RSD endpoint: \(ep.host):\(ep.port)")

        _ = try await runWithTimeoutLogged(cmd + [
            "mounter", "auto-mount",
            "--rsd", ep.host, ep.port
        ], timeout: AppConstants.Timeouts.mountTimeout, step: "掛載 Developer Disk Image")

        _ = try await runWithTimeoutLogged(cmd + [
            "remote", "rsd-info",
            "--rsd", ep.host, ep.port
        ], timeout: AppConstants.Timeouts.rsdInfo, step: "讀取 RSD 資訊")

        simulateLocationMode = try await detectSimulateLocationMode(using: cmd, ep: ep)
        appendLog("simulate-location 使用：\(simulateLocationMode?.rawValue ?? "unknown")")
    }

    private func detectSimulateLocationMode(using cmd: [String], ep: Endpoint) async throws -> SimulateLocationMode {
        setStage("偵測 simulate-location 模式")
        do {
            _ = try await runWithTimeoutLogged(
                cmd + SimulateLocationMode.dvt.clearArgs(host: ep.host, port: ep.port, udid: nil),
                timeout: AppConstants.Timeouts.rsdInfo,
                step: "嘗試 dvt clear"
            )
            return .dvt
        } catch {
            appendLog("dvt simulate-location 不可用：\(error.localizedDescription)")
        }
        _ = try await runWithTimeoutLogged(
            cmd + SimulateLocationMode.legacy.clearArgs(host: ep.host, port: ep.port, udid: nil),
            timeout: AppConstants.Timeouts.rsdInfo,
            step: "嘗試 legacy clear"
        )
        return .legacy
    }

    private var effectiveTunnelUDID: String? {
        let trimmed = tunnelUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var effectiveTunnelConnectionType: TunnelConnectionType {
        activeTunnelConnectionType ?? (isWirelessMode ? .wifi : .usb)
    }

    private func shouldFallbackToUSBTunnel(using cmd: [String], errorMessage: String) async throws -> Bool {
        guard effectiveTunnelConnectionType == .wifi else { return false }
        let lower = errorMessage.lowercased()
        guard lower.contains("operation not supported by device")
            || lower.contains("no route to host")
            || lower.contains("network is unreachable") else {
            return false
        }
        let devices = try await listConnectedDevices(using: cmd)
        return !devices.isEmpty
    }

    private func shouldFallbackToAnyDevice(for errorMessage: String) -> Bool {
        guard effectiveTunnelUDID != nil else { return false }
        let lower = errorMessage.lowercased()
        return lower.contains("device is not connected")
            || lower.contains("no device connected")
            || lower.contains("usbmux")
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
        
        if !newDevices.isEmpty {
            appendLog("即插即連：偵測到 iOS 裝置已接入，自動啟動連線流程...")
            Task {
                await connectDeviceInternal(autoTriggered: false, force: true)
            }
        }
    }

    private func listConnectedDevices(using cmd: [String]) async throws -> [USBMuxDevice] {
        return self.usbmuxMonitor.devices
    }

    private func matchesDevice(_ device: USBMuxDevice, requestedUDID: String) -> Bool {
        device.identifier == requestedUDID || device.uniqueDeviceID == requestedUDID
    }

    private func deviceDebugLabel(for device: USBMuxDevice) -> String {
        let name = device.deviceName ?? device.productType ?? device.deviceClass ?? "Apple Device"
        let transport = device.connectionType?.uppercased() ?? "UNKNOWN"
        let identifier = device.identifier ?? device.uniqueDeviceID ?? "no-id"
        return "\(name) [\(transport)] \(identifier)"
    }

    private func resolveConnectedDeviceLabel(using cmd: [String], preferredUDID: String?) async throws -> String {
        let devices = try await listConnectedDevices(using: cmd)
        guard !devices.isEmpty else {
            return "Apple Device"
        }

        let preferred = preferredUDID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked =
            devices.first(where: {
                guard let preferred else { return false }
                return $0.identifier == preferred || $0.uniqueDeviceID == preferred
            }) ??
            devices.first(where: { ($0.connectionType ?? "").uppercased() == "USB" }) ??
            devices.first

        guard let picked else { return "Apple Device" }
        let type = picked.productType ?? picked.deviceClass ?? "Apple Device"
        if let name = picked.deviceName, !name.isEmpty {
            return "\(name) \(type)"
        }
        return type
    }

    private func connectedDeviceLabel(using cmd: [String]) async -> String {
        if effectiveTunnelConnectionType == .wifi {
            if let requested = effectiveTunnelUDID {
                return "Apple Device (Wi‑Fi: \(requested))"
            }
            return "Apple Device (Wi‑Fi)"
        }
        return (try? await resolveConnectedDeviceLabel(using: cmd, preferredUDID: effectiveTunnelUDID)) ?? "Apple Device"
    }

    private func startTunnelWithAdminPrompt(using cmd: [String], udid: String?) async throws {
        var failures: [String] = []
        let candidates: [String?] = udid == nil ? [nil] : [udid, nil]

        for candidateUDID in candidates {
            if udid != nil && candidateUDID == nil {
                appendLog("改用目前已連線裝置重試管理員 tunnel")
            }
            var shouldMoveToNextCandidate = false
            for transport in TunnelTransport.allCases {
                do {
                    try await startTunnelWithAdminPrompt(using: cmd, udid: candidateUDID, transport: transport)
                    return
                } catch {
                    let failure = "\(transport.rawValue): \(error.localizedDescription)"
                    failures.append(failure)
                    appendLog("管理員 tunnel 失敗（\(failure)）")
                    stopPrivilegedTunnelProcessIfNeeded()
                    if candidateUDID != nil && shouldFallbackToAnyDevice(for: error.localizedDescription) {
                        shouldMoveToNextCandidate = true
                        break
                    }
                }
            }
            if shouldMoveToNextCandidate {
                continue
            }
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "已要求管理員權限，但所有 tunnel 協定都失敗。\n" + failures.joined(separator: "\n")
        ])
    }

    private func startTunnelWithAdminPrompt(using cmd: [String], udid: String?, transport: TunnelTransport) async throws {
        setStage("請求系統授權")
        let full = cmd + startTunnelArguments(transport: transport, udid: udid, isPrivileged: true)
        let cmdLine = full.map { shellEscape($0) }.joined(separator: " ")

        let shellCmd =
            "LOG=\(shellEscape(privilegedTunnelLog)); " +
            "PIDFILE=\(shellEscape(privilegedTunnelPid)); " +
            ": > \"$LOG\"; " +
            "\(cmdLine) >> \"$LOG\" 2>&1 & " +
            "echo $! > \"$PIDFILE\""

        if await runWithNonInteractiveSudo(shellCmd) {
            appendLog("以 sudo -n 啟動管理員 tunnel")
        } else {
            let apple = "do shell script " + "\"" + shellEscapeForAppleScript(shellCmd) + "\" with administrator privileges"
            _ = try await runProcessAsync(["/usr/bin/osascript", "-e", apple])
            appendLog("以系統授權視窗啟動管理員 tunnel (\(transport.rawValue))")
        }
        appendLog("管理員 tunnel 已啟動，等待 RSD 位址 (\(transport.rawValue))")

        let deadline = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: privilegedTunnelLog, encoding: .utf8) {
                if let pair = TunnelOutputParser.endpoint(in: text) {
                    rsdEndpoint = Endpoint(host: pair.host, port: pair.port)
                    let ep = rsdEndpoint!
                    appendLog("管理員 tunnel RSD：\(ep.host):\(ep.port)")
                    return
                }
                if let failure = TunnelOutputParser.immediateFailure(in: text) {
                    throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: failure
                    ])
                }
            }
            try await Task.sleep(nanoseconds: UInt64(AppConstants.Timeouts.pollInterval * 1_000_000_000))
        }

        let logText = (try? String(contentsOfFile: privilegedTunnelLog, encoding: .utf8)) ?? ""
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "已要求管理員權限，但仍未拿到 RSD 位址。\n\(logText)"
        ])
    }

    private func startTunnelArguments(transport: TunnelTransport, udid: String?, isPrivileged: Bool = false) -> [String] {
        var args = [
            "remote", "start-tunnel",
            "--connection-type", "USB",
            "--script-mode",
            "-p", transport.rawValue
        ]
        if let udid = udid {
            args += ["--udid", udid]
        }
        
        if isPrivileged {
            args += ["--pairing-records", "/var/db/lockdown"]
        }
        
        return args
    }

    private func shellEscape(_ s: String) -> String {
        if s.isEmpty { return "''" }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func shellEscapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func stopPrivilegedTunnelProcessIfNeeded() {
        if let pidStr = try? String(contentsOfFile: privilegedTunnelPid, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !pidStr.isEmpty {
            let cmd = "if [ -f \(shellEscape(privilegedTunnelPid)) ]; then kill \(pidStr) >/dev/null 2>&1 || true; rm -f \(shellEscape(privilegedTunnelPid)); fi"
            Task {
                if await runWithNonInteractiveSudo(cmd) {
                    // Success
                } else {
                    let apple = "do shell script " + "\"" + shellEscapeForAppleScript(cmd) + "\" with administrator privileges"
                    _ = try? await runProcessAsync(["/usr/bin/osascript", "-e", apple])
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
        if isLegacyMode { return }
        Task {
            guard let ep = self.rsdEndpoint else { return }
            guard self.simulateLocationMode == .dvt else { return }
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
        do {
            let cmd = try resolveCLI()
            let mode = self.simulateLocationMode ?? .legacy
            self.dvtStream.clear()
            
            let args: [String]
            if self.isLegacyMode {
                args = mode.clearArgs(host: nil, port: nil, udid: self.connectedUDID)
            } else {
                guard let ep = self.rsdEndpoint else { return }
                args = mode.clearArgs(host: ep.host, port: ep.port, udid: nil)
            }
            
            _ = try await self.runWithTimeoutLogged(
                cmd + args,
                timeout: AppConstants.Timeouts.rsdInfo,
                step: "清除模擬定位"
            )
            print("Sweep: cleared location")
        } catch {
            print("Sweep: failed to clear location: \(error.localizedDescription)")
            self.appendLog("清除模擬定位失敗：\(error.localizedDescription)")
            throw error
        }
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

            guard self.rsdEndpoint != nil || self.isLegacyMode else {
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

    func resolveCLI() throws -> [String] {
        if let path = cachedCLIPath { return [path] }
        let path = try resolveCLIPath()
        cachedCLIPath = path
        return [path]
    }

    private func resolveCLIPath() throws -> String {
        if let resourcesURL = Bundle.main.resourceURL {
            let dirPath = resourcesURL.appendingPathComponent("pymobiledevice3", isDirectory: true)
            let binaryPath = dirPath.appendingPathComponent("pymobiledevice3", isDirectory: false).path
            if FileManager.default.isExecutableFile(atPath: binaryPath) {
                return binaryPath
            }
            
            let bundledPath = resourcesURL.appendingPathComponent("pymobiledevice3").path
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }
        
        let systemPaths = ["/usr/local/bin/pymobiledevice3", "/usr/bin/pymobiledevice3", "/opt/homebrew/bin/pymobiledevice3"]
        for path in systemPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "找不到 pymobiledevice3 CLI。請確認 App 完整性或安裝 Python 套件。"
        ])
    }

    private func startTunnelAndResolveEndpoint(using cmd: [String], udid: String?) async throws {
        var failures: [String] = []
        for transport in TunnelTransport.allCases {
            do {
                try await startTunnelAndResolveEndpoint(using: cmd, udid: udid, transport: transport)
                return
            } catch {
                let failure = "\(transport.rawValue): \(error.localizedDescription)"
                failures.append(failure)
                appendLog("tunnel 失敗（\(failure)）")
                stopTunnel()
            }
        }
        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "所有 tunnel 協定都失敗。\n" + failures.joined(separator: "\n")
        ])
    }

    private func startTunnelAndResolveEndpoint(using cmd: [String], udid: String?, transport: TunnelTransport) async throws {
        stopTunnel()
        setStage("等待連線就緒")

        guard !cmd.isEmpty else { return }
        let p = Process()
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["TERM"] = "dumb"
        p.environment = env
        
        p.executableURL = URL(fileURLWithPath: cmd[0])
        p.arguments = Array(cmd.dropFirst()) + startTunnelArguments(transport: transport, udid: udid, isPrivileged: false)

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let capturedBuffer = LockedDataBuffer()
        
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { capturedBuffer.append(data) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { capturedBuffer.append(data) }
        }

        try p.run()

        p.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            Task { @MainActor in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if self.rsdEndpoint != nil && !self.userInitiatedDisconnect {
                    self.handleUnexpectedConnectionLoss(reason: "tunnel 行程已結束（code: \(proc.terminationStatus)）")
                }
            }
        }

        tunnelProcess = p
        tunnelOutPipe = out
        tunnelErrPipe = err

        let deadline = Date().addingTimeInterval(AppConstants.Timeouts.tunnelReady)
        appendLog("等待 tunnel 輸出 RSD 位址 (\(transport.rawValue))")

        while Date() < deadline {
            let currentText = String(data: capturedBuffer.snapshot(), encoding: .utf8) ?? ""
            if let pair = TunnelOutputParser.endpoint(in: currentText) {
                let ep = Endpoint(host: pair.host, port: pair.port)
                rsdEndpoint = ep
                appendLog("抓到 RSD 位址：\(ep.host):\(ep.port)")
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                return
            }

            if let failure = TunnelOutputParser.immediateFailure(in: currentText) {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: failure
                ])
            }

            if !p.isRunning {
                break
            }

            try await Task.sleep(nanoseconds: 150 * 1_000_000)
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        let finalText = String(data: capturedBuffer.snapshot(), encoding: .utf8) ?? ""
        appendLog("tunnel 未返回 RSD 位址 (\(transport.rawValue))")

        throw NSError(domain: "DeviceManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "start-tunnel 逾時或未輸出 RSD 位址。\n\(finalText)"
        ])
    }

    private func stopSendPipelineSynchronously() {
        expectedDvtStreamExit = true
        dvtStream.stop()
        pendingCoordinate = nil
        inFlight = false
    }

    private func stopTunnel() {
        terminateAllProcesses()
    }

    private func startWatchdog() {
        stopWatchdog()
        // Check health every 5 seconds
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.checkConnectionHealth()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func checkConnectionHealth() {
        guard isConnected, !userInitiatedDisconnect else {
            stopWatchdog()
            return
        }
        
        if isLegacyMode {
            // Legacy mode doesn't have a persistent tunnel process to monitor
            return
        }
        
        // Monitor tunnel process
        if let p = tunnelProcess, !p.isRunning {
            handleUnexpectedConnectionLoss(reason: "Tunnel 服務已中斷")
            return
        }
        
        // Monitor DVT location stream if active
        if simulateLocationMode == .dvt && !dvtStream.isRunning {
            handleUnexpectedConnectionLoss(reason: "定位串流服務已中斷")
            return
        }
    }

    private func handleUnexpectedConnectionLoss(reason: String) {
        guard !userInitiatedDisconnect else { return }
        guard rsdEndpoint != nil || connectionState.isConnected else { return }
        appendLog("連線中斷：\(reason)")
        stopTunnel()
        setConnectionState(.failed, deviceName: "連線已中斷", lastError: reason)
        scheduleAutoReconnect(reason: reason)
    }

    @discardableResult
    private func runWithNonInteractiveSudo(_ shellCmd: String) async -> Bool {
        do {
            _ = try await runProcessAsync(["/usr/bin/sudo", "-n", "/bin/sh", "-c", shellCmd])
            return true
        } catch {
            return false
        }
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
        stopSystemMonitoring()
        
        guard let udid = connectedUDID, let cli = cachedCLIPath else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["remote", "diagnostics", "sysmontap", "--udid", udid, "--json"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            if let line = String(data: data, encoding: .utf8) {
                // Buffer lines as sysmontap output can be fragmented
                DispatchQueue.main.async { [weak self] in
                    self?.parseSystemInfoChunk(line)
                }
            }
        }
        
        do {
            try process.run()
            sysMonProcess = process
            print("[DeviceManager] System monitoring started for \(udid)")
        } catch {
            print("[DeviceManager] Failed to start system monitoring: \(error)")
        }
    }
    
    private func stopSystemMonitoring() {
        sysMonProcess?.terminate()
        sysMonProcess = nil
        systemInfo = IOSSystemInfo()
    }
    
    private func parseSystemInfoChunk(_ chunk: String) {
        Task { @MainActor in
            var updated = systemInfo
            
            // Sysmontap JSON output is complex. We use regex to find key metrics.
            // CPU: "CPU": 12.5
            if let cpuMatch = chunk.range(of: "\"CPU\"\\s*:\\s*([0-9.]+)", options: .regularExpression) {
                let parts = chunk[cpuMatch].split(separator: ":")
                if parts.count == 2, let val = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    updated.cpuUsage = val
                }
            }
            
            // RAM: "phys_footprint": 123456789
            if let ramMatch = chunk.range(of: "\"phys_footprint\"\\s*:\\s*([0-9.]+)", options: .regularExpression) {
                let parts = chunk[ramMatch].split(separator: ":")
                if parts.count == 2, let val = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    updated.ramUsed = val / (1024 * 1024 * 1024)
                    updated.ramTotal = 8.0 // Approx for modern iPhones
                }
            }
            
            // Battery & Thermal (Optional fallback via diagnostics relay if sysmontap doesn't include it)
            // For now, focus on CPU/RAM from sysmontap
            
            self.systemInfo = updated
        }
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

    private func runWithTimeoutLogged(_ args: [String], timeout: TimeInterval, step: String) async throws -> String {
        appendLog("▶ \(step)")
        appendLog("cmd: \(args.joined(separator: " "))")
        do {
            let out = try await runProcessAsync(args, timeout: timeout)
            let trimmed = summarizeOutput(out)
            if !trimmed.isEmpty {
                appendLog("out: \(trimmed)")
            }
            appendLog("✓ \(step)")
            return out
        } catch {
            appendLog("✗ \(step): \(error.localizedDescription)")
            throw error
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
        let cmd = try resolveCLI()
        let mode = simulateLocationMode ?? .legacy
        
        if isLegacyMode {
            _ = try await runProcessAsync(
                cmd + mode.setArgs(host: nil, port: nil, udid: connectedUDID, latitude: latitude, longitude: longitude),
                timeout: AppConstants.Timeouts.coordinateSend
            )
            return
        }

        guard let ep = rsdEndpoint else {
            throw NSError(domain: "DeviceManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "RSD 未就緒"
            ])
        }

        if simulateLocationMode == .dvt {
            try await startDvtStreamIfNeeded(host: ep.host, port: ep.port)
            try dvtStream.send(latitude: latitude, longitude: longitude)
            return
        }

        _ = try await runProcessAsync(
            cmd + mode.setArgs(host: ep.host, port: ep.port, udid: nil, latitude: latitude, longitude: longitude),
            timeout: AppConstants.Timeouts.coordinateSend
        )
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

    private func runProcessAsync(_ args: [String], timeout: TimeInterval? = nil) async throws -> String {
        guard !args.isEmpty else { return "" }
        let p = Process()
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["TERM"] = "dumb"
        p.environment = env
        
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        p.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutBuffer.append(data) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                
                let stdoutString = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
                let stderrString = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
                
                if proc.terminationStatus != 0 {
                    let details = [stderrString, stdoutString]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty }) ?? "Command failed"
                    continuation.resume(throwing: NSError(domain: "DeviceManager", code: Int(proc.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: details
                    ]))
                } else {
                    continuation.resume(returning: stdoutString)
                }
            }

            do {
                try p.run()
                if let timeout = timeout {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        if p.isRunning {
                            p.terminate()
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
        
        let scriptPath: String
        if let resourcesURL = Bundle.main.resourceURL {
            scriptPath = resourcesURL.appendingPathComponent("repair-environment.sh").path
        } else {
            scriptPath = "./scripts/repair-environment.sh"
        }
        
        let fileManager = FileManager.default
        let resolvedPath: String
        if fileManager.fileExists(atPath: scriptPath) {
            resolvedPath = scriptPath
        } else {
            let fallbackPath = "/Users/yusenhan/Code/flyflyfly/scripts/repair-environment.sh"
            if fileManager.fileExists(atPath: fallbackPath) {
                resolvedPath = fallbackPath
            } else {
                appendRepairLog("[ERROR] 找不到修復腳本：\(scriptPath)")
                flushPendingRepairLogs()
                repairTimer?.cancel()
                repairTimer = nil
                isRepairing = false
                return
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [resolvedPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let line = String(data: data, encoding: .utf8) {
                let lines = line.components(separatedBy: .newlines)
                for l in lines {
                    let trimmed = l.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self?.appendRepairLog(trimmed)
                    }
                }
            }
        }
        
        do {
            try process.run()
            
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            fileHandle.readabilityHandler = nil
            if let lastData = try? fileHandle.readToEnd(), !lastData.isEmpty {
                if let line = String(data: lastData, encoding: .utf8) {
                    let lines = line.components(separatedBy: .newlines)
                    for l in lines {
                        let trimmed = l.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.appendRepairLog(trimmed)
                        }
                    }
                }
            }
            
            let status = process.terminationStatus
            if status == 0 {
                appendRepairLog("[SUCCESS] 修復已順利完成！")
            } else {
                appendRepairLog("[ERROR] 修復腳本執行出錯，結束代碼：\(status)")
            }
        } catch {
            appendRepairLog("[ERROR] 無法執行修復腳本：\(error.localizedDescription)")
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