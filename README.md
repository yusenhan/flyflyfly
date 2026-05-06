# ✈️ flyflyfly - macOS iOS Location Simulation Utility

English Version: [English README](./README.en.md)

![macOS Support](https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple)
![iOS Support](https://img.shields.io/badge/iOS-16.0+-brightgreen?style=flat-square&logo=ios)
![Apple Silicon Support](https://img.shields.io/badge/Apple%20Silicon-Native-orange?style=flat-square)
![C++ Core](https://img.shields.io/badge/Engine-C%2B%2B20-blueviolet?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

**flyflyfly 是一款專為 macOS 打造的 iOS 全球定位模擬旗艦工具。**  
透過 C++20 效能引擎與原生 Socket 注入技術，讓開發者在 Apple Silicon (M1/M2/M3) 或 Intel Mac 上，以極低資源佔用精準控制 iPhone/iPad GPS 座標，完美支持 iOS 17 & 18。

---

## ✨ 核心應用場景

### 🎮 地理位置服務 (LBS) 極致體驗
*   **絲滑遊戲測試**：針對 *Pokémon GO*、*Monster Hunter Now* 等遊戲，提供毫秒級反應的移動模擬。
*   **全球虛擬打卡**：即時切換社群定位，足跡遍佈全球名勝。

### 🛡️ 隱私與開發測試
*   **數位足跡隱蔽**：徹底遮蔽真實住家/辦公位置，防止 App 追蹤。
*   **專業算法驗證**：精確模擬 A-B 路徑插值，適合地圖與物流應用開發。

---

## 🚀 性能革命 (C++ 驅動優化)

本專案已完成從純 Swift 向 **Swift-C++ 混合架構** 的全面轉型，帶來前所未有的效能：

*   **🚀 C++ 高效能運算核心**：核心座標插值與距離計算採用 C++20 重構，搜尋複雜度從 $O(N)$ 優化至 $O(\log N)$，運算延遲近乎於零。
*   **🎯 原生空間索引 (Quadtree)**：利用 C++ 實作四元樹索引，支援地圖上同時載入**數萬個**點位而無任何縮放卡頓。
*   **⚡ 原生通訊隧道 (Native Tunnel)**：徹底移除 Python 推送進程。改用 C++ 直接透過 Socket 與 iOS 設備通訊：
    *   **記憶體節省 90%**：單個連線開銷從 50MB+ 降至 **5MB 以下**。
    *   **零延遲注入**：消除 IPC (管道) 序列化延遲，定位更新更加精準。
*   **📐 垂直摺疊控制面板**：取代舊式 Tab 切換，採用分段摺疊設計，消除分頁切換延遲，操作更直觀。
*   **⚡ 側邊欄零延遲體驗**：透過 UI 架構優化與 C++ 運算核心隔離，確保介面反應毫秒級同步。
*   **🔌 直覺連線管理**：連線按鈕整合至裝置狀態行，一鍵點擊即可完成手機與 Mac 的通訊連結。
*   **📦 速度精確控制**：移除冗餘的拖拉 Bar，改用 TextField 與 Stepper 組合，提供更專業、穩定的速度設定。


---

## ⚙️ 技術工作流程 (Technical Workflow)

```mermaid
graph TD
    %% 角色定義
    subgraph UI_Layer [SwiftUI 介面層]
        A[ContentView / Sidebar] -->|1. 選擇連線| B(AppViewModel)
        A -->|4. 設定座標| B
        A -->|6. 開始移動| B
    end

    subgraph Logic_Layer [C++ 效能引擎層]
        B -->|2. 要求連線| C{DeviceManager}
        
        subgraph Connection_Process [RSD 隧道建立]
            C -->|偵測裝置| D[USBMuxD / mDNS]
            D -->|呼叫| G[bundled/pymobiledevice3]
            G -->|要求權限| H[macOS 密碼提示]
            H -->|成功| I[實體 RSD 通道建立]
        end

        B -->|5. 軌跡運算| J[C++ FastMotionEngine]
        J -->|O log N 檢索| K[座標插值串流]
    end

    subgraph Native_Service [原生注入服務]
        I -->|3. 通道就緒| B
        B -->|7. 啟動原生流| L[DVTLocationStream]
        L -->|C++ Socket| M[原生通訊隧道]
        K -->|零拷貝推送| M
    end

    subgraph iOS_Device [iOS 裝置端]
        M -->|DVT Instruments| N[iOS 定位子系統]
        N -->|覆蓋 GPS| O[第三方 App / 遊戲]
    end
```

---

## 🛠️ 技術指標

| 項目 | 支援規格 |
|------|-------------|
| **引擎標準** | C++ 20 / Swift 5.9 Interop |
| **硬體架構** | Apple Silicon (M1/M2/M3), Intel x86_64 |
| **系統版本** | macOS 13+, iOS 16, 17, 18+ |
| **通訊方式** | USB High-Speed / 無線 RSD 隧道 |

---

## 🚀 快速上手

目前 C++ 核心版本建議直接編譯建置：
```bash
git clone https://github.com/flyflyfly/flyflyfly.git
cd flyflyfly
# 執行自動配置腳本
python3 update_pbxproj.py
# 編譯並執行
./runfly.sh
```

---

## ⚖️ 免責聲明
本工具僅供教育、開發測試與隱私保護用途。使用者須自行承擔法律與第三方服務條款之風險。

<!-- 
#flyflyfly #iOSGPS #iPhoneGPS #GPSSpoofer #PokemonGO #PikminBloom #MonsterHunterNow #iOS17 #iOS18 #AppleSilicon #MacGPS #iOS定位修改 #iPhone虛擬定位 #iOS開發測試 #AppleM3 #LocationSimulator #MockLocation #FakeGPS
-->
