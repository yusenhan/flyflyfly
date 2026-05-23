# flyflyfly - 系統設計文件 (System Design)

**文件與系統版本**：`v0.99a`

## 1. 架構設計 (Architecture)
flyflyfly 採用 **100% 全原生 Swift 架構**，擺脫了所有外部 Python 背景行程 (`pymobiledevice3`)、外部二進位工具 (`dvt-location-stream`) 及 C++ 通訊封裝與 Socket 隧道。這項革新不僅顯著降低了系統資源佔用，亦解決了多執行緒同步、本地埠衝突與 Apple 安全沙盒權限限制等棘手問題。

### 1.1 分層架構
*   **UI Layer (SwiftUI)**：負責佈局、動畫及使用者交互。採用高防禦性的單向資料流狀態同步（Store Pattern），側邊欄與地圖視區實現了高度自適應。
*   **Business Logic (Swift Core)**：
    *   `AppViewModel.swift`：全域運算與模擬中樞，協調定位搜尋、隨機漫步防作弊注入及狀態機切換。
    *   `RouteMotionEngine.swift`：純 Swift 實作的 GPS 高頻插值與路網行進邏輯。
*   **Native Connection Core (Swift Services)**：
    *   `USBMuxMonitor`：直連 `/var/run/usbmuxd` 本地網域通訊端（Domain Socket），實時感應 USB 熱插拔並擷取 `lockdownd` 裝置資訊。
    *   `DTXClient` 與 `DTXMessage`：自研的純 Swift DTX 協定封裝器，支援 TLS（NWConnection）與 TCP 連線，複用單一通道並行傳輸多個控制服務。
    *   `DVTLocationStream`：原生 DTX 位置模擬適配器，將精緻插值後的座標直接編碼為 binary Plist 並以 DTX `Buffer` (TypeTag = 2) 封裝，發射至 Apple 私有模擬服務。

---

## 2. 關鍵組件設計

### 2.1 原生 USBMux 監聽服務 (`USBMuxMonitor`)
*   **技術實作**：使用原生 Socket 連接 `unix://var/run/usbmuxd`，發送 `Listen` 協定封包。
*   **即時回應**：當收到 `Attached` 事件後，異步建立與手機 `lockdownd`（Port 62078）的連線，透過 plist 握手協議解析出手機的名稱、ProductType 以及 ProductVersion，實現毫秒級的隨插即用體驗。

### 2.2 純 Swift 原生 DTX 協定引擎 (`DTXMessage` & `DTXClient`)
*   **編解碼安全性**：
    *   **無對齊安全加固**：使用 `.loadUnaligned(as:)` 防範記憶體非對齊存取造成的 `EXC_BAD_ACCESS` 閃退。
    *   **相對偏移切片**：全面採用 `self.startIndex` 動態偏移範圍讀取，徹底根治 `removeFirst()` 引起 Range 越界 index OOB 崩潰。
    *   **正確編碼**：以 `Swift.withUnsafeBytes(of:)` 封裝數值寫入，避免 `Data.append` 發生的序列數字 Byte 截斷問題。
*   **多路複用 (Multiplexing)**：
    *   **Channel 1 (sysmontap)**：訂閱實時系統 CPU 與 RAM 效能數據。
    *   **Channel 2 (coreservices.LocationSimulation)**：定位模擬專用通道。透過 `NSKeyedArchiver` 序列化將緯度與經度包裹在 `NSNumber` 中，並作為 `simulateLocationWithLatitude:longitude:` RPC 參數發送。

### 2.3 軌跡插值與防作弊漂移引擎 (`RouteMotionEngine`)
*   **物理漫步漂移 (Jitter Spoofer)**：實作隨機漫步運動模型，當車輛行駛或定點定位時，在 `[-0.25m, 0.25m]` 範圍內進行微幅呼吸式抖動，防止第三方防作弊機制檢測到「完美靜止」狀態。
*   **隨機紅綠燈模擬**：每行駛一定距離自動觸發 `[15s ~ 45s]` 的紅燈等待狀態，模擬真實車流。

---

## 3. 數據流與狀態管理
*   **單一事實來源 (Single Source of Truth)**：由 `AppViewModel` 主導全域狀態管理，包含 `AppState`（連線中、已連線、定位中、模擬行進中等）的狀態機流轉。
*   **Throttling & Debounce**：針對高頻 GPS 點位更新與側邊欄狀態渲染，實作排程節流，防止主執行緒 AttributeGraph 渲染超載，確保 UI 更新率維持在 60 FPS。

---

## 4. 外部整合與環境修復
*   **純 Native 零依賴**：完全不依賴 python 執行環境、`pymobiledevice3` 套件、`dvt-location-stream` 外部 CLI、虛擬環境或 Homebrew。
*   **一鍵自癒修復 (`repair-environment.sh`)**：重置本地 USBMuxd 系統守護服務，排除連線埠佔用或通道衝突，隨後重新建立 Native Socket 連接。

---

## 5. 編譯與分發
*   專案直接利用原生 Xcode 建置系統編譯。
*   不含任何外部 Python Script 打包配置或 spec 檔案，確保在 Debug 與 Release（WMO `-O` 全模組優化）環境下皆能 100% 綠燈成功編譯，產生極輕量、零污染的 macOS 應用程式。
