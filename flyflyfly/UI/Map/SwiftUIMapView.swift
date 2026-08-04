import SwiftUI
import MapKit

struct SwiftUIMapView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var simulationStore: SimulationStore
    var renderedPurePoints: [VisiblePurePoint] = []

    init(vm: AppViewModel, simulationStore: SimulationStore, renderedPurePoints: [VisiblePurePoint] = []) {
        self.vm = vm
        self.simulationStore = simulationStore
        self.renderedPurePoints = renderedPurePoints
    }

    struct MapItem: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String?
        let color: Color
        let iconName: String
    }

    private var annotationItems: [MapItem] {
        var items: [MapItem] = []

        // 1. Current Position
        if let current = simulationStore.currentPosition {
            items.append(MapItem(
                id: "currentPosition",
                coordinate: current,
                title: "目前位置",
                subtitle: nil,
                color: Color(red: 0.08, green: 0.24, blue: 0.62),
                iconName: "mappin.circle.fill"
            ))
        }

        // 2. Draft Point A / Fixed Point
        if let a = vm.pointA {
            let title = (vm.operationMode == .fixedPoint) ? "定點位置" : "草稿起點 A"
            items.append(MapItem(
                id: "pointA",
                coordinate: a,
                title: title,
                subtitle: nil,
                color: .yellow,
                iconName: "mappin.and.ellipse"
            ))
        }

        // 3. Draft Point B
        if let b = vm.pointB {
            items.append(MapItem(
                id: "pointB",
                coordinate: b,
                title: "草稿終點 B",
                subtitle: nil,
                color: .orange,
                iconName: "mappin"
            ))
        }

        // 4. MultiPoint Waypoints
        if vm.operationMode == .multiPoint {
            for (idx, point) in vm.waypoints.enumerated() {
                items.append(MapItem(
                    id: "multiPoint-\(idx)",
                    coordinate: point,
                    title: "P\(idx + 1)",
                    subtitle: nil,
                    color: .yellow,
                    iconName: "\(min(idx + 1, 50)).circle.fill"
                ))
            }
        }

        // 5. Temp Coordinate
        if let temp = vm.tempCoordinate {
            items.append(MapItem(
                id: "tempCoordinate",
                coordinate: temp,
                title: "確認位置",
                subtitle: nil,
                color: .brown,
                iconName: "questionmark.circle.fill"
            ))
        }

        return items
    }

    public var body: some View {
        Map(coordinateRegion: $vm.mapRegion, annotationItems: annotationItems) { item in
            MapAnnotation(coordinate: item.coordinate) {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        Image(systemName: item.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(item.color)
                    }
                    Text(item.title)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
        }
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let tapPoint = value.location
                                let center = vm.mapRegion.center
                                let span = vm.mapRegion.span
                                
                                // Map local view click to coordinate estimation
                                let width = geo.size.width
                                let height = geo.size.height
                                guard width > 0, height > 0 else { return }
                                
                                let dx = (tapPoint.x - width / 2.0) / width
                                let dy = (height / 2.0 - tapPoint.y) / height
                                
                                let targetLat = center.latitude + (dy * span.latitudeDelta)
                                let targetLon = center.longitude + (dx * span.longitudeDelta)
                                let clickedCoord = CLLocationCoordinate2D(latitude: targetLat, longitude: targetLon)
                                
                                vm.handleMapTap(at: clickedCoord)
                            }
                    )
            }
        )
    }
}
