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
    @State var activeTab: WorkflowTab = .connect
    @State var useSwiftUIMap: Bool = false
    let routeColors: [Color] = [.yellow, .orange, .mint, .pink]
    private let purePointViewportPadding = AppConstants.PurePoint.viewportPadding


    init() {
        let defaults = UserDefaults.standard
        let lat = defaults.object(forKey: PersistedMapKeys.centerLat) as? Double ?? AppConstants.Map.defaultLatitude
        let lon = defaults.object(forKey: PersistedMapKeys.centerLon) as? Double ?? AppConstants.Map.defaultLongitude
        let spanLatRaw = defaults.object(forKey: PersistedMapKeys.spanLat) as? Double ?? 0.05
        let spanLonRaw = defaults.object(forKey: PersistedMapKeys.spanLon) as? Double ?? 0.05
        let spanLat = spanLatRaw.isFinite ? spanLatRaw : 0.05
        let spanLon = spanLonRaw.isFinite ? spanLonRaw : 0.05
        let centerCandidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let center: CLLocationCoordinate2D
        if CLLocationCoordinate2DIsValid(centerCandidate),
           centerCandidate.latitude.isFinite,
           centerCandidate.longitude.isFinite,
           (abs(centerCandidate.latitude) > 0.001 || abs(centerCandidate.longitude) > 0.001) {
            center = centerCandidate
        } else {
            center = CLLocationCoordinate2D(
                latitude: AppConstants.Map.defaultLatitude,
                longitude: AppConstants.Map.defaultLongitude
            )
        }
        print("Debug: ContentView.init - 載入地圖中心座標為: \(center.latitude), \(center.longitude), span: \(spanLat), \(spanLon)")
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

    func purePointRenderNotice(for state: PurePointRenderState) -> String? {
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
                PurePointStoreReader(store: vm.purePointStore) { renderState in
                    SimulationStoreReader(store: vm.simulationStore) { simulationStore in
                        ZStack(alignment: .top) {
                            ZStack(alignment: .bottomTrailing) {
                                ZStack(alignment: .topTrailing) {
                                    if useSwiftUIMap {
                                        SwiftUIMapView(vm: vm, simulationStore: simulationStore, renderedPurePoints: renderState.points)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .ignoresSafeArea()
                                    } else {
                                        LegacyMapView(vm: vm, simulationStore: simulationStore, renderedPurePoints: renderState.points)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .ignoresSafeArea()
                                    }
                                    
                                    // Map Engine & Style Controls
                                    HStack(spacing: 8) {
                                        Picker("", selection: $useSwiftUIMap) {
                                            Text("AppKit 地圖").tag(false)
                                            Text("SwiftUI 原生地圖").tag(true)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 170)
                                        
                                        Picker("", selection: Binding(
                                            get: { vm.mapType },
                                            set: { vm.mapType = $0 }
                                        )) {
                                            Text("標準").tag(MKMapType.standard)
                                            Text("衛星").tag(MKMapType.satellite)
                                            Text("混合").tag(MKMapType.hybrid)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 140)
                                    }
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                                    .padding(12)
                                }
                                
                                // Floating Joystick Panel (bottom-right)
                                joystickPanel(simulationStore: simulationStore)
                            }
                            
                            // Floating PurePoint HUD Bubble (top center)
                            if let notice = purePointRenderNotice(for: renderState) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                    Text(notice)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                                .padding(.top, 12)
                            }
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func joystickPanel(simulationStore: SimulationStore) -> some View {
        let hasActiveCoordinate = vm.tempCoordinate != nil || (vm.appState == .moving && simulationStore.currentPosition != nil) || (vm.pointA != nil && (vm.appState == .selectingA || vm.appState == .readyToMove)) || (vm.pointB != nil && vm.appState == .selectingB)
        
        if hasActiveCoordinate {
            VStack(spacing: 8) {
                // Step Size Selector
                HStack(spacing: 3) {
                    Text("微調步長").font(.system(size: 9)).foregroundColor(.secondary)
                    Spacer()
                    ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { size in
                        Button(action: { vm.joystickStepSize = size }) {
                            Text("\(Int(size))m")
                                .font(.system(size: 8, weight: vm.joystickStepSize == size ? .bold : .regular))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(vm.joystickStepSize == size ? ModernTheme.accent : Color.primary.opacity(0.05))
                                .foregroundColor(vm.joystickStepSize == size ? .white : .primary)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                
                // D-Pad Grid
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 28, height: 28)
                        
                        // Up / North
                        joystickButton(direction: "up", icon: "chevron.up")
                        
                        Color.clear.frame(width: 28, height: 28)
                    }
                    
                    GridRow {
                        // Left / West
                        joystickButton(direction: "left", icon: "chevron.left")
                        
                        // Center icon/scope
                        ZStack {
                            Circle()
                                .fill(ModernTheme.accent.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "scope")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(ModernTheme.accent)
                        }
                        
                        // Right / East
                        joystickButton(direction: "right", icon: "chevron.right")
                    }
                    
                    GridRow {
                        Color.clear.frame(width: 28, height: 28)
                        
                        // Down / South
                        joystickButton(direction: "down", icon: "chevron.down")
                        
                        Color.clear.frame(width: 28, height: 28)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .frame(width: 130)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .padding([.bottom, .trailing], 12)
        }
    }

    @ViewBuilder
    private func joystickButton(direction: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7)) {
                vm.moveCoordinateStep(direction: direction, distanceMeters: vm.joystickStepSize)
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workflow Navigation Enum
public enum WorkflowTab: String, CaseIterable, Identifiable {
    case connect = "連線"
    case locate = "定位"
    case layers = "圖層"
    case settings = "設定"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .connect: return "cable.connector"
        case .locate: return "location.fill"
        case .layers: return "square.3.layers.3d.down.forward"
        case .settings: return "slider.horizontal.3"
        }
    }
}
