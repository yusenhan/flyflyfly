# flyflyfly — Project Knowledge Base

**Generated:** 2026-04-07
**Commit:** Current State (Fixed Missing Extensions)
**Branch:** main

## OVERVIEW

macOS SwiftUI app that spoofs iOS device GPS location via `pymobiledevice3`. Connects to iPhone/iPad over USB or Wi-Fi tunnel, then injects simulated coordinates through DVT instruments or legacy `simulate-location` CLI. Supports A→B route following, fixed-point pinning, multi-waypoint routes, and KML-based "PurePoint" overlay import.

## STRUCTURE

```
flyflyfly/
├── AppViewModel.swift              # Observable ViewModel: route calc, simulation, state management
├── ContentView.swift               # Main view entry, uses extensions for sub-views
├── Core/
│   ├── Algorithms/
│   │   └── RouteMotionEngine.swift  # GPS interpolation and loop logic
│   ├── Constants/
│   │   └── AppConstants.swift       # Global timeouts, speeds, and map defaults
│   ├── Models/
│   │   ├── AppState.swift           # UI state machine enum
│   │   ├── Item.swift               # SwiftData @Model placeholder
│   │   ├── MapKit+Extensions.swift  # [FIXED] MKMapItem/CLPlacemark extensions & AddressRepresentations
│   │   ├── ShuangbeiPurePointData.swift # PurePoint and Category models
│   │   └── Types.swift               # OperationMode and DeviceConnectionState
│   └── Protocols/
│       ├── DeviceControlling.swift
│       ├── DVTStreaming.swift
│       └── LocationSearching.swift
├── Services/
│   ├── Device/
│   │   ├── DeviceManager.swift      # Orchestrates pymobiledevice3 and tunnel mgmt
│   │   ├── DVTLocationStream.swift  # Process wrapper for dvt-location-stream binary
│   │   └── MockDVTLocationStream.swift
│   ├── Diagnostics/
│   │   └── AppDiagnostics.swift     # Crash monitoring and session logging
│   ├── Location/
│   │   └── LocationSearchService.swift # MKLocalSearch wrapper with ranking/dedupe
│   └── PurePoint/
│       ├── PurePointOverlaySupport.swift # KML parser and repository
│       └── PurePointRenderEngine.swift   # Map viewport filtering/capping logic
└── UI/ (Sub-view extensions and components)
    ├── Controls/
    ├── Map/
    ├── PurePoint/
    ├── Search/
    ├── Shared/
    └── Sidebar/
bundled/
├── dvt-location-stream              # Binary tool for DVT injection
└── pymobiledevice3                  # Bundled CLI binary
```

## KEY FIXES

- **Missing Extensions (2026-04-07):** Restored `MKMapItem` and `CLPlacemark` extensions (including `location`, `address`, `shortAddress`, `fullAddress`) and implemented `AddressRepresentations` to fix build failures. Located in `Core/Models/MapKit+Extensions.swift`.

## CONVENTIONS

- **Language**: All UI strings in Traditional Chinese (zh-TW). Code comments in Chinese/English.
- **Architecture**: Decoupled into `Core`, `Services`, and `UI`. `ContentView` uses `@StateObject` for `AppViewModel`.
- **Concurrency**: `@MainActor` on ViewModels. `DeviceManager` uses `DispatchQueue` and `NSLock` for thread safety.
- **Process Management**: `Process` + `Pipe` for CLI tools.
- **Builds**: 所有的建置（Builds）都必須同時編譯 Debug 與 Release 兩個版本，以確保兩種配置下的代碼均能正常編譯無誤。


## NOTES

- The app depends on bundled binaries in the `bundled/` directory.
- `Item.swift` remains as a SwiftData placeholder but is currently unused.
