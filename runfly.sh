#!/bin/bash
# 運行編譯好的 flyflyfly App
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/build/Debug/flyflyfly.app"

if [ -d "$APP_PATH" ]; then
    echo "正在開啟 ${APP_PATH}..."
    open "$APP_PATH"
else
    echo "錯誤：找不到 App。請先執行 'xcodebuild -project flyflyfly.xcodeproj -scheme flyflyfly -configuration Debug build CONFIGURATION_BUILD_DIR=build/Debug' 進行編譯。"
    exit 1
fi
