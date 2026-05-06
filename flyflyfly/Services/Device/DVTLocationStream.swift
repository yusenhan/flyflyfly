import Foundation

final class DVTLocationStream: DVTStreaming, @unchecked Sendable {
    private let engine = FastMotionEngineWrapper()
    private var currentHost: String?
    private var currentPort: String?
    private let stateLock = NSLock()
    private var isReady = false

    var isRunning: Bool {
        engine.isNativeTunnelConnected()
    }

    deinit {
        stop()
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

        guard let portInt = Int32(port) else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效的連接埠"])
        }

        let success = engine.connect(toHost: host, port: portInt)
        
        if success {
            currentHost = host
            currentPort = port
            setReady(true)
            onOutput("CONNECTED\n")
            onOutput("READY\n")
        } else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "原生隧道連接失敗"])
        }
    }

    func send(latitude: Double, longitude: Double) throws {
        guard isRunning else {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "隧道未連線"])
        }
        
        let success = engine.sendNativeCoordinateLat(latitude, lon: longitude)
        if !success {
            throw NSError(domain: "DVTLocationStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "坐標發送失敗"])
        }
    }

    func clear() {
        // Native tunnel simplified: clear not explicitly needed for location override
    }

    func stop() {
        engine.disconnectNativeTunnel()
        setReady(false)
        currentHost = nil
        currentPort = nil
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
