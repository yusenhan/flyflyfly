#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="flyflyfly"

usage() {
  cat <<EOF
Usage:
  ./runfly.sh [run|release]      Launch build/release/flyflyfly.app (default)
  ./runfly.sh help               Show this help
EOF
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

main() {
  local command="${1:-run}"
  if [[ $# -gt 1 ]]; then
    usage
    exit 64
  fi

  case "${command}" in
    run|release)
      launch_app
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
