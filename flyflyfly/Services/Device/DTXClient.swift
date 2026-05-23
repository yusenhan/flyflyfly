import Foundation
import Network
import Combine

/// iOS 系統效能數據 delegate
@MainActor
public protocol DTXClientDelegate: AnyObject, Sendable {
    func dtxClient(_ client: DTXClient, didReceiveCPU cpu: Double, ramUsedGB ram: Double)
    func dtxClient(_ client: DTXClient, didDisconnectWithError error: Error?)
    func dtxClient(_ client: DTXClient, didLogMessage message: String)
}

public class DTXClient: @unchecked Sendable {
    public weak var delegate: DTXClientDelegate?
    
    private func log(_ msg: String) {
        print("[DTXClient] \(msg)")
        let currentDelegate = self.delegate
        Task { @MainActor in
            currentDelegate?.dtxClient(self, didLogMessage: msg)
        }
    }
    
    private var nwConnection: NWConnection?
    private var socketFd: Int32 = -1
    
    private let readQueue = DispatchQueue(label: "flyflyfly.dtx.read", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "flyflyfly.dtx.write", qos: .userInitiated)
    private var isRunning = false
    private var nextIdentifier: UInt32 = 1
    private var isLegacy = false
    private var sslReader: CFReadStream?
    private var sslWriter: CFWriteStream?
    private var identity: SecIdentity?
    
    private var currentBuffer = Data()
    
    public init() {}
    
    /// 以 iOS 17+ (RSD IPv6 TLS) 模式啟動
    public func startRsd(host: String, rsdPort: Int) async throws {
        self.isLegacy = false
        self.isRunning = true
        
        log("正在以 RSD 模式連接到 \(host):\(rsdPort)")
        
        // 1. 連接 RSD Service 以查詢 com.apple.instruments.deviceserver 埠號
        let rsdMetadata = try await connectRsdAndQueryService(host: host, rsdPort: rsdPort)
        guard let servicePort = rsdMetadata["Port"] as? Int else {
            throw NSError(domain: "DTXClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "RSD 查詢未返回 service Port"])
        }
        
        log("RSD 查詢成功，com.apple.instruments.deviceserver 位於 Port \(servicePort)")
        
        // 2. 連接真正的 DTX 服務 Port
        try await connectToServicePort(host: host, port: servicePort)
        
        // 3. 背景啟動 Read Loop
        startReadLoop()
        
        // 4. 發起 DTX 通訊流程
        try await runDTXProtocolFlow()
    }
    
    /// 以 iOS 16- (USBMux Direct Socket) 模式啟動
    public func startLegacy(socketFd: Int32, identity: SecIdentity? = nil) async throws {
        self.isLegacy = true
        self.socketFd = socketFd
        self.isRunning = true
        self.identity = identity
        
        log("正在以 Legacy (Socket FD: \(socketFd)) 模式啟動")
        
        if let ident = identity {
            log("正在為 Legacy 定位 Socket 建立 SSL/TLS 連接 (mTLS)...")
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketFd, &readStream, &writeStream)
            
            if let rUnmanaged = readStream, let wUnmanaged = writeStream {
                let r = rUnmanaged.takeRetainedValue()
                let w = wUnmanaged.takeRetainedValue()
                
                let sslSettings: [String: Any] = [
                    kCFStreamSSLIsServer as String: false,
                    kCFStreamSSLCertificates as String: [ident] as CFArray,
                    kCFStreamSSLValidatesCertificateChain as String: false
                ]
                
                CFReadStreamSetProperty(r, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslSettings as CFTypeRef)
                CFWriteStreamSetProperty(w, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslSettings as CFTypeRef)
                
                // 在各自專屬的執行緒隊列中非同步並行開啟 Stream，保證 CFStream 執行緒安全
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let group = DispatchGroup()
                    
                    group.enter()
                    readQueue.async {
                        CFReadStreamOpen(r)
                        group.leave()
                    }
                    
                    group.enter()
                    writeQueue.async {
                        CFWriteStreamOpen(w)
                        group.leave()
                    }
                    
                    group.notify(queue: .global()) {
                        continuation.resume()
                    }
                }
                
                var timeoutCount = 0
                while CFReadStreamGetStatus(r) != .open || CFWriteStreamGetStatus(w) != .open {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    timeoutCount += 1
                    if timeoutCount > 60 { break }
                }
                
                if CFReadStreamGetStatus(r) == .open && CFWriteStreamGetStatus(w) == .open {
                    self.sslReader = r
                    self.sslWriter = w
                    log("SSL/TLS 連線建立成功！已進入安全加密傳輸模式。")
                } else {
                    log("警告：無法開啟 SSL/TLS 加密流，將退回明文連線。")
                    CFReadStreamClose(r)
                    CFWriteStreamClose(w)
                }
            }
        } else {
            log("檢測到 Legacy 模式未提供 SSL 憑證，將以原始 Socket 明文通訊。")
        }
        
        if !isLegacy {
            startReadLoop()
            
            log("開始執行 DTX 初始協議握手流程...")
            try await runDTXProtocolFlow()
            log("DTX 初始協議握手完成。")
            
            startHeartbeat()
        } else {
            log("Legacy 模式：獨立定位服務已安全開啟，直接就緒。")
        }
    }
    
    private func startHeartbeat() {
        Task { [weak self] in
            while let self = self, self.isRunning {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 秒
                guard self.isRunning else { break }
                log("發送心跳 Ping 以維持連線活性...")
                let pingMsg = try? DTXMessage.makeMethodCall(
                    identifier: getNextIdentifier(),
                    channelCode: 0,
                    selector: "noop:",
                    arguments: [],
                    expectsReply: false
                )
                if let msg = pingMsg {
                    _ = try? await self.sendDTXMessage(msg)
                }
            }
        }
    }

    public func stop() {
        stopInternal(error: nil)
    }

    private func stopInternal(error: Error?) {
        guard isRunning else { return }
        isRunning = false
        log("正在停止連線服務... \(error?.localizedDescription ?? "正常停止")")
        
        if let nw = nwConnection {
            nw.cancel()
            nwConnection = nil
        }
        
        if let r = sslReader {
            CFReadStreamClose(r)
            sslReader = nil
        }
        if let w = sslWriter {
            CFWriteStreamClose(w)
            sslWriter = nil
        }
        
        if socketFd >= 0 {
            Darwin.shutdown(socketFd, SHUT_RDWR)
            close(socketFd)
            socketFd = -1
        }
        
        let currentDelegate = self.delegate
        Task { @MainActor in
            currentDelegate?.dtxClient(self, didDisconnectWithError: error)
        }
    }
    
    private func connectRsdAndQueryService(host: String, rsdPort: Int) async throws -> [String: Any] {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (_, _, verifyComplete) in
            verifyComplete(true)
        }, DispatchQueue.global())
        
        let parameters = NWParameters(tls: options)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(rsdPort)), using: parameters)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let err): continuation.resume(throwing: err)
                case .cancelled: continuation.resume(throwing: NSError(domain: "DTXClient", code: -11, userInfo: [NSLocalizedDescriptionKey: "RSD 連線被取消"]))
                default: break
                }
            }
            connection.start(queue: readQueue)
        }
        
        defer { connection.cancel() }
        
        let request: [String: Any] = ["Request": "StartService", "Service": "com.apple.instruments.deviceserver"]
        let reqData = try PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0)
        var sendData = Data()
        sendData.appendUInt32Big(UInt32(reqData.count))
        sendData.append(reqData)
        
        try await sendNwData(connection, data: sendData)
        
        let lenData = try await receiveNwData(connection, length: 4)
        let responseLength = lenData.withUnsafeBytes { buffer in
            CFSwapInt32BigToHost(buffer.load(as: UInt32.self))
        }
        
        guard responseLength > 0 && responseLength < 1_000_000 else {
            throw NSError(domain: "DTXClient", code: -12, userInfo: [NSLocalizedDescriptionKey: "無效的 RSD 回覆長度: \(responseLength)"])
        }
        
        let plistData = try await receiveNwData(connection, length: Int(responseLength))
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "DTXClient", code: -13, userInfo: [NSLocalizedDescriptionKey: "無法解析 RSD 回覆 plist"])
        }
        
        return plist
    }
    
    private func connectToServicePort(host: String, port: Int) async throws {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (_, _, verifyComplete) in
            verifyComplete(true)
        }, DispatchQueue.global())
        
        let parameters = NWParameters(tls: options)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: parameters)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let err): continuation.resume(throwing: err)
                case .cancelled: continuation.resume(throwing: NSError(domain: "DTXClient", code: -14, userInfo: [NSLocalizedDescriptionKey: "Service 連線被取消"]))
                default: break
                }
            }
            connection.start(queue: readQueue)
        }
        
        self.nwConnection = connection
    }
    
    private func sendNwData(_ nw: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nw.send(content: data, completion: .contentProcessed { error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
    
    private func receiveNwData(_ nw: NWConnection, length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            nw.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let data = data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: NSError(domain: "DTXClient", code: -15, userInfo: [NSLocalizedDescriptionKey: "NWConnection 讀取無數據"])) }
            }
        }
    }
    
    private func sendDTXMessage(_ msg: DTXMessage) async throws {
        let payload = msg.serialize()
        log("準備發送訊息: ID=\(msg.identifier), Channel=\(msg.channelCode), 長度=\(payload.count)")
        
        if let nw = nwConnection {
            try await sendNwData(nw, data: payload)
        } else if let w = sslWriter {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeQueue.async {
                    let bytesWritten = payload.withUnsafeBytes { buffer in
                        CFWriteStreamWrite(w, buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), payload.count)
                    }
                    if bytesWritten != payload.count {
                        continuation.resume(throwing: NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy SSL socket 寫入失敗"]))
                    } else {
                        continuation.resume()
                    }
                }
            }
            log("SSL 寫入成功: \(payload.count) bytes")
        } else if socketFd >= 0 {
            let currentSocketFd = self.socketFd
            try await Task.detached(priority: .userInitiated) { [currentSocketFd, payload] in
                let bytesWritten = payload.withUnsafeBytes { buffer in
                    write(currentSocketFd, buffer.baseAddress, payload.count)
                }
                if bytesWritten != payload.count {
                    throw NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy socket 寫入失敗"])
                }
            }.value
            log("Socket 寫入成功: \(payload.count) bytes")
        } else {
            throw NSError(domain: "DTXClient", code: -17, userInfo: [NSLocalizedDescriptionKey: "無有效連線實體"])
        }
    }
    
    private func sendRawData(_ payload: Data) async throws {
        log("準備發送原始數據，長度=\(payload.count)")
        if let nw = nwConnection {
            try await sendNwData(nw, data: payload)
        } else if let w = sslWriter {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeQueue.async {
                    let bytesWritten = payload.withUnsafeBytes { buffer in
                        CFWriteStreamWrite(w, buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), payload.count)
                    }
                    if bytesWritten != payload.count {
                        continuation.resume(throwing: NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy SSL socket 寫入失敗"]))
                    } else {
                        continuation.resume()
                    }
                }
            }
            log("SSL 寫入原始數據成功: \(payload.count) bytes")
        } else if socketFd >= 0 {
            let currentSocketFd = self.socketFd
            try await Task.detached(priority: .userInitiated) { [currentSocketFd, payload] in
                let bytesWritten = payload.withUnsafeBytes { buffer in
                    write(currentSocketFd, buffer.baseAddress, payload.count)
                }
                if bytesWritten != payload.count {
                    throw NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy socket 寫入失敗"])
                }
            }.value
            log("Socket 寫入原始數據成功: \(payload.count) bytes")
        } else {
            throw NSError(domain: "DTXClient", code: -17, userInfo: [NSLocalizedDescriptionKey: "無有效連線實體"])
        }
    }
    
    private func readNetworkBytes(length: Int) async throws -> Data {
        if let nw = nwConnection {
            return try await receiveNwData(nw, length: length)
        } else if let r = sslReader {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                readQueue.async {
                    var buffer = [UInt8](repeating: 0, count: length)
                    var totalBytes = 0
                    var errorToThrow: Error? = nil
                    while totalBytes < length {
                        let readChunk = CFReadStreamRead(r, &buffer[totalBytes], length - totalBytes)
                        if readChunk < 0 {
                            let streamError = CFReadStreamGetError(r)
                            errorToThrow = NSError(domain: "DTXClient", code: Int(streamError.error), userInfo: [
                                NSLocalizedDescriptionKey: "Legacy SSL socket 讀取失敗 (代碼: \(streamError.error), domain: \(streamError.domain))"
                            ])
                            break
                        } else if readChunk == 0 {
                            errorToThrow = NSError(domain: "DTXClient", code: -18, userInfo: [NSLocalizedDescriptionKey: "Legacy SSL socket 斷開 (EOF)"])
                            break
                        }
                        totalBytes += readChunk
                    }
                    if let err = errorToThrow {
                        continuation.resume(throwing: err)
                    } else {
                        continuation.resume(returning: Data(buffer))
                    }
                }
            }
        } else if socketFd >= 0 {
            let currentSocketFd = self.socketFd
            return try await Task.detached(priority: .userInitiated) { [currentSocketFd] in
                var buffer = [UInt8](repeating: 0, count: length)
                var totalBytes = 0
                while totalBytes < length {
                    let readChunk = read(currentSocketFd, &buffer[totalBytes], length - totalBytes)
                    if readChunk < 0 {
                        let err = errno
                        throw NSError(domain: "DTXClient", code: Int(err), userInfo: [
                            NSLocalizedDescriptionKey: "Legacy socket 讀取失敗 (errno: \(err))"
                        ])
                    } else if readChunk == 0 {
                        throw NSError(domain: "DTXClient", code: -18, userInfo: [NSLocalizedDescriptionKey: "Legacy socket 斷開 (EOF)"])
                    }
                    totalBytes += readChunk
                }
                return Data(buffer)
            }.value
        } else {
            throw NSError(domain: "DTXClient", code: -17, userInfo: [NSLocalizedDescriptionKey: "無有效連線實體"])
        }
    }
    
    private func startReadLoop() {
        Task { [weak self] in
            guard let self = self else { return }
            log("啟動背景讀取迴圈...")
            if self.socketFd >= 0 {
                var tv = timeval(tv_sec: 0, tv_usec: 0)
                setsockopt(self.socketFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            }
            while self.isRunning {
                do {
                    let headerData = try await self.readNetworkBytes(length: 32)
                    let dataSizeVal = headerData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
                    let bodySize = Int(UInt32(littleEndian: dataSizeVal))
                    let bodyData = try await self.readNetworkBytes(length: bodySize)
                    var fullPacket = Data(); fullPacket.append(headerData); fullPacket.append(bodyData)
                    if let (msg, _) = try DTXMessage.parse(from: fullPacket) {
                        log("收到封包: ID=\(msg.identifier), Channel=\(msg.channelCode), Body=\(bodySize) bytes")
                        self.handleIncomingMessage(msg)
                    }
                } catch {
                    if self.isRunning {
                        let nsError = error as NSError
                        if nsError.code == 35 || error.localizedDescription.contains("timeout") || error.localizedDescription.contains("Operation timed out") {
                            continue
                        }
                        log("讀取迴圈中斷: \(error.localizedDescription) (Code: \(nsError.code))")
                        self.stopInternal(error: error)
                    }
                    break
                }
            }
        }
    }
    
    private func handleIncomingMessage(_ msg: DTXMessage) {
        if msg.channelCode == 1 && (msg.type == .dispatch || msg.type == .object) {
            do {
                let args = try msg.parseArguments()
                if let dict = args.first as? [String: Any] {
                    parseAndNotifyPerformanceData(dict)
                }
            } catch {
                log("無法解析推送的資料: \(error.localizedDescription)")
            }
        }
    }
    
    private func parseAndNotifyPerformanceData(_ dict: [String: Any]) {
        var cpuVal: Double = 0
        var ramBytes: Double = 0
        if let cpu = dict["CPU"] as? Double { cpuVal = cpu }
        else if let cpu = dict["CPU"] as? NSNumber { cpuVal = cpu.doubleValue }
        if let ram = dict["phys_footprint"] as? Double { ramBytes = ram }
        else if let ram = dict["phys_footprint"] as? NSNumber { ramBytes = ram.doubleValue }
        if let sysInfo = dict["System"] as? [String: Any] {
            if let cpu = sysInfo["CPU"] as? Double { cpuVal = cpu }
            else if let cpu = sysInfo["CPU"] as? NSNumber { cpuVal = cpu.doubleValue }
            if let ram = sysInfo["phys_footprint"] as? Double { ramBytes = ram }
            else if let ram = sysInfo["phys_footprint"] as? NSNumber { ramBytes = ram.doubleValue }
        }
        let ramGB = ramBytes / (1024.0 * 1024.0 * 1024.0)
        
        let finalCpu = cpuVal
        let finalRamGB = ramGB
        Task { @MainActor in
            delegate?.dtxClient(self, didReceiveCPU: finalCpu, ramUsedGB: finalRamGB)
        }
    }
    
    private func runDTXProtocolFlow() async throws {
        if isLegacy {
            log("Legacy 模式：獨立定位服務，無須通道註冊握手，直接就緒。")
            return
        }
        
        log("正在發送註冊 Channel 1 請求...")
        let requestChannelMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 0,
            selector: "_requestChannelWithIdentifier:target:",
            arguments: [.int32(1), .string("com.apple.instruments.server.services.sysmontap")],
            expectsReply: true
        )
        try await sendDTXMessage(requestChannelMsg)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        log("正在配置 sysmontap 採樣參數...")
        let config: NSDictionary = [
            "ur": 1000,
            "pr": ["cpuUsage", "physFootprint", "memStatus"] as NSArray,
            "sys": ["cpuUsage", "memStatus"] as NSArray
        ]
        let archivedConfig = try NSKeyedArchiver.archivedData(withRootObject: config, requiringSecureCoding: false)
        let setConfigMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 1,
            selector: "setConfig:",
            arguments: [.buffer(archivedConfig)],
            expectsReply: true
        )
        try await sendDTXMessage(setConfigMsg)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        log("正在發送 start 訊息啟動系統資源監控...")
        let startMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 1,
            selector: "start",
            arguments: [],
            expectsReply: true
        )
        try await sendDTXMessage(startMsg)
        log("原生系統效能監控啟動成功！")
        
        log("正在發送註冊 Channel 2 (LocationSimulation) 請求...")
        let requestLocationChannelMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 0,
            selector: "_requestChannelWithIdentifier:target:",
            arguments: [
                .int32(2),
                .string("com.apple.instruments.server.services.coreservices.LocationSimulation")
            ],
            expectsReply: true
        )
        try await sendDTXMessage(requestLocationChannelMsg)
        try await Task.sleep(nanoseconds: 200_000_000)
        log("原生位置模擬通道註冊成功！")
    }
    
    public func simulateLocation(latitude: Double, longitude: Double) async throws {
        guard isRunning else { throw NSError(domain: "DTXClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "DTXClient 未連線"]) }
        
        if isLegacy {
            // Legacy 模式使用自定義二進位 Plist/String 協定
            let latStr = String(format: "%.6f", latitude)
            let lonStr = String(format: "%.6f", longitude)
            guard let latBytes = latStr.data(using: .utf8),
                  let lonBytes = lonStr.data(using: .utf8) else {
                throw NSError(domain: "DTXClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "無法序列化經緯度字串"])
            }
            
            var sendData = Data()
            sendData.appendUInt32Big(0) // 0 表示設定定位
            sendData.appendUInt32Big(UInt32(latBytes.count))
            sendData.append(latBytes)
            sendData.appendUInt32Big(UInt32(lonBytes.count))
            sendData.append(lonBytes)
            
            try await sendRawData(sendData)
            return
        }
        
        // iOS 17+ RSD 模式
        let latNum = NSNumber(value: latitude)
        let lonNum = NSNumber(value: longitude)
        let latData = try NSKeyedArchiver.archivedData(withRootObject: latNum, requiringSecureCoding: false)
        let lonData = try NSKeyedArchiver.archivedData(withRootObject: lonNum, requiringSecureCoding: false)
        let msg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 2,
            selector: "simulateLocationWithLatitude:longitude:",
            arguments: [.buffer(latData), .buffer(lonData)],
            expectsReply: true
        )
        try await sendDTXMessage(msg)
    }

    public func stopLocationSimulation() async throws {
        guard isRunning else { throw NSError(domain: "DTXClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "DTXClient 未連線"]) }
        
        if isLegacy {
            // Legacy 模式使用自定義二進位 Plist/String 協定
            var sendData = Data()
            sendData.appendUInt32Big(1) // 1 表示停止定位
            try await sendRawData(sendData)
            return
        }
        
        // iOS 17+ RSD 模式
        let msg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 2,
            selector: "stopLocationSimulation",
            arguments: [],
            expectsReply: true
        )
        try await sendDTXMessage(msg)
    }
    
    private func getNextIdentifier() -> UInt32 {
        let ident = nextIdentifier
        nextIdentifier += 1
        return ident
    }
}

extension Data {
    mutating func appendUInt32Big(_ value: UInt32) {
        var val = value.bigEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
}
