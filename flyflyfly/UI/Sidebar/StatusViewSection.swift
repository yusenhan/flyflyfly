import SwiftUI
import MapKit

struct StatusViewSection: View {
    @ObservedObject var vm: AppViewModel
    let routeColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.hasActiveRouteSnapshot {
                Text(vm.isActiveSimulationRunning ? "Blue line syncing..." : "Blue line fixed")
                    .foregroundColor(ModernTheme.info)
            }

            switch vm.appState {
            case .selectingA:
                if vm.operationMode == .multiPoint {
                    Text("Shift + Click to add points").foregroundColor(ModernTheme.accent)
                } else if vm.operationMode == .fixedPoint {
                    Text("Shift + Click to set point").foregroundColor(ModernTheme.accent)
                } else {
                    Text("Shift + Click to set point A").foregroundColor(ModernTheme.accent)
                }
            case .confirmingA:
                if vm.operationMode == .fixedPoint {
                    Text("Location selected, confirm/cancel on map").foregroundColor(ModernTheme.success)
                } else {
                    Text("Point A selected, confirm/cancel on map").foregroundColor(ModernTheme.success)
                }
            case .selectingB:
                Text("Shift + Click to set point B").foregroundColor(ModernTheme.accent)
            case .confirmingB:
                Text("Point B selected, confirm/cancel on map").foregroundColor(ModernTheme.success)
            case .calculatingRoute:
                Text("Calculating...").foregroundColor(ModernTheme.info)
            case .routeSelection:
                Text(vm.hasActiveRouteSnapshot ? "Select draft route" : "Select a route")
                    .foregroundColor(Color(red: 0.76, green: 0.62, blue: 0.15))
                Picker("Select Route", selection: $vm.selectedRouteIndex) {
                    ForEach(Array(vm.routes.enumerated()), id: \.offset) { index, route in
                        Text("Route \(index + 1) (\(String(format: "%.1f", route.distance / 1000)) km)").tag(index)
                    }
                }
                .pickerStyle(.radioGroup)
            case .readyToMove:
                Text(vm.hasActiveRouteSnapshot ? "Draft ready, start new route" : "Ready")
                    .foregroundColor(vm.hasActiveRouteSnapshot ? .yellow : ModernTheme.info)
            case .moving:
                Text("Moving...").foregroundColor(ModernTheme.info)
            }
        }
        .font(.headline)
        .animation(.easeInOut, value: vm.appState)
    }
}
