import Foundation
import CoreLocation

enum FavoriteType: String, Codable {
    case point = "定點"
    case route = "路線"
}

struct FavoriteCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(_ coord: CLLocationCoordinate2D) {
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }
}

struct FavoriteItem: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let type: FavoriteType
    let coordinates: [FavoriteCoordinate]
    let transportType: TransportType?
    let createdAt: Date
    var country: String?
    var city: String?
    
    var firstCoordinate: CLLocationCoordinate2D {
        coordinates.first?.clCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    init(id: UUID = UUID(), name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType? = nil, createdAt: Date = Date(), country: String? = nil, city: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.coordinates = coordinates.map { FavoriteCoordinate($0) }
        self.transportType = transportType
        self.createdAt = createdAt
        self.country = country
        self.city = city
    }
}

@MainActor
final class FavoriteStore: ObservableObject {
    @Published var items: [FavoriteItem] = [] {
        didSet {
            updateGroups()
        }
    }
    
    @Published private(set) var groups: [FavoriteType: [String: [String: [FavoriteItem]]]] = [:]
    
    private let storageKey = "flyflyfly.favorites.v3"
    private let v2Key = "flyflyfly.favorites.v2"
    private let legacyKey = "flyflyfly.favorites"
    
    init() {
        load()
        updateGroups()
    }
    
    private func updateGroups() {
        var newGroups: [FavoriteType: [String: [String: [FavoriteItem]]]] = [:]
        for item in items {
            let mode = item.type
            let country = item.country ?? "未知國家"
            let city = item.city ?? "未知地區"
            
            if newGroups[mode] == nil { newGroups[mode] = [:] }
            if newGroups[mode]![country] == nil { newGroups[mode]![country] = [:] }
            
            newGroups[mode]![country]![city, default: []].append(item)
        }
        self.groups = newGroups
    }
    
    func add(name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType? = nil) {
        let newItem = FavoriteItem(name: name, type: type, coordinates: coordinates, transportType: transportType)
        items.insert(newItem, at: 0)
        save()
        geocode(newItem)
    }

    func geocode(_ item: FavoriteItem) {
        guard let coord = item.coordinates.first?.clCoordinate else { return }
        
        // OSM Nominatim API (OpenStreetMap)
        let urlString = "https://nominatim.openstreetmap.org/reverse?format=json&lat=\(coord.latitude)&lon=\(coord.longitude)&zoom=10&addressdetails=1&accept-language=zh-TW"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("flyflyfly-macos-app/1.0 (Location Spoofing Tool)", forHTTPHeaderField: "User-Agent")
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(OSMNominatimResponse.self, from: data)
                
                let country = response.address.country
                let city = response.address.city ?? response.address.town ?? response.address.village ?? response.address.suburb ?? response.address.state
                
                updateItemLocation(id: item.id, country: country, city: city)
            } catch {
                print("[ERROR] OSM Geocoding failed: \(error)")
            }
        }
    }

    private func updateItemLocation(id: UUID, country: String?, city: String?) {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            self.items[index].country = country
            self.items[index].city = city
            self.save()
        }
    }
    
    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }
    
    func remove(_ item: FavoriteItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func update(_ item: FavoriteItem, withName name: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].name = name
            save()
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func load() {
        // Try loading v3
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            items = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            return
        }
        
        // Migrate from v2 (Keep geocode here to populate initial data for migration)
        if let data = UserDefaults.standard.data(forKey: v2Key),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            items = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            save()
            for item in items { geocode(item) }
            UserDefaults.standard.removeObject(forKey: v2Key)
            return
        }
        
        // Migrate from v1
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let decodedLegacy = try? JSONDecoder().decode([LegacyFavoriteLocation].self, from: legacyData) {
            items = decodedLegacy.map { legacy in
                FavoriteItem(
                    name: legacy.name,
                    type: .point,
                    coordinates: [CLLocationCoordinate2D(latitude: legacy.latitude, longitude: legacy.longitude)],
                    createdAt: legacy.createdAt
                )
            }.sorted(by: { $0.createdAt > $1.createdAt })
            save()
            for item in items { geocode(item) }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }
}

// OSM helper models
private struct OSMNominatimResponse: Codable {
    let address: OSMAddress
}

private struct OSMAddress: Codable {
    let country: String?
    let city: String?
    let town: String?
    let village: String?
    let suburb: String?
    let state: String?
}

// Helper for migration
private struct LegacyFavoriteLocation: Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
}
