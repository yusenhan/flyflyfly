# Architecture & UI Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slim down `AppViewModel` and improve Map performance with clustering.

**Architecture:** Split `AppViewModel` into functional ViewModels and implement `MKPointAnnotation` clustering.

**Tech Stack:** SwiftUI, MapKit (Clustering).

---

### Task 1: Split `AppViewModel` (Phase 1: Search & Location)

**Files:**
- Create: `flyflyfly/UI/Search/SearchViewModel.swift`
- Modify: `flyflyfly/AppViewModel.swift`

- [ ] **Step 1: Create `SearchViewModel` and move search logic**

```swift
@MainActor
class SearchViewModel: ObservableObject {
    @Published var placeKeyword: String = ""
    @Published var placeResults: [MKMapItem] = []
    @Published var isSearching: Bool = false
    // ... move search logic from AppViewModel
}
```

- [ ] **Step 2: Update `AppViewModel` to delegate search**

---

### Task 2: Implement Map Clustering for PurePoints

**Files:**
- Modify: `flyflyfly/UI/Map/LegacyMapView.swift`

- [ ] **Step 1: Enable clustering on Annotation Views**

```swift
// In MKMapViewDelegate
func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "PurePoint", for: annotation)
    view.clusteringIdentifier = "purePointCluster"
    return view
}
```

- [ ] **Step 2: Custom Cluster View**

```swift
// Implement a cluster view to show counts
```
