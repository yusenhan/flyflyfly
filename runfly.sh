#!/bin/bash
# 運行編譯好的 flyflyfly App (優先運行 Release 版本)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RELEASE_PATH_NEW="${SCRIPT_DIR}/build/dmg/DerivedData/Build/Products/Release/flyflyfly.app"
RELEASE_PATH_OLD="${SCRIPT_DIR}/build/Release/flyflyfly.app"
DEBUG_PATH_NEW="${SCRIPT_DIR}/build/DerivedData_Debug/Build/Products/Debug/flyflyfly.app"
DEBUG_PATH_OLD="${SCRIPT_DIR}/build/Debug/flyflyfly.app"

if [ -d "$RELEASE_PATH_NEW" ]; then
    echo "[INFO] 正在開啟最新 Release 版本: ${RELEASE_PATH_NEW}..."
    open "$RELEASE_PATH_NEW"
elif [ -d "$RELEASE_PATH_OLD" ]; then
    echo "[INFO] 正在開啟 Release 版本: ${RELEASE_PATH_OLD}..."
    open "$RELEASE_PATH_OLD"
elif [ -d "$DEBUG_PATH_NEW" ]; then
    echo "[INFO] 正在開啟最新 Debug 版本: ${DEBUG_PATH_NEW}..."
    open "$DEBUG_PATH_NEW"
elif [ -d "$DEBUG_PATH_OLD" ]; then
    echo "[INFO] 正在開啟 Debug 版本: ${DEBUG_PATH_OLD}..."
    open "$DEBUG_PATH_OLD"
else
    echo "錯誤：找不到 App。"
    echo "請執行以下指令進行編譯與打包："
    echo "bash scripts/build-dmg.sh"
    exit 1
fi
