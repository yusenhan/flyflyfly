# ✈️ flyflyfly (macOS GPS Spoofing Tool)

中文版: [繁體中文 README](./README.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**A powerful GPS spoofing utility for iOS devices, built exclusively for macOS.**  
Inject simulated coordinates into iPhone/iPad over USB or Wi-Fi. Supports native execution on Apple Silicon (M1/M2/M3) and Intel Macs.

---

## ✨ Features

- 🚀 **Instant Setup**: Plug & play, supports both USB and Wi-Fi Tunneling.
- 🗺️ **Three Operation Modes**:
  - **A-B Route**: Auto-calculates routes with realistic movement.
  - **Pin Mode**: Fixed location spoofing with a single click.
  - **Multi-Waypoints**: Customize complex paths for precise control.
- 📍 **KML Overlays**: Import `.kml` files to display custom POIs (PurePoint).
- ⚙️ **No Jailbreak Required**: Works entirely within iOS "Developer Mode."
- 💻 **All-in-One**: No need to install Python, Homebrew, or external packages.

---

## 🛠️ Requirements

| Item | Requirement |
|------|-------------|
| **macOS** | 13.0 Ventura or later (Universal Binary) |
| **iOS / iPadOS** | 16.0 or later (Developer Mode enabled) |
| **Connection** | USB (for pairing) or Wi-Fi (same network) |

---

## 🚀 Quick Start

1. **Enable Developer Mode**: `Settings` → `Privacy & Security` → `Developer Mode` → `On`.
2. **Trust the Mac**: Connect via USB, unlock your phone, and tap "Trust."
3. **Launch flyflyfly**: Choose connection mode and click **"Start Connection."**
4. **Spoof Location**: Select a point on the map and click "Start."

---

## 📦 Installation

### Option 1: DMG (Recommended)
Download the latest `flyflyfly.dmg` from the [Releases](../../releases) page and drag it to your Applications folder.

### Option 2: Build from Source
```bash
git clone https://github.com/agocia/flyflyfly.git
cd flyflyfly
xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build
```

---

## ⚖️ Disclaimer
This tool is for development testing and privacy protection only. Users are responsible for any actions that violate terms of service (e.g., game cheating or fraud).

---

## ☕ Support
If this project helps you, consider supporting its development via [Ko-fi](https://ko-fi.com/agocia).
