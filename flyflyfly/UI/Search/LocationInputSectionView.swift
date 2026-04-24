import SwiftUI
import MapKit

@MainActor
struct LocationInputSectionView: View {
    @ObservedObject var vm: AppViewModel
    let currentRegion: MKCoordinateRegion?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Search Location").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
                if vm.isSearching {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }

            SearchBar(placeKeyword: $vm.placeKeyword, onSearch: { vm.searchPlaces(currentRegion: currentRegion) })

            if let completerError = vm.locationSearchService.completerError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Search Error").font(.caption).fontWeight(.bold).foregroundColor(.red)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(completerError, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc").font(.caption2)
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

            // integrated results
            let completions = vm.locationSearchService.completions
            
            if !completions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(completions.enumerated()), id: \.offset) { _, completion in
                            Button(action: { vm.selectCompletion(completion) }) {
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
                    }
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }

            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $vm.coordinateInputText,
                    prompt: Text("Coordinate Hint").foregroundColor(.secondary)
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.insertCoordinateFromInput() }
                Button("Confirm") { vm.insertCoordinateFromInput() }
                    .buttonStyle(.borderedProminent)
                    .tint(ModernTheme.accent)
                    .controlSize(.small)
            }

            if let err = vm.locationInputError, !err.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error Details").font(.caption).fontWeight(.bold).foregroundColor(.red)
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.top, 4)
            }
        }
    }
}
