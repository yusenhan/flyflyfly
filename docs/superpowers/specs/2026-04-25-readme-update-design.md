# README Update Design Doc

**Goal:** Update `README.md` and `README.en.md` to highlight recent performance and UI optimizations.

**Architecture:** Add a new "Latest Features & Performance Optimizations" section to both Chinese and English READMEs.

**Tech Stack:** Markdown.

---

## 1. Traditional Chinese README Updates (`README.md`)

Insert the following section after the "✨ 核心應用場景" section:

```markdown
---

## 🚀 最新特性與效能優化 (v1.1+)

我們持續優化核心算法與使用者體驗，最新版本包含以下重大改進：

*   **⚡ 並行路徑計算**：採用 Swift Concurrency 的 `TaskGroup` 技術，大幅提升多點路徑規劃的生成速度。
*   **🌍 高精度大圓路徑插值**：針對超過 500 米的長距離移動，自動啟用大圓路徑 (Great Circle) 算法，確保全球尺度的移動軌跡精確無誤。
*   **⏲️ 動態更新頻率**：根據移動時速自動調整心跳包頻率（高速 0.5s / 低速 2.0s），在維持模擬流暢度的同時極大化節省 CPU 資源。
*   **🎯 智能地圖聚合 (Clustering)**：地圖點位自動根據縮放比例進行聚合，即使導入成千上萬個「純點」圖層也能保持介面清爽流暢。
*   **🛡️ 連線守護進程 (Watchdog)**：內建連線監控機制，自動偵測並恢復中斷的 RSD 隧道，確保長時間模擬的穩定性。
```

## 2. English README Updates (`README.en.md`)

Insert the following section after the "✨ Key Use Cases" section:

```markdown
---

## 🚀 Latest Features & Performance Optimizations (v1.1+)

We are constantly improving our core algorithms and user experience. The latest version includes:

*   **⚡ Parallel Route Calculation**: Leverages Swift Concurrency's `TaskGroup` to significantly speed up multi-point path generation.
*   **🌍 High-Precision Great Circle Interpolation**: Automatically employs Great Circle algorithms for segments over 500m, ensuring pinpoint accuracy for long-distance simulations.
*   **⏲️ Adaptive Update Frequency**: Dynamically adjusts coordinate injection frequency (0.5s for high speeds / 2.0s for low speeds) to balance smoothness and CPU efficiency.
*   **🎯 Smart Map Annotation Clustering**: Annotations automatically cluster based on zoom level, maintaining UI responsiveness even with thousands of "PurePoints" imported.
*   **🛡️ Connection Watchdog**: Built-in monitoring detects and recovers interrupted RSD tunnels, ensuring rock-solid stability during long simulation sessions.
```
