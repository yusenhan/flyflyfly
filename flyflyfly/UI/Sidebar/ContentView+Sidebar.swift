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
            get: { vm.deviceManager.isWirelessMode },
            set: { newValue in
                let manager = vm.deviceManager
                guard manager.isWirelessMode != newValue else { return }
                guard !manager.isConnecting else { return }

                if manager.isConnected {
                    Task {
                        await manager.disconnectAsync()
                        DispatchQueue.main.async {
                            manager.isWirelessMode = newValue
                            manager.connectDevice()
                        }
                    }
                } else {
                    manager.isWirelessMode = newValue
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
                // Fixed height placeholder to prevent jumping
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

    func sidebarSections(isCompactSidebar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Tab Picker
            Picker("", selection: $sidebarTab) {
                Label("模擬", systemImage: "location.north.fill").tag(0)
                Label("資料", systemImage: "tray.full.fill").tag(1)
                Label("配置", systemImage: "slider.horizontal.3").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, isCompactSidebar ? 10 : 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
            
            Divider()

            ZStack(alignment: .topLeading) {
                // Tab 0: 模擬
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        operationModePicker
                        deviceStatusSection(isCompactSidebar: isCompactSidebar)
                        locationInputSection
                        
                        if vm.isActiveSimulationRunning || vm.appState == .moving {
                            StatusViewSection(vm: vm, routeColors: routeColors)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, isCompactSidebar ? 10 : 16)
                    .padding(.vertical, 16)
                }
                .opacity(sidebarTab == 0 ? 1 : 0)
                .disabled(sidebarTab != 0)

                // Tab 1: 資料
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("常用收藏").font(.subheadline.bold())
                        FavoritesSectionView(vm: vm)
                    }
                    .padding(.horizontal, isCompactSidebar ? 10 : 16)
                    .padding(.vertical, 16)
                }
                .opacity(sidebarTab == 1 ? 1 : 0)
                .disabled(sidebarTab != 1)

                // Tab 2: 設定
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("移動參數").font(.subheadline.bold())
                        movementSettingsSection
                        
                        Divider()
                        
                        Text("連線與診斷").font(.subheadline.bold())
                    }
                    .padding(.horizontal, isCompactSidebar ? 10 : 16)
                    .padding(.vertical, 16)
                }
                .opacity(sidebarTab == 2 ? 1 : 0)
                .disabled(sidebarTab != 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 3. Fixed Footer for Critical Controls
            VStack(spacing: 12) {
                Divider()
                pinnedCoordinateSection
                sidebarFooter(isCompactSidebar: isCompactSidebar)
            }
            .padding(.horizontal, isCompactSidebar ? 10 : 16)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(Material.regular) // Ensure footer is distinct
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

    var speedTextBinding: Binding<String> {
        Binding(
            get: { String(format: "%.1f", vm.speed) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = Double(trimmed) else { return }
                vm.speed = min(max(parsed, AppConstants.Simulation.speedStep), vm.maximumSpeed)
            }
        )
    }

    @ViewBuilder
    var movementSettingsSection: some View {
        MovementSettingsSectionView(
            vm: vm,
            speedText: speedTextBinding
        )
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
