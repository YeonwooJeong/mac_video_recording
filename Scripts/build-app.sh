#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_DIR="${ROOT_DIR}/Build/Screen Recorder.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${ROOT_DIR}"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${ROOT_DIR}/.build/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${ROOT_DIR}/.build/swiftpm-module-cache}"

if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
fi

swift build -c "${CONFIGURATION}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_DIR}/ScreenRecorderApp" "${MACOS_DIR}/ScreenRecorderApp"
cp "${ROOT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

if [[ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]]; then
    cp "${ROOT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

chmod +x "${MACOS_DIR}/ScreenRecorderApp"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "${APP_DIR}" >/dev/null
fi

echo "${APP_DIR}"
