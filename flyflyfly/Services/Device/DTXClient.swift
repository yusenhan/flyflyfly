import Foundation
import Network
import Combine

/// iOS 系統效能數據 delegate
@MainActor
public protocol DTXClientDelegate: AnyObject {
    func dtxClient(_ client: DTXClient, didReceiveCPU cpu: Double, ramUsedGB ram: Double)
    func dtxClient(_ client: DTXClient, didDisconnectWithError error: Error?)
}

public class DTXClient: @unchecked Sendable {
    public weak var delegate: DTXClientDelegate?
    
    private var nwConnection: NWConnection?
    private var socketFd: Int32 = -1
    
    private let readQueue = DispatchQueue(label: "flyflyfly.dtx.read", qos: .userInitiated)
    private var isRunning = false
    private var nextIdentifier: UInt32 = 1
    private var isLegacy = false
    private var sslReader: CFReadStream?
    private var sslWriter: CFWriteStream?
    
    private var currentBuffer = Data()
    
    public init() {}
    
    /// 以 iOS 17+ (RSD IPv6 TLS) 模式啟動
    public func startRsd(host: String, rsdPort: Int) async throws {
        self.isLegacy = false
        self.isRunning = true
        
        print("[DTXClient] 正在以 RSD 模式連接到 \(host):\(rsdPort)")
        
        // 1. 連接 RSD Service 以查詢 com.apple.instruments.deviceserver 埠號
        let rsdMetadata = try await connectRsdAndQueryService(host: host, rsdPort: rsdPort)
        guard let servicePort = rsdMetadata["Port"] as? Int else {
            throw NSError(domain: "DTXClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "RSD 查詢未返回 service Port"])
        }
        
        print("[DTXClient] RSD 查詢成功，com.apple.instruments.deviceserver 位於 Port \(servicePort)")
        
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
        
        print("[DTXClient] 正在以 Legacy (Socket FD: \(socketFd)) 模式啟動")
        
        if let ident = identity {
            // 升級 Socket 為 SSL/TLS 加密通道 (mTLS 雙向認證)
            print("[DTXClient] 正在為 Legacy 定位 Socket 建立 SSL/TLS 連接 (mTLS)...")
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
                
                CFReadStreamOpen(r)
                CFWriteStreamOpen(w)
                
                // 等待流開啟且 TLS 握手成功 (最多等待 3 秒)
                var timeoutCount = 0
                while CFReadStreamGetStatus(r) != .open || CFWriteStreamGetStatus(w) != .open {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 等待 50 毫秒
                    timeoutCount += 1
                    if timeoutCount > 60 { // 3 秒超時
                        break
                    }
                }
                
                if CFReadStreamGetStatus(r) == .open && CFWriteStreamGetStatus(w) == .open {
                    self.sslReader = r
                    self.sslWriter = w
                    print("[DTXClient] SSL/TLS 連線建立成功！已進入安全加密傳輸模式。")
                } else {
                    print("[DTXClient] 警告：無法開啟 SSL/TLS 加密流，將退回明文連線。")
                    CFReadStreamClose(r)
                    CFWriteStreamClose(w)
                }
            }
        } else {
            print("[DTXClient] 檢測到 Legacy 模式禁用了 SSL 升級，將以原始 Socket 明文通訊。")
        }
        
        // 背景啟動 Read Loop
        startReadLoop()
        
        // 發起 DTX 通訊流程
        try await runDTXProtocolFlow()
    }
    
    public func stop() {
        stopInternal(error: nil)
    }

    private func stopInternal(error: Error?) {
        guard isRunning else { return }
        isRunning = false
        print("[DTXClient] 正在停止連線服務... \(error?.localizedDescription ?? "正常停止")")
        
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
    
    // ==============================================================================
    // 底層連線與 RSD 服務協商
    // ==============================================================================
    
    private func connectRsdAndQueryService(host: String, rsdPort: Int) async throws -> [String: Any] {
        // 配置 TLS 參數，跳過憑證驗證
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (_, _, verifyComplete) in
            verifyComplete(true)
        }, DispatchQueue.global())
        
        let parameters = NWParameters(tls: options)
        
        // 連接 RSD IPv6 Address
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(rsdPort)), using: parameters)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let err):
                    continuation.resume(throwing: err)
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "DTXClient", code: -11, userInfo: [NSLocalizedDescriptionKey: "RSD 連線被取消"]))
                default:
                    break
                }
            }
            connection.start(queue: readQueue)
        }
        
        defer { connection.cancel() }
        
        // 傳送 StartService 請求
        let request: [String: Any] = [
            "Request": "StartService",
            "Service": "com.apple.instruments.deviceserver"
        ]
        
        let reqData = try PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0)
        var sendData = Data()
        // 4-byte big endian length
        sendData.appendUInt32Big(UInt32(reqData.count))
        sendData.append(reqData)
        
        try await sendNwData(connection, data: sendData)
        
        // 讀取回覆長度
        let lenData = try await receiveNwData(connection, length: 4)
        let responseLength = lenData.withUnsafeBytes { buffer in
            CFSwapInt32BigToHost(buffer.load(as: UInt32.self))
        }
        
        guard responseLength > 0 && responseLength < 1_000_000 else {
            throw NSError(domain: "DTXClient", code: -12, userInfo: [NSLocalizedDescriptionKey: "無效的 RSD 回覆長度: \(responseLength)"])
        }
        
        // 讀取回覆 XML Plist
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
                case .ready:
                    continuation.resume()
                case .failed(let err):
                    continuation.resume(throwing: err)
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "DTXClient", code: -14, userInfo: [NSLocalizedDescriptionKey: "Service 連線被取消"]))
                default:
                    break
                }
            }
            connection.start(queue: readQueue)
        }
        
        self.nwConnection = connection
    }
    
    // ==============================================================================
    // Network.framework Raw Helpers
    // ==============================================================================
    
    private func sendNwData(_ nw: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nw.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receiveNwData(_ nw: NWConnection, length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            nw.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "DTXClient", code: -15, userInfo: [NSLocalizedDescriptionKey: "NWConnection 讀取無數據"]))
                }
            }
        }
    }
    
    // ==============================================================================
    // DTX Transport API (讀/寫)
    // ==============================================================================
    
    private func sendDTXMessage(_ msg: DTXMessage) async throws {
        let payload = msg.serialize()
        if let nw = nwConnection {
            try await sendNwData(nw, data: payload)
        } else if let w = sslWriter {
            try await Task.detached(priority: .userInitiated) { [w] in
                let bytesWritten = payload.withUnsafeBytes { buffer in
                    CFWriteStreamWrite(w, buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), payload.count)
                }
                if bytesWritten != payload.count {
                    throw NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy SSL socket 寫入失敗"])
                }
            }.value
        } else if socketFd >= 0 {
            try await Task.detached(priority: .userInitiated) { [socketFd] in
                let bytesWritten = payload.withUnsafeBytes { buffer in
                    write(socketFd, buffer.baseAddress, payload.count)
                }
                if bytesWritten != payload.count {
                    throw NSError(domain: "DTXClient", code: -16, userInfo: [NSLocalizedDescriptionKey: "Legacy socket 寫入失敗"])
                }
            }.value
        } else {
            throw NSError(domain: "DTXClient", code: -17, userInfo: [NSLocalizedDescriptionKey: "無有效連線實體"])
        }
    }
    
    private func readNetworkBytes(length: Int) async throws -> Data {
        if let nw = nwConnection {
            return try await receiveNwData(nw, length: length)
        } else if let r = sslReader {
            return try await Task.detached(priority: .userInitiated) { [r] in
                var buffer = [UInt8](repeating: 0, count: length)
                var totalBytes = 0
                while totalBytes < length {
                    let readChunk = CFReadStreamRead(r, &buffer[totalBytes], length - totalBytes)
                    if readChunk < 0 {
                        let streamError = CFReadStreamGetError(r)
                        throw NSError(domain: "DTXClient", code: Int(streamError.error), userInfo: [
                            NSLocalizedDescriptionKey: "Legacy SSL socket 讀取失敗 (代碼: \(streamError.error), domain: \(streamError.domain))"
                        ])
                    } else if readChunk == 0 {
                        throw NSError(domain: "DTXClient", code: -18, userInfo: [NSLocalizedDescriptionKey: "Legacy SSL socket 斷開 (EOF)"])
                    }
                    totalBytes += readChunk
                }
                return Data(buffer)
            }.value
        } else if socketFd >= 0 {
            return try await Task.detached(priority: .userInitiated) { [socketFd] in
                var buffer = [UInt8](repeating: 0, count: length)
                var totalBytes = 0
                while totalBytes < length {
                    let readChunk = read(socketFd, &buffer[totalBytes], length - totalBytes)
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
    
    // ==============================================================================
    // Read Loop & Packet Parsing
    // ==============================================================================
    
    private func startReadLoop() {
        Task { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                do {
                    // 1. 先讀取 32 bytes DTX Header
                    let headerData = try await self.readNetworkBytes(length: 32)
                    
                    // 2. 獲取 body size
                    let dataSizeVal = headerData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
                    let bodySize = Int(UInt32(littleEndian: dataSizeVal))
                    
                    // 3. 讀取 body 內容
                    let bodyData = try await self.readNetworkBytes(length: bodySize)
                    
                    // 4. 重組完整封包並解析
                    var fullPacket = Data()
                    fullPacket.append(headerData)
                    fullPacket.append(bodyData)
                    
                    if let (msg, _) = try DTXMessage.parse(from: fullPacket) {
                        self.handleIncomingMessage(msg)
                    }
                    
                } catch {
                    if self.isRunning {
                        let errorDescription = error.localizedDescription
                        // 忽略一些常見的、可能在剛建立連線時發生的瞬時錯誤或超時，避免直接斷開
                        if errorDescription.contains("timeout") || errorDescription.contains("Operation timed out") {
                            print("[DTXClient] 讀取超時，重試中...")
                            continue
                        }

                        print("[DTXClient] 讀取迴圈異常中斷: \(errorDescription)")
                        self.stopInternal(error: error)
                    }
                    break
                }
            }
        }
    }
    
    private func handleIncomingMessage(_ msg: DTXMessage) {
        // print("[DTXClient] 收到 DTX 訊息: \(msg)")
        
        // 若 channel 為 1 且為 Dispatch / Object，這通常是 sysmontap 效能指標的推送資料！
        if msg.channelCode == 1 && (msg.type == .dispatch || msg.type == .object) {
            do {
                let args = try msg.parseArguments()
                if let dict = args.first as? [String: Any] {
                    // 解析 CPU / RAM 指標
                    parseAndNotifyPerformanceData(dict)
                }
            } catch {
                print("[DTXClient] 無法解析推送的資料: \(error.localizedDescription)")
            }
        }
    }
    
    private func parseAndNotifyPerformanceData(_ dict: [String: Any]) {
        // sysmontap 推送的 dictionary 結構極為複雜，裡面通常有：
        // "CPU" -> CPU 佔用率 (如 12.5)
        // "phys_footprint" -> 記憶體實體足跡位元組數 (如 123456789)
        // 或者是 dict 裡面有 SystemInfo 等層級
        // 在 Python 中：
        // cpu = dict.get("CPU", 0)
        // ram = dict.get("phys_footprint", 0)
        
        var cpuVal: Double = 0
        var ramBytes: Double = 0
        
        if let cpu = dict["CPU"] as? Double {
            cpuVal = cpu
        } else if let cpu = dict["CPU"] as? NSNumber {
            cpuVal = cpu.doubleValue
        }
        
        if let ram = dict["phys_footprint"] as? Double {
            ramBytes = ram
        } else if let ram = dict["phys_footprint"] as? NSNumber {
            ramBytes = ram.doubleValue
        }
        
        // 如果 dict 包含 "SystemInfo"
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
    
    // ==============================================================================
    // DTX Protocol RPC 流程
    // ==============================================================================
    
    private func runDTXProtocolFlow() async throws {
        if isLegacy {
            print("[DTXClient] Legacy 模式：僅註冊 Channel 2 (LocationSimulation) 核心定位服務")
            let requestLocationChannelMsg = try DTXMessage.makeMethodCall(
                identifier: getNextIdentifier(),
                channelCode: 0,
                selector: "_requestChannelWithIdentifier:target:",
                arguments: [
                    .int32(2), // Channel ID
                    .string("com.apple.instruments.server.services.coreservices.LocationSimulation") // Target Service Name
                ],
                expectsReply: true
            )
            
            try await sendDTXMessage(requestLocationChannelMsg)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            print("[DTXClient] 原生位置模擬通道註冊成功！")
            return
        }
        
        // RSD 模式 (iOS 17+)
        // 1. 發送管道請求：_requestChannelWithIdentifier:target:
        // 我們將 Channel 1 註冊給 sysmontap 服務
        print("[DTXClient] 正在發送註冊 Channel 1 請求...")
        let requestChannelMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 0,
            selector: "_requestChannelWithIdentifier:target:",
            arguments: [
                .int32(1), // Channel ID
                .string("com.apple.instruments.server.services.sysmontap") // Target Service Name
            ],
            expectsReply: true
        )
        
        try await sendDTXMessage(requestChannelMsg)
        
        // 等待一下，讓 Channel 啟動完成
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // 2. 發送 setConfig: 設定監控參數
        print("[DTXClient] 正在配置 sysmontap 採樣參數...")
        // 構造配置 NSDictionary
        let config: NSDictionary = [
            "ur": 1000, // 1000 毫秒 (1秒) 更新頻率
            "pr": ["cpuUsage", "physFootprint", "memStatus"] as NSArray,
            "sys": ["cpuUsage", "memStatus"] as NSArray
        ]
        
        // 用 NSKeyedArchiver 序列化 config 字典
        let archivedConfig: Data
        if #available(macOS 10.13, *) {
            archivedConfig = try NSKeyedArchiver.archivedData(withRootObject: config, requiringSecureCoding: false)
        } else {
            archivedConfig = NSKeyedArchiver.archivedData(withRootObject: config)
        }
        
        let setConfigMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 1, // 發送在 Channel 1
            selector: "setConfig:",
            arguments: [
                .buffer(archivedConfig)
            ],
            expectsReply: true
        )
        
        try await sendDTXMessage(setConfigMsg)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 3. 發送 start 啟動指標數據串流監聽
        print("[DTXClient] 正在發送 start 訊息啟動系統資源監控...")
        let startMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 1, // Channel 1
            selector: "start",
            arguments: [],
            expectsReply: true
        )
        
        try await sendDTXMessage(startMsg)
        print("[DTXClient] 原生系統效能監控啟動成功！")
        
        // 4. 發送管道請求：將 Channel 2 註冊給 LocationSimulation 服務
        print("[DTXClient] 正在發送註冊 Channel 2 (LocationSimulation) 請求...")
        let requestLocationChannelMsg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 0,
            selector: "_requestChannelWithIdentifier:target:",
            arguments: [
                .int32(2), // Channel ID
                .string("com.apple.instruments.server.services.coreservices.LocationSimulation") // Target Service Name
            ],
            expectsReply: true
        )
        
        try await sendDTXMessage(requestLocationChannelMsg)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        print("[DTXClient] 原生位置模擬通道註冊成功！")
    }
    
    /// 原生發送模擬坐標 (Channel 2)
    public func simulateLocation(latitude: Double, longitude: Double) async throws {
        guard isRunning else {
            throw NSError(domain: "DTXClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "DTXClient 未連線"])
        }
        
        // 將 Double 包裝為 NSNumber 物件
        let latNum = NSNumber(value: latitude)
        let lonNum = NSNumber(value: longitude)
        
        // 使用 NSKeyedArchiver 序列化為 NSKeyedArchiver Data (ObjC id)
        let latData: Data
        let lonData: Data
        if #available(macOS 10.13, *) {
            latData = try NSKeyedArchiver.archivedData(withRootObject: latNum, requiringSecureCoding: false)
            lonData = try NSKeyedArchiver.archivedData(withRootObject: lonNum, requiringSecureCoding: false)
        } else {
            latData = NSKeyedArchiver.archivedData(withRootObject: latNum)
            lonData = NSKeyedArchiver.archivedData(withRootObject: lonNum)
        }
        
        let msg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 2, // Channel 2
            selector: "simulateLocationWithLatitude:longitude:",
            arguments: [
                .buffer(latData),
                .buffer(lonData)
            ],
            expectsReply: true
        )
        try await sendDTXMessage(msg)
    }

    /// 原生清除模擬定位 (Channel 2)
    public func stopLocationSimulation() async throws {
        guard isRunning else {
            throw NSError(domain: "DTXClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "DTXClient 未連線"])
        }
        let msg = try DTXMessage.makeMethodCall(
            identifier: getNextIdentifier(),
            channelCode: 2, // Channel 2
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

// ---------------------------------------------------------------------------
// Big Endian 寫入 Helper
// ---------------------------------------------------------------------------
extension Data {
    mutating func appendUInt32Big(_ value: UInt32) {
        var val = value.bigEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
}
