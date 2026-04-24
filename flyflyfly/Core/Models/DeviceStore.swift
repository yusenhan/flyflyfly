import Foundation
import Combine
import MapKit

@MainActor
final class DeviceStore: ObservableObject {
    let deviceManager: any DeviceControlling
    
    @Published var dependencyVersion: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    init(deviceManager: any DeviceControlling) {
        self.deviceManager = deviceManager
        
        // Relay changes from deviceManager to trigger objectWillChange if needed,
        // or just observe specific properties.
        deviceManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.dependencyVersion += 1
            }
            .store(in: &cancellables)
    }
    
    var isConnected: Bool { deviceManager.isConnected }
    var isConnecting: Bool { deviceManager.isConnecting }
    var connectionStage: String { deviceManager.connectionStage }
    var deviceName: String { deviceManager.deviceName }
    var lastError: String? { deviceManager.lastError }
    
    func connect() {
        deviceManager.connectDevice()
    }
    
    func disconnect() {
        deviceManager.disconnect()
    }
}
