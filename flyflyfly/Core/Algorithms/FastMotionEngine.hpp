#ifndef FastMotionEngine_hpp
#define FastMotionEngine_hpp

#ifdef __cplusplus
#include <vector>
#include <cmath>

struct CPPCoordinate {
    double latitude;
    double longitude;
};

class FastMotionEngine {
public:
    /// Fast Haversine distance calculation
    static double fastDistance(CPPCoordinate c1, CPPCoordinate c2);

    /// Great Circle (Slerp) interpolation
    static CPPCoordinate greatCircleCoordinate(CPPCoordinate start, CPPCoordinate end, double ratio);

    /// Calculate target distance based on loop mode
    /// 0: singlePass, 1: pingPong, 2: circular
    static double targetDistance(double traveledDistance, double routeDistance, int loopMode, bool* outOfBounds);

    /// Batch calculate cumulative distances for a path
    static std::vector<double> cumulativeDistances(const std::vector<CPPCoordinate>& points);

    /// Core logic: find coordinate at specific distance along the path
    static CPPCoordinate coordinateAtDistance(
        double targetDistance,
        const std::vector<CPPCoordinate>& points,
        const std::vector<double>& distances
    );
};
#endif

#endif /* FastMotionEngine_hpp */
