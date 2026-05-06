import Foundation
import MapKit
import CoreLocation

// MARK: - CityContext
public enum CityContext {
    case automatic
}

// MARK: - AddressRepresentations
public struct AddressRepresentations {
    private let placemark: CLPlacemark

    init(placemark: CLPlacemark) {
        self.placemark = placemark
    }

    public func fullAddress(includingRegion: Bool, singleLine: Bool) -> String? {
        let components = [
            placemark.country,
            includingRegion ? placemark.administrativeArea : nil,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ].compactMap { $0 }
        
        guard !components.isEmpty else { return nil }
        return components.joined(separator: singleLine ? " " : "\n")
    }

    public func cityWithContext(_ context: CityContext) -> String? {
        return placemark.locality ?? placemark.administrativeArea
    }
}

// MARK: - MKMapItem Extensions
extension MKMapItem {
    public convenience init(location: CLLocation, address: String?) {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        self.init(placemark: placemark)
    }

    public var location: CLLocation {
        return placemark.location ?? CLLocation(latitude: 0, longitude: 0)
    }

    public var address: CLPlacemark? {
        return placemark
    }

    public var addressRepresentations: AddressRepresentations? {
        return AddressRepresentations(placemark: placemark)
    }
}

extension MKPolyline {
    public var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - CLPlacemark Extensions
extension CLPlacemark {
    public var shortAddress: String? {
        let components = [
            thoroughfare,
            subThoroughfare
        ].compactMap { $0 }
        
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    public var fullAddress: String? {
        let components = [
            locality,
            subLocality,
            thoroughfare,
            subThoroughfare
        ].compactMap { $0 }
        
        return components.isEmpty ? nil : components.joined(separator: " ")
    }
}
