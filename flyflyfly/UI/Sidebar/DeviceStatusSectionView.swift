import SwiftUI

struct DeviceStatusSectionView: View {
    @ObservedObject var vm: AppViewModel
    let isCompactSidebar: Bool
    @Binding var isWirelessMode: Bool

    @State private var isShowingLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label Header
            Text("裝置連線").font(.caption.bold()).foregroundColor(.secondary)

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

                if vm.deviceManager.isConnected {
                    Button(action: { vm.deviceManager.disconnect() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("斷開連線")
                } else {
                    Button(action: { vm.deviceManager.connectDevice() }) {
                        Text(vm.deviceManager.isConnecting ? "連線中..." : "連線")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(vm.deviceManager.isConnecting ? Color.gray : ModernTheme.accent)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.deviceManager.isConnecting)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))

            if vm.deviceManager.isConnected {
                systemMonitorPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Transport Switcher
            Picker("連線模式", selection: $isWirelessMode) {
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
                     ? "確保 iPhone 與 Mac 在同一個 Wi‑Fi 網路，按下上方工具列的連線按鈕。"
                     : "插上手機並解鎖，按下上方工具列的連線按鈕即可。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !vm.deviceManager.debugLog.isEmpty && !vm.isActiveSimulationRunning {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { withAnimation { isShowingLogs.toggle() } }) {
                        HStack {
                            Label(isShowingLogs ? "隱藏連線日誌" : "顯示連線日誌", 
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

    private var systemMonitorPanel: some View {
        VStack(spacing: 8) {
            let info = vm.deviceManager.systemInfo
            
            // CPU Row
            resourceRow(
                label: "CPU",
                value: String(format: "%.1f%%", info.cpuUsage),
                percent: info.cpuUsage / 100.0,
                color: .blue
            )
            
            // RAM Row
            resourceRow(
                label: "RAM",
                value: String(format: "%.1f GB", info.ramUsed),
                percent: info.ramPercentage / 100.0,
                color: .purple
            )
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
    
    private func resourceRow(label: String, value: String, percent: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 10, weight: .bold))
                Spacer()
                Text(value).font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(.secondary)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.05))
                    Capsule()
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 1)))
                }
            }
            .frame(height: 4)
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
