import SwiftUI
import MapKit

extension ContentView {
    @ViewBuilder
    func purePointOverlaySection(_ overlay: PurePointOverlay, isCompactSidebar: Bool) -> some View {
        PurePointOverlaySection(
            overlay: overlay,
            isCompactSidebar: isCompactSidebar,
            state: bindingForOverlayState(overlay),
            visiblePoints: visiblePoints(for: overlay),
            pointCountByCategory: pointCountByCategory(for: overlay),
            isImported: !overlay.isBuiltIn,
            onToggleEnabled: { newValue in
                var s = overlayState(for: overlay)
                s.isEnabled = newValue
                purePointOverlayStates[overlay.id] = s
            },
            onToggleFilterExpanded: { newValue in
                var s = overlayState(for: overlay)
                s.isFilterExpanded = newValue
                purePointOverlayStates[overlay.id] = s
            },
            onToggleCategory: { categoryID in
                toggleCategory(categoryID, in: overlay)
            },
            onSelectAllCategories: { selectAllCategories(in: overlay) },
            onClearAllCategories: { clearAllCategories(in: overlay) },
            onFocus: { focusPurePoints(in: overlay) },
            onRemoveImported: { removeImportedOverlay(overlay) }
        )
    }

    @ViewBuilder
    var locationInputSection: some View {
        LocationInputSectionView(vm: vm, searchViewModel: vm.searchViewModel, currentRegion: vm.visibleMapRegion)
    }

    var wirelessModeBinding: Binding<Bool> {
        Binding(
            get: { vm.isWirelessMode },
            set: { newValue in
                let manager = vm.deviceManager
                guard manager.isWirelessMode != newValue else { return }
                guard !manager.isConnecting else { return }

                if manager.isConnected {
                    Task {
                        await manager.disconnectAsync()
                        DispatchQueue.main.async {
                            vm.isWirelessMode = newValue
                            manager.connectDevice()
                        }
                    }
                } else {
                    vm.isWirelessMode = newValue
                }
            }
        )
    }

    var operationModePicker: some View {
        Picker("模式", selection: $vm.operationMode) {
            ForEach(OperationMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .background(ModernTheme.panelRaised.cornerRadius(8))
    }

    func deviceStatusSection(isCompactSidebar: Bool) -> some View {
        DeviceStatusSectionView(
            vm: vm,
            isCompactSidebar: isCompactSidebar,
            isWirelessMode: wirelessModeBinding
        )
    }

    @ViewBuilder
    var pinnedCoordinateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pinned = vm.pinnedCoordinate {
                Text(
                    String(
                        format: "目前座標：%.6f, %.6f",
                        pinned.latitude,
                        pinned.longitude
                    )
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            } else {
                Text("目前座標：尚未開始模擬")
                    .font(.caption)
                    .foregroundColor(.clear)
            }
        }
        .frame(height: 14, alignment: .leading)
        
        if let notice = vm.activityNotice {
            Text(notice)
                .font(.caption)
                .foregroundColor(.yellow)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    func sidebarPane(isCompactSidebar: Bool) -> some View {
        SidebarView {
            sidebarSections(isCompactSidebar: isCompactSidebar)
        }
        .frame(maxWidth: .infinity)
    }

    func handleDeviceConnectionChange(isConnected: Bool) {
        guard isConnected else {
            vm.handleDeviceDisconnected()
            return
        }

        vm.startIfReadyAndConnected()

        guard let current = vm.currentPosition else { return }
        vm.deviceManager.startContinuousLocationStream()
        Task {
            try? await vm.deviceManager.sendLocationToDeviceAsync(latitude: current.latitude, longitude: current.longitude)
        }
    }

    func handleOperationModeChange() {
        vm.switchModePreservingPinnedLocation()
    }

    func handlePlaceKeywordChange(_ newValue: String) {
        vm.locationSearchService.updateQuery(newValue, region: vm.mapRegion)
    }

    func clampSpeedIfNeeded(_ newValue: Double) {
        let clamped = min(max(newValue, AppConstants.Simulation.speedStep), vm.maximumSpeed)
        if abs(clamped - newValue) > 0.0001 {
            vm.speed = clamped
        }
    }

    func handleClosedLoopChange(_ isEnabled: Bool) {
        if isEnabled {
            vm.isEndlessLoop = false
        }
        vm.recalculateRoute()
    }

    func handleScenePhaseUpdate(_ newPhase: ScenePhase) {
        diagnostics.noteScenePhase(newPhase)
        vm.handleScenePhaseChange(newPhase)
    }

    func handlePurePointImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            prepareImportedPurePointOverlays(from: urls)
        case .failure(let error):
            purePointImportError = error.localizedDescription
        }
    }

    func configureCameraRequestHandler() {
        vm.requestCameraPosition = { [weak vm] region in
            guard let vm = vm else { return }
            vm.mapRegion = region
        }
    }

    @ViewBuilder
    func sidebarSections(isCompactSidebar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 頂部 Workflow Tab 導航列
            HStack(spacing: 4) {
                ForEach(WorkflowTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                            activeTab = tab
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(activeTab == tab ? ModernTheme.accent.opacity(0.15) : Color.clear)
                        )
                        .foregroundColor(activeTab == tab ? ModernTheme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.horizontal, isCompactSidebar ? 10 : 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            // 分頁滾動內容區
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch activeTab {
                    case .connect:
                        VStack(alignment: .leading, spacing: 16) {
                            deviceStatusSection(isCompactSidebar: isCompactSidebar)
                        }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)), removal: .opacity))

                    case .locate:
                        VStack(alignment: .leading, spacing: 16) {
                            operationModePicker
                            
                            locationInputSection
                            
                            Divider().opacity(0.3)
                            
                            Text("常用收藏")
                                .font(.subheadline.bold())
                                .foregroundColor(ModernTheme.label)
                            
                            FavoritesSectionView(vm: vm)
                        }
                        .transition(.opacity)

                    case .layers:
                        VStack(alignment: .leading, spacing: 16) {
                            Text("地圖圖層")
                                .font(.subheadline.bold())
                                .foregroundColor(ModernTheme.label)
                            
                            purePointControlsSection(isCompactSidebar: isCompactSidebar)
                        }
                        .transition(.opacity)

                    case .settings:
                        VStack(alignment: .leading, spacing: 16) {
                            Text("移動參數設定")
                                .font(.subheadline.bold())
                                .foregroundColor(ModernTheme.label)
                            
                            MovementSettingsSectionView(vm: vm)
                        }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                    }
                }
                .padding(.horizontal, isCompactSidebar ? 10 : 16)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 固定底部常駐控制與監控區
            VStack(spacing: 8) {
                Divider()
                
                // 當正在模擬運行或處於與移動相關狀態時，動態展開顯示狀態通知
                if vm.isActiveSimulationRunning || vm.appState == .moving || vm.appState == .calculatingRoute || vm.appState == .routeSelection {
                    StatusViewSection(vm: vm, routeColors: routeColors)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                pinnedCoordinateSection
                
                sidebarFooter(isCompactSidebar: isCompactSidebar)
            }
            .padding(.horizontal, isCompactSidebar ? 10 : 16)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(Material.regular)
        }
        .frame(maxWidth: .infinity)
    }


    @ViewBuilder
    func sidebarFooter(isCompactSidebar: Bool) -> some View {
        SidebarFooterView(
            vm: vm,
            isCompactSidebar: isCompactSidebar
        )
    }

    @ViewBuilder
    func purePointControlsSection(isCompactSidebar: Bool) -> some View {
        PurePointControlsSectionView(
            overlayCount: purePointOverlays.count,
            importError: purePointImportError,
            renderNotice: purePointRenderNotice,
            hasVisiblePoints: !vm.purePointStore.renderedPurePoints.isEmpty,
            onImport: {
                purePointImportError = nil
                isImportingPurePointKML = true
            },
            onFocusAll: focusAllPurePoints
        ) {
            ForEach(purePointOverlays) { overlay in
                purePointOverlaySection(overlay, isCompactSidebar: isCompactSidebar)
            }
        }
    }

    var routeReplacementSheetBinding: Binding<Bool> {
        Binding(
            get: { vm.isShowingRouteReplacementConfirmation },
            set: { newValue in
                vm.isShowingRouteReplacementConfirmation = newValue
            }
        )
    }

    var routeReplacementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("開始新路線")
                .font(.title3)
                .fontWeight(.semibold)

            Text("將以新路線取代目前藍線路線，但不會中斷裝置連線。")
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    vm.cancelRouteReplacement()
                }
                .buttonStyle(.bordered)

                Button("確認開始") {
                    vm.confirmRouteReplacement()
                }
                .buttonStyle(.borderedProminent)
                .tint(ModernTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Support View

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @State private var isExpanded: Bool
    let content: () -> Content

    init(title: String, icon: String, defaultExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self._isExpanded = State(initialValue: defaultExpanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { 
                    isExpanded.toggle() 
                } 
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(ModernTheme.accent)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(ModernTheme.label)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
