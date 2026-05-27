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
            
            if isWirelessMode {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "shield.lamppost.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("安全提示：無線 TLS 連線跳過了設備自簽名憑證驗證。請確保您處於受信賴的局域網環境，避免在公用 Wi-Fi 使用以防中間人攻擊。")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity)
            }

            // Auto-Connect Toggle
            Toggle(isOn: $vm.isAutoConnectEnabled) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(vm.isAutoConnectEnabled ? .green : .secondary)
                        .font(.system(size: 12))
                    Text("啟動時自動偵測連線裝置")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(vm.deviceManager.isConnecting)
            .padding(.vertical, 2)

            if let err = vm.deviceManager.lastError, !err.isEmpty {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            if !vm.deviceManager.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Label("🔌 連線故障排障指引", systemImage: "questionmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(ModernTheme.accent)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        troubleStepRow(step: "1", text: "請確認解鎖 iPhone 螢幕，並在彈窗點選「信任此電腦」")
                        troubleStepRow(step: "2", text: "請確保已在 iPhone「設定 > 隱私權與安全性」最下方開啟「開發者模式」並重啟")
                        troubleStepRow(step: "3", text: "如拔插傳輸線仍無效，可一鍵重置 macOS 本地 USBMuxd 系統服務")
                        troubleStepRow(step: "4", text: "若發生依賴缺失或權限錯誤，可執行下方「一鍵修復環境」")
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 1))
                
                // 一鍵修復按鈕
                VStack(alignment: .leading, spacing: 8) {
                    if vm.isRepairing {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在自動修復系統依賴...")
                                    .font(.caption.bold())
                                    .foregroundColor(ModernTheme.accent)
                                Spacer()
                            }
                            
                            // 滾動日誌毛玻璃面板
                            VStack(alignment: .leading, spacing: 4) {
                                Text("修復進度與日誌:")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(vm.repairLogs, id: \.self) { log in
                                            Text(log)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.primary.opacity(0.8))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(4)
                                }
                                .frame(height: 100)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    } else {
                        Button(action: {
                            Task {
                                await vm.repairEnvironment()
                            }
                        }) {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                Text("一鍵修復環境依賴")
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("點擊自動給予二進制檔執行權限、清理背景進程並重啟 usbmuxd 轉發服務")
                    }
                }
                .padding(.top, 4)
            }

            if !vm.deviceManager.debugLog.isEmpty {
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

    private func troubleStepRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(step)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 14, height: 14)
                .background(ModernTheme.accent.opacity(0.8))
                .clipShape(Circle())
                .padding(.top, 1)
            
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
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
