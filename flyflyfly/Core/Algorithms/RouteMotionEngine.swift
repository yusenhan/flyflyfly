import Foundation
import MapKit

enum RouteMotionEngine {
    enum LoopMode {
        case singlePass
        case pingPong
        case circular
        
        var cppValue: Int32 {
            switch self {
            case .singlePass: return 0
            case .pingPong:   return 1
            case .circular:   return 2
            }
        }
    }

    /// Fast Haversine distance calculation.
    static func fastDistance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        return FastMotionEngineWrapper.fastDistanceBetween(c1, and: c2)
    }

    static func greatCircleCoordinate(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, ratio: Double) -> CLLocationCoordinate2D {
        return FastMotionEngineWrapper.greatCircleCoordinate(from: start, to: end, ratio: ratio)
    }

    static func targetDistance(traveledDistance: Double, routeDistance: Double, loopMode: LoopMode) -> Double? {
        var outOfBounds: ObjCBool = false
        let dist = FastMotionEngineWrapper.targetDistance(forTraveled: traveledDistance, total: routeDistance, loopMode: loopMode.cppValue, outOfBounds: &outOfBounds)
        if outOfBounds.boolValue && loopMode == .singlePass {
            return nil
        }
        return dist
    }

    static func coordinate(
        at targetDistance: Double,
        in points: [CLLocationCoordinate2D],
        distances: [Double]
    ) -> CLLocationCoordinate2D? {
        guard points.count >= 2, distances.count == points.count else { return points.first }
        
        let nsPoints = points.map { NSValue(mkCoordinate: $0) }
        let nsDistances = distances.map { NSNumber(value: $0) }
        
        return FastMotionEngineWrapper.coordinate(atDistance: targetDistance, inPoints: nsPoints, distances: nsDistances)
    }

    static func cumulativeDistances(for points: [CLLocationCoordinate2D]) -> [Double] {
        guard !points.isEmpty else { return [] }
        let nsPoints = points.map { NSValue(mkCoordinate: $0) }
        let res = FastMotionEngineWrapper.cumulativeDistances(forPoints: nsPoints)
        return res.map { $0.doubleValue }
    }
}
