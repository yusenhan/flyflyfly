import SwiftUI
import MapKit

@MainActor
struct MovementSettingsSectionView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("移動設定").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
            
            if vm.operationMode != .fixedPoint {
                VStack(alignment: .leading, spacing: 5) {
                    Text("路徑規劃模式").font(.caption).foregroundColor(.secondary)
                    Picker("路徑模式", selection: $vm.transportType) {
                        ForEach(TransportType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .onChange(of: vm.transportType) { _ in
                    vm.recalculateRoute()
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("當前速度: \(String(format: "%.1f", vm.speed)) km/h")
                    if !vm.routes.isEmpty || vm.totalRouteDistance > 0 {
                        HStack(spacing: 4) {
                            Text("單趟: \(vm.estimatedTime)")
                            if let progress = vm.progressPercentage {
                                Text("(\(progress))")
                                    .fontWeight(.bold)
                            }
                        }
                        .foregroundColor(ModernTheme.info)
                    }
                }
                .font(.callout)
                
                HStack(spacing: 8) {
                    TextField("速度", text: $vm.speedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                        .onSubmit {
                            vm.updateSpeedFromText()
                        }

                    Stepper(
                        "微調 0.1",
                        value: $vm.speed,
                        in: AppConstants.Simulation.speedStep...vm.maximumSpeed,
                        step: AppConstants.Simulation.speedStep
                    )
                    .fixedSize()
                }
            }

            Toggle("來回巡邏", isOn: $vm.isEndlessLoop)
                .tint(ModernTheme.accent)
                .disabled(vm.operationMode == .multiPoint && vm.isClosedLoop)

            if vm.operationMode == .multiPoint {
                Text(
                    vm.isClosedLoop
                        ? "閉圈啟用時會持續繞圈，來回巡邏會自動關閉。"
                        : "來回巡邏會在非閉圈路線下於終點原路返回。"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if vm.operationMode == .multiPoint {
                multiPointWaypointControls
                Toggle("閉圈（最後連回 P1）", isOn: $vm.isClosedLoop)
                    .tint(ModernTheme.accent)
                    .disabled(vm.appState != .selectingA && vm.appState != .readyToMove)
            }
            
            Divider().padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("真實防作弊模擬 (iOS 安全防護)").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("真實隨機漂移", isOn: $vm.isJitterEnabled)
                        .tint(.green)
                    
                    if vm.isJitterEnabled {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("漂移半徑限制:")
                                Spacer()
                                Text(String(format: "%.1f 公尺", vm.jitterRangeMeters))
                                    .fontWeight(.bold)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            Slider(value: $vm.jitterRangeMeters, in: 0.5...5.0, step: 0.1)
                                .tint(.green)
                        }
                        .padding(.leading, 12)
                        .transition(.slide.combined(with: .opacity))
                    }
                }
                
                if vm.operationMode != .fixedPoint {
                    Toggle("模擬紅綠燈停等", isOn: $vm.isTrafficLightEnabled)
                        .tint(.red)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .animation(.spring(), value: vm.isJitterEnabled)

        }
    }

    private var multiPointWaypointControls: some View {
        HStack {
            Text("多點數量：\(vm.waypoints.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("移除最後點") {
                if !vm.waypoints.isEmpty { vm.waypoints.removeLast() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(vm.waypoints.isEmpty || vm.appState != .selectingA)
        }
    }

}
