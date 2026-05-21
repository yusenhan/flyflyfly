import Foundation

/// DTX 訊息類型
public enum DTXMessageType: UInt8, Sendable {
    case ok = 0
    case data = 1
    case dispatch = 2
    case object = 3
    case error = 4
    case barrier = 5
    case primitive = 6
    case compressed = 7
    case proxiedMessage = 8
}

/// DTX 傳輸原始資料型態 (Primitives)
public enum DTXPrimitive: Sendable, Hashable {
    case null
    case string(String)
    case int32(Int32)
    case int64(Int64)
    case buffer(Data)
    case double(Double)
    indirect case dictionary([DTXPrimitive: [DTXPrimitive]])
    
    public var typeCode: UInt8 {
        switch self {
        case .null: return 10
        case .string: return 1
        case .int32: return 3
        case .int64: return 6
        case .buffer: return 2
        case .double: return 9
        case .dictionary: return 0xF0
        }
    }
    
    /// 將 Primitive 編碼為二進位資料 (小端位元組序)
    public func encode() -> Data {
        var data = Data()
        switch self {
        case .null:
            data.appendUInt32Le(UInt32(typeCode))
            
        case .string(let val):
            data.appendUInt32Le(UInt32(typeCode))
            if let utf8 = val.data(using: .utf8) {
                data.appendUInt32Le(UInt32(utf8.count))
                data.append(utf8)
            } else {
                data.appendUInt32Le(0)
            }
            
        case .int32(let val):
            data.appendUInt32Le(UInt32(typeCode))
            data.appendInt32Le(val)
            
        case .int64(let val):
            data.appendUInt32Le(UInt32(typeCode))
            data.appendInt64Le(val)
            
        case .buffer(let val):
            data.appendUInt32Le(UInt32(typeCode))
            data.appendUInt32Le(UInt32(val.count))
            data.append(val)
            
        case .double(let val):
            data.appendUInt32Le(UInt32(typeCode))
            data.appendDoubleLe(val)
            
        case .dictionary(let dict):
            // Dictionary header:
            // 4-byte: 0x1F0 (0x100 | 0xF0)
            // 4-byte: 0 (unknown_flags)
            // 8-byte: body_length
            var body = Data()
            for (key, values) in dict {
                for value in values {
                    body.append(key.encode())
                    body.append(value.encode())
                }
            }
            data.appendUInt32Le(0x1F0)
            data.appendUInt32Le(0)
            data.appendUInt64Le(UInt64(body.count))
            data.append(body)
        }
        return data
    }
    
    /// 從二進位資料解碼 Primitive
    public static func decode(from data: inout Data) throws -> DTXPrimitive {
        guard data.count >= 4 else {
            throw NSError(domain: "DTXPrimitive", code: -1, userInfo: [NSLocalizedDescriptionKey: "資料長度不足讀取 TypeTag"])
        }
        
        let rawTypeCode = data.readUInt32Le() ?? 0
        let typeCode = UInt8(rawTypeCode & 0xFF)
        
        switch typeCode {
        case 10: // Null
            return .null
            
        case 1: // String
            guard let len = data.readUInt32Le() else {
                throw NSError(domain: "DTXPrimitive", code: -2, userInfo: [NSLocalizedDescriptionKey: "無法讀取字串長度"])
            }
            guard let strBytes = data.readBytes(Int(len)) else {
                throw NSError(domain: "DTXPrimitive", code: -3, userInfo: [NSLocalizedDescriptionKey: "字串資料不足"])
            }
            let str = String(data: strBytes, encoding: .utf8) ?? ""
            return .string(str)
            
        case 3: // Int32
            guard let val = data.readInt32Le() else {
                throw NSError(domain: "DTXPrimitive", code: -4, userInfo: [NSLocalizedDescriptionKey: "無法讀取 Int32"])
            }
            return .int32(val)
            
        case 6: // Int64
            guard let val = data.readInt64Le() else {
                throw NSError(domain: "DTXPrimitive", code: -5, userInfo: [NSLocalizedDescriptionKey: "無法讀取 Int64"])
            }
            return .int64(val)
            
        case 2: // Buffer
            guard let len = data.readUInt32Le() else {
                throw NSError(domain: "DTXPrimitive", code: -6, userInfo: [NSLocalizedDescriptionKey: "無法讀取 Buffer 長度"])
            }
            guard let buf = data.readBytes(Int(len)) else {
                throw NSError(domain: "DTXPrimitive", code: -7, userInfo: [NSLocalizedDescriptionKey: "Buffer 資料不足"])
            }
            return .buffer(buf)
            
        case 9: // Double
            guard let val = data.readDoubleLe() else {
                throw NSError(domain: "DTXPrimitive", code: -8, userInfo: [NSLocalizedDescriptionKey: "無法讀取 Double"])
            }
            return .double(val)
            
        case 0xF0: // Dictionary
            // 讀取接下來的 4-byte unknown_flags 與 8-byte body_length
            guard let _ = data.readUInt32Le(), let bodyLen = data.readUInt64Le() else {
                throw NSError(domain: "DTXPrimitive", code: -9, userInfo: [NSLocalizedDescriptionKey: "無法讀取 Dictionary 標頭資訊"])
            }
            guard var bodyData = data.readBytes(Int(bodyLen)) else {
                throw NSError(domain: "DTXPrimitive", code: -10, userInfo: [NSLocalizedDescriptionKey: "Dictionary Body 長度不足"])
            }
            
            var dict: [DTXPrimitive: [DTXPrimitive]] = [:]
            while !bodyData.isEmpty {
                let key = try decode(from: &bodyData)
                let value = try decode(from: &bodyData)
                var list = dict[key] ?? []
                list.append(value)
                dict[key] = list
            }
            return .dictionary(dict)
            
        default:
            throw NSError(domain: "DTXPrimitive", code: -99, userInfo: [NSLocalizedDescriptionKey: "未知的 TypeTag: \(typeCode)"])
        }
    }
}

/// DTX Message 結構
public struct DTXMessage: Sendable, CustomStringConvertible {
    public var type: DTXMessageType
    public var identifier: UInt32
    public var conversationIndex: UInt32
    public var channelCode: Int32
    public var expectsReply: Bool
    public var payload: Data      // 主要是 Selector 經過 NSKeyedArchiver 序列化的結果
    public var auxiliary: Data    // 主要是 Arguments 經過 Primitive 序列化的結果
    
    public static let magic: UInt32 = 0x1F3D5B79
    
    public init(type: DTXMessageType, identifier: UInt32, conversationIndex: UInt32 = 0, channelCode: Int32 = 0, expectsReply: Bool = false, payload: Data = Data(), auxiliary: Data = Data()) {
        self.type = type
        self.identifier = identifier
        self.conversationIndex = conversationIndex
        self.channelCode = channelCode
        self.expectsReply = expectsReply
        self.payload = payload
        self.auxiliary = auxiliary
    }
    
    /// 建構 RPC 方法呼叫輔助方法
    public static func makeMethodCall(identifier: UInt32, channelCode: Int32, selector: String, arguments: [DTXPrimitive] = [], expectsReply: Bool = false) throws -> DTXMessage {
        // 1. 序列化 Selector 為 NSKeyedArchiver Blob (Main Payload)
        // 在 macOS Swift 中直接使用 NSKeyedArchiver
        let selectorData: Data
        if #available(macOS 10.13, *) {
            selectorData = try NSKeyedArchiver.archivedData(withRootObject: selector, requiringSecureCoding: false)
        } else {
            selectorData = NSKeyedArchiver.archivedData(withRootObject: selector)
        }
        
        // 2. 序列化 Arguments 為 Auxiliary PrimitiveDictionary
        var auxData = Data()
        if !arguments.isEmpty {
            // 建構一個 PDict { PNULL: arguments }
            let pdict = DTXPrimitive.dictionary([.null: arguments])
            auxData = pdict.encode()
        }
        
        return DTXMessage(
            type: .dispatch,
            identifier: identifier,
            conversationIndex: 0,
            channelCode: channelCode,
            expectsReply: expectsReply,
            payload: selectorData,
            auxiliary: auxData
        )
    }
    
    /// 解析傳入的 Auxiliary 參數列表
    public func parseArguments() throws -> [Any] {
        guard !auxiliary.isEmpty else { return [] }
        var tempAux = auxiliary
        let pdict = try DTXPrimitive.decode(from: &tempAux)
        
        guard case .dictionary(let dict) = pdict else {
            throw NSError(domain: "DTXMessage", code: -20, userInfo: [NSLocalizedDescriptionKey: "Auxiliary 不是一個 Dictionary 結構"])
        }
        
        guard let list = dict[.null] else {
            return []
        }
        
        var results: [Any] = []
        for item in list {
            switch item {
            case .null:
                results.append(NSNull())
            case .string(let s):
                results.append(s)
            case .int32(let i):
                results.append(i)
            case .int64(let i):
                results.append(i)
            case .double(let d):
                results.append(d)
            case .buffer(let buf):
                if buf.isEmpty {
                    results.append(NSNull())
                } else {
                    // 嘗試以 NSKeyedUnarchiver 反序列化物件
                    do {
                        if let obj = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(buf) {
                            results.append(obj)
                        } else {
                            results.append(buf)
                        }
                    } catch {
                        // 降級：若反序列化失敗，則視為普通 Data
                        results.append(buf)
                    }
                }
            case .dictionary:
                results.append(item)
            }
        }
        
        return results
    }
    
    /// 解析傳回的 Payload 物件 (通常是 Selector 或回傳值)
    public func parsePayload() -> Any? {
        guard !payload.isEmpty else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(payload)
        } catch {
            // 若為 Plist
            if let plist = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil) {
                return plist
            }
            return payload
        }
    }
    
    /// 序列化整個 DTX 訊息二進位資料包 (小端)
    public func serialize() -> Data {
        var data = Data()
        let bodyLength = 16 + auxiliary.count + payload.count
        
        // ----------------------------------------------------
        // 1. DTX Header (32 bytes)
        // ----------------------------------------------------
        data.appendUInt32Le(Self.magic)                // magic
        data.appendUInt32Le(32)                        // header_size
        data.appendUInt16Le(0)                         // fragment index
        data.appendUInt16Le(1)                         // fragment count
        data.appendUInt32Le(UInt32(bodyLength))        // data_size
        data.appendUInt32Le(identifier)                // identifier
        data.appendUInt32Le(conversationIndex)         // conversationIndex
        data.appendInt32Le(channelCode)                // channelCode
        data.appendUInt32Le(expectsReply ? 1 : 0)      // flags (expectsReply)
        
        // ----------------------------------------------------
        // 2. Payload Header (16 bytes)
        // ----------------------------------------------------
        data.append(type.rawValue)                     // msg_type
        data.append(0)                                 // flags_a
        data.append(0)                                 // flags_b
        data.append(0)                                 // reserved
        data.appendUInt32Le(UInt32(auxiliary.count))   // aux_size
        data.appendUInt32Le(UInt32(auxiliary.count + payload.count)) // total_size
        data.appendUInt32Le(0)                         // flags (unused)
        
        // ----------------------------------------------------
        // 3. Aux & Payload Body
        // ----------------------------------------------------
        data.append(auxiliary)
        data.append(payload)
        
        return data
    }
    
    /// 從 Data 中解碼出一包完整的 DTX Message
    /// 回傳的 (message, consumedBytes) 元組
    public static func parse(from data: Data) throws -> (DTXMessage, Int)? {
        guard data.count >= 48 else { return nil }
        
        let magicVal = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard UInt32(littleEndian: magicVal) == Self.magic else {
            throw NSError(domain: "DTXMessage", code: -100, userInfo: [NSLocalizedDescriptionKey: "無效的 DTX Magic 標頭"])
        }
        
        let headerSizeVal = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        let headerSize = Int(UInt32(littleEndian: headerSizeVal))
        
        guard data.count >= headerSize + 16 else { return nil }
        
        let dataSizeVal = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let bodySize = Int(UInt32(littleEndian: dataSizeVal))
        
        let totalSize = headerSize + bodySize
        guard data.count >= totalSize else {
            return nil // 還不夠一整包
        }
        
        // 解析 Header
        let identifierVal = data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }
        let identifier = UInt32(littleEndian: identifierVal)
        
        let convIndexVal = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self) }
        let conversationIndex = UInt32(littleEndian: convIndexVal)
        
        let chanCodeVal = data.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: Int32.self) }
        let channelCode = Int32(littleEndian: chanCodeVal)
        
        let flagsVal = data.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
        let expectsReply = UInt32(littleEndian: flagsVal) != 0
        
        // 解析 Payload Header (位於 headerSize 開始的 16 個 bytes)
        let payloadHeaderOffset = headerSize
        let msgTypeRaw = data[payloadHeaderOffset]
        guard let msgType = DTXMessageType(rawValue: msgTypeRaw) else {
            throw NSError(domain: "DTXMessage", code: -101, userInfo: [NSLocalizedDescriptionKey: "無效的 MessageType: \(msgTypeRaw)"])
        }
        
        let auxSizeVal = data.subdata(in: (payloadHeaderOffset + 4)..<(payloadHeaderOffset + 8)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let auxSize = Int(UInt32(littleEndian: auxSizeVal))
        
        let totalPayloadSizeVal = data.subdata(in: (payloadHeaderOffset + 8)..<(payloadHeaderOffset + 12)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let totalPayloadSize = Int(UInt32(littleEndian: totalPayloadSizeVal))
        
        let payloadSize = totalPayloadSize - auxSize
        
        let auxStart = payloadHeaderOffset + 16
        let payloadStart = auxStart + auxSize
        
        guard payloadStart + payloadSize <= totalSize else {
            throw NSError(domain: "DTXMessage", code: -102, userInfo: [NSLocalizedDescriptionKey: "資料包大小不一致"])
        }
        
        let auxData = data.subdata(in: auxStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<(payloadStart + payloadSize))
        
        let msg = DTXMessage(
            type: msgType,
            identifier: identifier,
            conversationIndex: conversationIndex,
            channelCode: channelCode,
            expectsReply: expectsReply,
            payload: payloadData,
            auxiliary: auxData
        )
        
        return (msg, totalSize)
    }
    
    public var description: String {
        let p = parsePayload() ?? "nil"
        let a = (try? parseArguments()) ?? []
        return "<DTXMessage: i\(identifier).\(conversationIndex) c\(channelCode) type:\(type) expectsReply:\(expectsReply) payload:\(p) aux:\(a)>"
    }
}

// ---------------------------------------------------------------------------
// Data 讀寫二進位 Helper Extensions
// ---------------------------------------------------------------------------
extension Data {
    mutating func readUInt32Le() -> UInt32? {
        guard self.count >= 4 else { return nil }
        let val = self.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        self.removeFirst(4)
        return UInt32(littleEndian: val)
    }
    
    mutating func readInt32Le() -> Int32? {
        guard self.count >= 4 else { return nil }
        let val = self.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: Int32.self) }
        self.removeFirst(4)
        return Int32(littleEndian: val)
    }
    
    mutating func readUInt64Le() -> UInt64? {
        guard self.count >= 8 else { return nil }
        let val = self.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: UInt64.self) }
        self.removeFirst(8)
        return UInt64(littleEndian: val)
    }
    
    mutating func readInt64Le() -> Int64? {
        guard self.count >= 8 else { return nil }
        let val = self.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: Int64.self) }
        self.removeFirst(8)
        return Int64(littleEndian: val)
    }
    
    mutating func readDoubleLe() -> Double? {
        guard self.count >= 8 else { return nil }
        let val = self.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: Double.self) }
        self.removeFirst(8)
        let bits = UInt64(littleEndian: val.bitPattern)
        return Double(bitPattern: bits)
    }
    
    mutating func readBytes(_ length: Int) -> Data? {
        guard self.count >= length else { return nil }
        let chunk = self.subdata(in: 0..<length)
        self.removeFirst(length)
        return chunk
    }
    
    mutating func appendUInt32Le(_ value: UInt32) {
        var val = value.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
    
    mutating func appendInt32Le(_ value: Int32) {
        var val = value.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
    
    mutating func appendUInt16Le(_ value: UInt16) {
        var val = value.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
    
    mutating func appendUInt64Le(_ value: UInt64) {
        var val = value.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
    
    mutating func appendInt64Le(_ value: Int64) {
        var val = value.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
    
    mutating func appendDoubleLe(_ value: Double) {
        var val = value.bitPattern.littleEndian
        withUnsafePointer(to: &val) { pointer in
            self.append(UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
}
