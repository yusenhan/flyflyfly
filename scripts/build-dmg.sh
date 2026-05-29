#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/dmg"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
STAGING_DIR="${BUILD_ROOT}/staging"
APP_NAME="flyflyfly"
PROJECT_PATH="${ROOT_DIR}/${APP_NAME}.xcodeproj"
APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="${ROOT_DIR}/build/dmg/${APP_NAME}.dmg"
TEMP_DMG_PATH="${BUILD_ROOT}/${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

rm -rf "${BUILD_ROOT}"
mkdir -p "${STAGING_DIR}"

if [[ ! -d "${ROOT_DIR}/build/release/${APP_NAME}.app" ]]; then
  echo "[INFO] Building ${APP_NAME} (Release)..."
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

  if [[ ! -d "${APP_PATH}" ]]; then
    echo "ERROR: App not found at ${APP_PATH}"
    exit 1
  fi

  echo "[INFO] Copying Release app bundle to build/release..."
  mkdir -p "${ROOT_DIR}/build/release"
  rm -rf "${ROOT_DIR}/build/release/${APP_NAME}.app"
  cp -R "${APP_PATH}" "${ROOT_DIR}/build/release/${APP_NAME}.app"
else
  APP_PATH="${ROOT_DIR}/build/release/${APP_NAME}.app"
fi

echo "[INFO] Sanitizing app bundle for distribution..."
find "${ROOT_DIR}/build/release/${APP_NAME}.app" -name '.DS_Store' -delete
xattr -cr "${ROOT_DIR}/build/release/${APP_NAME}.app" 2>/dev/null || true
rm -rf "${ROOT_DIR}/build/release/${APP_NAME}.app/Contents/Resources/.claude"
rm -f "${ROOT_DIR}/build/release/${APP_NAME}.app/Contents/Resources/settings.local.json"

echo "[INFO] Preparing DMG staging directory..."
cp -R "${ROOT_DIR}/build/release/${APP_NAME}.app" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}" "${TEMP_DMG_PATH}"

echo "[INFO] Creating DMG..."
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "[INFO] DMG created at ${DMG_PATH}"
