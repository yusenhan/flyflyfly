import Foundation
import MapKit
import Combine

@MainActor
final class MapStateStore: ObservableObject {
    // MARK: - Draft workflow state
    @Published var appState: AppState = .selectingA
    @Published var operationMode: OperationMode = .fixedPoint
    @Published var pendingModeSwitch: OperationMode?

    @Published var pointA: CLLocationCoordinate2D?
    @Published var pointB: CLLocationCoordinate2D?
    @Published var tempCoordinate: CLLocationCoordinate2D?
    @Published var waypoints: [CLLocationCoordinate2D] = []
    @Published var customRoutePolyline: MKPolyline?
    @Published var routes: [MKRoute] = []
    @Published var selectedRouteIndex: Int = 0
    @Published var transportType: TransportType = .walking
    @Published var draftRoutePoints: [CLLocationCoordinate2D] = []
    @Published var draftCumulativeRouteDistances: [Double] = []
    @Published var draftTotalRouteDistance: Double = 0.0

    // MARK: - Map camera / view state
    @Published var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: AppConstants.Map.defaultLatitude, longitude: AppConstants.Map.defaultLongitude),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var visibleMapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: AppConstants.Map.defaultLatitude, longitude: AppConstants.Map.defaultLongitude),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var requestCameraPosition: ((MKCoordinateRegion) -> Void)?
    
    // MARK: - Search results (UI state)
    @Published var placeKeyword: String = ""
    @Published var placeResults: [MKMapItem] = []
    @Published var coordinateInputText: String = ""
    @Published var locationInputError: String?
}
