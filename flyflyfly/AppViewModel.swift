import Combine
import Foundation
import MapKit
import SwiftUI

private final class MultiPointRouteAccumulator: @unchecked Sendable {
    var combinedPoints: [CLLocationCoordinate2D] = []
    var totalDistance: Double = 0
}

private final class UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

// MARK: - OSM Helper Models

private struct OSMSearchResult: Codable {
    let lat: String
    let lon: String
    let display_name: String
    
    func toMKMapItem() -> MKMapItem {
        let latitude = Double(lat) ?? 0.0
        let longitude = Double(lon) ?? 0.0
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: [
            "FormattedAddressLines": [display_name]
        ])
        
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = display_name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        return mapItem
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Sub-Stores
    let deviceStore: DeviceStore
    let simulationStore: SimulationStore
    let mapStateStore: MapStateStore
    let purePointStore: PurePointStore
    let favoriteStore: FavoriteStore
    let searchViewModel: SearchViewModel
    
    // MARK: - Dependencies
    let deviceManager: any DeviceControlling
    let locationSearchService: any LocationSearching

    // MARK: - Draft workflow (Delegated)
    var appState: AppState {
        get { mapStateStore.appState }
        set { mapStateStore.appState = newValue }
    }
    var operationMode: OperationMode {
        get { mapStateStore.operationMode }
        set { mapStateStore.operationMode = newValue }
    }
    var pendingModeSwitch: OperationMode? {
        get { mapStateStore.pendingModeSwitch }
        set { mapStateStore.pendingModeSwitch = newValue }
    }

    var pointA: CLLocationCoordinate2D? {
        get { mapStateStore.pointA }
        set { mapStateStore.pointA = newValue }
    }
    var pointB: CLLocationCoordinate2D? {
        get { mapStateStore.pointB }
        set { mapStateStore.pointB = newValue }
    }
    var tempCoordinate: CLLocationCoordinate2D? {
        get { mapStateStore.tempCoordinate }
        set { mapStateStore.tempCoordinate = newValue }
    }
    var waypoints: [CLLocationCoordinate2D] {
        get { mapStateStore.waypoints }
        set { mapStateStore.waypoints = newValue }
    }
    var customRoutePolyline: MKPolyline? {
        get { mapStateStore.customRoutePolyline }
        set { mapStateStore.customRoutePolyline = newValue }
    }
    var routes: [MKRoute] {
        get { mapStateStore.routes }
        set { mapStateStore.routes = newValue }
    }
    var selectedRouteIndex: Int {
        get { mapStateStore.selectedRouteIndex }
        set { mapStateStore.selectedRouteIndex = newValue }
    }
    var transportType: TransportType {
        get { mapStateStore.transportType }
        set { mapStateStore.transportType = newValue }
    }
    var draftRoutePoints: [CLLocationCoordinate2D] {
        get { mapStateStore.draftRoutePoints }
        set { mapStateStore.draftRoutePoints = newValue }
    }
    var draftCumulativeRouteDistances: [Double] {
        get { mapStateStore.draftCumulativeRouteDistances }
        set { mapStateStore.draftCumulativeRouteDistances = newValue }
    }
    var draftTotalRouteDistance: Double {
        get { mapStateStore.draftTotalRouteDistance }
        set { mapStateStore.draftTotalRouteDistance = newValue }
    }

    // MARK: - Active route / simulation (Delegated)
    var activeOperationMode: OperationMode {
        get { simulationStore.activeOperationMode }
        set { simulationStore.activeOperationMode = newValue }
    }
    var activeRoutePolyline: MKPolyline? {
        get { simulationStore.activeRoutePolyline }
        set { simulationStore.activeRoutePolyline = newValue }
    }
    var currentPosition: CLLocationCoordinate2D? {
        get { simulationStore.currentPosition }
        set { simulationStore.currentPosition = newValue }
    }
    var currentRoutePoints: [CLLocationCoordinate2D] {
        get { simulationStore.currentRoutePoints }
        set { simulationStore.currentRoutePoints = newValue }
    }
    var cumulativeRouteDistances: [Double] {
        get { simulationStore.cumulativeRouteDistances }
        set { simulationStore.cumulativeRouteDistances = newValue }
    }
    var traveledDistance: Double {
        get { simulationStore.traveledDistance }
        set { simulationStore.traveledDistance = newValue }
    }
    var totalRouteDistance: Double {
        get { simulationStore.totalRouteDistance }
        set { simulationStore.totalRouteDistance = newValue }
    }
    var activeIsClosedLoop: Bool {
        get { simulationStore.activeIsClosedLoop }
        set { simulationStore.activeIsClosedLoop = newValue }
    }
    var activeIsEndlessLoop: Bool {
        get { simulationStore.activeIsEndlessLoop }
        set { simulationStore.activeIsEndlessLoop = newValue }
    }
    var isActiveSimulationRunning: Bool {
        get { simulationStore.isActiveSimulationRunning }
        set { simulationStore.isActiveSimulationRunning = newValue }
    }
    var shouldResumeActiveAfterReconnect: Bool {
        get { simulationStore.shouldResumeActiveAfterReconnect }
        set { simulationStore.shouldResumeActiveAfterReconnect = newValue }
    }
    
    @Published var isShowingRouteReplacementConfirmation: Bool = false
    private var multiPointTask: Task<Void, Never>?

    // MARK: - Settings (Delegated)
    var speed: Double {
        get { simulationStore.speed }
        set {
            simulationStore.speed = newValue
            // Keep text in sync
            speedText = String(format: "%.1f", newValue)
        }
    }
    var isEndlessLoop: Bool {
        get { simulationStore.isEndlessLoop }
        set { simulationStore.isEndlessLoop = newValue }
    }
    var isClosedLoop: Bool {
        get { simulationStore.isClosedLoop }
        set { simulationStore.isClosedLoop = newValue }
    }

    // MARK: - Location input (Delegated)

    // MARK: - Map camera (Delegated)
    var mapRegion: MKCoordinateRegion {
        get { mapStateStore.mapRegion }
        set { mapStateStore.mapRegion = newValue }
    }
    var visibleMapRegion: MKCoordinateRegion {
        get { mapStateStore.visibleMapRegion }
        set { mapStateStore.visibleMapRegion = newValue }
    }
    var requestCameraPosition: ((MKCoordinateRegion) -> Void)? {
        get { mapStateStore.requestCameraPosition }
        set { mapStateStore.requestCameraPosition = newValue }
    }

    // MARK: - Pure Point (Delegated)
    var availableOverlays: [PurePointOverlay] {
        get { purePointStore.availableOverlays }
        set { purePointStore.availableOverlays = newValue }
    }
    var selectedOverlayIDs: Set<String> {
        get { purePointStore.selectedOverlayIDs }
        set { purePointStore.selectedOverlayIDs = newValue }
    }
    var renderedPurePoints: [VisiblePurePoint] {
        get { purePointStore.renderedPurePoints }
        set { purePointStore.renderedPurePoints = newValue }
    }
    var isPurePointLoading: Bool { purePointStore.isLoading }
    var purePointRenderState: PurePointRenderState { purePointStore.renderState }

    // MARK: - Private state
    private var cancellables: Set<AnyCancellable> = []
    private var stateBeforeConfirm: AppState = .selectingA
    
    // MARK: - Compatibility accessors for View
    var dependencyVersion: Int { deviceStore.dependencyVersion }
    var isConnected: Bool { deviceStore.isConnected }
    var isConnecting: Bool { deviceStore.isConnecting }
    var connectionStage: String { deviceStore.connectionStage }
    var deviceName: String { deviceStore.deviceName }
    var lastError: String? { deviceStore.lastError }
    var manualRsdHost: String {
        get { deviceManager.manualRsdHost }
        set { deviceManager.manualRsdHost = newValue }
    }
    var manualRsdPort: String {
        get { deviceManager.manualRsdPort }
        set { deviceManager.manualRsdPort = newValue }
    }
    var tunnelUDID: String {
        get { deviceManager.tunnelUDID }
        set { deviceManager.tunnelUDID = newValue }
    }
    @Published var isWirelessMode: Bool = false {
        didSet {
            deviceManager.isWirelessMode = isWirelessMode
        }
    }
    
    var developerModeDisabled: Bool { deviceManager.developerModeDisabled }
    var debugLog: [String] { deviceManager.debugLog }

    let maximumSpeed = AppConstants.Simulation.maximumSpeed

    @Published var speedText: String = ""
    
    // MARK: - Initialization
    
    init(deviceManager: any DeviceControlling, locationSearchService: any LocationSearching) {
        self.deviceManager = deviceManager
        self.locationSearchService = locationSearchService
        
        let mapStore = MapStateStore()
        self.mapStateStore = mapStore
        self.deviceStore = DeviceStore(deviceManager: deviceManager)
        self.simulationStore = SimulationStore(deviceManager: deviceManager)
        self.purePointStore = PurePointStore(mapStateStore: mapStore)
        self.favoriteStore = FavoriteStore()
        self.searchViewModel = SearchViewModel(mapStateStore: mapStore, locationSearchService: locationSearchService)
        self.searchViewModel.setAppViewModel(self)
        
        // Initialize speed text
        self.speedText = String(format: "%.1f", simulationStore.speed)
        self.isWirelessMode = deviceManager.isWirelessMode
        
        // Link changes from stores to AppViewModel to trigger View updates with stable throttling
        deviceStore.objectWillChange.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        simulationStore.objectWillChange.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        mapStateStore.objectWillChange.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        purePointStore.objectWillChange.throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        favoriteStore.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        searchViewModel.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        
        setupDeviceObservers()
        
        // Pre-warm CLI path in background task to avoid lag on first use in Settings tab
        Task {
            _ = try? deviceManager.resolveCLI()
        }
    }

    func updateSpeedFromText() {
        let trimmed = speedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed) else {
            // Reset to current speed if invalid
            speedText = String(format: "%.1f", speed)
            return
        }
        speed = min(max(parsed, AppConstants.Simulation.speedStep), maximumSpeed)
        speedText = String(format: "%.1f", speed)
    }

    // MARK: - Favorites helper
    func addToFavorites(name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType? = nil) {
        favoriteStore.add(name: name, type: type, coordinates: coordinates, transportType: transportType)
    }

    func selectFavorite(_ item: FavoriteItem) {
        resetDraft(clearActive: false)
        
        switch item.type {
        case .point:
            operationMode = .fixedPoint
            if let coord = item.coordinates.first?.clCoordinate {
                handleMapTap(at: coord)
            }
        case .route:
            if item.coordinates.count == 2 {
                operationMode = .routeAB
                let start = item.coordinates[0].clCoordinate
                let end = item.coordinates[1].clCoordinate
                
                pointA = start
                pointB = end
                if let transport = item.transportType {
                    self.transportType = transport
                }
                calculateRoute()
                centerMap(on: start)
            } else if item.coordinates.count > 2 {
                operationMode = .multiPoint
                waypoints = item.coordinates.map { $0.clCoordinate }
                if let transport = item.transportType {
                    self.transportType = transport
                }
                calculateMultiPointRoute()
                if let first = waypoints.first {
                    centerMap(on: first)
                }
            }
        }
    }

    private func setupDeviceObservers() {
        deviceManager.objectWillChange.sink { [weak self] _ in
            guard let self = self else { return }
            if self.deviceManager.isConnected && self.shouldResumeActiveAfterReconnect {
                self.startIfReadyAndConnected()
            }
        }.store(in: &cancellables)
    }

    // MARK: - Logic (Moved/Refactored)

    var selectedRoute: MKRoute? {
        guard !routes.isEmpty else { return nil }
        if routes.indices.contains(selectedRouteIndex) {
            return routes[selectedRouteIndex]
        }
        return routes.first
    }

    var pinnedCoordinate: CLLocationCoordinate2D? {
        currentPosition ?? simulationStore.lastSentPosition
    }

    var hasActiveRouteSnapshot: Bool {
        activeRoutePolyline != nil || (activeOperationMode == .fixedPoint && currentPosition != nil)
    }

    var hasDraftPreview: Bool {
        !routes.isEmpty
            || (customRoutePolyline?.pointCount ?? 0) > 1
            || draftRoutePoints.count > 1
    }

    var hasDraftEdits: Bool {
        appState != .selectingA
            || pointA != nil
            || pointB != nil
            || tempCoordinate != nil
            || !waypoints.isEmpty
            || hasDraftPreview
    }

    var hasReadyDraft: Bool {
        guard appState == .readyToMove || appState == .routeSelection || appState == .moving else { return false }
        switch operationMode {
        case .fixedPoint:
            return pointA != nil
        case .routeAB, .multiPoint:
            // Ensure we have actual points from a route or custom line
            return !draftRoutePoints.isEmpty || selectedRoute != nil || customRoutePolyline != nil
        }
    }

    var shouldUseDraftControls: Bool {
        !hasActiveRouteSnapshot || hasDraftEdits
    }

    var shouldShowResetButton: Bool {
        hasDraftEdits
    }

    var resetButtonTitle: String {
        if hasActiveRouteSnapshot {
            return "清除草稿路線"
        }
        return operationMode == .fixedPoint ? "清除定位點" : "清除目前路線"
    }

    var activityNotice: String? {
        if hasActiveRouteSnapshot && hasDraftEdits {
            return "目前藍線持續運作中，正在編輯黃線草稿。"
        }
        if hasActiveRouteSnapshot && !isActiveSimulationRunning {
            return "目前藍線已停止移動，但定位仍固定在裝置上。"
        }
        return nil
    }

    private var _cachedEstimatedTime: String = "--"
    private var _lastEstimatedSpeed: Double = 0
    private var _lastEstimatedDistance: Double = 0
    
    var estimatedTime: String {
        let distance: Double
        if let route = selectedRoute {
            distance = route.distance
        } else if draftTotalRouteDistance > 0 {
            distance = draftTotalRouteDistance
        } else if totalRouteDistance > 0 {
            distance = totalRouteDistance
        } else {
            return "--"
        }
        
        // Cache optimization
        if abs(speed - _lastEstimatedSpeed) < 0.1 && abs(distance - _lastEstimatedDistance) < 1.0 {
            return _cachedEstimatedTime
        }
        
        let timeSeconds = distance / (speed * (1000.0 / 3600.0))
        if timeSeconds.isInfinite || timeSeconds.isNaN { return "--" }
        let result = "\(Int(timeSeconds) / 60) 分 \(Int(timeSeconds) % 60) 秒"
        
        _cachedEstimatedTime = result
        _lastEstimatedSpeed = speed
        _lastEstimatedDistance = distance
        
        return result
    }

    private var _cachedProgress: String? = nil
    private var _lastTraveledForProgress: Double = -1
    private var _lastIsEndlessForProgress: Bool = false

    var progressPercentage: String? {
        guard isActiveSimulationRunning, totalRouteDistance > 0 else { return nil }

        // Cache check
        if abs(traveledDistance - _lastTraveledForProgress) < 0.5 && isEndlessLoop == _lastIsEndlessForProgress {
            return _cachedProgress
        }

        let result: String
        if isEndlessLoop {
            let cycleDistance = totalRouteDistance * 2.0
            let phase = traveledDistance.truncatingRemainder(dividingBy: cycleDistance)
            let isReturning = phase > totalRouteDistance
            let current = isReturning ? (cycleDistance - phase) : phase
            let percent = (current / totalRouteDistance) * 100
            let direction = isReturning ? " (回程)" : " (去程)"
            result = String(format: "%.1f%%%@", percent, direction)
        } else {
            let current = min(traveledDistance, totalRouteDistance)
            let percent = (current / totalRouteDistance) * 100
            result = String(format: "%.1f%%", percent)
        }

        _cachedProgress = result
        _lastTraveledForProgress = traveledDistance
        _lastIsEndlessForProgress = isEndlessLoop
        return result
    }
    var buttonTitle: String {
        if !deviceManager.isConnected && (hasReadyDraft || hasActiveRouteSnapshot) {
            return "請先連線裝置"
        }
        if shouldUseDraftControls {
            if hasActiveRouteSnapshot && hasReadyDraft {
                return "開始新路線"
            }
            return draftButtonTitle
        }
        return activeButtonTitle
    }

    var isMainActionDisabled: Bool {
        if shouldUseDraftControls {
            return draftActionDisabled
        }
        return activeActionDisabled
    }

    var isMainActionDestructive: Bool {
        !shouldUseDraftControls && isActiveSimulationRunning
    }

    private var draftButtonTitle: String {
        if operationMode == .fixedPoint {
            switch appState {
            case .selectingA, .confirmingA: return "選擇定位點"
            case .readyToMove: return "開始定位"
            case .moving: return "設定定位點"
            default: break
            }
        }
        if operationMode == .multiPoint && appState == .selectingA {
            return waypoints.count >= 2 ? "完成選點並計算路線" : "請先選至少 2 點"
        }
        switch appState {
        case .selectingA: return "請先選擇起點"
        case .selectingB: return "請先選擇終點"
        case .confirmingA, .confirmingB: return "確認位置"
        case .routeSelection: return "開始模擬移動"
        case .readyToMove: return "開始模擬移動"
        case .moving: return "停止模擬"
        case .calculatingRoute: return "路線計算中..."
        }
    }

    private var activeButtonTitle: String {
        isActiveSimulationRunning ? "停止模擬" : "繼續模擬"
    }

    private var draftActionDisabled: Bool {
        if !deviceManager.isConnected { return true }
        if operationMode == .multiPoint && appState == .selectingA {
            return waypoints.count < 2
        }
        return appState == .selectingA || appState == .selectingB
    }

    private var activeActionDisabled: Bool {
        !deviceManager.isConnected
    }

    // MARK: - Actions

    func connectDevice() { deviceStore.connect() }
    func disconnect() { deviceStore.disconnect() }

    func handleMainAction() {
        if appState == .confirmingA || appState == .confirmingB {
            confirmTempCoordinate()
            return
        }
        
        if shouldUseDraftControls {
            if hasActiveRouteSnapshot && hasReadyDraft {
                isShowingRouteReplacementConfirmation = true
            } else {
                startSimulationFromDraft()
            }
        } else {
            if isActiveSimulationRunning {
                simulationStore.stopSimulation()
            } else {
                simulationStore.continueSimulation()
            }
        }
    }

    func confirmRouteReplacement() {
        isShowingRouteReplacementConfirmation = false
        startSimulationFromDraft()
    }

    func cancelRouteReplacement() {
        isShowingRouteReplacementConfirmation = false
    }

    private func startSimulationFromDraft() {
        guard hasReadyDraft else { return }
        
        simulationStore.stopSimulation()
        
        activeOperationMode = operationMode
        speed = simulationStore.speed
        activeIsClosedLoop = isClosedLoop
        activeIsEndlessLoop = isEndlessLoop
        
        if operationMode == .fixedPoint, let target = pointA {
            currentPosition = target
            appState = .moving
            simulationStore.startPinnedLocationKeepAlive(at: target)
            centerMap(on: target)
            Task {
                try? await deviceManager.sendLocationToDeviceAsync(latitude: target.latitude, longitude: target.longitude)
            }
        } else {
            // CRITICAL: Ensure we use the latest points from selectedRoute OR custom polyline
            if let route = selectedRoute {
                currentRoutePoints = route.polyline.coordinates
                totalRouteDistance = route.distance
                activeRoutePolyline = route.polyline
            } else if let custom = customRoutePolyline {
                currentRoutePoints = custom.coordinates
                totalRouteDistance = draftTotalRouteDistance
                activeRoutePolyline = custom
            } else {
                currentRoutePoints = draftRoutePoints
                totalRouteDistance = draftTotalRouteDistance
                activeRoutePolyline = customRoutePolyline
            }
            
            cumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: currentRoutePoints)
            appState = .moving
            
            if let start = currentRoutePoints.first {
                centerMap(on: start)
            }
            simulationStore.startSimulation()
        }
        
        resetDraft(clearActive: false)
    }

    func resetDraft(clearActive: Bool = true) {
        pointA = nil
        pointB = nil
        tempCoordinate = nil
        waypoints = []
        routes = []
        selectedRouteIndex = 0
        customRoutePolyline = nil
        draftRoutePoints = []
        draftCumulativeRouteDistances = []
        draftTotalRouteDistance = 0
        searchViewModel.locationInputError = nil
        
        if clearActive {
            appState = .selectingA
            simulationStore.stopSimulation()
            activeRoutePolyline = nil
            currentPosition = nil
            currentRoutePoints = []
            cumulativeRouteDistances = []
            traveledDistance = 0
            totalRouteDistance = 0
            simulationStore.stopPinnedLocationKeepAlive()
            
            Task {
                try? await deviceManager.clearSimulatedLocationAsync()
            }
        } else if appState != .moving {
            appState = .selectingA
        }
    }

    func resetAll() {
        resetDraft(clearActive: true)
    }

    func handleMapDoubleTap(at coordinate: CLLocationCoordinate2D) {
        if operationMode == .fixedPoint {
            // Immediately execute positioning
            pointA = coordinate
            tempCoordinate = nil
            currentPosition = coordinate
            appState = .moving
            
            // Start keep-alive at this new point
            simulationStore.startPinnedLocationKeepAlive(at: coordinate)
            
            // Send to device
            Task {
                try? await deviceManager.sendLocationToDeviceAsync(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            
            centerMap(on: coordinate)
            resetDraft(clearActive: false)
        }
    }

    func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        if operationMode == .multiPoint {
            if appState == .selectingA || appState == .readyToMove || appState == .calculatingRoute {
                waypoints.append(coordinate)
                if waypoints.count >= 2 {
                    calculateMultiPointRoute()
                }
                centerMap(on: coordinate)
                return
            }
        }
        
        switch appState {
        case .selectingA, .confirmingA:
            tempCoordinate = coordinate
            stateBeforeConfirm = .selectingA
            appState = .confirmingA
            centerMap(on: coordinate)
        case .selectingB, .confirmingB:
            tempCoordinate = coordinate
            stateBeforeConfirm = .selectingB
            appState = .confirmingB
            centerMap(on: coordinate)
        case .moving:
            if activeOperationMode == .fixedPoint {
                currentPosition = coordinate
                simulationStore.startPinnedLocationKeepAlive(at: coordinate)
                centerMap(on: coordinate)
                Task {
                    try? await deviceManager.sendLocationToDeviceAsync(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
            } else {
                tempCoordinate = coordinate
                stateBeforeConfirm = .moving
                appState = .confirmingA
                centerMap(on: coordinate)
            }
        default:
            // Allow re-selecting even in other states if needed
            tempCoordinate = coordinate
            appState = .confirmingA
            centerMap(on: coordinate)
        }
    }

    func confirmTempCoordinate() {
        guard let temp = tempCoordinate else { return }
        if appState == .confirmingA {
            pointA = temp
            tempCoordinate = nil
            if stateBeforeConfirm == .moving {
                appState = .moving
                currentPosition = temp
                centerMap(on: temp)
                
                if operationMode == .fixedPoint {
                    simulationStore.startPinnedLocationKeepAlive(at: temp)
                } else if !isActiveSimulationRunning {
                    // Start/Update keep-alive even in route mode if paused
                    simulationStore.startPinnedLocationKeepAlive(at: temp)
                }
                
                Task { try? await deviceManager.sendLocationToDeviceAsync(latitude: temp.latitude, longitude: temp.longitude) }
            } else if operationMode == .fixedPoint {
                appState = .readyToMove
                centerMap(on: temp)
            } else {
                appState = .selectingB
                centerMap(on: temp)
            }
        } else if appState == .confirmingB {
            pointB = temp
            tempCoordinate = nil
            calculateRoute()
            centerMap(on: temp)
        }
    }

    func cancelTempCoordinate() {
        tempCoordinate = nil
        appState = stateBeforeConfirm
    }

    func recalculateRoute() {
        if operationMode == .routeAB && pointA != nil && pointB != nil {
            calculateRoute()
        } else if operationMode == .multiPoint && waypoints.count >= 2 {
            calculateMultiPointRoute()
        }
    }

    func selectRoute(at index: Int) {
        guard routes.indices.contains(index) else { return }
        selectedRouteIndex = index
        let route = routes[index]
        draftRoutePoints = route.polyline.coordinates
        draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: draftRoutePoints)
        draftTotalRouteDistance = route.distance
    }

    private func calculateRoute() {
        guard let a = pointA, let b = pointB else { return }
        
        let distance = RouteMotionEngine.fastDistance(from: a, to: b)
        if distance < 2.0 {
            fallbackToDirectLine(from: a, to: b)
            return
        }
        
        appState = .calculatingRoute
        searchViewModel.locationInputError = nil
        
        let primaryType = transportType.mkType
        let secondaryType: MKDirectionsTransportType = (transportType == .automobile ? TransportType.walking : TransportType.automobile).mkType
        
        performRouteCalculation(source: a, destination: b, transportType: primaryType) { [weak self] success in
            guard let self = self else { return }
            if !success {
                // Retry with secondary if primary fails
                self.performRouteCalculation(source: a, destination: b, transportType: secondaryType) { success in
                    if !success {
                        self.searchViewModel.locationInputError = "無法計算建議路線（可能是該區域無路徑數據），已自動改用直線模式。"
                        self.fallbackToDirectLine(from: a, to: b)
                    }
                }
            }
        }
    }
    
    private func performRouteCalculation(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, transportType: MKDirectionsTransportType, completion: @escaping (Bool) -> Void) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType
        request.requestsAlternateRoutes = (transportType == .automobile)
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let routes = response?.routes, !routes.isEmpty {
                    self.routes = routes
                    self.selectRoute(at: 0)
                    self.appState = .routeSelection
                    self.searchViewModel.locationInputError = nil // Clear any previous error
                    
                    // Auto-zoom to fit the route
                    let allCoords = routes.flatMap { $0.polyline.coordinates }
                    self.mapRegion = self.mapRegion(fitting: allCoords)
                    
                    completion(true)
                } else {
                    if let error = error {
                        print("MapKit directions error (\(transportType == .walking ? "walking" : "auto")): \(error.localizedDescription)")
                    }
                    completion(false)
                }
            }
        }
    }

    private func calculateMultiPointRoute() {
        guard waypoints.count >= 2 else { return }
        
        multiPointTask?.cancel()
        
        let waypointsToUse = waypoints
        let isClosed = isClosedLoop
        let transportTypeToUse = self.transportType.mkType
        let accumulator = MultiPointRouteAccumulator()
        
        appState = .calculatingRoute
        searchViewModel.locationInputError = nil
        
        multiPointTask = Task {
            let count = waypointsToUse.count
            let segments = isClosed ? count : (count - 1)
            
            await withTaskGroup(of: (Int, [CLLocationCoordinate2D], Double).self) { group in
                for i in 0..<segments {
                    let start = waypointsToUse[i]
                    let end = waypointsToUse[(i + 1) % count]
                    
                    group.addTask {
                        if RouteMotionEngine.fastDistance(from: start, to: end) < 2.0 {
                            return (i, [start, end], RouteMotionEngine.fastDistance(from: start, to: end))
                        }
                        
                        let request = MKDirections.Request()
                        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                        request.transportType = transportTypeToUse
                        
                        let directions = MKDirections(request: request)
                        do {
                            let response = try await directions.calculate()
                            if let route = response.routes.first {
                                return (i, route.polyline.coordinates, route.distance)
                            }
                        } catch {
                            // Fallback to direct line on error
                        }
                        let dist = RouteMotionEngine.fastDistance(from: start, to: end)
                        return (i, [start, end], dist)
                    }
                }
                
                var results = [(Int, [CLLocationCoordinate2D], Double)]()
                for await result in group {
                    results.append(result)
                }
                results.sort { $0.0 < $1.0 }
                
                for (_, coords, dist) in results {
                    accumulator.combinedPoints.append(contentsOf: coords)
                    accumulator.totalDistance += dist
                }
            }
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                if Task.isCancelled { return }
                self.draftRoutePoints = accumulator.combinedPoints
                self.draftTotalRouteDistance = accumulator.totalDistance
                self.draftCumulativeRouteDistances = RouteMotionEngine.cumulativeDistances(for: self.draftRoutePoints)
                self.customRoutePolyline = MKPolyline(coordinates: self.draftRoutePoints, count: self.draftRoutePoints.count)
                
                // Auto-zoom to fit all waypoints
                self.mapRegion = self.mapRegion(fitting: self.draftRoutePoints)
                
                self.appState = .readyToMove
            }
        }
    }

    private func fallbackToDirectLine(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) {
        let coords = [a, b]
        customRoutePolyline = MKPolyline(coordinates: coords, count: 2)
        draftRoutePoints = coords
        draftTotalRouteDistance = RouteMotionEngine.fastDistance(from: a, to: b)
        draftCumulativeRouteDistances = [0, draftTotalRouteDistance]
        
        // Auto-zoom
        self.mapRegion = self.mapRegion(fitting: coords)
        
        appState = .readyToMove
    }

    func switchOperationMode(to mode: OperationMode) {
        if hasActiveRouteSnapshot {
            pendingModeSwitch = mode
        } else {
            operationMode = mode
            resetDraft(clearActive: false)
        }
    }

    func confirmModeSwitch() {
        if let mode = pendingModeSwitch {
            operationMode = mode
            resetDraft(clearActive: true)
            pendingModeSwitch = nil
        }
    }

    func cancelModeSwitch() {
        pendingModeSwitch = nil
    }

    func normalizeMapRegion(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        var r = region
        r.span.latitudeDelta = max(0.0001, min(150, r.span.latitudeDelta))
        r.span.longitudeDelta = max(0.0001, min(150, r.span.longitudeDelta))
        return r
    }

    func mapRegion(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return mapRegion }
        
        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4, longitudeDelta: (maxLon - minLon) * 1.4)
        return MKCoordinateRegion(center: center, span: span)
    }
    
    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        let latSpan = min(mapRegion.span.latitudeDelta, AppConstants.Map.defaultSpanDelta)
        let lonSpan = min(mapRegion.span.longitudeDelta, AppConstants.Map.defaultSpanDelta)
        mapRegion = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    }

    // MARK: - Pure Point Logic
    func toggleOverlay(_ id: String) { purePointStore.toggleOverlay(id) }
    func addImportedOverlays(_ overlays: [PurePointOverlay]) { purePointStore.addImportedOverlays(overlays) }
    func removeOverlay(_ overlay: PurePointOverlay) { purePointStore.removeOverlay(overlay) }

    // MARK: - Compatibility / Lifecycle
    
    func handleDeviceDisconnected() {
        if isActiveSimulationRunning {
            shouldResumeActiveAfterReconnect = true
            simulationStore.stopSimulation()
        }
    }
    
    func startIfReadyAndConnected() {
        guard deviceManager.isConnected else { return }
        if shouldResumeActiveAfterReconnect {
            shouldResumeActiveAfterReconnect = false
            simulationStore.startSimulation()
        }
    }
    
    func switchModePreservingPinnedLocation() { 
        resetDraft(clearActive: false)
    }
    func handleScenePhaseChange(_ phase: ScenePhase) { }

    func cleanup() {
        simulationStore.cleanup()
    }
}
