import SwiftUI

// Route control panel wrapper moved from ContentView. Keeps business logic intact
// while presenting a clean, focused UI surface.
struct RouteControlPanel: View {
    @ObservedObject var vm: AppViewModel

    init(vm: AppViewModel) {
        self.vm = vm
    }

    var body: some View {
        VStack(spacing: 12) {
            // Stats Panel
            if vm.appState == .readyToMove || vm.appState == .routeSelection || vm.appState == .moving {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated Time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(vm.estimatedTime)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                    }
                    Spacer()
                    if let progress = vm.progressPercentage {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Current Progress")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(progress)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Main Action Button
            Button(action: vm.handleMainAction) {
                Text(vm.buttonTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isMainActionDestructive ? Color.red : ModernTheme.accent)
            .controlSize(.regular)
            .disabled(vm.isMainActionDisabled)
        }
    }
}
