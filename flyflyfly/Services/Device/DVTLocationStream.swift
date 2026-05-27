import Foundation

final class DVTLocationStream: DVTStreaming, @unchecked Sendable {
    /// 日誌回調，供 DeviceManager 收集合併日誌
    var onLog: (@Sendable (String) -> Void)?
    
    private var _onSendLegacy: (@MainActor @Sendable (Double, Double) -> Void)?
    var onSendLegacy: (@MainActor @Sendable (Double, Double) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onSendLegacy
        }
        set {
            stateLock.lock()
            _onSendLegacy = newValue
            stateLock.unlock()
        }
    }

    private var dtxClient: DTXClient?
    private var currentHost: String?
    private var currentPort: String?
    private let stateLock = NSLock()
    private var isReady = false

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (dtxClient != nil || _onSendLegacy != nil) && isReady
    }

    deinit {
        stop()
    }

    /// 注入當前設備作用中的 DTXClient 連線實體
    func setClient(_ client: DTXClient?) {
        stateLock.lock()
        self.dtxClient = client
        stateLock.unlock()
    }

    func start(
        host: String,
        port: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        stateLock.lock()
        let running = (dtxClient != nil || _onSendLegacy != nil) && isReady
        let sameEndpoint = currentHost == host && currentPort == port
        stateLock.unlock()

        if running, sameEndpoint {
            return
        }

        stop()

        stateLock.lock()
        let clientExists = dtxClient != nil
        let legacyExists = _onSendLegacy != nil
        let ready = isReady
        stateLock.unlock()

        onLog?("Debug: DVTLocationStream.start - dtxClient存在: \(clientExists), onSendLegacy存在: \(legacyExists), isReady: \(ready)")

        guard clientExists || legacyExists else {
            throw NSError(
                domain: "DVTLocationStream",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "原生 DTX 客戶端未建立 (dtxClient=\(clientExists), legacy=\(legacyExists))"]
            )
        }

        stateLock.lock()
        currentHost = host
        currentPort = port
        isReady = true
        stateLock.unlock()

        onOutput("CONNECTED\n")
        onOutput("READY\n")
    }

    func send(latitude: Double, longitude: Double) throws {
        stateLock.lock()
        let legacy = _onSendLegacy
        let client = dtxClient
        stateLock.unlock()

        onLog?("Debug: DVTLocationStream.send - legacy存在: \(legacy != nil), client存在: \(client != nil)")

        if let sendLegacy = legacy {
            Task { @MainActor in
                sendLegacy(latitude, longitude)
            }
            return
        }

        guard let activeClient = client else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "隧道未連線"])
        }

        // 透過 Task 異步投遞位置模擬，防止 UI/主執行緒卡頓，提供流暢高頻的軌跡注入
        Task {
            do {
                try await activeClient.simulateLocation(latitude: latitude, longitude: longitude)
            } catch {
                print("[DVTLocationStream] 原生位置模擬注入失敗: \(error.localizedDescription)")
                onLog?("⚠️ 原生位置模擬注入失敗: \(error.localizedDescription)")
            }
        }
    }

    func clear() {
        stateLock.lock()
        let legacyExists = _onSendLegacy != nil
        let client = dtxClient
        stateLock.unlock()

        if legacyExists {
            // Legacy 模式下清除模擬只需發送一次性的 stop 即可
            return
        }
        Task {
            try? await client?.stopLocationSimulation()
        }
    }

    func stop() {
        stateLock.lock()
        let wasReady = isReady
        isReady = false
        currentHost = nil
        currentPort = nil
        let client = dtxClient
        stateLock.unlock()

        if wasReady {
            Task {
                try? await client?.stopLocationSimulation()
            }
        }
    }
}

