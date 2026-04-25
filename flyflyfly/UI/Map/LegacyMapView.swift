import SwiftUI
import MapKit

@MainActor
class FlyAnnotation: MKPointAnnotation {
    enum AnnotationType: Equatable {
        case currentPosition
        case draftPointA
        case draftPointB
        case draftFixedPoint
        case multiPoint(index: Int)
        case tempCoordinate
        case purePoint(id: String, category: ShuangbeiPurePointCategory?)
    }

    let id: String
    let type: AnnotationType

    init(id: String, type: AnnotationType, coordinate: CLLocationCoordinate2D, title: String? = nil, subtitle: String? = nil) {
        self.id = id
        self.type = type
        super.init()
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
struct LegacyMapView: NSViewRepresentable {
    @ObservedObject var vm: AppViewModel
    var renderedPurePoints: [VisiblePurePoint] = []

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        
        let tapGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTapGesture(_:)))
        tapGesture.numberOfClicksRequired = 1
        tapGesture.buttonMask = 0x1 // Left click
        mapView.addGestureRecognizer(tapGesture)

        let doubleTapGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapDoubleTapGesture(_:)))
        doubleTapGesture.numberOfClicksRequired = 2
        doubleTapGesture.buttonMask = 0x1 // Left click
        mapView.addGestureRecognizer(doubleTapGesture)
        
        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        updateOverlays(nsView)
        updateAnnotations(nsView)
        
        // Update region if vm.mapRegion changed
        if !context.coordinator.isUpdatingFromExternal, !isSameRegion(nsView.region, vm.mapRegion) {
            context.coordinator.isUpdatingFromExternal = true
            nsView.setRegion(vm.mapRegion, animated: true)
            // Reset after a short delay to allow animation to start
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                context.coordinator.isUpdatingFromExternal = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func isSameRegion(_ r1: MKCoordinateRegion, _ r2: MKCoordinateRegion) -> Bool {
        abs(r1.center.latitude - r2.center.latitude) < 0.000001 &&
        abs(r1.center.longitude - r2.center.longitude) < 0.000001 &&
        abs(r1.span.latitudeDelta - r2.span.latitudeDelta) < 0.00001 &&
        abs(r1.span.longitudeDelta - r2.span.longitudeDelta) < 0.00001
    }

    private func updateOverlays(_ mapView: MKMapView) {
        let existingPolylines = mapView.overlays.compactMap { $0 as? MKPolyline }
        
        var newPolylines: [MKPolyline] = []
        if let active = vm.activeRoutePolyline {
            newPolylines.append(active)
        }
        
        if !vm.routes.isEmpty {
            if vm.appState == .routeSelection {
                newPolylines.append(contentsOf: vm.routes.map { $0.polyline })
            } else if let selected = vm.selectedRoute {
                newPolylines.append(selected.polyline)
            }
        } else if let custom = vm.customRoutePolyline {
            newPolylines.append(custom)
        }
        
        // Track selection to trigger redraw
        let selectionKey = "lastSelectedRouteIndex"
        let lastIndex = mapView.layer?.value(forKey: selectionKey) as? Int
        
        if existingPolylines != newPolylines || lastIndex != vm.selectedRouteIndex {
            mapView.removeOverlays(existingPolylines)
            mapView.addOverlays(newPolylines)
            mapView.layer?.setValue(vm.selectedRouteIndex, forKey: selectionKey)
        }
    }

    private func updateAnnotations(_ mapView: MKMapView) {
        let existingAnnotations = mapView.annotations.compactMap { $0 as? FlyAnnotation }
        var currentAnnotationsMap = Dictionary(uniqueKeysWithValues: existingAnnotations.map { ($0.id, $0) })
        
        var newAnnotations: [FlyAnnotation] = []
        
        // 1. App State Annotations
        if vm.operationMode == .multiPoint {
            for (idx, point) in vm.waypoints.enumerated() {
                let id = "multiPoint-\(idx)"
                let type = FlyAnnotation.AnnotationType.multiPoint(index: idx)
                newAnnotations.append(createOrUpdateAnnotation(id: id, type: type, coordinate: point, title: "P\(idx + 1)", in: &currentAnnotationsMap))
            }
        } else {
            if let a = vm.pointA {
                let id = "pointA"
                let type = (vm.operationMode == .fixedPoint) ? FlyAnnotation.AnnotationType.draftFixedPoint : FlyAnnotation.AnnotationType.draftPointA
                let title = (vm.operationMode == .fixedPoint) ? "草稿定點" : "草稿起點 A"
                newAnnotations.append(createOrUpdateAnnotation(id: id, type: type, coordinate: a, title: title, in: &currentAnnotationsMap))
            }
            if let b = vm.pointB {
                let id = "pointB"
                newAnnotations.append(createOrUpdateAnnotation(id: id, type: .draftPointB, coordinate: b, title: "草稿終點 B", in: &currentAnnotationsMap))
            }
        }
        
        if let temp = vm.tempCoordinate {
            let id = "tempCoordinate"
            newAnnotations.append(createOrUpdateAnnotation(id: id, type: .tempCoordinate, coordinate: temp, title: "確認位置", in: &currentAnnotationsMap))
        }
        
        if let current = vm.currentPosition {
            let id = "currentPosition"
            newAnnotations.append(createOrUpdateAnnotation(id: id, type: .currentPosition, coordinate: current, title: "目前位置", in: &currentAnnotationsMap))
        }
        
        // 2. Pure Point Annotations
        for entry in renderedPurePoints {
            let id = "purePoint-\(entry.id)"
            let type = FlyAnnotation.AnnotationType.purePoint(id: entry.id, category: entry.category)
            newAnnotations.append(createOrUpdateAnnotation(id: id, type: type, coordinate: entry.point.coordinate, title: "PurePoint", subtitle: entry.point.name, in: &currentAnnotationsMap))
        }
        
        let newIds = Set(newAnnotations.map { $0.id })
        let removedAnnotations = existingAnnotations.filter { !newIds.contains($0.id) }
        let addedAnnotations = newAnnotations.filter { ann in !existingAnnotations.contains { $0.id == ann.id } }
        
        if !removedAnnotations.isEmpty {
            mapView.removeAnnotations(removedAnnotations)
        }
        if !addedAnnotations.isEmpty {
            mapView.addAnnotations(addedAnnotations)
        }
    }

    private func createOrUpdateAnnotation(id: String, type: FlyAnnotation.AnnotationType, coordinate: CLLocationCoordinate2D, title: String? = nil, subtitle: String? = nil, in map: inout [String: FlyAnnotation]) -> FlyAnnotation {
        if let existing = map[id], existing.type == type {
            if abs(existing.coordinate.latitude - coordinate.latitude) > 0.0000001 || abs(existing.coordinate.longitude - coordinate.longitude) > 0.0000001 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = AppConstants.Simulation.timerInterval
                    existing.coordinate = coordinate
                }
            }
            return existing
        } else {
            return FlyAnnotation(id: id, type: type, coordinate: coordinate, title: title, subtitle: subtitle)
        }
    }

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LegacyMapView
        var isUpdatingFromExternal: Bool = false

        init(_ parent: LegacyMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                if polyline === parent.vm.activeRoutePolyline {
                    renderer.strokeColor = NSColor(red: 0.08, green: 0.24, blue: 0.62, alpha: 1.0)
                    renderer.lineWidth = 5
                } else if parent.vm.appState == .routeSelection {
                    if let index = parent.vm.routes.firstIndex(where: { $0.polyline === polyline }) {
                         let colors: [NSColor] = [.systemYellow, .systemOrange, .systemMint, .systemPink]
                         renderer.strokeColor = index == parent.vm.selectedRouteIndex ? colors[index % colors.count] : NSColor.gray.withAlphaComponent(0.3)
                         renderer.lineWidth = index == parent.vm.selectedRouteIndex ? 6 : 3
                    } else {
                        renderer.strokeColor = .systemYellow
                        renderer.lineWidth = 5
                    }
                } else if polyline === parent.vm.selectedRoute?.polyline || polyline === parent.vm.customRoutePolyline {
                    renderer.strokeColor = .systemYellow
                    renderer.lineWidth = 5
                } else {
                    renderer.strokeColor = .systemYellow
                    renderer.lineWidth = 5
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            
            if let cluster = annotation as? MKClusterAnnotation {
                let identifier = "PurePointCluster"
                var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if clusterView == nil {
                    clusterView = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                } else {
                    clusterView?.annotation = cluster
                }
                clusterView?.markerTintColor = .systemPurple
                clusterView?.displayPriority = .defaultHigh
                return clusterView
            }
            
            guard let flyAnn = annotation as? FlyAnnotation else { return nil }
            
            let identifier: String
            if case .purePoint = flyAnn.type {
                identifier = "PurePoint"
            } else {
                identifier = "FlyAnnotation"
            }
            
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: flyAnn, reuseIdentifier: identifier)
            } else {
                view?.annotation = flyAnn
            }

            switch flyAnn.type {
            case .purePoint(_, let category):
                let color = PurePointRenderEngine.safeMapColor(for: category)
                view?.markerTintColor = NSColor(color)
                view?.displayPriority = .defaultLow
                view?.glyphText = ""
                view?.clusteringIdentifier = "purePointCluster"

            case .currentPosition:
                view?.markerTintColor = NSColor(red: 0.08, green: 0.24, blue: 0.62, alpha: 1.0)
                view?.glyphImage = NSImage(systemSymbolName: "mappin.circle.fill", accessibilityDescription: nil)
                view?.displayPriority = .required
                view?.clusteringIdentifier = nil

            case .draftPointA, .draftFixedPoint, .multiPoint:
                view?.markerTintColor = .systemYellow
                view?.displayPriority = .required
                view?.clusteringIdentifier = nil

            case .draftPointB:
                view?.markerTintColor = .systemOrange
                view?.displayPriority = .required
                view?.clusteringIdentifier = nil

            case .tempCoordinate:
                view?.markerTintColor = .systemBrown
                view?.displayPriority = .required
                view?.clusteringIdentifier = nil
            }
            
            return view
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            self.parent.vm.visibleMapRegion = mapView.region
            
            // Only sync mapRegion back to VM if it was user-driven (not from updateNSView)
            if !isUpdatingFromExternal {
                self.parent.vm.mapRegion = mapView.region
            }
        }

        @objc func handleMapTapGesture(_ gesture: NSClickGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            
            // Use window-based coordinates to bypass safe area and view offset issues on macOS
            let locationInWindow = gesture.location(in: nil)
            let locationInMapView = mapView.convert(locationInWindow, from: nil)
            
            // Proper hit testing for annotations
            if let hitView = mapView.hitTest(locationInMapView), hitView is MKAnnotationView {
                return 
            }
            
            let coordinate = mapView.convert(locationInMapView, toCoordinateFrom: mapView)
            self.parent.vm.handleMapTap(at: coordinate)
        }

        @objc func handleMapDoubleTapGesture(_ gesture: NSClickGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            
            let locationInWindow = gesture.location(in: nil)
            let locationInMapView = mapView.convert(locationInWindow, from: nil)
            
            if let hitView = mapView.hitTest(locationInMapView), hitView is MKAnnotationView {
                return 
            }
            
            let coordinate = mapView.convert(locationInMapView, toCoordinateFrom: mapView)
            self.parent.vm.handleMapDoubleTap(at: coordinate)
        }
    }
}
