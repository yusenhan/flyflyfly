# ✈️ flyflyfly - macOS iOS Location Simulation Utility

中文版: [Traditional Chinese README](./README.md)

![Version](https://img.shields.io/badge/Version-v0.99a-brightgreen?style=flat-square)
![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![Swift Native](https://img.shields.io/badge/Language-Swift-orange?style=flat-square&logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Swift--native%20DTX-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**Current Version**: `v0.99a`

**flyflyfly is a flagship-grade iOS location simulation utility built exclusively for macOS.**  
Powered by a **Swift-native DTX protocol and USBMux communication core**, it allows developers and testers on Apple Silicon (M1/M2/M3/M4) or Intel Macs to spoof iPhone/iPad GPS coordinates with low runtime overhead. iOS 17+ currently still requires a manually provided RSD address and port; route calculation and PurePoint spatial indexing still retain C++/Objective-C++ acceleration modules.

---

## ✨ Flagship Features

### ⚡ Pure Swift DTX Core (Self-Developed)
*   **Channel Multiplexing**: Seamlessly operates multiple system streams over a single underlying TLS / Raw Socket connection, maximizing throughput and minimizing lag.
    *   *Channel 1 (sysmontap)*: Streams real-time device CPU & RAM footprint metrics natively in the background.
    *   *Channel 2 (coreservices.LocationSimulation)*: Handles coordinate setup, injection, and mock clear RPCs, completely eliminating redundant socket overhead.

### 🔌 Real-Time USBMux Domain Socket Listening (USBMuxMonitor)
*   **Instant Plug-and-Play**: Connects directly to `/var/run/usbmuxd` Domain Socket to capture hotplug events instantly at a millisecond level.
*   **Native Lockdownd Handshake**: Communicates directly with the device's lockdown service (Port 62078) to extract key metadata (DeviceName, ProductType, ProductVersion) natively without external helpers.

### 🚀 Ultra-Lightweight & Zero UI Stutter
*   **Low Runtime Overhead**: Coordinate injection now goes through the in-process Swift DTX client instead of a persistent `dvt-location-stream` subprocess. Endpoint discovery and selected compute paths still depend on external tooling or C++ acceleration.
*   **Smooth High-Frequency Injection**: Distributes coordinate generation using Swift asynchronous Tasks in background threads. Coordinates are serialized into NSNumber plist data via `NSKeyedArchiver` and transmitted as DTX Buffers (TypeTag = 2) to perfectly match Apple's native API signature, yielding a buttery-smooth route simulation.

### 🚦 Realistic Physical Jitter Spoofer (Anti-Cheat Defense)
*   **Random Walk Motion Engine**: Spoofing coordinates micro-drift smoothly between `[-0.25m, 0.25m]` (restricting drift radius to `[0.5m ~ 5.0m]`) during static pinpoints, movement, and red light delays. This perfectly mimics human hand tremors and defeats strict static GPS detection from third-party apps or games.

### 🚦 Smart Simulated Traffic Lights
*   **Natural Route Behaviors**: Randomly triggers red light delays lasting `[15s ~ 45s]` for every `[300m ~ 800m]` traveled to simulate realistic road congestion.
*   **Dynamic Countdown HUD**: Displays an elegant countdown HUD on the sidebar and status bar. During red-light stops, the traveling distance pauses while the spoofer continues to inject realistic physical jitter to defeat anti-cheat engines.

### 📐 Premium SwiftUI Design & One-Click Self-Healing
*   **Collapsible Modern Sidebar**: Vertical collapsible layout ensures maximum SwiftUI layout performance and smooth updates.
*   **Interactive Diagnostic Card**: Slides out beautiful, actionable steps (Developer Mode enablement, lock-screen trust prompts, cable inspections) when connectivity errors occur.
*   **One-Click Environment Auto-Repair**: Resets macOS local USBMuxd daemons and clears port conflicts with an elegant `.ultraThinMaterial` frosted glass logging panel streaming real-time stdout/stderr diagnostic feeds.

---

## ⚙️ Technical Workflow

```mermaid
graph TD
    %% Roles
    subgraph UI_Layer [SwiftUI UI Layer]
        A[ContentView / Sidebar] -->|1. Connect| B(AppViewModel)
        A -->|4. Set Coords| B
        A -->|6. Start Moving| B
        Z[🚦 Countdown HUD] <-->|Sync State| B
        Y[🛠️ Glass Console] <-->|Streaming Logs| B
    end

    subgraph Logic_Layer [Swift DTX Core + C++ Accelerated Engine]
        B -->|2. Req Connection| C{DeviceManager}
        B -->|5. Path Planning| J[Swift RouteMotionEngine]
        J -->|Interpolation| K[Smooth Coords Stream]
        
        %% Anti-Cheat
        K -->|Physics Drift| P{Random Walk & Traffic Check}
        P -->|Yes: Red Light| PA[Traffic Light Timer]
        PA -->|Sync| Z
        P -->|Micro Drift| PB[Jitter Random Walk]
        
        subgraph Connection_Process [Pure Swift Socket Penetration]
            C -->|Discovery| D[USBMuxMonitor Domain Socket]
            D -->|Hotplug Event/Native Handshake| G[DTXClient Handshake Flow]
            G -->|Multiplexing| I[Channel 1 sysmontap & Channel 2 LocationSimulation]
            
            %% Auto Repair
            C -->|Err| Q[🔌 Diagnostic Card]
            Q -->|Repair| R[Swift USBMuxMonitor restart]
            R -->|1. Reset USBMuxd<br>2. Clear Ports| Y
            R -->|Resolved| C
        end
    end

    subgraph Native_Service [Native Injection Service]
        I -->|3. DTX Channels Ready| B
        B -->|7. Start Stream| L[DVTLocationStream Adapter]
        L -->|NSKeyedArchiver ObjC id| M[DTXClient Channel 2 RPC]
        PB -->|Zero-Lag Task Dispatch| M
        PA -->|Keep Jitter Spoofer Active| M
    end

    subgraph iOS_Device [iOS Device]
        M -->|DVT Instruments| N[iOS Location Subsystem]
        N -->|Override GPS| O[Third-party Apps / Games]
    end
```

---

## 🛠️ Technical Specifications

| Item | Details |
|------|---------|
| **Core Compute Standard** | SwiftUI + Swift Concurrency; DTX/USBMux communication is Swift-native, with C++/Objective-C++ retained for route and spatial-index acceleration |
| **Hardware Compatibility** | Apple Silicon (M1/M2/M3/M4 All Series), Intel x86_64 Mac |
| **System Version** | macOS 13+, iOS 16, 17, 18+ |
| **Connection Protocol** | USBMuxd direct socket (Legacy) / manually supplied RSD host:port (iOS 17+) |
| **Resource Footprint** | Designed for low background overhead; concrete figures should be verified with Instruments or Activity Monitor |

---

## 🚀 Getting Started

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/yusenhan/flyflyfly.git
   cd flyflyfly
   ```
2. **Automated Compilation & Packaging** (Recommended):
   Run the one-click rebuild script in the project root to automatically build both Debug and Release configurations locally, and package a purified DMG installation disk image:
   ```bash
   ./rebuild.sh
   ```
   All compiled build files will be neatly output under the root `build/` directory:
   - `build/debug/flyflyfly.app` - Debug configuration build for active development and inspection.
   - `build/release/flyflyfly.app` - Highly optimized production Release configuration build.
   - `build/dmg/flyflyfly.dmg` - Distribution package disc image with drag-and-drop installation support.
3. **Launching an already built app**:
   Run `./runfly.sh` to open `build/release/flyflyfly.app` directly.
4. **Xcode Manual Development**:
   Double-click `flyflyfly.xcodeproj` to open the project in Xcode. Select the main Scheme and press **Run (⌘R)** to compile, deploy, and inspect the app natively!

### 🛠️ Build & Commit Guidelines
To ensure development efficiency and release stability, please follow these guidelines carefully:
*   **Development Phase**: Use `./rebuild.sh debug` for day-to-day **Debug** builds, and run `./rebuild.sh` before integration or submission to verify **Debug + Release + dmg** together.
*   **Release & Submission**: Once features are fully verified, write detailed change summaries in Traditional Chinese to `git_change_log.md` and keep the changes local for the next submission step.

---

## 📚 Documentation
*   **[Functional Specification (FSD)](./docs/FunctionalSpecification.md)**: Product features and user scenarios.
*   **[System Design (SD)](./docs/SystemDesign.md)**: Swift-native DTX/USBMux architecture, retained C++ acceleration, and optimization details.

## ⚖️ Open Source Attribution & Disclaimer

This project is an open-source implementation created strictly for academic research, technological exploration, and educational purposes. The core concepts are referenced and adapted from the open-source project [O.paperclip](https://github.com/agocia/O.paperclip). On top of the original work, this project has been deeply refactored into native Swift, performance-optimized, and security-hardened utilizing advanced Artificial Intelligence (AI) technologies.

This project is an independent research initiative and shares no commercial association, affiliation, endorsement, or partnership with the original project's authors.

**Important Notice to All Users**:
- This software is strictly intended for developmental debugging, academic study, educational analysis, and personal privacy protection. Do NOT use this tool for any commercial purposes that violate third-party terms of service, applicable laws, or local regulations.
- The authors and contributors of this project do not condone, support, or encourage any inappropriate or illegal usage. Users assume sole and full responsibility for all risks and legal liabilities (including but not limited to penalties under third-party terms of service) arising from the use of this software.
