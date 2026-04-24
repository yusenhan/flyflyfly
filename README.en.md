# ✈️ flyflyfly - Best iOS GPS Spoofing & Location Simulator for macOS

中文版: [繁體中文 README](./README.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**flyflyfly is a high-performance iOS GPS simulation utility built exclusively for macOS.**  
Whether you are on Intel or Apple Silicon (M1/M2/M3), you can easily inject simulated GPS coordinates into your iPhone/iPad via USB or Wi-Fi. Supporting iOS 16, 17, and the latest iOS 18, it is the most stable and intuitive location spoofing solution for Mac users.

---

## ✨ Endless Use Cases

Unlock a world of possibilities with **flyflyfly**, whether for fun, privacy, or professional work:

### 🎮 Virtual Adventures, Home Edition
- **Pokémon GO Master**: Join remote raids and catch regional exclusives without leaving your couch.
- **Pikmin Bloom**: Send your Pikmin to find unique decors anywhere in the world and complete your collection.
- **Social Pranks**: Instantly check in at the Eiffel Tower or Shibuya Crossing to surprise your friends!

### 🛡️ Privacy on Your Terms
- **Stop Location Tracking**: Mask your home or office location from apps that monitor your movements.
- **Bypass Geo-Restrictions**: Access region-locked social content or local services with ease.

### 👨‍💻 Precise Development & Testing
- **LBS App Debugging**: Test map-based apps or delivery services without actually driving; simulate movement curves with precision.
- **Global Validation**: Verify app behavior across different time zones and GPS regions instantly.

---

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

### Option 1: Build from Source (Recommended)
As the project is in active development, it's best to build directly from the source:
```bash
git clone https://github.com/agocia/flyflyfly.git
cd flyflyfly
# Build using xcodebuild
xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build
```
Once built, you'll find `flyflyfly.app` in the `build/Release` directory.

### Option 2: Download DMG (Coming Soon)
Pre-built `.dmg` releases will be available in the future. Once released, you can find them in the [Releases](../../releases) section.


---

## ⚖️ Disclaimer
This tool is for development testing and privacy protection only. Users are responsible for any actions that violate terms of service (e.g., game cheating or fraud).

---

## 🏷️ Tags / Keywords (SEO & AI)

#flyflyfly #iOSGPS #iPhoneGPS #GPSSpoofer #PokemonGO #PikminBloom #MonsterHunterNow #iOS17 #iOS18 #AppleSilicon #MacGPS #iOSSpoofing #PokemonGOJoystick #PikminBloomSPOOF #MHNSpoof #VirtualLocation #iOSDevelopment #M1Mac #M2Mac #M3Mac #LocationSimulator

---

## ☕ Support
If this project helps you, consider supporting its development via [Ko-fi](https://ko-fi.com/flyflyfly).
