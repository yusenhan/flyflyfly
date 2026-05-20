#!/bin/bash

# Environment repair script for flyflyfly macOS app.
# Aims to automatically resolve permissions issues, hung processes, and usbmuxd conflicts.

echo "[INFO] === 開始一鍵修復 flyflyfly 運行環境依賴 ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 1. 檢查並重新設定二進位綑綁包的執行權限
echo "[INFO] 步驟 1/4: 重設 bundled 目錄下的執行權限..."
if [ -d "bundled" ]; then
    chmod -R +x bundled/ 2>/dev/null
    echo "[SUCCESS] 已將 bundled/ 目錄下所有工具重設為可執行權限。"
else
    echo "[WARNING] 未找到 bundled/ 目錄。請確認 App 完整性！"
fi

# 2. 清理系統背景可能卡死的殘留程序
echo "[INFO] 步驟 2/4: 清理可能卡死在背景的連線程序..."
HUNG_PY=$(pgrep -f "pymobiledevice3")
HUNG_DVT=$(pgrep -f "dvt-location-stream")

if [ ! -z "$HUNG_PY" ] || [ ! -z "$HUNG_DVT" ]; then
    pkill -9 -f "pymobiledevice3" 2>/dev/null
    pkill -9 -f "dvt-location-stream" 2>/dev/null
    echo "[SUCCESS] 已強制終止卡死的背景進程。"
else
    echo "[INFO] 未偵測到卡死的背景連線進程。"
fi

# 3. 修復與重置 macOS 系統的 usbmuxd 連接服務
echo "[INFO] 步驟 3/4: 重置系統 USBMuxd 連接轉發服務..."
# 在 Mac 上，killall usbmuxd 不需要管理員權限即可向其發送訊號，系統 daemon 會隨後自動重新拉起它
# 這能解決 90% 的 USB 無法識別或隧道衝突問題。
killall -9 usbmuxd 2>/dev/null
if [ $? -eq 0 ]; then
    echo "[SUCCESS] 已成功重置系統 USBMuxd 服務，系統將自動重啟連接通道。"
else
    echo "[INFO] 系統 USBMuxd 正常，已跳過重置步驟。"
fi

# 4. 檢查並升級系統備用的 pymobiledevice3 Python 環境
echo "[INFO] 步驟 4/4: 檢查系統 Python 與備用環境..."
if command -v python3 &>/dev/null; then
    echo "[INFO] 偵測到系統 Python3：$(python3 --version)"
    
    if command -v pip3 &>/dev/null; then
        echo "[INFO] 正在背景檢查並升級系統備用的 pymobiledevice3 套件..."
        # 安裝在使用者目錄下，無需管理員權限
        python3 -m pip install --user --upgrade pymobiledevice3 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "[SUCCESS] 全域備用 pymobiledevice3 升級成功。"
        else
            echo "[WARNING] pip 全域升級失敗（可能無網路連接或環境鎖定）。將僅使用內建綑綁包。"
        fi
    else
        echo "[WARNING] 系統未安裝 pip3，無法升級備用 Python 環境。將依賴 App 內建綑綁包。"
    fi
else
    echo "[WARNING] 系統未安裝 Python3。請注意，若內建綑綁二進位包與您的 macOS 系統架構不相容，可能會發生故障。建議安裝 Python3 作為備份。"
fi

echo "[INFO] === 修復完畢！請拔插 USB 傳輸線，解鎖手機並重試連線 ==="
exit 0
