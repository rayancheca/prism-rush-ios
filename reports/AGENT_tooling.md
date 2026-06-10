# AGENT_tooling — PRISM RUSH standalone tooling

Owner: `tooling` subagent. Scope is strictly the three tools below plus this
report. App sources (`PrismRush/`), `project.yml`, `Tools/build.sh`, and
`Tools/qa.sh` are owned by the orchestrator and were not modified.

Files produced:

- `Tools/gen_icon.swift` — programmatic 1024×1024 App Store icon generator
- `Tools/screenshots.sh` — App Store screenshot capture flow
- `Tools/ci.sh` — local CI gate (generate ▸ build ▸ test)

---

## 1. `Tools/gen_icon.swift`

A standalone macOS Swift script (no Xcode project, no UIKit). Renders a fully
opaque 1024×1024 PNG using only **CoreGraphics + ImageIO + Foundation**
(`UniformTypeIdentifiers` for the PNG UTType, with a `public.png` string
fallback). No text, no binary assets.

### Run

```bash
cd /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios
swift Tools/gen_icon.swift            # → Store/icon_1024.png (default)
swift Tools/gen_icon.swift path.png   # → custom output path
```

### Design rationale

- **Background** — vertical void-purple gradient `#0A0420` (top) →
  `#07021A` → near-black `#040010` (bottom), with a soft radial magenta→
  transparent glow centered slightly above middle. Fully opaque field.
- **Character** — a cute "prism-slime": a rounded blob/orb body fused with an
  **octahedral gem facet** core. Body is filled with the PRISM RUSH neon ramp
  cyan `#00F5FF` → magenta `#FF2BD6` → amber `#FFB13D`. The gem facet, facet
  ridge, glossy highlight, and halo are drawn with additive (`plusLighter`)
  blending so the character reads as *emitting* light. Two dark void eyes with
  white catch-lights give it personality. A thin antenna rises from the crown
  to a glowing cyan tip dot.
- **Composition** — centered, ~12% safe margin, bold silhouette that stays
  readable at small sizes. **No rounded-corner mask** (Apple applies it) and
  **no alpha channel** in the output (App Store icons must be fully opaque).

### Confirmation — it actually ran and produced a valid 1024×1024 PNG

`swift Tools/gen_icon.swift` output:

```
gen_icon: wrote /Users/.../prism-rush-ios/Store/icon_1024.png
gen_icon: 1024×1024 px, opaque sRGB PNG
```

`sips` verification (note `hasAlpha: no` — fully opaque, App Store compliant):

```
$ sips -g pixelWidth -g pixelHeight -g hasAlpha Store/icon_1024.png
  pixelWidth: 1024
  pixelHeight: 1024
  hasAlpha: no
```

`file` verification:

```
$ file Store/icon_1024.png
Store/icon_1024.png: PNG image data, 1024 x 1024, 8-bit/color RGB, non-interlaced
```

Implementation note: the first pass emitted an RGBA PNG (alpha channel present),
which the App Store rejects for icons. Fixed by rendering into a
`CGImageAlphaInfo.noneSkipFirst` (opaque XRGB) bitmap context so ImageIO writes
an **RGB PNG with no alpha channel**. Re-verified above.

---

## 2. `Tools/screenshots.sh`

App Store screenshot capture. `set -euo pipefail`, idempotent.

### Run

```bash
./Tools/build.sh            # produce the .app bundle first
./Tools/screenshots.sh
```

### What it does

1. Verifies the built bundle exists at
   `.dd/Build/Products/Debug-iphonesimulator/Prism Rush.app`.
2. Boots the **6.9"** simulator — iPhone 17 Pro Max,
   UDID `52DF5467-1BF8-40B2-BD4D-8EEECA9062DF`, iOS 26.5 (override via
   `PR_SIM_69_UDID`).
3. Installs `com.rayancheca.prismrush`, launches it, and captures a named
   sequence into `Store/screenshots/6.9/`:
   `01_menu`, `02_world1`, `03_world2`, `04_world3`, `05_streak`, `06_gameover`.
   Between shots it `sleep`s and prints the state an operator must drive the app
   into (worlds/streak/game-over need real gameplay).
4. **Also attempts a 6.5" device** if one is available, capturing into
   `Store/screenshots/6.5/`.

### 6.5" warning (current machine)

There is **no 6.5" simulator** installed (only iPhone 17-series / iPhone Air).
The script detects this via `xcrun simctl list devices available` (matching
iPhone 11 Pro Max / XS Max / Plus families) and, when none is found, prints a
clear WARNING with download instructions — it does **not** fail. Verified:

```
RESULT: empty -> WARNING path triggers (correct: no 6.5-inch sim present)
```

To satisfy the second required App Store size, an operator must download a 6.5"
display sim (e.g. iPhone 11 Pro Max) via Xcode ▸ Settings ▸ Components, then
`xcrun simctl create '11ProMax' 'iPhone 11 Pro Max'`.

This script is exercised for real in **Phase 8** once the game is playable; it
does not require the app to be playable now.

---

## 3. `Tools/ci.sh`

Local CI gate. `set -euo pipefail`, `cd`s to repo root, each step behind a
banner.

### Run

```bash
./Tools/ci.sh
PR_SIM_NAME='iPhone 17' PR_SIM_OS=26.5 ./Tools/ci.sh   # env overrides
```

### Steps

1. `xcodegen generate` — regenerate `PrismRush.xcodeproj` from `project.yml`.
2. `./Tools/build.sh` — Simulator build (no code signing).
3. `xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush
   -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
   -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO`.

Prints **CI GREEN** on success. Honors `PR_SIM_NAME` / `PR_SIM_OS` overrides
(same convention as `build.sh`).

**Test-step caveat (documented in the script):** `project.yml` already declares
the `PrismRushTests` target, but the `xcodebuild test` step only goes green once
**Phase 2 lands actual test sources** under `Tests/`. Until then the test step
may report no test bundle / fail — that is expected and documented.

---

## Status

| Tool | Executable | Verified |
|------|-----------|----------|
| `Tools/gen_icon.swift` | run via `swift` (has shebang) | ✅ ran clean → `Store/icon_1024.png` 1024×1024, opaque RGB |
| `Tools/screenshots.sh` | ✅ `chmod +x` | ✅ `bash -n` clean; 6.5" detection verified (WARNING path) |
| `Tools/ci.sh` | ✅ `chmod +x` | ✅ `bash -n` clean |
