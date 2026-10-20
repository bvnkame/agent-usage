#!/bin/bash
# Build Agent Usage.
#   ./build.sh mac          native macOS menu-bar app (Swift)  -> mac/AgentUsageBar.app
#   ./build.sh mac-app      macOS Electron build (dmg + zip)   -> desktop/dist/
#   ./build.sh win          Windows installer + portable exe   -> desktop/dist/
#   ./build.sh linux        Linux AppImage + deb               -> desktop/dist/
#   ./build.sh all          every target above available on this machine
# Windows/Linux builds are most reliable on their own OS; the GitHub Action in
# .github/workflows/release.yml builds all three on native runners.
set -euo pipefail
cd "$(dirname "$0")"

electron() {   # $1 = electron-builder script name
  (cd desktop && { [ -d node_modules ] || npm install --no-audit --no-fund; } && npm run "$1")
}

case "${1:-}" in
  mac)     [ "$(uname)" = Darwin ] || { echo "the native app needs macOS" >&2; exit 1; }; ./mac/build_app.sh ;;
  mac-app) electron dist:mac ;;
  win)     electron dist:win ;;
  linux)   electron dist:linux ;;
  all)     [ "$(uname)" = Darwin ] && ./mac/build_app.sh
           electron dist:win
           electron dist:linux ;;
  *)       sed -n '2,10p' "$0"; exit 1 ;;
esac
