import SwiftUI
import MapKit

@MainActor
struct MovementSettingsSectionView: View {
    @ObservedObject var vm: AppViewModel
    @Binding var speedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Settings").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
            
            if vm.operationMode != .fixedPoint {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Path Mode").font(.caption).foregroundColor(.secondary)
                    Picker("Path Mode", selection: $vm.transportType) {
                        ForEach(TransportType.allCases) { type in
                            Text(LocalizedStringKey(type.rawValue)).tag(type)
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
                    Text("Current Speed: \(String(format: "%.1f", vm.speed)) km/h")
                    if !vm.routes.isEmpty || vm.totalRouteDistance > 0 {
                        HStack(spacing: 4) {
                            Text("Estimated Time:").font(.caption).foregroundColor(.secondary)
                            Text(vm.estimatedTime).font(.caption.monospacedDigit()).foregroundColor(.primary)
                            if let progress = vm.progressPercentage {
                                Text("(\(progress))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(ModernTheme.accent)
                            }
                        }
                    }

                }
                .font(.callout)
                Slider(
                    value: $vm.speed,
                    in: AppConstants.Simulation.speedStep...vm.maximumSpeed,
                    step: AppConstants.Simulation.speedStep
                )
                HStack(spacing: 8) {
                    TextField("Speed", text: $speedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)

                    Stepper(
                        "Fine-tune",
                        value: $vm.speed,
                        in: AppConstants.Simulation.speedStep...vm.maximumSpeed,
                        step: AppConstants.Simulation.speedStep
                    )
                    .fixedSize()
                }
            }

            Toggle("Patrol Mode", isOn: $vm.isEndlessLoop)
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

        }
    }

    private var multiPointWaypointControls: some View {
        HStack {
            Text("Waypoints: \(vm.waypoints.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Remove Last") {
                if !vm.waypoints.isEmpty { vm.waypoints.removeLast() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(vm.waypoints.isEmpty || vm.appState != .selectingA)
        }
    }

}
