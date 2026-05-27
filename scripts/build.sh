#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="flyflyfly"
PROJECT_PATH="${ROOT_DIR}/${APP_NAME}.xcodeproj"

# 1. 建置 Debug 版本
echo "[INFO] 正在建置 ${APP_NAME} (Debug)..."
DEBUG_BUILD_ROOT="${ROOT_DIR}/build/debug_build"
DEBUG_DERIVED_DIR="${DEBUG_BUILD_ROOT}/DerivedData"
DEBUG_APP_PATH="${DEBUG_DERIVED_DIR}/Build/Products/Debug/${APP_NAME}.app"

rm -rf "${DEBUG_BUILD_ROOT}"
mkdir -p "${DEBUG_BUILD_ROOT}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${APP_NAME}" \
  -configuration Debug \
  -derivedDataPath "${DEBUG_DERIVED_DIR}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "[INFO] 正在複製 Debug app bundle 至 build/debug..."
mkdir -p "${ROOT_DIR}/build/debug"
rm -rf "${ROOT_DIR}/build/debug/${APP_NAME}.app"
cp -R "${DEBUG_APP_PATH}" "${ROOT_DIR}/build/debug/${APP_NAME}.app"
rm -rf "${DEBUG_BUILD_ROOT}"

# 2. 建置 Release 版本與 DMG 套件
echo "[INFO] 正在調用 build-dmg.sh 進行 Release 與 DMG 建置..."
"${SCRIPT_DIR}/build-dmg.sh"

echo "[INFO] 所有建置皆已成功完成！"
