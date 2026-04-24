#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 若未指定 PYTHON_BIN，嘗試環境中的 python3
if [ -z "${PYTHON_BIN:-}" ]; then
  PYTHON_BIN="python3"
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: Python not found at $PYTHON_BIN"
  exit 1
fi

echo "[INFO] Using Python: $PYTHON_BIN"
echo "[INFO] Building pymobiledevice3 bundle..."

# 執行 PyInstaller
"$PYTHON_BIN" -m PyInstaller --noconfirm --clean \
  --distpath "$ROOT_DIR/bundled" \
  --workpath "$ROOT_DIR/build/pyinstaller" \
  "$ROOT_DIR/pymobiledevice3.spec"

# 重新命名目錄以符合 Xcode 預期
if [ -d "$ROOT_DIR/bundled/pymobiledevice3" ]; then
    echo "[INFO] Built and placed at: $ROOT_DIR/bundled/pymobiledevice3"
else
    echo "ERROR: Failed to build bundled pymobiledevice3"
    exit 1
fi
