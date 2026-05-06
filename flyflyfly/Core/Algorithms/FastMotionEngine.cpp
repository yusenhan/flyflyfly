#include "FastMotionEngine.hpp"
#include <algorithm>

double FastMotionEngine::fastDistance(CPPCoordinate c1, CPPCoordinate c2) {
    const double earthRadius = 6371000.0;
    double lat1 = c1.latitude * M_PI / 180.0;
    double lat2 = c2.latitude * M_PI / 180.0;
    double deltaLat = (c2.latitude - c1.latitude) * M_PI / 180.0;
    double deltaLon = (c2.longitude - c1.longitude) * M_PI / 180.0;

    double a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
               cos(lat1) * cos(lat2) *
               sin(deltaLon / 2.0) * sin(deltaLon / 2.0);
    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));

    return earthRadius * c;
}

CPPCoordinate FastMotionEngine::greatCircleCoordinate(CPPCoordinate start, CPPCoordinate end, double ratio) {
    double lat1 = start.latitude * M_PI / 180.0;
    double lon1 = start.longitude * M_PI / 180.0;
    double lat2 = end.latitude * M_PI / 180.0;
    double lon2 = end.longitude * M_PI / 180.0;
    
    double d = 2.0 * asin(sqrt(pow(sin((lat1 - lat2) / 2.0), 2) + cos(lat1) * cos(lat2) * pow(sin((lon1 - lon2) / 2.0), 2)));
    
    if (d < 0.00000001) return start;
    
    double a = sin((1.0 - ratio) * d) / sin(d);
    double b = sin(ratio * d) / sin(d);
    
    double x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2);
    double y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2);
    double z = a * sin(lat1) + b * sin(lat2);
    
    double lat = atan2(z, sqrt(pow(x, 2) + pow(y, 2)));
    double lon = atan2(y, x);
    
    return { lat * 180.0 / M_PI, lon * 180.0 / M_PI };
}

double FastMotionEngine::targetDistance(double traveledDistance, double routeDistance, int loopMode, bool* outOfBounds) {
    *outOfBounds = false;
    if (routeDistance <= 0) return 0;

    switch (loopMode) {
        case 2: // circular
            return fmod(traveledDistance, routeDistance);
        case 1: // pingPong
        {
            double cycleDistance = routeDistance * 2.0;
            double phase = fmod(traveledDistance, cycleDistance);
            return phase <= routeDistance ? phase : (cycleDistance - phase);
        }
        case 0: // singlePass
        default:
            if (traveledDistance >= routeDistance) {
                *outOfBounds = true;
                return routeDistance;
            }
            return traveledDistance;
    }
}

std::vector<double> FastMotionEngine::cumulativeDistances(const std::vector<CPPCoordinate>& points) {
    if (points.empty()) return {};
    if (points.size() == 1) return {0.0};

    std::vector<double> result;
    result.reserve(points.size());
    result.push_back(0.0);
    
    double total = 0;
    for (size_t i = 0; i < points.size() - 1; ++i) {
        total += fastDistance(points[i], points[i+1]);
        result.push_back(total);
    }
    return result;
}

CPPCoordinate FastMotionEngine::coordinateAtDistance(
    double targetDistance,
    const std::vector<CPPCoordinate>& points,
    const std::vector<double>& distances
) {
    if (points.size() < 2) return points.empty() ? CPPCoordinate{0,0} : points[0];
    double total = distances.back();

    if (targetDistance <= 0) return points.front();
    if (targetDistance >= total) return points.back();

    // Binary search for the segment using std::lower_bound
    auto it = std::lower_bound(distances.begin(), distances.end(), targetDistance);
    size_t upper = std::distance(distances.begin(), it);
    if (upper == 0) upper = 1;
    
    size_t lower = upper - 1;
    double segmentDistance = distances[upper] - distances[lower];
    if (segmentDistance <= 0.00000001) return points[upper];

    double ratio = (targetDistance - distances[lower]) / segmentDistance;
    if (ratio < 0) ratio = 0;
    if (ratio > 1) ratio = 1;
    
    if (segmentDistance > 500.0) {
        return greatCircleCoordinate(points[lower], points[upper], ratio);
    } else {
        double lat = points[lower].latitude + (points[upper].latitude - points[lower].latitude) * ratio;
        double lon = points[lower].longitude + (points[upper].longitude - points[lower].longitude) * ratio;
        return { lat, lon };
    }
}
