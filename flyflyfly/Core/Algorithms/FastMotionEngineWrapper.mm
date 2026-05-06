#import "FastMotionEngineWrapper.h"
#include "FastMotionEngine.hpp"
#include "SpatialIndex.hpp"
#include "NativeTunnel.hpp"

@implementation FastMotionEngineWrapper {
    SpatialIndex *_spatialIndex;
    NativeTunnel *_nativeTunnel;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _spatialIndex = new SpatialIndex();
        _nativeTunnel = new NativeTunnel();
    }
    return self;
}

- (void)dealloc {
    delete _spatialIndex;
    delete _nativeTunnel;
}

// --- Phase 1: Motion ---

+ (double)fastDistanceBetween:(CLLocationCoordinate2D)c1 and:(CLLocationCoordinate2D)c2 {
    return FastMotionEngine::fastDistance({c1.latitude, c1.longitude}, {c2.latitude, c2.longitude});
}

+ (CLLocationCoordinate2D)greatCircleCoordinateFrom:(CLLocationCoordinate2D)start 
                                                 to:(CLLocationCoordinate2D)end 
                                              ratio:(double)ratio {
    CPPCoordinate res = FastMotionEngine::greatCircleCoordinate({start.latitude, start.longitude}, {end.latitude, end.longitude}, ratio);
    return CLLocationCoordinate2DMake(res.latitude, res.longitude);
}

+ (double)targetDistanceForTraveled:(double)traveled 
                              total:(double)total 
                           loopMode:(int)loopMode 
                        outOfBounds:(BOOL *)outOfBounds {
    bool oob = false;
    double res = FastMotionEngine::targetDistance(traveled, total, loopMode, &oob);
    *outOfBounds = oob;
    return res;
}

+ (NSArray<NSNumber *> *)cumulativeDistancesForPoints:(NSArray<NSValue *> *)points {
    std::vector<CPPCoordinate> cppPoints;
    cppPoints.reserve(points.count);
    for (NSValue *val in points) {
        CLLocationCoordinate2D coord;
        [val getValue:&coord];
        cppPoints.push_back({coord.latitude, coord.longitude});
    }
    std::vector<double> dists = FastMotionEngine::cumulativeDistances(cppPoints);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:dists.size()];
    for (double d : dists) {
        [result addObject:@(d)];
    }
    return result;
}

+ (CLLocationCoordinate2D)coordinateAtDistance:(double)targetDistance 
                                      inPoints:(NSArray<NSValue *> *)points 
                                     distances:(NSArray<NSNumber *> *)distances {
    std::vector<CPPCoordinate> cppPoints;
    cppPoints.reserve(points.count);
    for (NSValue *val in points) {
        CLLocationCoordinate2D coord;
        [val getValue:&coord];
        cppPoints.push_back({coord.latitude, coord.longitude});
    }
    std::vector<double> cppDists;
    cppDists.reserve(distances.count);
    for (NSNumber *n in distances) {
        cppDists.push_back(n.doubleValue);
    }
    CPPCoordinate res = FastMotionEngine::coordinateAtDistance(targetDistance, cppPoints, cppDists);
    return CLLocationCoordinate2DMake(res.latitude, res.longitude);
}

// --- Phase 2: Spatial Index ---

- (void)buildSpatialIndexWithPoints:(NSArray<NSValue *> *)points {
    std::vector<CPPCoordinate> cppPoints;
    cppPoints.reserve(points.count);
    for (NSValue *val in points) {
        CLLocationCoordinate2D coord;
        [val getValue:&coord];
        cppPoints.push_back({coord.latitude, coord.longitude});
    }
    _spatialIndex->build(cppPoints);
}

- (NSArray<NSNumber *> *)searchPointsInRectMinLat:(double)minLat maxLat:(double)maxLat minLon:(double)minLon maxLon:(double)maxLon {
    std::vector<uint32_t> indices = _spatialIndex->search({minLat, maxLat, minLon, maxLon});
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:indices.size()];
    for (uint32_t idx : indices) {
        [result addObject:@(idx)];
    }
    return result;
}

- (NSInteger)spatialPointCount {
    return (NSInteger)_spatialIndex->count();
}

// --- Phase 3: Native Tunnel ---

- (BOOL)connectToHost:(NSString *)host port:(int)port {
    return _nativeTunnel->connect_to_tunnel(host.UTF8String, port);
}

- (void)disconnectNativeTunnel {
    _nativeTunnel->disconnect();
}

- (BOOL)sendNativeCoordinateLat:(double)lat lon:(double)lon {
    return _nativeTunnel->send_coordinate(lat, lon);
}

- (BOOL)isNativeTunnelConnected {
    return _nativeTunnel->is_connected();
}

@end
