#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${ROOT_DIR}/Build/Screen Recorder.app"

if [[ ! -d "${APP_PATH}" ]]; then
    "${ROOT_DIR}/Scripts/build-app.sh"
fi

open "${APP_PATH}"
