# Session 018 — PASS 018: the character preview seam

**Date:** 2026-08-04 · **Recovery tag:** `pre-s018` = `d88728a` · **Decisions:** D-054, D-055
**Commits:** `c81d32a`, `e6ca8dc`, `968dbb0` · `layoutVersion` untouched at **12**, v13 pin unspent

---

## The one job, and what it actually was

The booked pass was "the character preview seam, then the asset pipeline", ahead of 019's new art
for all 24 characters (D-050). The stated problem was that every character is built twice. The
measured problem turned out to be worse and more specific:

**Only the BODY was shared.** `CharacterProportions` pinned five constants and nothing else. The
crest, the antenna and the aura were two hand-tuned number sets with no shared constant and no
test — `grep -rn "crest\|aura" Tests/ UITests/` returned zero matches — and they had drifted:

| feature | rig (bodyR) | swatch (bodyR) | |
|---|---|---|---|
| horns apex reach | 0.680 | **1.370** | the swatch drew horns **twice as wide** as the rig |
| crown centre spike | 0.290 | **0.620** | 2.14×; its outer spikes 1.45× — one crest, two factors |
| ears height | 0.581 | 0.920 | 1.58× |
| fin spikes | 0.677 | 1.050 | 1.55× |
| halo width | 0.629 | 0.850 | 1.35× |
| antenna stem | 0.677 | **0.560** | the one pointing the other way — 17 % **short**, on all 24 |
| aura node count | 1 | **2** | the second node was never in the game |

And the clipping (PR-0312, PR-0453) was a *symptom* of that drift landing in a canvas hand-tuned
around the cropped result: 23 of 24 characters cut at the top, 12 of 24 at the sides, all four
legendary auras cut on every surface including the hero.

## What shipped

| | | |
|---|---|---|
| `c81d32a` | **PR-0477** | `docs/agent/11_ASSETS.md` committed. `CLAUDE.md`'s amended iron rule 6 pointed at gitignored session scratch — an iron rule citing a file that dies with its session. Three charter sites and the root `/prompt` file, all of which would have told a future agent to re-enforce the revoked "zero binary assets" decree, struck or bannered. |
| `e6ca8dc` | **PR-0478** | `Meta/CharacterGeometry.swift` — one spec, in one unit (bodyR from the body centre), listed in `Package.swift`. `CharacterParityTests` loses its `#if canImport(UIKit)` gate. **274 → 284 SPM tests.** No behaviour change, so the next commit's screenshot diff has exactly one cause. |
| `968dbb0` | **PR-0312 / PR-0453 / PR-0479** | Both layers read the spec; the canvas is derived from the roster's extent; the shop rail goes lazy. |

**Three rig defects were corrected rather than copied**, each found by re-deriving the rig's own
arithmetic:

- **D1** — the antenna socket was pinned at world y 1.21 for every body with no shape branch, so
  its depth was an accident of body height: correct on a sphere, **0.360 bodyR buried inside a
  crystal**, 0.032 bodyR floating clear of a cube.
- **D2** — the crown's five spikes started at angle 0, putting them at
  x = {+0.30, +0.093, −0.243, −0.243, +0.093}: lopsided from the only angle the player ever sees
  it from, and lopsided in a way the preview never reproduced because it drew an evenly spaced row.
- **D4** — floppy ears hard-coded world y 0.92 instead of hanging off `crestY`, so a crystal body
  wore them halfway down its face.

## The canvas, and why nothing moved

`.frame` sets layout size and **does not clip**. So the `Canvas` is sized from
`CharacterGeometry.rosterExtentInSizeUnits` and wrapped in the historic slot; the figure bleeds
past its slot instead of being cut inside it, and `canvasOffsetY` lands its centre on the exact
pixel it landed on before. **No `.frame` moved and nothing on screen shifted position.**

Rejected: **fit-to-box** (shrink each skin to fill today's slot). Also layout-neutral, never
bleeds — and renders monarch at 50.7 % and pebble at 127.6 % of today's size. A rarity ladder
whose top rung is the smallest figure on the shelf is worse than the bug.

Two sites take a zero-bleed slot because their neighbours sit inside the spill: the NEXT UNLOCK
row and the shop featured hero (whose 72 pt reservation becomes 96).

## Why it could not regress before, and can now

`Package.swift` does not compile `UI/` or `Render/`. Every number that caused PR-0312 lived
there, which is why `CharacterParityTests` had to be UIKit-gated and why the defect survived
sixteen sessions unseen by CI. **That gate is the mechanism, not a footnote.** The spec and the
six call-site slots (`Meta/CharacterSwatchSlot.swift`) are now in `Meta/` and in `Package.swift`,
and `testNoCallSiteBleedsOntoItsNeighbours` runs on Linux on every push.

## The fleet, and the refutations that changed the build

5 investigations + 5 hostile verifications + a ruling, all on disk at
`docs/agent/audits/scratch/s018_*.md`. **Every verifier returned PARTIALLY REFUTED, and three of
the refutations changed what shipped:**

1. **The eye ruling was dropped (D-055).** The geometry investigation's headline was a sign flip in
   the face. Its verifier showed the figure is the REST pose and that `RealityRenderer:389`
   disables the rig outside a live run — in play the eye lives in −0.074…+0.029 bodyR. The
   proposed fix would have over-shot the real in-run eye at every speed.
2. **"Slot presets must live in `Meta/`."** Without it PR-0312 does not close under `swift test` at
   all. This is the correction that made the pass's central claim testable.
3. **Two wrong `file:line`s inside text already committed as policy.** Found in `11_ASSETS.md` §6
   after the commit; fixed by amend, and then all 20 of its citations were checked by hand.

I also derived the extent table and the rig/swatch parity table independently in Python before
reading the fleet's, and the numbers agree to four decimals — including both of us independently
correcting S-016's aura figure from 1.86 to 1.791 bodyR (it bounded the node glow with the
near-pass radius at the ring's widest angle, where the node is at mid-depth).

## Command output

```
$ swift test -c release
   Executed 286 tests, with 0 failures (0 unexpected) in 37.890 seconds     # 274 at session start

$ ./Tools/build.sh
   BUILD OK

$ xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
   Executed 290 tests, with 0 failures (0 unexpected) in 291.686 seconds
   Executed 12 tests, with 0 failures (0 unexpected) in 168.106 seconds     # XCUITest
   ** TEST SUCCEEDED **                                                     # 293 at session start
```

Baseline captured at `d88728a` before any edit: `** TEST SUCCEEDED **`, exit 0 — so nothing here
is attributed to a pre-existing failure, and nothing pre-existing was inherited red.

The SPM `found 58 file(s) which are unhandled` warning is **pre-existing** — confirmed by stashing
and rebuilding, not assumed.

## Captures — opened and looked at, `docs/agent/scratch/s018/`

`after_00_splash` · `after_03_monarch_hero` · plus the legendary grid section read live.
**All four legendary aura rings render complete for the first time.** Monarch's hero shows the
whole ring, a symmetric crown with a centre spike, and the full antenna.

## The honest cost

**Previews are now less flattering.** Monarch's crown really is a row of short points, not the
tall spikes the swatch drew; the horns on five skins are half as wide. That is what "previews
never lie" buys. D-050 ordered new art for all 24 — 019 can now author it in ONE place, and the
brief starts from a true baseline instead of a generous one.

## Traps worth inheriting

- **`.frame` does not clip; `Canvas` does.** The whole fix rests on that. If someone "simplifies"
  the double frame back to one, 23 of 24 characters start cropping again silently.
- **`GridItem(.adaptive(minimum: 104))` must NOT become 112** — at 375 pt that drops the shelf to
  two columns. The bleed budget is sized to fit inside 104.
- **The rig's rest pose is not the rig** (D-055). Any parity work on a z-bearing feature — the
  face, the crown ring, the aura ring — must say which pose it is matching.
- **`Package.swift` decides what CI can see.** Anything new in `Meta/` must be Foundation-only,
  and must be added to the `sources` list or it silently does not compile on Linux.
- **A static member referenced from an instance context needs `Self.`** — cost one build cycle.
- **The simulator MCP's first gesture after an install can time out** ("the simulator likely
  rebooted"). Retry once; it works.
