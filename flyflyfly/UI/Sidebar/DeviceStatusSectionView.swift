import SwiftUI

struct DeviceStatusSectionView: View {
    @ObservedObject var vm: AppViewModel
    let isCompactSidebar: Bool
    @Binding var isWirelessMode: Bool

    @State private var isShowingLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label Header
            Text("Device Connection").font(.caption.bold()).foregroundColor(.secondary)

            // Device Name Display
            HStack(spacing: 12) {
                DeviceConnectionIndicator(state: vm.deviceManager.connectionState)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.deviceManager.deviceName)
                        .font(.subheadline.weight(.medium))
                    
                    Text(vm.deviceManager.connectionStage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))

            // Transport Switcher
            Picker("Connection Mode", selection: $isWirelessMode) {
                Text("USB").tag(false)
                Text("Wi‑Fi").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(vm.deviceManager.isConnecting)

            if let err = vm.deviceManager.lastError, !err.isEmpty {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            } else if !vm.deviceManager.isConnected {
                Text(isWirelessMode
                     ? "Wi-Fi Mode Hint"
                     : "USB Mode Hint")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !vm.deviceManager.debugLog.isEmpty && !vm.isActiveSimulationRunning {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { withAnimation { isShowingLogs.toggle() } }) {
                        HStack {
                            Label(isShowingLogs ? "Hide Logs" : "Show Logs", 
                                  systemImage: isShowingLogs ? "chevron.up.circle" : "chevron.down.circle")
                            Spacer()
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    if isShowingLogs {
                        debugLogPanel
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

        }
    }

    private var debugLogPanel: some View {
        let recentLines = Array(vm.deviceManager.debugLog.suffix(isCompactSidebar ? 15 : 20))
        let logText = recentLines.joined(separator: "\n")

        return VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: .constant(logText))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .scrollContentBackground(.hidden)
                .frame(height: isCompactSidebar ? 80 : 120)
                .padding(4)
                .background(ModernTheme.inset)
                .cornerRadius(6)
        }
    }

}
