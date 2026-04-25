import Foundation
import MapKit

enum RouteMotionEngine {
    enum LoopMode {
        case singlePass
        case pingPong
        case circular
    }

    /// Fast Haversine distance calculation to avoid CLLocation object allocation overhead.
    /// Returns distance in meters.
    static func fastDistance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0 // meters
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let deltaLat = (c2.latitude - c1.latitude) * .pi / 180.0
        let deltaLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))

        return earthRadius * c
    }

    static func greatCircleCoordinate(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, ratio: Double) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        let lat2 = end.latitude * .pi / 180.0
        let lon2 = end.longitude * .pi / 180.0
        
        let d = 2.0 * asin(sqrt(pow(sin((lat1 - lat2) / 2.0), 2) + cos(lat1) * cos(lat2) * pow(sin((lon1 - lon2) / 2.0), 2)))
        
        if d == 0 { return start }
        
        let a = sin((1.0 - ratio) * d) / sin(d)
        let b = sin(ratio * d) / sin(d)
        
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        
        let lat = atan2(z, sqrt(pow(x, 2) + pow(y, 2)))
        let lon = atan2(y, x)
        
        return CLLocationCoordinate2D(latitude: lat * 180.0 / .pi, longitude: lon * 180.0 / .pi)
    }

    static func targetDistance(traveledDistance: Double, routeDistance: Double, loopMode: LoopMode) -> Double? {
        guard routeDistance > 0 else { return nil }

        switch loopMode {
        case .circular:
            return traveledDistance.truncatingRemainder(dividingBy: routeDistance)
        case .pingPong:
            let cycleDistance = routeDistance * 2.0
            let phase = traveledDistance.truncatingRemainder(dividingBy: cycleDistance)
            return phase <= routeDistance ? phase : (cycleDistance - phase)
        case .singlePass:
            guard traveledDistance <= routeDistance else { return nil }
            return traveledDistance
        }
    }

    static func coordinate(
        at targetDistance: Double,
        in points: [CLLocationCoordinate2D],
        distances: [Double]
    ) -> CLLocationCoordinate2D? {
        guard points.count >= 2, distances.count == points.count else { return points.first }
        guard let total = distances.last else { return points.first }

        if targetDistance <= 0 { return points.first }
        if targetDistance >= total { return points.last }

        // Binary search for the segment
        var low = 0
        var high = distances.count - 1
        while low < high {
            let mid = (low + high) / 2
            if distances[mid] < targetDistance {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let upper = max(1, low)
        let lower = upper - 1
        let segmentDistance = distances[upper] - distances[lower]
        if segmentDistance <= 0 { return points[upper] }

        let ratio = max(0, min(1, (targetDistance - distances[lower]) / segmentDistance))
        
        if segmentDistance > 500.0 { // Use Great Circle for segments > 500m
            return greatCircleCoordinate(from: points[lower], to: points[upper], ratio: ratio)
        } else {
            // Linear interpolation is sufficient for small segments in GPS spoofing
            let lat = points[lower].latitude + (points[upper].latitude - points[lower].latitude) * ratio
            let lon = points[lower].longitude + (points[upper].longitude - points[lower].longitude) * ratio
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    static func cumulativeDistances(for points: [CLLocationCoordinate2D]) -> [Double] {
        guard !points.isEmpty else { return [] }
        if points.count == 1 { return [0] }

        var result = [Double]()
        result.reserveCapacity(points.count)
        result.append(0.0)
        
        var total: Double = 0
        for i in 0..<(points.count - 1) {
            total += fastDistance(from: points[i], to: points[i + 1])
            result.append(total)
        }
        return result
    }
}
