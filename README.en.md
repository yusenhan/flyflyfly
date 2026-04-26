# ✈️ flyflyfly: macOS iOS Location Simulation Utility

中文版: [繁體中文 README](./README.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**flyflyfly is a high-performance iOS global positioning simulation suite designed exclusively for macOS.**  
This lightweight utility enables developers and users on Apple Silicon (M1/M2/M3) or Intel Macs to precisely inject GPS coordinates into iPhone or iPad devices over high-speed USB or wireless tunnels, fully compatible with iOS 17 and iOS 18.

---

## ✨ Key Use Cases

### 🎮 LBS (Location Based Service) Optimization
- **Seamless Game Testing**: Ideal for Location Based games like *Pokémon GO*, *Pikmin Bloom*, or *Monster Hunter Now*. Simulate movement paths and explore regional content with ease.
- **Virtual Social Discovery**: Check in at global landmarks or discover new social content without the need for physical travel.

### 🛡️ Privacy on Your Terms
- **Precise Location Masking**: Protect your digital footprint by hiding your real home or office coordinates from location-tracking apps.
- **Bypass Regional Restrictions**: Access geo-locked social feeds or local services instantly.

### 👨‍💻 Engineering & Development
- **Navigation Logic Validation**: Accurately test A-B movement interpolation for logistics, maps, and ride-hailing applications.
- **Global Environment Simulation**: Verify app behavior across international time zones and GPS coordinates.

---

## 🚀 Latest Features & Performance Optimizations (v1.1+)

We are constantly improving our core algorithms and user experience. The latest version includes:

*   **⚡ Parallel Route Calculation**: Leverages Swift Concurrency's `TaskGroup` to significantly speed up multi-point path generation.
*   **🌍 High-Precision Great Circle Interpolation**: Automatically employs Great Circle algorithms for segments over 500m, ensuring pinpoint accuracy for long-distance simulations.
*   **⏲️ Adaptive Update Frequency**: Dynamically adjusts coordinate injection frequency (0.5s for high speeds / 2.0s for low speeds) to balance smoothness and CPU efficiency.
*   **🎯 Smart Map Annotation Clustering**: Annotations automatically cluster based on zoom level, maintaining UI responsiveness even with thousands of "PurePoints" imported.
*   **⚡ Zero-Lag Sidebar Tab Switching**: Employs `ZStack` view persistence to eliminate UI stuttering during tab transitions.
*   **📦 Favorite Grouping Cache Optimization**: Pre-calculates and caches location groupings for "Favorites," ensuring instant loading even with hundreds of saved entries.
*   **🛡️ Connection Watchdog**: Built-in monitoring detects and recovers interrupted RSD tunnels, ensuring rock-solid stability during long simulation sessions.

---

## ⚙️ Technical Workflow

**flyflyfly** orchestrates a seamless location injection flow from macOS to iOS:

```mermaid
graph TD
    %% Roles
    subgraph UI_Layer [SwiftUI UI Layer]
        A[ContentView / Sidebar] -->|1. Select Mode| B(AppViewModel)
        A -->|4. Set Coords/Route| B
        A -->|6. Click Start| B
    end

    subgraph Logic_Layer [Core Logic Layer]
        B -->|2. Req Connection| C{DeviceManager}
        
        subgraph Connection_Process [Tunneling & Connectivity]
            C -->|USB| D[USBMuxD Discovery]
            C -->|Wi-Fi| E[mDNS / ZeroConf Search]
            D & E --> F[Build RSD Tunnel]
            F -->|Invoke| G[bundled/pymobiledevice3]
            G -->|Elevate| H[macOS Password Prompt]
            H -->|Success| I[Established Tunnel]
        end

        B -->|5. Path Planning| J[RouteMotionEngine]
        J -->|Interpolation| K[Smooth Coords Stream]
    end

    subgraph Service_Layer [Service & Background Process]
        I -->|3. Status Update| B
        B -->|7. Start Stream| L[DVTLocationStream]
        L -->|Data Pipe| M[bundled/dvt-location-stream]
        K -->|Real-time Push| L
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
| **Arch** | Apple Silicon (M1/M2/M3), Intel x86_64 |
| **macOS** | macOS 13 Ventura / 14 Sonoma / 15 Sequoia |
| **iOS / iPadOS** | 16.0, 17.0, 18.0+ |
| **Connectivity** | High-Speed USB, Wireless RSD Tunneling |

---

## 🚀 Getting Started

### 1. Device Setup
- Enable "Developer Mode" on your iOS device.
- Connect via USB once to establish trust with your Mac.

### 2. Build & Run
```bash
git clone https://github.com/flyflyfly/flyflyfly.git
cd flyflyfly
xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build
```

---

## ⚖️ Disclaimer
This tool is for educational purposes, development testing, and personal privacy only. Users are responsible for compliance with third-party terms of service.

---

## ☕ Support
If you find this project useful, consider supporting development via [Ko-fi](https://ko-fi.com/flyflyfly).

<!-- 
SEO Metadata & AI Indexing Keywords:
#flyflyfly #iOSGPS #iPhoneGPS #GPSSpoofer #PokemonGO #PikminBloom #MonsterHunterNow #iOS17 #iOS18 #AppleSilicon #MacGPS #iOSSpoofing #PokemonGOJoystick #PikminBloomSPOOF #MHNSpoof #VirtualLocation #iOSDevelopment #M1Mac #M2Mac #M3Mac #LocationSimulator #MockLocation #FakeGPS
-->
