#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="flyflyfly"
PROJECT_PATH="${ROOT_DIR}/${APP_NAME}.xcodeproj"
MODE="${1:-all}"

usage() {
  echo "Usage: $0 [debug|release|dmg|all]"
  echo "  all = build Debug + Release + DMG"
}

build_configuration() {
  local configuration="$1"
  local output_dir="$2"
  local build_root="${ROOT_DIR}/build/${output_dir}_build"
  local derived_dir="${build_root}/DerivedData"
  local app_path="${derived_dir}/Build/Products/${configuration}/${APP_NAME}.app"

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

  echo "[INFO] 正在複製 ${configuration} app bundle 至 build/${output_dir}..."
  mkdir -p "${ROOT_DIR}/build/${output_dir}"
  rm -rf "${ROOT_DIR}/build/${output_dir}/${APP_NAME}.app"
  cp -R "${app_path}" "${ROOT_DIR}/build/${output_dir}/${APP_NAME}.app"
  rm -rf "${build_root}"
}

build_all() {
  build_configuration Debug debug
  build_configuration Release release
  "${SCRIPT_DIR}/build-dmg.sh"
}

case "${MODE}" in
  debug)
    build_configuration Debug debug
    ;;
  release)
    build_configuration Release release
    ;;
  dmg)
    "${SCRIPT_DIR}/build-dmg.sh"
    ;;
  all)
    build_all
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
