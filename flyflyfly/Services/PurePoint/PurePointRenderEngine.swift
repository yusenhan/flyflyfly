import MapKit
import SwiftUI

public struct PurePointRenderEngine {
    static func renderState(
        using index: FastMotionEngineWrapper,
        lookup: [VisiblePurePoint],
        selectedIDs: Set<String>,
        region: MKCoordinateRegion,
        padding: Double,
        limit: Int,
        activationCount: Int,
        wideSpanThreshold: Double
    ) -> PurePointRenderState {
        guard !lookup.isEmpty else { return .empty }

        let latPadding = region.span.latitudeDelta * padding
        let lonPadding = region.span.longitudeDelta * padding
        let minLat = region.center.latitude - (region.span.latitudeDelta / 2) - latPadding
        let maxLat = region.center.latitude + (region.span.latitudeDelta / 2) + latPadding
        let minLon = region.center.longitude - (region.span.longitudeDelta / 2) - lonPadding
        let maxLon = region.center.longitude + (region.span.longitudeDelta / 2) + lonPadding

        // 1. $O(\log N)$ Spatial Search using C++ Quadtree
        let foundIndices = index.searchPoints(inRectMinLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        
        // 2. Map indices back to objects and filter by selected overlay IDs
        var viewportEntries: [VisiblePurePoint] = []
        viewportEntries.reserveCapacity(foundIndices.count)
        
        for idx in foundIndices {
            let i = idx.intValue
            if i < lookup.count {
                let entry = lookup[i]
                if selectedIDs.contains(entry.overlay.id) {
                    viewportEntries.append(entry)
                }
            }
        }

        let rendered = cappedEntries(viewportEntries, limit: limit, region: region)
        
        return PurePointRenderState(
            points: rendered,
            totalMatchingCount: lookup.count,
            viewportMatchingCount: viewportEntries.count,
            isViewportFiltered: true,
            isDensityLimited: viewportEntries.count > rendered.count
        )
    }

    // MARK: - Density Capping logic (Remains similar to before)
    static func cappedEntries(_ entries: [VisiblePurePoint], limit: Int, region: MKCoordinateRegion) -> [VisiblePurePoint] {
        guard entries.count > limit else { return entries }
        let latSpan = max(region.span.latitudeDelta, AppConstants.Map.minimumSpanDelta)
        let lonSpan = max(region.span.longitudeDelta, AppConstants.Map.minimumSpanDelta)
        let aspectRatio = max(lonSpan / latSpan, 0.5)
        let columnCount = max(1, Int((Double(limit) * aspectRatio).squareRoot().rounded(.up)))
        let rowCount = max(1, Int(ceil(Double(limit) / Double(columnCount))))
        let minLat = region.center.latitude - (region.span.latitudeDelta / 2)
        let minLon = region.center.longitude - (region.span.longitudeDelta / 2)

        var bucketed: [String: VisiblePurePoint] = [:]
        for entry in entries {
            let coordinate = entry.point.coordinate
            let normalizedX = (coordinate.longitude - minLon) / lonSpan
            let normalizedY = (coordinate.latitude - minLat) / latSpan
            let x = min(columnCount - 1, max(0, Int(floor(normalizedX * Double(columnCount)))))
            let y = min(rowCount - 1, max(0, Int(floor(normalizedY * Double(rowCount)))))
            let key = "\(x):\(y)"
            if bucketed[key] == nil {
                bucketed[key] = entry
            }
        }

        var result = entries.filter { bucketed[bucketKey(for: $0.point.coordinate, region: region, columns: columnCount, rows: rowCount)]?.id == $0.id }
        if result.count > limit { result = Array(result.prefix(limit)) }
        if result.count == limit { return result }

        let existingIDs = Set(result.map { $0.id })
        let remaining = entries.filter { !existingIDs.contains($0.id) }
        result.append(contentsOf: remaining.prefix(limit - result.count))
        return result
    }

    static func bucketKey(for coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion, columns: Int, rows: Int) -> String {
        let latSpan = max(region.span.latitudeDelta, AppConstants.Map.minimumSpanDelta)
        let lonSpan = max(region.span.longitudeDelta, AppConstants.Map.minimumSpanDelta)
        let minLat = region.center.latitude - (region.span.latitudeDelta / 2)
        let minLon = region.center.longitude - (region.span.longitudeDelta / 2)
        let normalizedX = (coordinate.longitude - minLon) / lonSpan
        let normalizedY = (coordinate.latitude - minLat) / latSpan
        let x = min(columns - 1, max(0, Int(floor(normalizedX * Double(columns)))))
        let y = min(rows - 1, max(0, Int(floor(normalizedY * Double(rows)))))
        return "\(x):\(y)"
    }

    static func safeMapColor(for category: ShuangbeiPurePointCategory?) -> Color {
        (category?.color ?? .blue).opacity(0.98)
    }
}
