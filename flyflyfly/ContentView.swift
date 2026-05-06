import SwiftUI
import MapKit
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    private enum PersistedMapKeys {
        static let centerLat = "map.center.lat"
        static let centerLon = "map.center.lon"
        static let spanLat = "map.span.lat"
        static let spanLon = "map.span.lon"
    }

    @StateObject var diagnostics = AppDiagnostics.shared
    @StateObject var vm: AppViewModel

    @State var purePointOverlays: [PurePointOverlay]
    @State var purePointOverlayStates: [String: PurePointOverlayUIState]
    @State var isImportingPurePointKML: Bool = false
    @State var purePointImportError: String?
    @State var pendingImportedOverlays: [PurePointOverlay] = []
    @State var pendingImportedOverlayTitles: [String: String] = [:]
    @State var isShowingImportedOverlayNamingSheet: Bool = false
    let routeColors: [Color] = [.yellow, .orange, .mint, .pink]
    private let purePointViewportPadding = AppConstants.PurePoint.viewportPadding

    init() {
        let defaults = UserDefaults.standard
        let lat = defaults.object(forKey: PersistedMapKeys.centerLat) as? Double ?? AppConstants.Map.defaultLatitude
        let lon = defaults.object(forKey: PersistedMapKeys.centerLon) as? Double ?? AppConstants.Map.defaultLongitude
        let spanLat = defaults.object(forKey: PersistedMapKeys.spanLat) as? Double ?? 0.05
        let spanLon = defaults.object(forKey: PersistedMapKeys.spanLon) as? Double ?? 0.05
        let centerCandidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let center: CLLocationCoordinate2D
        if CLLocationCoordinate2DIsValid(centerCandidate),
           centerCandidate.latitude.isFinite,
           centerCandidate.longitude.isFinite {
            center = centerCandidate
        } else {
            center = CLLocationCoordinate2D(
                latitude: AppConstants.Map.defaultLatitude,
                longitude: AppConstants.Map.defaultLongitude
            )
        }
        let minSpan = AppConstants.Map.minimumSpanDelta
        let maxSpan = AppConstants.Map.maximumSpanDelta
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(spanLat, minSpan), maxSpan),
                longitudeDelta: min(max(spanLon, minSpan), maxSpan)
            )
        )
        let initialOverlays = PurePointOverlayRepository.initialOverlays()
        _purePointOverlays = State(initialValue: initialOverlays)
        _purePointOverlayStates = State(initialValue: Self.makeOverlayStates(for: initialOverlays))
        let deviceManager = DeviceManager()
        let locationSearchService = LocationSearchService()
        let initialVM = AppViewModel(deviceManager: deviceManager, locationSearchService: locationSearchService)
        initialVM.mapRegion = region
        initialVM.visibleMapRegion = region
        _vm = StateObject(wrappedValue: initialVM)
    }

    private var purePointRenderState: PurePointRenderState {
        vm.purePointStore.renderState
    }

    private var renderedPurePoints: [VisiblePurePoint] {
        purePointRenderState.points
    }

    var purePointRenderNotice: String? {
        let state = purePointRenderState
        guard state.totalMatchingCount > 0 else { return nil }

        if state.isDensityLimited {
            return "為了避免地圖當掉，純點目前只顯示視野內 \(state.points.count) / \(state.viewportMatchingCount) 個。請放大地圖或縮小分類。"
        }
        
        if state.isViewportFiltered && state.viewportMatchingCount < state.totalMatchingCount {
             return "純點數量較多，地圖目前只渲染視野內的 \(state.viewportMatchingCount) 個點位。"
        }
        return nil
    }

    var body: some View {
        let _ = vm.dependencyVersion
        contentRoot
        .onChange(of: vm.deviceManager.isConnected) { isConnected in
            handleDeviceConnectionChange(isConnected: isConnected)
        }
        .onChange(of: vm.operationMode) { _ in
            handleOperationModeChange()
        }
        .onChange(of: vm.searchViewModel.placeKeyword) { newValue in
            handlePlaceKeywordChange(newValue)
        }
        .onChange(of: vm.speed) { newValue in
            clampSpeedIfNeeded(newValue)
        }
        .onChange(of: vm.isClosedLoop) { isEnabled in
            handleClosedLoopChange(isEnabled)
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseUpdate(newPhase)
        }
        .fileImporter(
            isPresented: $isImportingPurePointKML,
            allowedContentTypes: [.kml],
            allowsMultipleSelection: true
        ) { result in
            handlePurePointImport(result)
        }
    }

    var contentRoot: some View {
        GeometryReader { geometry in
            HSplitView {
                sidebarSections(isCompactSidebar: geometry.size.width < 800)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 450)
                    .layoutPriority(1)
                
                mapPane
                    .frame(minWidth: 400)
                    .layoutPriority(0)
            }
        }
    }

    var mapPane: some View {
        GeometryReader { geometry in
            if geometry.size.width > 20, geometry.size.height > 20 {
                LegacyMapView(vm: vm, renderedPurePoints: renderedPurePoints)
                    .ignoresSafeArea()
            } else {
                Color.clear
            }
        }
    }
}
