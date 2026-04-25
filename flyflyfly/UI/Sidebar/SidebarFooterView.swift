import SwiftUI

struct SidebarFooterView: View {
    @ObservedObject var vm: AppViewModel
    let isCompactSidebar: Bool

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            RouteControlPanel(vm: vm)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())

            if vm.shouldShowResetButton {
                Button(action: vm.resetAll) {
                    Text(vm.resetButtonTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(ModernTheme.danger)
                .controlSize(isCompactSidebar ? .regular : .large)
            }

            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Image("operation_paperclip_icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("飛不飛都得飛")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("app created by Hanson Han")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.horizontal, isCompactSidebar ? 12 : 14)
        .padding(.top, 8)
        .padding(.bottom, isCompactSidebar ? 10 : 12)
        .background(ModernTheme.panelRaised)
    }
}
