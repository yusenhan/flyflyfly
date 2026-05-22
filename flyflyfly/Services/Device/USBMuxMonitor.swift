import Foundation
import Combine

public struct USBMuxDevice: Codable, Sendable, Identifiable, Equatable {
    public var id: String { identifier ?? uniqueDeviceID ?? "unknown" }
    public let connectionType: String?
    public let deviceClass: String?
    public let deviceName: String?
    public let identifier: String?
    public let uniqueDeviceID: String?
    public let productType: String?
    public let productVersion: String?
    public let deviceID: Int?
    
    public init(connectionType: String?, deviceClass: String?, deviceName: String?, identifier: String?, uniqueDeviceID: String?, productType: String?, productVersion: String?, deviceID: Int?) {
        self.connectionType = connectionType
        self.deviceClass = deviceClass
        self.deviceName = deviceName
        self.identifier = identifier
        self.uniqueDeviceID = uniqueDeviceID
        self.productType = productType
        self.productVersion = productVersion
        self.deviceID = deviceID
    }
}

public class USBMuxMonitor: ObservableObject {
    @Published public private(set) var devices: [USBMuxDevice] = []
    
    private let monitorQueue = DispatchQueue(label: "flyflyfly.usbmux.monitor", qos: .userInitiated)
    private let lock = NSLock()
    private var isRunning = false
    private var listenFd: Int32 = -1
    private var activeDeviceMap: [Int: USBMuxDevice] = [:] // Map DeviceID -> USBMuxDevice
    
    public init() {}
    
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true
        monitorQueue.async { [weak self] in
            self?.runMonitorLoop()
        }
    }
    
    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        isRunning = false
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
    }
    
    private func runMonitorLoop() {
        let socketPath = "/var/run/usbmuxd"
        
        while true {
            lock.lock()
            let shouldRun = isRunning
            lock.unlock()
            guard shouldRun else { break }
            
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            if fd < 0 {
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }
            
            lock.lock()
            self.listenFd = fd
            lock.unlock()
            
            var addr = sockaddr_un()
            addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            
            _ = withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
                let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
                for (i, byte) in pathBytes.enumerated() {
                    if i < 104 {
                        rawPointer[i] = byte
                    }
                }
            }
            
            let addrSize = MemoryLayout<sockaddr_un>.size
            let connectRes = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    connect(fd, sockaddrPointer, socklen_t(addrSize))
                }
            }
            
            if connectRes < 0 {
                close(fd)
                lock.lock()
                self.listenFd = -1
                lock.unlock()
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }
            
            // Send Listen Packet
            let listenPlist: [String: Any] = [
                "ClientVersionString": "flyflyfly-monitor",
                "MessageType": "Listen",
                "ProgName": "flyflyfly"
            ]
            
            guard sendPlist(fd, plist: listenPlist, tag: 1) else {
                close(fd)
                lock.lock()
                self.listenFd = -1
                lock.unlock()
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }
            
            // Read Listen Response (Result)
            guard let result = readResponse(fd, timeoutSeconds: 5) else {
                close(fd)
                lock.lock()
                self.listenFd = -1
                lock.unlock()
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }
            
            if let number = result["Number"] as? Int, number != 0 {
                close(fd)
                lock.lock()
                self.listenFd = -1
                lock.unlock()
                Thread.sleep(forTimeInterval: 2.0)
                continue
            }
            
            // Success. Loop for incoming Attached/Detached events
            while true {
                lock.lock()
                let shouldRun = isRunning
                lock.unlock()
                guard shouldRun else { break }
                
                guard let event = readResponse(fd, timeoutSeconds: 0) else {
                    // Timeout or read failure
                    break
                }
                
                handleUSBMuxEvent(event)
            }
            
            close(fd)
            lock.lock()
            self.listenFd = -1
            let stillRunning = isRunning
            lock.unlock()
            
            if stillRunning {
                // Connection lost, clear state on MainActor and sleep before retry
                Task { @MainActor in
                    self.devices = []
                }
                lock.lock()
                self.activeDeviceMap = [:]
                lock.unlock()
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    
    private func handleUSBMuxEvent(_ event: [String: Any]) {
        guard let msgType = event["MessageType"] as? String else { return }
        
        if msgType == "Attached" {
            guard let deviceID = event["DeviceID"] as? Int,
                  let props = event["Properties"] as? [String: Any] else { return }
            
            let connType = props["ConnectionType"] as? String
            let serial = props["SerialNumber"] as? String ?? props["UDID"] as? String
            
            // Query detailed info asynchronously via lockdownd in a detached task
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                let details = self.fetchLockdownDetails(deviceID: deviceID)
                
                let newDevice = USBMuxDevice(
                    connectionType: connType ?? "USB",
                    deviceClass: details["DeviceClass"],
                    deviceName: details["DeviceName"],
                    identifier: serial,
                    uniqueDeviceID: serial,
                    productType: details["ProductType"],
                    productVersion: details["ProductVersion"],
                    deviceID: deviceID
                )
                
                self.lock.lock()
                self.activeDeviceMap[deviceID] = newDevice
                let list = Array(self.activeDeviceMap.values)
                self.lock.unlock()
                
                Task { @MainActor in
                    self.devices = list
                }
            }
            
        } else if msgType == "Detached" {
            guard let deviceID = event["DeviceID"] as? Int else { return }
            
            self.lock.lock()
            self.activeDeviceMap.removeValue(forKey: deviceID)
            let list = Array(self.activeDeviceMap.values)
            self.lock.unlock()
            
            Task { @MainActor in
                self.devices = list
            }
        }
    }
    
    // ==============================================================================
    // Raw Socket Helper Functions
    // ==============================================================================
    
    private struct UsbmuxHeader {
        var length: UInt32
        var version: UInt32
        var type: UInt32
        var tag: UInt32
    }
    
    private func sendPlist(_ socketFd: Int32, plist: [String: Any], tag: UInt32) -> Bool {
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }
        
        let headerLength = MemoryLayout<UsbmuxHeader>.size
        let totalLength = headerLength + plistData.count
        
        var header = UsbmuxHeader(
            length: UInt32(totalLength),
            version: 1, // Protocol version
            type: 8,    // Plist message type
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
    
    private func readResponse(_ socketFd: Int32, timeoutSeconds: Int) -> [String: Any]? {
        if timeoutSeconds > 0 {
            var tv = timeval()
            tv.tv_sec = timeoutSeconds
            tv.tv_usec = 0
            setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        } else {
            // Remove timeout for continuous listening
            var tv = timeval()
            tv.tv_sec = 0
            tv.tv_usec = 0
            setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        
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
    
    // ==============================================================================
    // Fetch Lockdownd details (Port 62078)
    // ==============================================================================
    
    private func fetchLockdownValue(fd: Int32, key: String) -> String? {
        let request: [String: Any] = [
            "Label": "flyflyfly",
            "Request": "GetValue",
            "Key": key
        ]
        
        guard let reqData = try? PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0) else {
            return nil
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
        guard bytesWritten == sendData.count else { return nil }
        
        var lenBuffer = [UInt8](repeating: 0, count: 4)
        let lenRead = read(fd, &lenBuffer, 4)
        guard lenRead == 4 else { return nil }
        
        let responseLength = lenBuffer.withUnsafeBytes { buffer in
            CFSwapInt32BigToHost(buffer.load(as: UInt32.self))
        }
        guard responseLength > 0 && responseLength < 1_000_000 else { return nil }
        
        var payloadBuffer = [UInt8](repeating: 0, count: Int(responseLength))
        var totalBytesRead = 0
        while totalBytesRead < Int(responseLength) {
            let readChunk = read(fd, &payloadBuffer[totalBytesRead], Int(responseLength) - totalBytesRead)
            if readChunk <= 0 { return nil }
            totalBytesRead += readChunk
        }
        
        let payloadData = Data(payloadBuffer)
        guard let plist = try? PropertyListSerialization.propertyList(from: payloadData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist["Value"] as? String
    }
    
    private func fetchLockdownDetails(deviceID: Int) -> [String: String] {
        var details: [String: String] = [:]
        let socketPath = "/var/run/usbmuxd"
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return details }
        defer { close(fd) }
        
        // Set brief timeout for the entire handshake
        var tv = timeval()
        tv.tv_sec = 2 // 2 seconds timeout
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
                connect(fd, sockaddrPointer, socklen_t(addrSize))
            }
        }
        
        guard connectRes >= 0 else { return details }
        
        // Connect to Lockdownd port (62078).
        // PortNumber MUST be network byte order (htons). htons(62078) = 32498
        let connectPlist: [String: Any] = [
            "ClientVersionString": "flyflyfly-monitor",
            "DeviceID": deviceID,
            "PortNumber": 32498, // htons(62078)
            "MessageType": "Connect",
            "ProgName": "flyflyfly"
        ]
        
        guard self.sendPlist(fd, plist: connectPlist, tag: 2) else { return details }
        guard let connResult = self.readResponse(fd, timeoutSeconds: 2) else { return details }
        
        if let number = connResult["Number"] as? Int, number != 0 {
            // Connection rejected by usbmuxd
            return details
        }
        
        // Socket is now a direct tunnel to lockdownd!
        // We fetch only the four specific, non-sensitive keys to avoid over-fetching
        // sensitive information such as SerialNumber, WiFiAddress, or BluetoothAddress.
        if let deviceClass = fetchLockdownValue(fd: fd, key: "DeviceClass") {
            details["DeviceClass"] = deviceClass
        }
        if let deviceName = fetchLockdownValue(fd: fd, key: "DeviceName") {
            details["DeviceName"] = deviceName
        }
        if let productType = fetchLockdownValue(fd: fd, key: "ProductType") {
            details["ProductType"] = productType
        }
        if let productVersion = fetchLockdownValue(fd: fd, key: "ProductVersion") {
            details["ProductVersion"] = productVersion
        }
        
        return details
    }
}
