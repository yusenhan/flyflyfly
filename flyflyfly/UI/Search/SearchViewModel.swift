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
    @Published var detectedClipboardCoordinate: String? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var searchTask: Task<Void, Never>?
    
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

    var completions: [MKLocalSearchCompletion] {
        locationSearchService.completions
    }

    var completerError: String? {
        locationSearchService.completerError
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
        locationSearchService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        mapStateStore.$placeKeyword
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] keyword in
                guard let self = self else { return }
                guard !keyword.isEmpty else {
                    self.placeResults = []
                    self.locationSearchService.clearSuggestions()
                    return
                }
                
                // 如果是經緯度格式，直接進行座標解析與定位，不觸發網路地址搜尋聯想
                if self.isCoordinateFormat(keyword) {
                    self.parseCoordinateInput(keyword)
                    self.placeResults = []
                    self.locationSearchService.clearSuggestions()
                } else {
                    self.locationSearchService.updateQuery(keyword, region: self.mapStateStore.visibleMapRegion)
                    self.searchPlaces(currentRegion: self.mapStateStore.visibleMapRegion)
                }
            }
            .store(in: &cancellables)
    }

    // 輔助方法：判定是否為合法的經緯度格式
    func isCoordinateFormat(_ text: String) -> Bool {
        CoordinateParser.isCoordinateLike(text)
    }

    // 檢查 macOS 剪貼簿是否含有座標
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard let clipboardString = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            self.detectedClipboardCoordinate = nil
            return
        }
        
        if CoordinateParser.isCoordinateLike(clipboardString) {
            // 這是一個合法的經緯度格式，且它不等於我們目前的搜尋關鍵字，避免重複提示
            if clipboardString != placeKeyword {
                self.detectedClipboardCoordinate = clipboardString
            } else {
                self.detectedClipboardCoordinate = nil
            }
        } else {
            self.detectedClipboardCoordinate = nil
        }
    }

    // 從剪貼簿載入並定位座標
    func loadFromClipboard() {
        guard let clip = detectedClipboardCoordinate else { return }
        if let coordinate = CoordinateParser.parse(clip) {
            insertPoint(coordinate)
            // 將 placeKeyword 設為座標以回饋用戶
            placeKeyword = clip
            detectedClipboardCoordinate = nil
        }
    }

    func searchPlaces(currentRegion: MKCoordinateRegion?) {
        let keyword = placeKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        // 優先判定是否為經緯度，若是則直接定位並跳過網路地址搜尋聯想
        if isCoordinateFormat(keyword) {
            parseCoordinateInput(keyword)
            placeResults = []
            return
        }
        
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearching = true
            do {
                let items = try await self.locationSearchService.search(for: keyword, region: currentRegion)
                guard !Task.isCancelled else { return }
                self.isSearching = false
                self.placeResults = items
            } catch {
                guard !Task.isCancelled else { return }
                self.isSearching = false
                self.placeResults = []
            }
        }
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearching = true
            do {
                let items = try await self.locationSearchService.search(
                    for: completion,
                    region: self.mapStateStore.visibleMapRegion
                )
                guard !Task.isCancelled else { return }
                self.isSearching = false
                if let item = items.first {
                    self.selectSearchItem(item)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isSearching = false
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

    func parseCoordinateInput(_ input: String) {
        locationInputError = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if let coordinate = CoordinateParser.parse(trimmed) {
            insertPoint(coordinate)
            locationInputError = nil
            return
        }
        
        locationInputError = "無法辨識座標。格式參考：25.033, 121.565"
    }

    func parseCoordinateInput() {
        let inputToParse = coordinateInputText.isEmpty ? placeKeyword : coordinateInputText
        parseCoordinateInput(inputToParse)
        if locationInputError == nil {
            coordinateInputText = ""
        }
    }
}
