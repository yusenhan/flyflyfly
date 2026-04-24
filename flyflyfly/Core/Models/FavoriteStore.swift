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
    @Published var items: [FavoriteItem] = []
    
    // Legacy storage keys for migration
    private let storageKey = "flyflyfly.favorites.v3"
    private let v2Key = "flyflyfly.favorites.v2"
    private let legacyKey = "flyflyfly.favorites"
    
    // New File System storage
    private var saveDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".flyflyfly", isDirectory: true)
    }
    
    private var saveFile: URL {
        saveDirectory.appendingPathComponent("flyflyfly.plist")
    }
    
    init() {
        load()
    }
    
    func add(name: String, type: FavoriteType, coordinates: [CLLocationCoordinate2D], transportType: TransportType? = nil) {
        let newItem = FavoriteItem(name: name, type: type, coordinates: coordinates, transportType: transportType)
        items.insert(newItem, at: 0)
        save()
        geocode(newItem)
    }

    func geocode(_ item: FavoriteItem) {
        guard let coord = item.coordinates.first?.clCoordinate else { return }
        
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
                
                await updateItemLocation(id: item.id, country: country, city: city)
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
    
    /// 導出所有我的最愛為 JSON 檔案
    /// - Returns: 導出檔案的路徑 URL
    func exportAll() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "flyflyfly-\(timestamp).json"
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let targetURL = downloadsDir.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: targetURL, options: .atomic)
            print("[INFO] Favorites exported to \(targetURL.path)")
            return targetURL
        } catch {
            print("[ERROR] Failed to export favorites: \(error)")
            return nil
        }
    }
    
    private func save() {
        do {
            if !FileManager.default.fileExists(atPath: saveDirectory.path) {
                try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            }
            
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml // Human readable plist
            let data = try encoder.encode(items)
            try data.write(to: saveFile, options: .atomic)
            print("[INFO] Favorites saved to \(saveFile.path)")
        } catch {
            print("[ERROR] Failed to save favorites: \(error)")
        }
    }
    
    private func load() {
        // 1. Try loading from new File System location
        if FileManager.default.fileExists(atPath: saveFile.path) {
            do {
                let data = try Data(contentsOf: saveFile)
                let decoder = PropertyListDecoder()
                items = try decoder.decode([FavoriteItem].self, from: data).sorted(by: { $0.createdAt > $1.createdAt })
                print("[INFO] Favorites loaded from File System")
                return
            } catch {
                print("[ERROR] Failed to load from File System: \(error)")
            }
        }
        
        // 2. Migration: Try loading v3 from UserDefaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            items = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            save()
            UserDefaults.standard.removeObject(forKey: storageKey)
            print("[INFO] Migrated favorites from UserDefaults v3 to File System")
            return
        }
        
        // 3. Migration: Migrate from v2
        if let data = UserDefaults.standard.data(forKey: v2Key),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            items = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            save()
            for item in items { geocode(item) }
            UserDefaults.standard.removeObject(forKey: v2Key)
            print("[INFO] Migrated favorites from UserDefaults v2 to File System")
            return
        }
        
        // 4. Migration: Migrate from v1
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
            print("[INFO] Migrated favorites from UserDefaults legacy to File System")
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
