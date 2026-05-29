# flyflyfly — Project Knowledge Base

**Generated:** 2026-05-22
**Version:** v0.99a
**Commit:** Swift-native DTX/USBMux with retained C++ acceleration
**Branch:** main

## OVERVIEW

macOS SwiftUI app that spoofs iOS device GPS location. It uses a self-developed Swift-native DTX protocol and USBMux socket architecture for device communication. The current codebase is Swift-first, but still retains Objective-C++/C++ acceleration for route math, spatial indexing, and legacy tunnel helpers (`FastMotionEngineWrapper`, `SpatialIndex`, `NativeTunnel`). iOS 17+ RSD endpoint discovery is not fully native yet; users may still need to provide an RSD host/port obtained externally.

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
│   │   ├── USBMuxMonitor.swift      # [NEW] Native Swift USBMux hotplug & lockdownd extractor
│   │   ├── DTXMessage.swift         # [NEW] Pure Swift DTX protocol frame encoder/decoder
│   │   ├── DTXClient.swift          # [NEW] Pure Swift DTX client (Sysmontap + LocationSimulation)
│   │   ├── DeviceManager.swift      # Orchestrates USBMuxMonitor, DTXClient, and connection state
│   │   ├── DVTLocationStream.swift  # [REWRITTEN] Swift-native adapter bridging to DTXClient Channel 2
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
```

## NATIVE SWIFT DEVICE CORE (2026-05)

1. **Native Device Detection (USBMuxMonitor):**
   - Connects directly to `/var/run/usbmuxd` Domain Socket, natively listening to USB attached/detached events.
   - Extracts device attributes (`DeviceName`, `ProductType`, `ProductVersion`) via `lockdownd` (Port 62078), achieving millisecond-level plug-and-play responsiveness.
2. **Native Performance Monitoring & DTX Protocol (DTXMessage & DTXClient):**
   - Decodes 32-byte DTXHeader, 16-byte PayloadHeader, and DTX Primitive types.
   - Operates a Swift-native client over TLS (`NWConnection`) or raw Socket fd, registering Channel 1 (`sysmontap`) to natively stream real-time CPU & RAM footprint metrics.
3. **Native Location Simulation (DTX Multiplexing):**
   - Registers Channel 2 pointing to the private `coreservices.LocationSimulation` service over the same underlying connection.
   - Implements native `simulateLocation(latitude:longitude:)` and `stopLocationSimulation()` RPCs.
   - **Key Fix:** Coordinates are wrapped inside `NSNumber` objects and serialized as binary Plist Data via `NSKeyedArchiver` to match the exact expected parameter signature (`-(void)simulateLocationWithLatitude:(NSNumber *)lat longitude:(NSNumber *)lon`). They are transmitted as DTX `Buffer` objects (TypeTag = 2).
4. **Adapter Mode for Location Stream (DVTLocationStream):**
   - Rewritten as a clean Swift adapter holding a weak reference to `DTXClient`. 
   - Dispatches coordinate mock requests asynchronously using Swift `Task` on background threads to ensure zero UI stutter.
5. **Dependency Boundary:**
   - Runtime location injection uses the in-process Swift `DTXClient` and `DVTLocationStream` adapter instead of spawning `dvt-location-stream`.
   - iOS 17+ RSD endpoint discovery is still manual; the app can consume an RSD host/port obtained via external remote tunnel tools.
   - Route interpolation and PurePoint spatial filtering still compile Objective-C++/C++ sources through `FastMotionEngineWrapper`.
   - "Clear simulation" is sent through the native DTX RPC path once the client is connected.

## CONVENTIONS

- **Language**: All UI strings in Traditional Chinese (zh-TW). Code comments in Chinese/English.
- **Architecture**: Decoupled into `Core`, `Services`, and `UI`. `ContentView` uses `@StateObject` for `AppViewModel`.
- **Concurrency**: `@MainActor` on ViewModels. Thread-safety managed via GCD queues and locks.
- **Builds**: 所有建置產生的檔案皆必須存放於專案根目錄的 `build` 目錄下（分別為 `build/debug`、`build/release` 與 `build/dmg`）。`rebuild.sh` 是唯一建置入口，支援 `debug`、`release`、`dmg` 與預設 `all`；`runfly.sh` 只負責執行 `build/release/flyflyfly.app`，不得加入建置或測試責任。
- **Git & GitHub 變更管理**: 目前所有的變更暫不推送（Push/Sync）至 GitHub。每次進行代碼、配置或準則變更時，皆必須在專案根目錄的 `git_change_log.md` 中以繁體中文詳細記錄變更內容（包括變更原因、具體修改細節與影響），以備日後提交 Git Commit 使用。

## NOTES

- The binaries in `bundled/` are deprecated for DTX location injection, but iOS 17+ RSD endpoint discovery may still require an external tool until native discovery is implemented.
- `Item.swift` remains as a SwiftData placeholder but is currently unused.
