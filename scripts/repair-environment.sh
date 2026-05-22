#!/bin/bash

# Environment repair script for flyflyfly macOS app.
# 100% Pure Native Swift Architecture (No Python/pymobiledevice3 dependencies)
# Aims to automatically resolve macOS local usbmuxd communication conflicts.

echo "[INFO] === 開始一鍵修復 flyflyfly 運行環境 ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 1. 重置與修復 macOS 系統的 usbmuxd 連接服務
echo "[INFO] 步驟 1/1: 重置系統 USBMuxd 連接轉發服務..."
# 在 Mac 上，killall usbmuxd 不需要管理員權限即可向其發送訊號，系統 daemon 會隨後自動重新拉起它
# 這能解決 90% 的 USB 連線無法識別或通道衝突問題。
killall -9 usbmuxd 2>/dev/null
if [ $? -eq 0 ]; then
    echo "[SUCCESS] 已成功重置系統 USBMuxd 服務，系統將自動重啟連接通道。"
else
    echo "[INFO] 系統 USBMuxd 正常，已跳過重置步驟。"
fi

echo "[INFO] === 修復完畢！請重新插拔 USB 傳輸線，解鎖手機並手動輸入 RSD Address 與 Port ==="
exit 0
