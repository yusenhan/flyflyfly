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
    
    // MARK: - Drift & Traffic Light Settings & States
    @Published var isJitterEnabled: Bool = false
    @Published var jitterRangeMeters: Double = 1.5
    @Published var isTrafficLightEnabled: Bool = false
    @Published var isWaitingForTrafficLight: Bool = false
    @Published var trafficLightRemainingSeconds: Int = 0
    
    private var moveTimer: Timer?
    private var pinnedKeepAliveTimer: Timer?
    private var trafficLightTimer: Timer?
    private var currentTimerInterval: TimeInterval = AppConstants.Simulation.timerInterval
    private let deviceManager: any DeviceControlling
    
    @Published var lastSentPosition: CLLocationCoordinate2D?
    @Published var lastSentAt: Date?
    
    // Drift (Random Walk) states
    private var currentJitterLatOffset: Double = 0.0
    private var currentJitterLonOffset: Double = 0.0
    
    // Traffic light states
    private var nextTrafficLightDistance: Double = 0.0
    
    init(deviceManager: any DeviceControlling) {
        self.deviceManager = deviceManager
    }
    
    // MARK: - Actions
    
    func stopSimulation() {
        moveTimer?.invalidate()
        moveTimer = nil
        trafficLightTimer?.invalidate()
        trafficLightTimer = nil
        isWaitingForTrafficLight = false
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
                    let finalCoord = self.applyJitter(to: coordinate)
                    try? await self.deviceManager.sendLocationToDeviceAsync(
                        latitude: finalCoord.latitude,
                        longitude: finalCoord.longitude
                    )
                }
            }
        }
    }
    
    func stopPinnedLocationKeepAlive() {
        pinnedKeepAliveTimer?.invalidate()
        pinnedKeepAliveTimer = nil
    }
    
    private func restartTimerIfNeeded() {
        let newInterval = AppConstants.Simulation.interval(for: speed)
        if abs(newInterval - currentTimerInterval) > 0.01 {
            moveTimer?.invalidate()
            currentTimerInterval = newInterval
            moveTimer = Timer.scheduledTimer(withTimeInterval: currentTimerInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.tickSimulation()
                }
            }
        }
    }
    
    func startSimulation() {
        stopSimulation()
        stopPinnedLocationKeepAlive() // Ensure keep-alive is OFF for route simulation
        isActiveSimulationRunning = true
        traveledDistance = 0
        
        // Initialize first traffic light distance trigger
        nextTrafficLightDistance = Double.random(in: 300...800)
        
        currentTimerInterval = AppConstants.Simulation.interval(for: speed)
        moveTimer = Timer.scheduledTimer(withTimeInterval: currentTimerInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.tickSimulation()
            }
        }
    }

    func continueSimulation() {
        stopPinnedLocationKeepAlive()
        isActiveSimulationRunning = true
        
        if nextTrafficLightDistance <= traveledDistance {
            nextTrafficLightDistance = traveledDistance + Double.random(in: 300...800)
        }
        
        currentTimerInterval = AppConstants.Simulation.interval(for: speed)
        moveTimer = Timer.scheduledTimer(withTimeInterval: currentTimerInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.tickSimulation()
            }
        }
    }
    
    private func startTrafficLightWaiting() {
        isWaitingForTrafficLight = true
        trafficLightRemainingSeconds = Int.random(in: 15...45)
        
        trafficLightTimer?.invalidate()
        trafficLightTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.trafficLightRemainingSeconds -= 1
                if self.trafficLightRemainingSeconds <= 0 {
                    self.stopTrafficLightWaiting()
                }
            }
        }
    }
    
    private func stopTrafficLightWaiting() {
        trafficLightTimer?.invalidate()
        trafficLightTimer = nil
        isWaitingForTrafficLight = false
        // Set next trigger distance
        nextTrafficLightDistance = traveledDistance + Double.random(in: 300...800)
    }
    
    private func applyJitter(to coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isJitterEnabled else {
            currentJitterLatOffset = 0.0
            currentJitterLonOffset = 0.0
            return coordinate
        }
        
        // Random Walk step sizes (approx. 0.25 meters max per change)
        let stepSizeMeters = 0.25
        let dx = Double.random(in: -stepSizeMeters...stepSizeMeters)
        let dy = Double.random(in: -stepSizeMeters...stepSizeMeters)
        
        // Meters to Lat/Lon degrees conversion
        let latDegreePerMeter = 1.0 / 111000.0
        let latRad = coordinate.latitude * .pi / 180.0
        let cosLat = cos(latRad) > 0.1 ? cos(latRad) : 1.0
        let lonDegreePerMeter = 1.0 / (111000.0 * cosLat)
        
        let dLat = dy * latDegreePerMeter
        let dLon = dx * lonDegreePerMeter
        
        // Update offset states smoothly
        currentJitterLatOffset += dLat
        currentJitterLonOffset += dLon
        
        // Calculate total distance offset in meters
        let currentDx = currentJitterLonOffset / lonDegreePerMeter
        let currentDy = currentJitterLatOffset / latDegreePerMeter
        let totalOffsetDistance = sqrt(currentDx * currentDx + currentDy * currentDy)
        
        // If drifted beyond jitter range boundary, scale back to center
        if totalOffsetDistance > jitterRangeMeters && totalOffsetDistance > 0 {
            let scale = jitterRangeMeters / totalOffsetDistance
            currentJitterLatOffset *= scale
            currentJitterLonOffset *= scale
        }
        
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + currentJitterLatOffset,
            longitude: coordinate.longitude + currentJitterLonOffset
        )
    }
    
    private func tickSimulation() async {
        guard isActiveSimulationRunning else { return }
        
        // If waiting for traffic light, stay stationary but still send jitter location
        if isTrafficLightEnabled && isWaitingForTrafficLight {
            if let baseCoord = currentPosition {
                let finalCoord = applyJitter(to: baseCoord)
                try? await deviceManager.sendLocationToDeviceAsync(latitude: finalCoord.latitude, longitude: finalCoord.longitude)
                lastSentPosition = finalCoord
                lastSentAt = Date()
            }
            return
        }
        
        let stepScale = 3600.0 / currentTimerInterval
        let distanceStep = speed * (1000.0 / stepScale)
        traveledDistance += distanceStep
        
        // Check if traffic light triggers
        if isTrafficLightEnabled && traveledDistance >= nextTrafficLightDistance {
            startTrafficLightWaiting()
            if let baseCoord = currentPosition {
                let finalCoord = applyJitter(to: baseCoord)
                try? await deviceManager.sendLocationToDeviceAsync(latitude: finalCoord.latitude, longitude: finalCoord.longitude)
                lastSentPosition = finalCoord
                lastSentAt = Date()
            }
            return
        }
        
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
            let finalCoord = applyJitter(to: newCoord)
            if shouldSendCoordinateUpdate(finalCoord) {
                try? await deviceManager.sendLocationToDeviceAsync(latitude: finalCoord.latitude, longitude: finalCoord.longitude)
                lastSentPosition = finalCoord
                lastSentAt = Date()
            }
        }
        
        if !activeIsEndlessLoop && traveledDistance >= totalRouteDistance {
            stopSimulation()
        } else {
            restartTimerIfNeeded()
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
