#!/bin/bash
# 運行編譯好的 flyflyfly App (優先運行 Release 版本)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RELEASE_PATH="${SCRIPT_DIR}/build/Release/flyflyfly.app"
DEBUG_PATH="${SCRIPT_DIR}/build/Debug/flyflyfly.app"

if [ -d "$RELEASE_PATH" ]; then
    echo "[INFO] 正在開啟 Release 版本: ${RELEASE_PATH}..."
    open "$RELEASE_PATH"
elif [ -d "$DEBUG_PATH" ]; then
    echo "[INFO] 正在開啟 Debug 版本: ${DEBUG_PATH}..."
    open "$DEBUG_PATH"
else
    echo "錯誤：找不到 App。"
    echo "請執行以下指令進行編譯："
    echo "xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Release build CONFIGURATION_BUILD_DIR=build/Release"
    exit 1
fi
