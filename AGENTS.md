# flyflyfly — Project Knowledge Base

**Generated:** 2026-05-22
**Commit:** Native Swift Architecture (DTX + USBMux)
**Branch:** main

## OVERVIEW

macOS SwiftUI app that spoofs iOS device GPS location. It utilizes a **100% self-developed, highly efficient, pure Swift native DTX protocol and USBMux Socket penetration architecture**, successfully eliminating all dependencies on external Python background processes (`pymobiledevice3`), external binary tools (`dvt-location-stream`), and C++ wrappers (`FastMotionEngineWrapper`).

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

## NATIVE SWIFT REVOLUTION (2026-05)

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
5. **Zero External Dependency:**
   - No Python runtime (`pymobiledevice3`) or helper binaries (`dvt-location-stream`) are needed for runtime operations.
   - "Clear simulation" is achieved entirely natively via DTX RPC without spawning sub-processes.

## CONVENTIONS

- **Language**: All UI strings in Traditional Chinese (zh-TW). Code comments in Chinese/English.
- **Architecture**: Decoupled into `Core`, `Services`, and `UI`. `ContentView` uses `@StateObject` for `AppViewModel`.
- **Concurrency**: `@MainActor` on ViewModels. Thread-safety managed via GCD queues and locks.
- **Builds**: 所有的建置（Builds）都必須同時編譯 Debug 與 Release 兩個版本，以確保兩種配置下的代碼均能正常編譯無誤。

## NOTES

- The binaries in `bundled/` are now entirely deprecated for the DVT mode but kept for fallback or backward compatibility.
- `Item.swift` remains as a SwiftData placeholder but is currently unused.
