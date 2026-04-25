import Foundation
import Combine
import MapKit
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    // Dependencies
    private let mapStateStore: MapStateStore
    private let locationSearchService: any LocationSearching
    private weak var appViewModel: AppViewModel?
    
    @Published var isSearching: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    
    var placeKeyword: String {
        get { mapStateStore.placeKeyword }
        set { mapStateStore.placeKeyword = newValue }
    }
    
    var placeResults: [MKMapItem] {
        get { mapStateStore.placeResults }
        set { mapStateStore.placeResults = newValue }
    }
    
    var coordinateInputText: String {
        get { mapStateStore.coordinateInputText }
        set { mapStateStore.coordinateInputText = newValue }
    }
    
    var locationInputError: String? {
        get { mapStateStore.locationInputError }
        set { mapStateStore.locationInputError = newValue }
    }

    init(mapStateStore: MapStateStore, locationSearchService: any LocationSearching) {
        self.mapStateStore = mapStateStore
        self.locationSearchService = locationSearchService
        
        setupSearchDebounce()
    }
    
    func setAppViewModel(_ vm: AppViewModel) {
        self.appViewModel = vm
    }
    
    private func setupSearchDebounce() {
        mapStateStore.$placeKeyword
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] keyword in
                guard !keyword.isEmpty else {
                    self?.placeResults = []
                    return
                }
                self?.searchPlaces(currentRegion: self?.mapStateStore.visibleMapRegion)
            }
            .store(in: &cancellables)
    }

    func searchPlaces(currentRegion: MKCoordinateRegion?) {
        let keyword = placeKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        if let region = currentRegion {
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSearching = false
                if let items = response?.mapItems {
                    self.placeResults = items
                }
            }
        }
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) {
        isSearching = true
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSearching = false
                if let item = response?.mapItems.first {
                    self.selectSearchItem(item)
                }
            }
        }
    }

    func selectSearchItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        placeKeyword = item.name ?? ""
        placeResults = []
        locationSearchService.completions = [] 
        insertPoint(coord)
    }

    func coordinate(for item: MKMapItem) -> CLLocationCoordinate2D? {
        item.placemark.coordinate
    }

    func insertPoint(_ coordinate: CLLocationCoordinate2D) {
        appViewModel?.handleMapTap(at: coordinate)
        if appViewModel?.appState == .confirmingA || appViewModel?.appState == .confirmingB {
            appViewModel?.confirmTempCoordinate()
        }
    }

    func insertCoordinateFromInput() {
        parseCoordinateInput()
    }

    func searchResultSubtitle(for item: MKMapItem) -> String {
        item.placemark.fullAddress ?? ""
    }

    func searchResultDistanceText(for item: MKMapItem, cameraRegion: MKCoordinateRegion?) -> String? {
        guard let center = cameraRegion?.center else { return nil }
        let dist = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
        if dist < 1000 {
            return String(format: "%.0f m", dist)
        } else {
            return String(format: "%.1f km", dist / 1000.0)
        }
    }

    func parseCoordinateInput() {
        locationInputError = nil
        let input = coordinateInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        let pattern = #"(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
            
            let latStr = (input as NSString).substring(with: match.range(at: 1))
            let lonStr = (input as NSString).substring(with: match.range(at: 2))
            
            if let lat = Double(latStr), let lon = Double(lonStr) {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if CLLocationCoordinate2DIsValid(coord) {
                    insertPoint(coord)
                    coordinateInputText = ""
                    return
                }
            }
        }
        
        locationInputError = "無法辨識座標。格式參考：25.033, 121.565"
    }
}
