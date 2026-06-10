#!/bin/bash
# screenshots.sh — App Store screenshot capture for PRISM RUSH.
#
# Boots the 6.9" device (iPhone 17 Pro Max), installs the built app, launches it,
# and captures a named sequence of screenshots into Store/screenshots/.
# Also attempts a 6.5" device if one exists (App Store requires both sizes);
# if none exists it prints a WARNING instead of failing.
#
# This is the *capture flow*. The deep game states (worlds, streak, game-over)
# need real gameplay; until the game is playable (Phase 8) the script still
# structures the run and prints guidance between shots so an operator — or a
# future automated driver — can reach each state. It does NOT require the app
# to be playable yet.
#
#   Usage:  ./Tools/screenshots.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

# ── Config ──────────────────────────────────────────────────────────────────
# 6.9" required App Store size · iPhone 17 Pro Max · iOS 26.5.
SIM_69_UDID="${PR_SIM_69_UDID:-52DF5467-1BF8-40B2-BD4D-8EEECA9062DF}"
BUNDLE_ID="com.rayancheca.prismrush"
APP=".dd/Build/Products/Debug-iphonesimulator/PrismRush.app"
OUT_DIR="Store/screenshots"
SHOT_DELAY="${PR_SHOT_DELAY:-3}"

# The named capture sequence (golden path order).
SHOTS=(
  "01_menu"
  "02_world1"
  "03_world2"
  "04_world3"
  "05_streak"
  "06_gameover"
)

# Human guidance for the state to reach before each shot.
declare -a GUIDANCE=(
  "Main menu / title screen — fresh launch, no input."
  "World 1 gameplay — tap Play, enter the first world."
  "World 2 gameplay — advance to the second world."
  "World 3 gameplay — advance to the third world."
  "Streak state — build a combo/streak so the streak UI is visible."
  "Game over screen — fail a run to reveal the score/game-over panel."
)

banner() { echo ""; echo "──────────────────────────────────────────────"; echo "  $1"; echo "──────────────────────────────────────────────"; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
banner "PRISM RUSH · App Store screenshot capture"
mkdir -p "$OUT_DIR"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: app bundle not found at: $APP"
  echo "       Build it first:  ./Tools/build.sh"
  exit 1
fi

# ── Detect a 6.5\" class device (iPhone 11 Pro Max / XS Max / Plus) ──────────
banner "Checking for a 6.5\" simulator (second required App Store size)"
SIM_65_UDID="$(
  xcrun simctl list devices available 2>/dev/null \
    | grep -iE "11 Pro Max|XS Max|8 Plus|7 Plus|6s Plus" \
    | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" \
    | head -1 || true
)"

if [[ -z "$SIM_65_UDID" ]]; then
  echo "WARNING: No 6.5\" display simulator is installed on this machine."
  echo "         The App Store requires BOTH a 6.9\" and a 6.5\" screenshot set."
  echo "         Download a 6.5\" device (e.g. iPhone 11 Pro Max) via:"
  echo "           Xcode ▸ Settings ▸ Components  (or 'xcodebuild -downloadPlatform iOS')"
  echo "         then create one:  xcrun simctl create '11ProMax' 'iPhone 11 Pro Max'"
  echo "         Capturing the 6.9\" set only for now."
else
  echo "Found 6.5\" simulator: $SIM_65_UDID"
fi

# ── Capture routine for one device ──────────────────────────────────────────
# $1 = simulator UDID, $2 = output subdir label (e.g. "6.9" or "6.5")
capture_device() {
  local udid="$1"
  local label="$2"
  local dest="$OUT_DIR/$label"
  mkdir -p "$dest"

  banner "Capturing $label set on $udid"

  # Boot (idempotent — already-booted is fine) and surface the Simulator UI.
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator || true
  # Wait for the device to settle into a Booted state.
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

  # Install + launch (re-install is idempotent and picks up the latest build).
  echo "Installing app…"
  xcrun simctl install "$udid" "$APP"
  echo "Launching $BUNDLE_ID…"
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

  local i
  for i in "${!SHOTS[@]}"; do
    local name="${SHOTS[$i]}"
    local hint="${GUIDANCE[$i]}"
    echo ""
    echo "  [$((i + 1))/${#SHOTS[@]}] $name"
    echo "       → reach: $hint"
    echo "       (sleeping ${SHOT_DELAY}s — drive the app to this state)"
    # Foreground sleep is fine here; this is an interactive capture tool.
    sleep "$SHOT_DELAY"
    local file="$dest/${name}.png"
    xcrun simctl io "$udid" screenshot "$file"
    echo "       saved: $file"
  done

  echo ""
  echo "  $label set complete → $dest"
}

# ── Run ─────────────────────────────────────────────────────────────────────
capture_device "$SIM_69_UDID" "6.9"

if [[ -n "$SIM_65_UDID" ]]; then
  capture_device "$SIM_65_UDID" "6.5"
fi

banner "DONE"
echo "Screenshots written under: $OUT_DIR/"
echo "NOTE: deep states (worlds/streak/game-over) require real gameplay."
echo "      Re-run after Phase 8 with the app driven to each state for final shots."
