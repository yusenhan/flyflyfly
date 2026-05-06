#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FastMotionEngineWrapper : NSObject

// --- Phase 1: Motion (Static) ---
+ (double)fastDistanceBetween:(CLLocationCoordinate2D)c1 and:(CLLocationCoordinate2D)c2;
+ (CLLocationCoordinate2D)greatCircleCoordinateFrom:(CLLocationCoordinate2D)start 
                                                 to:(CLLocationCoordinate2D)end 
                                              ratio:(double)ratio;
+ (double)targetDistanceForTraveled:(double)traveled 
                              total:(double)total 
                           loopMode:(int)loopMode 
                        outOfBounds:(BOOL *)outOfBounds;
+ (NSArray<NSNumber *> *)cumulativeDistancesForPoints:(NSArray<NSValue *> *)points;
+ (CLLocationCoordinate2D)coordinateAtDistance:(double)targetDistance 
                                      inPoints:(NSArray<NSValue *> *)points 
                                     distances:(NSArray<NSNumber *> *)distances;

// --- Phase 2: Spatial Index (Instance) ---
- (void)buildSpatialIndexWithPoints:(NSArray<NSValue *> *)points;
- (NSArray<NSNumber *> *)searchPointsInRectMinLat:(double)minLat maxLat:(double)maxLat minLon:(double)minLon maxLon:(double)maxLon;
- (NSInteger)spatialPointCount;

// --- Phase 3: Native Tunnel (Instance) ---
- (BOOL)connectToHost:(NSString *)host port:(int)port;
- (void)disconnectNativeTunnel;
- (BOOL)sendNativeCoordinateLat:(double)lat lon:(double)lon;
- (BOOL)isNativeTunnelConnected;

@end

NS_ASSUME_NONNULL_END
