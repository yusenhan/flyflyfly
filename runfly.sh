#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="flyflyfly"
PROJECT_PATH="${SCRIPT_DIR}/${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
BUILD_SCRIPT="${SCRIPT_DIR}/scripts/build.sh"
TEST_DERIVED_DATA="${SCRIPT_DIR}/build/test-derived"

usage() {
  cat <<EOF
Usage:
  ./runfly.sh [run|release]      Launch build/release/flyflyfly.app (default)
  ./runfly.sh build              Build Debug only
  ./runfly.sh build-release      Build Release only
  ./runfly.sh test               Build and run unit tests
  ./runfly.sh xcode-test         Run the full Xcode test action
  ./runfly.sh help               Show this help
EOF
}

ensure_xcodebuild() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "[ERROR] 找不到 xcodebuild。請先安裝 Xcode，並確認 Command Line Tools 已設定。"
    exit 127
  fi
}

build_app() {
  local mode="$1"
  "${BUILD_SCRIPT}" "${mode}"
}

launch_app() {
  local app_path="${SCRIPT_DIR}/build/release/${APP_NAME}.app"
  local app_executable="${app_path}/Contents/MacOS/${APP_NAME}"

  if [[ ! -d "${app_path}" ]]; then
    echo "[ERROR] 找不到 App Bundle：${app_path}"
    echo "[INFO] 請先執行 ./rebuild.sh"
    exit 1
  fi

  if [[ ! -x "${app_executable}" ]]; then
    echo "[ERROR] 找不到可執行檔：${app_executable}"
    exit 1
  fi

  echo "[INFO] 正在開啟 Release 版本：${app_path}"
  if ! open -n "${app_path}" 2>/dev/null; then
    echo "[WARN] open 啟動失敗，改用二進位直接執行。"
    exec "${app_executable}"
  fi
}

build_for_unit_tests() {
  echo "[INFO] 正在建置單元測試..."
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${TEST_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build-for-testing
}

run_unit_tests() {
  local app_path="${TEST_DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
  local test_bundle="${app_path}/Contents/PlugIns/${APP_NAME}Tests.xctest"
  local app_macos_path="${app_path}/Contents/MacOS"

  if [[ ! -d "${test_bundle}" ]]; then
    echo "[ERROR] 找不到測試 bundle：${test_bundle}"
    exit 1
  fi

  echo "[INFO] 正在執行單元測試..."
  DYLD_LIBRARY_PATH="${app_macos_path}" \
    /Applications/Xcode.app/Contents/Developer/usr/bin/xctest "${test_bundle}"
}

run_xcode_tests() {
  echo "[INFO] 正在執行完整 Xcode 測試動作..."
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "${TEST_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    test
}

main() {
  local command="${1:-run}"

  case "${command}" in
    run|release)
      launch_app
      ;;
    build|build-debug|debug)
      ensure_xcodebuild
      build_app debug
      ;;
    build-release)
      ensure_xcodebuild
      build_app release
      ;;
    test|unit-test)
      ensure_xcodebuild
      build_for_unit_tests
      run_unit_tests
      ;;
    xcode-test)
      ensure_xcodebuild
      run_xcode_tests
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 64
      ;;
  esac
}

main "$@"
