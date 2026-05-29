#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="flyflyfly"
PROJECT_PATH="${SCRIPT_DIR}/${APP_NAME}.xcodeproj"
MODE="${1:-all}"

usage() {
  cat <<EOF
Usage:
  ./rebuild.sh [all|debug|release|dmg|help]

Commands:
  all      Build Debug + Release, then package build/dmg/flyflyfly.dmg (default)
  debug    Build Debug app into build/debug/flyflyfly.app
  release  Build Release app into build/release/flyflyfly.app
  dmg      Package build/dmg/flyflyfly.dmg, building Release first if needed
  help     Show this help
EOF
}

ensure_xcodebuild() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "[ERROR] 找不到 xcodebuild。請先安裝 Xcode，並確認 Command Line Tools 已設定。"
    exit 127
  fi
}

build_configuration() {
  local configuration="$1"
  local output_dir="$2"
  local build_root="${SCRIPT_DIR}/build/${output_dir}_build"
  local derived_dir="${build_root}/DerivedData"
  local app_path="${derived_dir}/Build/Products/${configuration}/${APP_NAME}.app"
  local output_path="${SCRIPT_DIR}/build/${output_dir}/${APP_NAME}.app"

  echo "[INFO] 正在建置 ${APP_NAME} (${configuration})..."
  rm -rf "${build_root}"
  mkdir -p "${build_root}"

  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${APP_NAME}" \
    -configuration "${configuration}" \
    -derivedDataPath "${derived_dir}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

  if [[ ! -d "${app_path}" ]]; then
    echo "[ERROR] 找不到建置產物：${app_path}"
    exit 1
  fi

  echo "[INFO] 正在複製 ${configuration} app bundle 至 build/${output_dir}..."
  mkdir -p "$(dirname "${output_path}")"
  rm -rf "${output_path}"
  cp -R "${app_path}" "${output_path}"
  rm -rf "${build_root}"
}

sanitize_release_app() {
  local release_app="${SCRIPT_DIR}/build/release/${APP_NAME}.app"

  if [[ ! -d "${release_app}" ]]; then
    echo "[ERROR] 找不到 Release App：${release_app}"
    echo "[INFO] 請先執行 ./rebuild.sh release"
    exit 1
  fi

  echo "[INFO] 正在淨化 Release app bundle..."
  find "${release_app}" -name '.DS_Store' -delete
  xattr -cr "${release_app}" 2>/dev/null || true
  rm -rf "${release_app}/Contents/Resources/.claude"
  rm -f "${release_app}/Contents/Resources/settings.local.json"
}

package_dmg() {
  local build_root="${SCRIPT_DIR}/build/dmg"
  local staging_dir="${build_root}/staging"
  local dmg_path="${build_root}/${APP_NAME}.dmg"
  local temp_dmg_path="${build_root}/${APP_NAME}-temp.dmg"
  local release_app="${SCRIPT_DIR}/build/release/${APP_NAME}.app"

  if [[ ! -d "${release_app}" ]]; then
    build_configuration Release release
  fi

  sanitize_release_app

  echo "[INFO] 正在準備 DMG 暫存目錄..."
  rm -rf "${build_root}"
  mkdir -p "${staging_dir}"
  cp -R "${release_app}" "${staging_dir}/${APP_NAME}.app"
  ln -s /Applications "${staging_dir}/Applications"
  rm -f "${dmg_path}" "${temp_dmg_path}"

  echo "[INFO] 正在建立 DMG..."
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    "${dmg_path}"

  echo "[INFO] DMG 已建立：${dmg_path}"
}

ensure_xcodebuild

case "${MODE}" in
  all)
    build_configuration Debug debug
    build_configuration Release release
    package_dmg
    ;;
  debug)
    build_configuration Debug debug
    ;;
  release)
    build_configuration Release release
    ;;
  dmg)
    package_dmg
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 64
    ;;
esac

echo "[INFO] 建置流程完成：${MODE}"
