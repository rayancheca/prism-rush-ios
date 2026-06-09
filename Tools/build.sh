#!/bin/bash
# Generate the Xcode project from project.yml and build the app for the Simulator.
# Simulator builds do not require code signing, so we disable it to stay green without a Team ID.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${PR_SIM_NAME:-iPhone 17 Pro}"
SIM_OS="${PR_SIM_OS:-26.5}"

xcodegen generate --quiet

xcodebuild -project PrismRush.xcodeproj -scheme PrismRush \
  -destination "platform=iOS Simulator,name=${SIM_NAME},OS=${SIM_OS}" \
  -derivedDataPath .dd \
  CODE_SIGNING_ALLOWED=NO \
  -quiet build

echo "BUILD OK"
