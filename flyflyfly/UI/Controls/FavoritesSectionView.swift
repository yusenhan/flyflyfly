import SwiftUI
import MapKit

@MainActor
struct FavoritesSectionView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var favoriteStore: FavoriteStore
    @State private var showingAddAlert = false
    @State private var newName = ""
    @State private var itemToSave: (type: FavoriteType, coords: [CLLocationCoordinate2D])?
    @State private var editingItem: FavoriteItem?
    @State private var isExpanded = true

    @State private var expandedModes: Set<FavoriteType> = [.point, .route]
    @State private var expandedCountries: Set<String> = []
    @State private var expandedCities: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("我的最愛").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(ModernTheme.label)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if favoriteStore.items.isEmpty {
                    Text("尚未儲存任何位置或路線")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            let modeGroups = favoriteStore.groups
                            let sortedModes = modeGroups.keys.sorted { $0.rawValue < $1.rawValue }
                            
                            ForEach(sortedModes, id: \.self) { mode in
                                let countries = modeGroups[mode]!
                                let totalInMode = countries.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
                                
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedModes.contains(mode) },
                                        set: { isExp in
                                            if isExp { expandedModes.insert(mode) }
                                            else { expandedModes.remove(mode) }
                                        }
                                    ),
                                    content: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            let sortedCountries = countries.keys.sorted()
                                            ForEach(sortedCountries, id: \.self) { country in
                                                let cities = countries[country]!
                                                let totalInCountry = cities.values.reduce(0) { $0 + $1.count }
                                                let countryKey = "\(mode.rawValue)-\(country)"
                                                
                                                DisclosureGroup(
                                                    isExpanded: Binding(
                                                        get: { expandedCountries.contains(countryKey) },
                                                        set: { isExp in
                                                            if isExp { expandedCountries.insert(countryKey) }
                                                            else { expandedCountries.remove(countryKey) }
                                                        }
                                                    ),
                                                    content: {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            let sortedCities = cities.keys.sorted()
                                                            ForEach(sortedCities, id: \.self) { city in
                                                                let cityItems = cities[city]!
                                                                let cityKey = "\(mode.rawValue)-\(country)-\(city)"
                                                                
                                                                DisclosureGroup(
                                                                    isExpanded: Binding(
                                                                        get: { expandedCities.contains(cityKey) },
                                                                        set: { isExp in
                                                                            if isExp { expandedCities.insert(cityKey) }
                                                                            else { expandedCities.remove(cityKey) }
                                                                        }
                                                                    ),
                                                                    content: {
                                                                        VStack(spacing: 4) {
                                                                            ForEach(cityItems) { item in
                                                                                favoriteRow(item)
                                                                            }
                                                                        }
                                                                        .padding(.leading, 8)
                                                                        .padding(.top, 4)
                                                                    },
                                                                    label: {
                                                                        HStack {
                                                                            Text(city)
                                                                                .font(.caption)
                                                                                .foregroundColor(.secondary)
                                                                            Spacer()
                                                                            Text("\(cityItems.count)")
                                                                                .font(.system(size: 9, weight: .bold))
                                                                                .foregroundColor(.secondary)
                                                                                .padding(.horizontal, 5)
                                                                                .background(Color.primary.opacity(0.05))
                                                                                .clipShape(Capsule())
                                                                        }
                                                                    }
                                                                )
                                                                .buttonStyle(.plain)
                                                                .padding(.leading, 8)
                                                            }
                                                        }
                                                    },
                                                    label: {
                                                        HStack {
                                                            Text(country)
                                                                .font(.caption)
                                                                .fontWeight(.bold)
                                                                .foregroundColor(.secondary)
                                                            Spacer()
                                                            Text("\(totalInCountry)")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                                .padding(.horizontal, 6)
                                                                .background(Color.primary.opacity(0.1))
                                                                .clipShape(Capsule())
                                                        }
                                                    }
                                                )
                                                .buttonStyle(.plain)
                                                .padding(.leading, 8)
                                            }
                                        }
                                        .padding(.top, 2)
                                    },
                                    label: {
                                        HStack {
                                            Label(mode.rawValue, systemImage: mode == .point ? "mappin.and.ellipse" : "map.fill")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(ModernTheme.accent)
                                            Spacer()
                                            Text("\(totalInMode)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(ModernTheme.accent)
                                                .padding(.horizontal, 8)
                                                .background(ModernTheme.accent.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                )
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }

                HStack(spacing: 8) {
                    if let current = vm.tempCoordinate ?? vm.currentPosition ?? (vm.operationMode == .fixedPoint ? vm.pointA : nil) {
                        saveButton(title: "存定點", icon: "mappin.and.ellipse", type: .point, coords: [current])
                    }
                    
                    if vm.operationMode == .routeAB, let a = vm.pointA, let b = vm.pointB {
                        saveButton(title: "存 A-B", icon: "arrow.left.and.right", type: .route, coords: [a, b])
                    } else if vm.operationMode == .multiPoint && vm.waypoints.count >= 2 {
                        saveButton(title: "存多點", icon: "polyline", type: .route, coords: vm.waypoints)
                    }
                }
            }
        }
        .padding(10)
        .background(ModernTheme.panelRaised.cornerRadius(8))
        .alert("儲存至我的最愛", isPresented: $showingAddAlert) {
            TextField("名稱", text: $newName)
            Button("取消", role: .cancel) { }
            Button("儲存") {
                if let data = itemToSave {
                    vm.addToFavorites(
                        name: newName.isEmpty ? (data.type == .point ? "未命名點位" : "未命名路線") : newName,
                        type: data.type,
                        coordinates: data.coords,
                        transportType: vm.transportType
                    )
                }
            }
        } message: {
            if let data = itemToSave {
                if data.type == .point {
                    Text(String(format: "座標: %.6f, %.6f", data.coords[0].latitude, data.coords[0].longitude))
                } else {
                    Text("包含 \(data.coords.count) 個點的路線")
                }
            }
        }
        .alert("重新命名", isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            TextField("名稱", text: $newName)
            Button("取消", role: .cancel) { }
            Button("更新") {
                if let item = editingItem {
                    favoriteStore.update(item, withName: newName.isEmpty ? "未命名" : newName)
                }
            }
        }
    }

    private func saveButton(title: String, icon: String, type: FavoriteType, coords: [CLLocationCoordinate2D]) -> some View {
        Button(action: {
            itemToSave = (type, coords)
            newName = ""
            showingAddAlert = true
        }) {
            Label(title, systemImage: icon)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.yellow)
    }

    private func favoriteRow(_ item: FavoriteItem) -> some View {
        HStack {
            Button(action: { vm.selectFavorite(item) }) {
                HStack(spacing: 8) {
                    Image(systemName: item.type == .point ? "mappin.circle.fill" : "arrow.triangle.pull")
                        .foregroundColor(item.type == .point ? .red : .blue)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .lineLimit(1)
                        if item.type == .point {
                            Text(String(format: "%.6f, %.6f", item.coordinates[0].latitude, item.coordinates[0].longitude))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(item.coordinates.count) 個點 • \(item.transportType?.rawValue ?? "")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button("重新命名") {
                    newName = item.name
                    editingItem = item
                }
                Button("刪除", role: .destructive) {
                    favoriteStore.remove(item)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(6)
        .background(Color.primary.opacity(0.05).cornerRadius(4))
    }
}
