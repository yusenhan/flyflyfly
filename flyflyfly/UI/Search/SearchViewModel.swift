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
                guard let self = self else { return }
                guard !keyword.isEmpty else {
                    self.placeResults = []
                    return
                }
                
                // 如果是經緯度格式，直接進行座標解析與定位，不觸發網路地址搜尋聯想
                if self.isCoordinateFormat(keyword) {
                    self.parseCoordinateInput(keyword)
                    self.placeResults = []
                } else {
                    self.searchPlaces(currentRegion: self.mapStateStore.visibleMapRegion)
                }
            }
            .store(in: &cancellables)
    }

    // 輔助方法：判定是否為合法的經緯度格式
    func isCoordinateFormat(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    // 檢查 macOS 剪貼簿是否含有座標
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard let clipboardString = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            self.detectedClipboardCoordinate = nil
            return
        }
        
        // 使用正則匹配經緯度
        let pattern = #"^(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let _ = regex.firstMatch(in: clipboardString, range: NSRange(clipboardString.startIndex..., in: clipboardString)) {
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
        let pattern = #"^(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: clip, range: NSRange(clip.startIndex..., in: clip)) {
            
            let latStr = (clip as NSString).substring(with: match.range(at: 1))
            let lonStr = (clip as NSString).substring(with: match.range(at: 2))
            
            if let lat = Double(latStr), let lon = Double(lonStr) {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if CLLocationCoordinate2DIsValid(coord) {
                    insertPoint(coord)
                    // 將 placeKeyword 設為座標以回饋用戶
                    placeKeyword = clip
                    detectedClipboardCoordinate = nil
                }
            }
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

    func parseCoordinateInput(_ input: String) {
        locationInputError = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let pattern = #"^(?i)(-?\d{1,3}(?:\.\d+)?)\s*[,，\s]\s*(-?\d{1,3}(?:\.\d+)?)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            
            let latStr = (trimmed as NSString).substring(with: match.range(at: 1))
            let lonStr = (trimmed as NSString).substring(with: match.range(at: 2))
            
            if let lat = Double(latStr), let lon = Double(lonStr) {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if CLLocationCoordinate2DIsValid(coord) {
                    insertPoint(coord)
                    locationInputError = nil
                    return
                }
            }
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
