import Foundation
import MapKit
import Combine

@MainActor
final class PurePointStore: ObservableObject {
    @Published var availableOverlays: [PurePointOverlay] = [] {
        didSet {
            rebuildSpatialIndex()
        }
    }
    @Published var selectedOverlayIDs: Set<String> = []
    @Published var renderedPurePoints: [VisiblePurePoint] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Rendering State
    @Published var renderState: PurePointRenderState = .empty
    
    private var cancellables = Set<AnyCancellable>()
    private let mapStateStore: MapStateStore
    private let spatialIndex = FastMotionEngineWrapper()
    private var allVisiblePointsLookup: [VisiblePurePoint] = []
    
    init(mapStateStore: MapStateStore) {
        self.mapStateStore = mapStateStore
        
        // Initial load
        Task {
            await loadInitialOverlays()
        }
        
        // Re-render when region or selected overlays change
        Publishers.CombineLatest(
            mapStateStore.$visibleMapRegion,
            $selectedOverlayIDs
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.updateRenderedPoints()
        }
        .store(in: &cancellables)
    }

    private func rebuildSpatialIndex() {
        // Flatten all points from all AVAILABLE overlays into a single list for C++ indexing
        let allPoints = availableOverlays.flatMap { overlay in
            overlay.points.map { point in
                VisiblePurePoint(
                    overlay: overlay,
                    point: point,
                    category: overlay.categories.first(where: { $0.id == point.categoryID })
                )
            }
        }
        self.allVisiblePointsLookup = allPoints
        
        let nsCoords = allPoints.map { NSValue(mkCoordinate: $0.point.coordinate) }
        spatialIndex.buildSpatialIndex(withPoints: nsCoords)
        print("[SpatialIndex] Rebuilt index with \(allPoints.count) points")
    }
    
    private func loadInitialOverlays() async {
        isLoading = true
        defer { isLoading = false }
        
        // Load built-in and imported overlays in background
        let overlays = await Task.detached(priority: .userInitiated) {
            return PurePointOverlayRepository.initialOverlays()
        }.value
        
        self.availableOverlays = overlays
    }
    
    func updateRenderedPoints() {
        let region = mapStateStore.visibleMapRegion
        let selectedIDs = selectedOverlayIDs
        let lookup = allVisiblePointsLookup
        let index = spatialIndex
        
        Task {
            let newState = await Task.detached(priority: .userInitiated) {
                return PurePointRenderEngine.renderState(
                    using: index,
                    lookup: lookup,
                    selectedIDs: selectedIDs,
                    region: region,
                    padding: 0.15,
                    limit: 1500,
                    activationCount: 200,
                    wideSpanThreshold: 0.8
                )
            }.value
            
            self.renderState = newState
            self.renderedPurePoints = newState.points
        }
    }
    
    func toggleOverlay(_ id: String) {
        if selectedOverlayIDs.contains(id) {
            selectedOverlayIDs.remove(id)
        } else {
            selectedOverlayIDs.insert(id)
        }
    }
    
    func addImportedOverlays(_ overlays: [PurePointOverlay]) {
        availableOverlays.append(contentsOf: overlays)
        for o in overlays {
            selectedOverlayIDs.insert(o.id)
        }
    }
    
    func removeOverlay(_ overlay: PurePointOverlay) {
        availableOverlays.removeAll { $0.id == overlay.id }
        selectedOverlayIDs.remove(overlay.id)
        ImportedPurePointOverlayStore.deleteStoredOverlay(overlay)
        
        let validPaths = availableOverlays.compactMap(\.sourceFilePath)
        ImportedPurePointOverlayStore.savePaths(validPaths)
    }
}
