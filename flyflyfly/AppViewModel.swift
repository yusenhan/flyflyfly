import SwiftUI
import MapKit
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Core Dependencies
    let deviceStore: DeviceStore
    let mapStateStore: MapStateStore
    let simulationStore: SimulationStore
    let locationSearchService: LocationSearchService
    
    var deviceManager: DeviceManager { deviceStore.deviceManager as! DeviceManager }
    var favoriteStore = FavoriteStore()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published States
    @Published var isSearching = false
    @Published var placeKeyword = ""
    @Published var coordinateInputText = ""
    @Published var locationInputError: String? = nil
    @Published var isShowingRouteReplacementConfirmation = false
    @Published var showingNewRouteConfirmation = false
    var requestCameraPosition: ((MKCoordinateRegion) -> Void)? = nil
    var developerModeDisabled: Bool { deviceManager.developerModeDisabled }
    var placeResults: [MKLocalSearchCompletion] { locationSearchService.completions }

    // MARK: - Delegation (MapStateStore)
    var appState: AppState { get { mapStateStore.appState } set { mapStateStore.appState = newValue } }
    var operationMode: OperationMode { get { mapStateStore.operationMode } set { mapStateStore.operationMode = newValue } }
    var transportType: TransportType { get { mapStateStore.transportType } set { mapStateStore.transportType = newValue } }
    var pointA: CLLocationCoordinate2D? { get { mapStateStore.pointA } set { mapStateStore.pointA = newValue } }
    var pointB: CLLocationCoordinate2D? { get { mapStateStore.pointB } set { mapStateStore.pointB = newValue } }
    var tempCoordinate: CLLocationCoordinate2D? { get { mapStateStore.tempCoordinate } set { mapStateStore.tempCoordinate = newValue } }
    var waypoints: [CLLocationCoordinate2D] { get { mapStateStore.waypoints } set { mapStateStore.waypoints = newValue } }
    var routes: [MKRoute] { get { mapStateStore.routes } set { mapStateStore.routes = newValue } }
    var selectedRouteIndex: Int { get { mapStateStore.selectedRouteIndex } set { mapStateStore.selectedRouteIndex = newValue } }
    var mapRegion: MKCoordinateRegion { get { mapStateStore.mapRegion } set { mapStateStore.mapRegion = newValue } }
    var visibleMapRegion: MKCoordinateRegion { get { mapStateStore.visibleMapRegion } set { mapStateStore.visibleMapRegion = newValue } }
    var customRoutePolyline: MKPolyline? { mapStateStore.customRoutePolyline }

    // Simulation Delegation
    var speed: Double { get { simulationStore.speed } set { simulationStore.speed = newValue } }
    var isEndlessLoop: Bool { get { simulationStore.isEndlessLoop } set { simulationStore.isEndlessLoop = newValue } }
    var isClosedLoop: Bool { get { simulationStore.isClosedLoop } set { simulationStore.isClosedLoop = newValue } }
    var currentPosition: CLLocationCoordinate2D? { simulationStore.currentPosition }
    var totalRouteDistance: Double { simulationStore.totalRouteDistance }
    var traveledDistance: Double { simulationStore.traveledDistance }
    var isActiveSimulationRunning: Bool { simulationStore.isActiveSimulationRunning }
    var activeRoutePolyline: MKPolyline? { simulationStore.activeRoutePolyline }
    var activeOperationMode: OperationMode? { simulationStore.activeOperationMode }

    // MARK: - Initialization
    init(deviceManager: DeviceManager, locationSearchService: LocationSearchService) {
        self.deviceStore = DeviceStore(deviceManager: deviceManager)
        self.mapStateStore = MapStateStore()
        self.simulationStore = SimulationStore(deviceManager: deviceManager)
        self.locationSearchService = locationSearchService
        setupObservers()
    }

    private func setupObservers() {
        deviceStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        mapStateStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        simulationStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        LanguageManager.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - UI Localization
    var buttonTitle: String {
        let key: String
        if !deviceManager.isConnected && (hasReadyDraft || hasActiveRouteSnapshot) { key = "Connect Device First" }
        else if shouldUseDraftControls {
            if hasActiveRouteSnapshot && hasReadyDraft { key = "Start New Route" }
            else { return NSLocalizedString(draftButtonKey, comment: "") }
        } else {
            key = isActiveSimulationRunning ? "Stop Simulation" : "Resume Simulation"
        }
        return NSLocalizedString(key, comment: "")
    }
    
    private var draftButtonKey: String {
        if operationMode == .fixedPoint {
            switch appState {
            case .selectingA, .confirmingA: return "Select Location Point"
            case .readyToMove: return "Start Positioning"
            case .moving: return "Set Location"
            default: return "Start Positioning"
            }
        }
        if operationMode == .multiPoint && appState == .selectingA {
            return waypoints.count >= 2 ? "Complete and Calculate" : "Select at least 2 points"
        }
        switch appState {
        case .selectingA: return "Select Start"
        case .selectingB: return "Select End"
        case .confirmingA, .confirmingB: return "Confirm Position"
        case .routeSelection, .readyToMove, .calculatingRoute: return "Start Movement"
        case .moving: return "Stop Simulation"
        default: return "Start Simulation"
        }
    }

    var resetButtonTitle: String {
        let key = hasActiveRouteSnapshot ? "Clear Draft" : (operationMode == .fixedPoint ? "Clear Point" : "Clear Route")
        return NSLocalizedString(key, comment: "")
    }

    var activityNotice: String? {
        if hasActiveRouteSnapshot && hasDraftEdits { return NSLocalizedString("Simulation running notice", comment: "") }
        if hasActiveRouteSnapshot && !isActiveSimulationRunning { return NSLocalizedString("Simulation fixed notice", comment: "") }
        return nil
    }

    var estimatedTime: String {
        let dist = selectedRoute?.distance ?? (mapStateStore.draftTotalRouteDistance > 0 ? mapStateStore.draftTotalRouteDistance : totalRouteDistance)
        guard dist > 0 else { return "--" }
        let sec = dist / (speed * (1000.0 / 3600.0))
        return "\(Int(sec)/60):\(String(format: "%02d", Int(sec)%60))"
    }

    var progressPercentage: String? {
        guard isActiveSimulationRunning, totalRouteDistance > 0 else { return nil }
        return String(format: "%.1f%%", min(traveledDistance / totalRouteDistance, 1.0) * 100)
    }

    // MARK: - Logic Helpers
    var hasActiveRouteSnapshot: Bool { activeRoutePolyline != nil || (simulationStore.activeOperationMode == .fixedPoint && currentPosition != nil) }
    var hasDraftEdits: Bool { appState != .selectingA || pointA != nil || pointB != nil || !waypoints.isEmpty || tempCoordinate != nil }
    var hasReadyDraft: Bool { operationMode == .fixedPoint ? pointA != nil : (!mapStateStore.draftRoutePoints.isEmpty || !routes.isEmpty) }
    var shouldUseDraftControls: Bool { !hasActiveRouteSnapshot || hasDraftEdits }
    var shouldShowResetButton: Bool { hasDraftEdits }
    var isMainActionDisabled: Bool {
        if !deviceManager.isConnected { return true }
        if shouldUseDraftControls {
            if operationMode == .multiPoint && appState == .selectingA { return waypoints.count < 2 }
            return appState == .selectingA || appState == .selectingB
        }
        return false
    }
    var isMainActionDestructive: Bool { !shouldUseDraftControls && isActiveSimulationRunning }
    var pinnedCoordinate: CLLocationCoordinate2D? { currentPosition ?? simulationStore.lastSentPosition }
    var selectedRoute: MKRoute? { routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : routes.first }
    var maximumSpeed: Double { AppConstants.Simulation.maximumSpeed }

    // MARK: - UI Handlers
    func handleMainAction() {
        if shouldUseDraftControls {
            if hasActiveRouteSnapshot && hasReadyDraft { isShowingRouteReplacementConfirmation = true; return }
            startIfReadyAndConnected()
        } else {
            if isActiveSimulationRunning { simulationStore.stopSimulation() }
            else { simulationStore.startSimulation() }
        }
    }
    func startIfReadyAndConnected() { simulationStore.startSimulation() }
    func resetAll() {
        pointA = nil; pointB = nil; waypoints = []; routes = []; selectedRouteIndex = 0; tempCoordinate = nil; appState = .selectingA
    }
    func recalculateRoute() { /* logic */ }
    func switchModePreservingPinnedLocation() { /* logic */ }
    func handleMapTap(at coord: CLLocationCoordinate2D) { /* logic */ }
    func handleMapDoubleTap(at coord: CLLocationCoordinate2D) { /* logic */ }
    func handleDeviceDisconnected() { deviceStore.disconnect() }
    func handleScenePhaseChange(_ phase: ScenePhase) { /* implementation */ }
    func handlePlaceKeywordChange(_ val: String) { locationSearchService.updateQuery(val, region: mapRegion) }
    func searchPlaces(currentRegion: MKCoordinateRegion?) {
        isSearching = true
        Task {
            do {
                let items = try await locationSearchService.search(for: placeKeyword, region: currentRegion ?? mapRegion)
                // Need to store items somewhere or assign to placeResults
                isSearching = false
            } catch {
                isSearching = false
            }
        }
    }
    func selectCompletion(_ completion: MKLocalSearchCompletion) {
        placeKeyword = completion.title
        searchPlaces(currentRegion: mapRegion)
    }
    func selectSearchItem(_ item: MKMapItem) {
        pointA = item.placemark.coordinate; appState = .confirmingA
    }
    func insertCoordinateFromInput() { /* logic */ }
    func normalizeMapRegion(_ r: MKCoordinateRegion) -> MKCoordinateRegion { r }
    func mapRegion(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion { mapRegion }
    func confirmNewRoute() { isShowingRouteReplacementConfirmation = false; startIfReadyAndConnected() }
    func cancelNewRoute() { isShowingRouteReplacementConfirmation = false }
    func cancelRouteReplacement() { isShowingRouteReplacementConfirmation = false }
    func confirmRouteReplacement() { confirmNewRoute() }
    func cleanup() { simulationStore.stopSimulation() }
    func addToFavorites(name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType?) {
        favoriteStore.add(name: name, type: type, coordinates: coordinates, transportType: transportType)
    }
    func selectFavorite(_ item: FavoriteItem) {
        pointA = item.firstCoordinate; operationMode = item.type == .point ? .fixedPoint : .routeAB; appState = .confirmingA
    }
    
    // UI Stub Helpers
    func searchResultSubtitle(for completion: MKLocalSearchCompletion) -> String { completion.subtitle }
    func searchResultSubtitle(for item: MKMapItem) -> String { item.placemark.title ?? "" }
    func searchResultDistanceText(for item: MKMapItem, cameraRegion: MKCoordinateRegion?) -> String? { nil }

    var dependencyVersion: String { "1.11.0" }
}
