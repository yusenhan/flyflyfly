import SwiftUI
import MapKit

@MainActor
struct LocationInputSectionView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var searchViewModel: SearchViewModel
    let currentRegion: MKCoordinateRegion?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("位置輸入").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
                if searchViewModel.isSearching {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }

            SearchBar(placeKeyword: $searchViewModel.placeKeyword, onSearch: { searchViewModel.searchPlaces(currentRegion: currentRegion) })

            // 智慧剪貼簿座標偵測膠囊
            if let clipCoord = searchViewModel.detectedClipboardCoordinate {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        searchViewModel.loadFromClipboard()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 11, weight: .semibold))
                        
                        Text("偵測到剪貼簿座標：\(clipCoord)")
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("一鍵定位")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(ModernTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ModernTheme.accent.opacity(0.12))
                    .foregroundColor(ModernTheme.accent)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ModernTheme.accent.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.vertical, 2)
            }

            if let completerError = vm.locationSearchService.completerError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("搜尋錯誤").font(.caption).fontWeight(.bold).foregroundColor(.red)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(completerError, forType: .string)
                        }) {
                            Label("複製", systemImage: "doc.on.doc").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    Text(completerError)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
            }

            // Integrated Search Results & Suggestions
            let completions = vm.locationSearchService.completions
            let results = searchViewModel.placeResults

            if !completions.isEmpty || !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !completions.isEmpty {
                            ForEach(Array(completions.enumerated()), id: \.offset) { _, completion in
                                Button(action: { searchViewModel.selectCompletion(completion) }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(completion.title).font(.subheadline)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(4)
                            }
                        } else {
                            ForEach(Array(results.prefix(8).enumerated()), id: \.offset) { _, item in
                                Button(action: { searchViewModel.selectSearchItem(item) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "未知地點").font(.subheadline)
                                            Text(searchViewModel.searchResultSubtitle(for: item)).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if let dist = searchViewModel.searchResultDistanceText(for: item, cameraRegion: currentRegion) {
                                            Text(dist).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }

            if let err = searchViewModel.locationInputError, !err.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("錯誤詳情").font(.caption).fontWeight(.bold).foregroundColor(.red)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(err, forType: .string)
                        }) {
                            Label("複製", systemImage: "doc.on.doc").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled) // Allow manual selection/copy
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            searchViewModel.checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            searchViewModel.checkClipboard()
        }
    }
}
