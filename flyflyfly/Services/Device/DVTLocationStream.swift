import Foundation

final class DVTLocationStream: DVTStreaming, @unchecked Sendable {
    private var dtxClient: DTXClient?
    private var currentHost: String?
    private var currentPort: String?
    private let stateLock = NSLock()
    private var isReady = false

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return dtxClient != nil && isReady
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
        if isRunning, currentHost == host, currentPort == port {
            return
        }

        stop()

        guard dtxClient != nil else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "原生 DTX 客戶端未建立"])
        }

        currentHost = host
        currentPort = port
        setReady(true)
        onOutput("CONNECTED\n")
        onOutput("READY\n")
    }

    func send(latitude: Double, longitude: Double) throws {
        guard let client = dtxClient else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "隧道未連線"])
        }
        
        // 透過 Task 異步投遞位置模擬，防止 UI/主執行緒卡頓，提供流暢高頻的軌跡注入
        Task {
            do {
                try await client.simulateLocation(latitude: latitude, longitude: longitude)
            } catch {
                print("[DVTLocationStream] 原生位置模擬注入失敗: \(error.localizedDescription)")
            }
        }
    }

    func clear() {
        Task {
            try? await dtxClient?.stopLocationSimulation()
        }
    }

    func stop() {
        let wasReady = readyState()
        setReady(false)
        currentHost = nil
        currentPort = nil
        if wasReady {
            Task {
                try? await dtxClient?.stopLocationSimulation()
            }
        }
    }

    private func setReady(_ ready: Bool) {
        stateLock.lock()
        isReady = ready
        stateLock.unlock()
    }

    private func readyState() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isReady
    }
}
