import SwiftUI
import MapKit

enum TransportType: String, CaseIterable, Identifiable, Codable {
    case automobile = "開車"
    case walking = "走路"

    var id: String { rawValue }

    var mkType: MKDirectionsTransportType {
        switch self {
        case .automobile: return .automobile
        case .walking: return .walking
        }
    }
}

enum OperationMode: String, CaseIterable, Identifiable {
    case routeAB = "A-B"
    case fixedPoint = "定點"
    case multiPoint = "多點"

    var id: String { rawValue }
}

enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting(step: String)
    case connected
    case failed

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "尚未連線"
        case .connecting(let step):
            return Self.userFacingStepText(step)
        case .connected:
            return "已連線"
        case .failed:
            return "暫時無法連線"
        }
    }

    private static func userFacingStepText(_ step: String) -> String {
        let normalized = step.lowercased()

        if normalized.contains("重連") {
            return "正在重新連線"
        }
        if step.contains("使用手動 RSD") {
            return "正在使用手動連線設定"
        }
        if step.contains("搜尋 Wi‑Fi 裝置") || step.contains("初始化") || step.contains("檢查") || step.contains("偵測連線裝置") {
            return "正在尋找你的裝置"
        }
        if step.contains("改用 USB") {
            return "正在切換為更穩定的連線方式"
        }
        if step.contains("建立") || step.contains("等待") {
            return "正在建立連線"
        }
        if step.contains("驗證") || step.contains("掛載") || step.contains("讀取") || step.contains("simulate-location") {
            return "正在準備裝置"
        }

        return "正在連線"
    }
}

public struct IOSSystemInfo: Codable, Equatable {
    public var cpuUsage: Double = 0.0      // 0.0 - 100.0
    public var ramUsed: Double = 0.0       // GB
    public var ramTotal: Double = 0.0      // GB
    public var batteryLevel: Int = 0       // 0 - 100
    public var isCharging: Bool = false
    public var thermalState: String = "正常" // 正常, 溫暖, 嚴重, 危險
    
    public var ramPercentage: Double {
        guard ramTotal > 0 else { return 0 }
        return (ramUsed / ramTotal) * 100.0
    }
}


