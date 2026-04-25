# Core Algorithm & Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve route calculation speed and motion simulation precision.

**Architecture:** Use `TaskGroup` for parallel route segments and enhance `RouteMotionEngine` with high-speed interpolation logic.

**Tech Stack:** Swift Concurrency (TaskGroup), MapKit.

---

### Task 1: Parallelize Multi-Point Route Calculation

**Files:**
- Modify: `flyflyfly/AppViewModel.swift:801-850`

- [ ] **Step 1: Refactor `calculateMultiPointRoute` to use `TaskGroup`**

```swift
// Replace the sequential for loop with a TaskGroup
multiPointTask = Task {
    let count = waypointsToUse.count
    let segments = isClosed ? count : (count - 1)
    
    await withTaskGroup(of: (Int, [CLLocationCoordinate2D], Double).self) { group in
        for i in 0..<segments {
            let start = waypointsToUse[i]
            let end = waypointsToUse[(i + 1) % count]
            
            group.addTask {
                if RouteMotionEngine.fastDistance(from: start, to: end) < 2.0 {
                    return (i, [start, end], RouteMotionEngine.fastDistance(from: start, to: end))
                }
                
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                request.transportType = self.transportType.mkType
                
                let directions = MKDirections(request: request)
                do {
                    let response = try await directions.calculate()
                    if let route = response.routes.first {
                        return (i, route.polyline.coordinates, route.distance)
                    }
                } catch {
                    // Fallback to direct line on error
                }
                let dist = RouteMotionEngine.fastDistance(from: start, to: end)
                return (i, [start, end], dist)
            }
        }
        
        var results = [(Int, [CLLocationCoordinate2D], Double)]()
        for await result in group {
            results.append(result)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, coords, dist) in results {
            accumulator.combinedPoints.append(contentsOf: coords)
            accumulator.totalDistance += dist
        }
    }
    
    // ... rest of the main actor block
}
```

- [ ] **Step 2: Verify by running a multi-point route calculation in the app**

---

### Task 2: Implement Great Circle Interpolation in `RouteMotionEngine`

**Files:**
- Modify: `flyflyfly/Core/Algorithms/RouteMotionEngine.swift`

- [ ] **Step 1: Add `greatCircleCoordinate` helper**

```swift
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
```

- [ ] **Step 2: Update `coordinate(at:in:distances:)` to use Great Circle for larger segments**

```swift
// Inside coordinate function:
// Use threshold to decide between linear and great circle
if segmentDistance > 500.0 { // Use Great Circle for segments > 500m
    return greatCircleCoordinate(from: points[lower], to: points[upper], ratio: ratio)
} else {
    let lat = points[lower].latitude + (points[upper].latitude - points[lower].latitude) * ratio
    let lon = points[lower].longitude + (points[upper].longitude - points[lower].longitude) * ratio
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}
```

---

### Task 3: Dynamic Timer Frequency in `SimulationStore`

**Files:**
- Modify: `flyflyfly/Core/Models/SimulationStore.swift`
- Modify: `flyflyfly/Core/Constants/AppConstants.swift`

- [ ] **Step 1: Define adaptive intervals in `AppConstants`**

```swift
enum Simulation {
    // ...
    static func interval(for speedKmh: Double) -> TimeInterval {
        if speedKmh > 100.0 { return 0.5 } // Faster updates for high speed
        if speedKmh < 5.0 { return 2.0 }   // Slower updates for walking/standing
        return 1.0
    }
}
```

- [ ] **Step 2: Update `SimulationStore` to restart timer when speed changes significantly**

```swift
// In SimulationStore, add a property to track current interval
private var currentTimerInterval: TimeInterval = 1.0

// Update startSimulation and tickSimulation to handle interval changes
```
