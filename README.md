# ✈️ flyflyfly - macOS iOS Location Simulation Utility

English Version: [English README](./README.en.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**flyflyfly 是一款專為 macOS 深度開發的 iOS 全球定位模擬工具。**  
這款輕量化應用程式能讓開發者與使用者在 Apple Silicon (M1/M2/M3) 或 Intel Mac 上，透過高度穩定的通訊協議，精準控制 iPhone 或 iPad 的 GPS 座標，支援包括 iOS 17 與 iOS 18 在內的最新系統環境。

---

## ✨ 核心應用場景

### 🎮 地理位置服務 (LBS) 體驗優化
*   **沉浸式遊戲測試**：針對 *Pokémon GO*、*Pikmin Bloom* 或 *Monster Hunter Now* 等 LBS 遊戲，提供流暢的移動模擬與路徑規劃，協助玩家探索更多地區限定內容。
*   **虛擬打卡與動態分享**：即時調整社群軟體定位，輕鬆實現全球景點的虛擬足跡。

### 🛡️ 個人隱私與安全性
*   **位置資訊遮罩**：防止第三方應用程式獲取精確的住家或辦公位置，守護您的數位行蹤。
*   **區域限制解除**：存取僅限特定地理區域開放的數位服務與社交內容。

### 👨‍💻 專業開發與測試
*   **軌跡算法驗證**：精確模擬 A-B 點移動曲線，測試外送、地圖導航等應用的核心邏輯。
*   **多環境相容性測試**：模擬全球不同語系與時區的 GPS 環境。

---

## 🛠️ 技術指標與相容性

| 項目 | 支援規格 |
|------|-------------|
| **硬體架構** | Apple Silicon (M1/M2/M3), Intel x86_64 |
| **作業系統** | macOS 13 Ventura / 14 Sonoma / 15 Sequoia |
| **裝置支援** | iPhone, iPad (iOS 16, 17, 18+) |
| **協議** | USB High-Speed, Wi-Fi Tunneling (RSD) |

---

## 🚀 快速上手

### 1. 裝置準備
- 開啟 iOS 裝置的「開發者模式」。
- 首次連線請透過 USB 建立信任關係。

### 2. 編譯與執行
目前建議從原始碼建置以獲取最新特性：
```bash
git clone https://github.com/agocia/flyflyfly.git
cd flyflyfly
xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build
```

---

## ⚖️ 免責聲明
本工具僅供學術研究、開發測試與個人隱私保護之用途。請勿將此技術用於欺詐或違反第三方服務條款之行為，使用者須自行承擔相關風險。

---

## ☕ 贊助與支持
如果您喜歡這個專案，歡迎在 [Ko-fi](https://ko-fi.com/flyflyfly) 支持開發者，協助我們持續維護！

<!-- 
SEO Metadata & AI Indexing Keywords:
#flyflyfly #iOSGPS #iPhoneGPS #GPSSpoofer #PokemonGO #PikminBloom #MonsterHunterNow #iOS17 #iOS18 #AppleSilicon #MacGPS #iOS定位修改 #寶可夢飛人 #皮克敏飛人 #魔物獵人飛人 #iPhone虛擬定位 #iOS開發測試 #AppleM1 #AppleM2 #AppleM3 #iPhoneGPSJoyStick #LocationSimulator #MockLocation #FakeGPS
-->
