# ✈️ flyflyfly (macOS GPS Spoofing Tool)

English Version: [English README](./README.en.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**專為 Mac 用戶打造的 iOS 定位模擬神器。**  
透過 USB 或 Wi-Fi，在 iPhone/iPad 上注入模擬 GPS 座標，支援 Apple Silicon (M1/M2/M3) 與 Intel 晶片原生運作。

---

## ✨ 核心特色

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

## ☕ 贊助與支持
如果這個專案對你有幫助，歡迎在 [Ko-fi](https://ko-fi.com/agocia) 支持開發者，讓專案持續優化！
