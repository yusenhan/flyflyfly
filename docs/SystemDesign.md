# flyflyfly - 系統設計文件 (SD)

## 1. 架構設計 (Architecture)
flyflyfly 採用 **Swift-C++ 混合架構**，結合了 SwiftUI 的宣告式 UI 優勢與 C++ 的硬體加速計算能力。

### 1.1 分層架構
*   **UI Layer (SwiftUI)**：負責佈局、動畫及使用者交互。採用 MVVM 模式。
*   **Business Logic (Swift)**：負責 Store 狀態管理（Combine）、KML 解析與地圖交互。
*   **Bridge Layer (Obj-C++)**：作為 Swift 與 C++ 之間的數據轉換橋樑 (`FastMotionEngineWrapper`)。
*   **Compute Core (C++20)**：負責重型數學運算、空間索引及原生 Socket 通訊。

## 2. 關鍵組件設計

### 2.1 C++ 效能引擎 (`FastMotionEngine`)
*   **數學模型**：實作 Haversine 公式進行距離計算，並使用 Slerp (球面線性插值) 確保長距離移動路徑精確。
*   **優化**：利用 C++ 二分搜尋 (`std::lower_bound`) 取代 Swift 線性搜尋，搜尋效率提升至 $O(\log N)$。

### 2.2 空間索引核心 (`SpatialIndex`)
*   **資料結構**：採用 **Quadtree (四元樹)** 進行地理座標管理。
*   **應用場景**：在地圖縮放時，快速篩選出可見範圍內的點位，支援 10 萬級數據的實時過濾。

### 2.3 原生通訊隧道 (`NativeTunnel`)
*   **技術實作**：使用 C++ 原生 Socket (POSIX) 直接與 iOS 的 DVT Instruments 埠通訊。
*   **協議優化**：移除了 Python 轉發進程，實現零拷貝 (Zero-copy) 數據推送，記憶體佔用降低 90%。

## 3. 數據流與狀態管理
*   **Store Pattern**：將 App 分為 `SimulationStore` (模擬狀態)、`DeviceStore` (裝置狀態) 等獨立儲存單元。
*   **Throttling (節流)**：在 ViewModel 層對 Store 的變動通知實施 100ms~500ms 的節流，防止高頻更新凍結 UI。

## 4. 外部整合
*   **pymobiledevice3**：作為初始化階段的「握手工具」，負責處理複雜的 Apple RSD 認證與隧道建立。
*   **USBMuxD**：底層 USB 通訊守護進程。

## 5. 編譯與自動化
*   **Xcode 配置**：需開啟 `C++ Interoperability Mode`。
*   **update_pbxproj.py**：自研的同步腳本，自動維護 Swift 與 C++ 混合檔案的編譯依賴關係。

## 6. 效能優化細節
*   **View Persistence**：側邊欄採用摺疊 Section 而非 Tab，確保佈局樹穩定，消除 AttributeGraph 循環渲染。
*   **Background Indexing**：所有大規模點位的索引構建均在背景執行 (`Task.detached`)，保證主執行緒永遠不會因為數據處理而卡頓。
