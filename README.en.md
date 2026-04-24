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
git clone https://github.com/agocia/flyflyfly.git
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
