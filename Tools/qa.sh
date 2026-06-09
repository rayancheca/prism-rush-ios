#!/bin/bash
# Build → install → launch → screenshot. The visual QA loop. Run it and READ the screenshot.
set -euo pipefail
cd "$(dirname "$0")/.."

# iPhone 17 Pro · iOS 26.5 (primary dev/QA device on this machine).
SIM_UDID="${PR_SIM_UDID:-10C15FE0-3D9A-40D5-9E45-C0702E906DF3}"
BUNDLE_ID="com.rayancheca.prismrush"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator

./Tools/build.sh

APP=".dd/Build/Products/Debug-iphonesimulator/Prism Rush.app"
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

sleep "${PR_SHOT_DELAY:-4}"
mkdir -p reports/shots
SHOT="reports/shots/shot_$(date +%s).png"
xcrun simctl io "$SIM_UDID" screenshot "$SHOT"
echo "SHOT SAVED: $SHOT — read it, critique it, iterate."
