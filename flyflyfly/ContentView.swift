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
    @State var sidebarTab: Int = 0 // 0: 模擬, 1: 圖層/收藏, 2: 設定
    let routeColors: [Color] = [.yellow, .orange, .mint, .pink]
    private let purePointViewportActivationCount = AppConstants.PurePoint.viewportActivationCount
    private let purePointRenderedLimit = AppConstants.PurePoint.renderedLimit
    private let purePointViewportPadding = AppConstants.PurePoint.viewportPadding
    private let purePointWideSpanThreshold = AppConstants.PurePoint.wideSpanThreshold

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

    var visiblePurePoints: [VisiblePurePoint] {
        purePointOverlays.flatMap { overlay in
            let lookup = categoryLookup(for: overlay)
            return visiblePoints(for: overlay).map { point in
                VisiblePurePoint(overlay: overlay, point: point, category: lookup[point.categoryID])
            }
        }
    }

    private var purePointRenderState: PurePointRenderState {
        PurePointRenderEngine.renderState(
            for: visiblePurePoints,
            region: vm.normalizeMapRegion(vm.visibleMapRegion),
            padding: purePointViewportPadding,
            limit: purePointRenderedLimit,
            activationCount: purePointViewportActivationCount,
            wideSpanThreshold: purePointWideSpanThreshold
        )
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
        if state.isViewportFiltered, state.viewportMatchingCount < state.totalMatchingCount {
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
        .onChange(of: vm.placeKeyword) { newValue in
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
        .sheet(isPresented: $isShowingImportedOverlayNamingSheet) {
            importedOverlayNamingSheet
        }
        .sheet(isPresented: routeReplacementSheetBinding) {
            routeReplacementSheet
        }
        .alert("未開啟開發者模式", isPresented: Binding(
            get: { vm.developerModeDisabled },
            set: { _ in vm.deviceManager.resetDeveloperModeDisabled() }
        )) {
            Button("如何開啟？") {
                if let url = URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("確定", role: .cancel) { }
        } message: {
            Text("偵測到您的 iPhone 未開啟「開發者模式」。請前往手機的「設定」>「隱私權與安全性」>「開發者模式」將其開啟並重新啟動手機，否則無法進行模擬定位。")
        }
        .onDisappear {
            vm.cleanup()
        }
        .onAppear {
            configureCameraRequestHandler()
        }
    }

    private var contentRoot: some View {
        ZStack {
            windowBackground
            splitViewContent
        }
    }

    private var windowBackground: some View {
        ModernTheme.background
            .ignoresSafeArea()
    }

    private var splitViewContent: some View {
        HStack(spacing: 0) {
            sidebarPane(isCompactSidebar: true)
                .frame(width: 320)
                .background(Material.thin) // 使用系統毛玻璃材質作為側邊欄背景
            Divider()
            detailPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Connection Button in Toolbar
                Button(action: {
                    vm.deviceManager.isConnected ? vm.deviceManager.disconnect() : vm.deviceManager.connectDevice()
                }) {
                    Label(vm.deviceManager.isConnecting ? "連線中…" : (vm.deviceManager.isConnected ? "中斷連線" : "開始連線"),
                          systemImage: vm.deviceManager.isConnected ? "cable.connector.slash" : "cable.connector")
                }
                .help(vm.deviceManager.isConnected ? "中斷裝置連線" : "開始連線裝置")
                .disabled(vm.deviceManager.isConnecting)

                Button(action: {
                    vm.resetAll()
                }) {
                    Label("重置所有", systemImage: "arrow.counterclockwise.circle")
                }
                .help("清除所有草稿與目前定位，回到真實位置")
            }
            
            ToolbarItem(placement: .status) {
                if vm.deviceManager.isConnecting {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                }
            }
        }
    }

    private var detailPane: some View {
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
