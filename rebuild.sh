#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] 正在確保子建置腳本具備執行權限..."
chmod +x "${SCRIPT_DIR}/scripts/build.sh" "${SCRIPT_DIR}/scripts/build-dmg.sh"

echo "[INFO] 正在啟動完整編譯與建置流程..."
"${SCRIPT_DIR}/scripts/build.sh" all
