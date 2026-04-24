import Foundation
import MapKit
import Combine

@MainActor
final class SimulationStore: ObservableObject {
    // MARK: - Active simulation state
    @Published var activeOperationMode: OperationMode = .routeAB
    @Published var activeRoutePolyline: MKPolyline?
    @Published var currentPosition: CLLocationCoordinate2D?
    @Published var currentRoutePoints: [CLLocationCoordinate2D] = []
    @Published var cumulativeRouteDistances: [Double] = []
    @Published var traveledDistance: Double = 0.0
    @Published var totalRouteDistance: Double = 0.0
    @Published var activeIsClosedLoop: Bool = false
    @Published var activeIsEndlessLoop: Bool = false
    @Published var isActiveSimulationRunning: Bool = false
    @Published var shouldResumeActiveAfterReconnect: Bool = false
    
    // MARK: - Settings
    @Published var speed: Double = AppConstants.Simulation.defaultSpeed
    @Published var isEndlessLoop: Bool = false
    @Published var isClosedLoop: Bool = false
    
    private var moveTimer: Timer?
    private var pinnedKeepAliveTimer: Timer?
    private let deviceManager: any DeviceControlling
    
    @Published var lastSentPosition: CLLocationCoordinate2D?
    @Published var lastSentAt: Date?
    
    init(deviceManager: any DeviceControlling) {
        self.deviceManager = deviceManager
    }
    
    // MARK: - Actions
    
    func stopSimulation() {
        moveTimer?.invalidate()
        moveTimer = nil
        isActiveSimulationRunning = false
        
        // Start keep-alive at current position to stay there
        if let current = currentPosition {
            startPinnedLocationKeepAlive(at: current)
        }
    }
    
    func startPinnedLocationKeepAlive(at coordinate: CLLocationCoordinate2D) {
        stopPinnedLocationKeepAlive()
        lastSentPosition = coordinate
        lastSentAt = Date()
        
        pinnedKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Timeouts.coordinateSend, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.deviceManager.isConnected && !self.isActiveSimulationRunning {
                    try? await self.deviceManager.sendLocationToDeviceAsync(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                }
            }
        }
    }
    
    func stopPinnedLocationKeepAlive() {
        pinnedKeepAliveTimer?.invalidate()
        pinnedKeepAliveTimer = nil
    }
    
    func startSimulation() {
        stopSimulation()
        stopPinnedLocationKeepAlive() // Ensure keep-alive is OFF for route simulation
        isActiveSimulationRunning = true
        traveledDistance = 0
        
        moveTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Simulation.timerInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.tickSimulation()
            }
        }
    }

    func continueSimulation() {
        stopPinnedLocationKeepAlive()
        isActiveSimulationRunning = true
        
        moveTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Simulation.timerInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.tickSimulation()
            }
        }
    }
    
    private func tickSimulation() async {
        guard isActiveSimulationRunning else { return }
        
        let stepScale = 3600.0 / AppConstants.Simulation.timerInterval
        let distanceStep = speed * (1000.0 / stepScale)
        traveledDistance += distanceStep
        
        let loopMode: RouteMotionEngine.LoopMode = activeIsClosedLoop ? .circular : (activeIsEndlessLoop ? .pingPong : .singlePass)
        
        let target = RouteMotionEngine.targetDistance(
            traveledDistance: traveledDistance,
            routeDistance: totalRouteDistance,
            loopMode: loopMode
        )
        
        guard let targetDist = target else {
            stopSimulation()
            return
        }
        
        if let newCoord = RouteMotionEngine.coordinate(
            at: targetDist,
            in: currentRoutePoints,
            distances: cumulativeRouteDistances
        ) {
            currentPosition = newCoord
            if shouldSendCoordinateUpdate(newCoord) {
                try? await deviceManager.sendLocationToDeviceAsync(latitude: newCoord.latitude, longitude: newCoord.longitude)
                lastSentPosition = newCoord
                lastSentAt = Date()
            }
        }
        
        if !activeIsEndlessLoop && traveledDistance >= totalRouteDistance {
            stopSimulation()
        }
    }
    
    private func shouldSendCoordinateUpdate(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let lastPos = lastSentPosition, let lastDate = lastSentAt else { return true }
        let dist = RouteMotionEngine.fastDistance(from: coord, to: lastPos)
        let time = Date().timeIntervalSince(lastDate)
        return dist >= AppConstants.Simulation.minimumDistance || time >= AppConstants.Simulation.minimumTimeInterval
    }
    
    func cleanup() {
        stopSimulation()
    }
}
