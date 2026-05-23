#!/usr/bin/env bash
set -euo pipefail

# 運行固定路徑的 flyflyfly App Release 版本。
RELEASE_APP="/private/tmp/flyflyfly-derived-release/Build/Products/Release/flyflyfly.app"
APP_EXECUTABLE="${RELEASE_APP}/Contents/MacOS/flyflyfly"

if [[ ! -d "${RELEASE_APP}" ]]; then
  echo "錯誤：找不到 App Bundle：${RELEASE_APP}"
  exit 1
fi

if [[ ! -x "${APP_EXECUTABLE}" ]]; then
  echo "錯誤：找不到可執行檔：${APP_EXECUTABLE}"
  exit 1
fi

echo "[INFO] 正在開啟固定路徑的 Release 版本: ${RELEASE_APP}..."
if ! open -n "${RELEASE_APP}" 2>/dev/null; then
  echo "[WARN] open 啟動失敗，改用二進位直接執行。"
  exec "${APP_EXECUTABLE}"
fi
