#!/bin/bash
# ci.sh — local CI gate for PRISM RUSH.
#
# Runs the same checks a CI server would, in order, each behind a banner:
#   (a) xcodegen generate        — regenerate the Xcode project from project.yml
#   (b) ./Tools/build.sh         — build the app for the Simulator (no signing)
#   (c) xcodebuild test          — run the unit test target
#
# Prints "CI GREEN" only if every step succeeds.
#
# NOTE ON TESTS: the test step requires the PrismRushTests target (declared in
# project.yml) to have at least one test source. project.yml already wires the
# target, but until Phase 2 lands actual test files the `xcodebuild test` step
# may report "no tests" / fail to find a test bundle. That is expected and
# documented — once Phase 2 adds tests under Tests/ this step goes green.
#
# Env overrides (same convention as build.sh):
#   PR_SIM_NAME   simulator device name (default: iPhone 17 Pro)
#   PR_SIM_OS     simulator OS version   (default: 26.5)
#
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${PR_SIM_NAME:-iPhone 17 Pro}"
SIM_OS="${PR_SIM_OS:-26.5}"

banner() {
  echo ""
  echo "════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════"
}

# ── (a) Generate project ────────────────────────────────────────────────────
banner "CI [1/3] · xcodegen generate"
xcodegen generate

# ── (b) Build ───────────────────────────────────────────────────────────────
banner "CI [2/3] · build (./Tools/build.sh)"
./Tools/build.sh

# ── (c) Test ────────────────────────────────────────────────────────────────
banner "CI [3/3] · xcodebuild test  (${SIM_NAME} · iOS ${SIM_OS})"
xcodebuild test \
  -project PrismRush.xcodeproj \
  -scheme PrismRush \
  -destination "platform=iOS Simulator,name=${SIM_NAME},OS=${SIM_OS}" \
  -derivedDataPath .dd \
  CODE_SIGNING_ALLOWED=NO

banner "CI GREEN"
echo "All steps passed: generate ▸ build ▸ test."
