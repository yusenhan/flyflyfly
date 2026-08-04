import Combine
import CoreLocation
import Foundation

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
    var useCount: Int
    var lastUsedAt: Date?
    
    var firstCoordinate: CLLocationCoordinate2D {
        coordinates.first?.clCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    init(id: UUID = UUID(), name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType? = nil, createdAt: Date = Date(), country: String? = nil, city: String? = nil, useCount: Int = 0, lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.coordinates = coordinates.map { FavoriteCoordinate($0) }
        self.transportType = transportType
        self.createdAt = createdAt
        self.country = country
        self.city = city
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, coordinates, transportType, createdAt, country, city, useCount, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(FavoriteType.self, forKey: .type)
        coordinates = try container.decode([FavoriteCoordinate].self, forKey: .coordinates)
        transportType = try container.decodeIfPresent(TransportType.self, forKey: .transportType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
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
        sortItems()
        updateGroups()
    }
    
    private func sortItems() {
        items.sort { a, b in
            if a.useCount != b.useCount {
                return a.useCount > b.useCount
            }
            let dateA = a.lastUsedAt ?? a.createdAt
            let dateB = b.lastUsedAt ?? b.createdAt
            return dateA > dateB
        }
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
        sortItems()
        save()
        geocode(newItem)
    }

    func incrementUseCount(for item: FavoriteItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].useCount += 1
            items[index].lastUsedAt = Date()
            sortItems()
            save()
        }
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
        for offset in offsets.sorted(by: >) where items.indices.contains(offset) {
            items.remove(at: offset)
        }
        save()
    }
    
    func remove(_ item: FavoriteItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func update(_ item: FavoriteItem, withName name: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].name = name
            sortItems()
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
            items = decoded
            sortItems()
            return
        }
        
        // Migrate from v2 (Keep geocode here to populate initial data for migration)
        if let data = UserDefaults.standard.data(forKey: v2Key),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            items = decoded
            sortItems()
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
            }
            sortItems()
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
