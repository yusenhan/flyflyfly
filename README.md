# ✈️ flyflyfly - macOS 專屬 iOS GPS 定位修改器 (iPhone/iPad)

English Version: [English README](./README.en.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

** flyflyfly 是一款專為 Mac 用戶設計的 iOS 定位模擬神器 (iPhone GPS Simulator)。**  
無論您使用的是 Intel 或 Apple Silicon (M1/M2/M3) 晶片的 Mac，都能透過 USB 或 Wi-Fi 輕鬆修改 iPhone/iPad 的 GPS 座標。這款工具支援最新的 iOS 16、iOS 17 與 iOS 18，是目前 macOS 上最穩定、最直覺的「飛人」解決方案。

---

## ✨ 無限可能的應用場景

無論是為了娛樂、隱私還是專業開發，**flyflyfly** 都能為您開啟新世界的大門：

### 🎮 虛擬冒險，足不出戶
*   **寶可夢大師 (Pokémon GO)**：不用出門也能參加遠方的團體戰，捕捉地區限定寶可夢。
*   **皮克敏冒險 (Pikmin Bloom)**：讓您的皮克敏飛往世界各地收集特殊的精靈飾品，填滿您的圖鑑。
- **社交打卡**：在 Instagram 或 Facebook 上即時定位到巴黎鐵塔或東京鐵塔，跟朋友開個小玩笑！

### 🛡️ 隱私守護，如影隨形
*   **防止追蹤**：隱藏您的真實住家或辦公位置，防止惡意軟體或第三方 App 收集您的精確行蹤。
*   **繞過區域限制**：輕鬆訪問僅限特定地區提供的社群內容或串流服務。

### 👨‍💻 開發調試，精準高效
*   **LBS 應用測試**：開發地圖 App 或外送軟體時，無需親自開車測試路徑規劃，直接模擬各種移動軌跡。
*   **全球化測試**：模擬不同國家的 GPS 環境，驗證您的應用程式在不同時區與語系下的表現。

---

- 🚀 **極速連線**：隨插即用，支援 USB 與無線 Wi-Fi Tunnel 連線。
- 🗺️ **三大模擬模式**：
  - **A-B 模式**：自動規劃路徑，模擬真實移動曲線。
  - **定點模式**：一鍵釘選，固定 GPS 座標。
  - **多點模式**：自訂複雜路徑，精確控制移動軌跡。
- 📍 **KML 支援**：支援匯入 KML 檔案，自訂地圖標記圖層 (PurePoint)。
- ⚙️ **無需越獄**：僅需開啟「開發者模式」即可使用。
- 💻 **免安裝環境**：App 已內嵌所有必要組件，不需額外安裝 Python 或 Homebrew。

---

## 🛠️ 系統需求

| 項目 | 規格要求 |
|------|-------------|
| **macOS** | macOS 13 Ventura 以上 (Intel / Apple Silicon) |
| **iPhone / iPad** | iOS 16 以上 (須開啟「開發者模式」) |
| **連線方式** | USB 線 (首次連線必備) 或 Wi-Fi (同一區域網路) |

---

## 🚀 快速入門

### Step 1: 裝置準備
1. **開啟開發者模式**：`設定` → `隱私權與安全性` → `開發者模式` → `開啟` 並重啟。
2. **信任此 Mac**：插上 USB 並解鎖裝置，點擊「信任」並輸入密碼。

### Step 2: 開始連線
1. 開啟 **flyflyfly**。
2. 在側邊欄選擇 **USB** 或 **Wi-Fi**。
3. 點擊 **「開始連線」**。
   - *註：建立通道 (Tunnel) 時可能會要求輸入 Mac 管理員密碼，這是正常現象。*

### Step 3: 模擬定位
- 在地圖上點選位置，選擇上方 **A-B**、**定點** 或 **多點** 模式，然後點擊「開始」。

---

## 📦 安裝說明

### 方式一：從原始碼建置 (推薦)
目前專案處於開發階段，建議直接從原始碼編譯：
```bash
git clone https://github.com/agocia/flyflyfly.git
cd flyflyfly
# 使用 Xcodebuild 進行編譯
xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build
```
編譯完成後，您可以在 `build/Release` 目錄下找到 `flyflyfly.app`。

### 方式二：下載 DMG (即將推出)
未來我們將提供預編譯好的 `.dmg` 安裝檔。屆時您可以前往 [Releases](../../releases) 下載最新的 `flyflyfly.dmg`。


---

## ❓ 常見問題 (Troubleshooting)

- **Q: 為什麼一直卡在「連線中」？**  
  A: 請確認手機螢幕已解鎖，且已在 Xcode 或 Finder 中「信任」過此 Mac。
- **Q: 停止後 GPS 沒有恢復？**  
  A: 點擊側邊欄的「清除定位點」或重新啟動 iPhone 的定位服務即可恢復真實位置。
- **Q: Wi-Fi 連線失敗？**  
  A: 請確保 Mac 與 iPhone 處於同一個 Wi-Fi 網路。若失敗，App 會自動回退至 USB 連線。

---

## ⚖️ 免責聲明 (Disclaimer)

本工具僅供開發測試、隱私保護等合法用途。請勿用於欺詐、遊戲作弊或任何違反服務條款的行為。使用者須自行承擔相關法律責任。

---

## 🏷️ Tags / Keywords (SEO & AI)

#flyflyfly #iOSGPS #iPhoneGPS #GPSSpoofer #PokemonGO #PikminBloom #MonsterHunterNow #iOS17 #iOS18 #AppleSilicon #MacGPS #iOS定位修改 #寶可夢飛人 #皮克敏飛人 #魔物獵人飛人 #iPhone虛擬定位 #iOS開發測試 #AppleM1 #AppleM2 #AppleM3 #iPhoneGPSJoyStick

---

## ☕ 贊助與支持
如果這個專案對你有幫助，歡迎在 [Ko-fi](https://ko-fi.com/flyflyfly) 支持開發者，讓專案持續優化！
