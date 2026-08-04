# HANDOFF → Session 020 · **PASS 020: THE CHARACTER ART, PART TWO**

## Paste this to start the next session

```
You are session 020 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file in full.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Session 019 shipped the Mystery Box fixes and the crest uplift, and discovered that the crest work
had a prerequisite the handoff did not know about. The designs for the remaining work exist and are
adversarially reviewed — and every review found blocking errors in them. Your first job is not to
build those designs. It is to correct them, then build.
```

---

Session 019 did steps 0 and 1 of the pass-019 plan. **D-2 (body shapes + prop slot), D-4 (run
cycles) and the model half of D-3 are not started** — deliberately, see §2A.

---

## 0. Start here

```bash
python3 -c "import os; print(os.getcwd())"      # env sanity (S-019's abort condition; now fine)
git log --oneline -4                             # expect 40bffce at HEAD
git tag pre-s020                                 # pre-s019 already exists at 12abbba — do not move it
```

Then the baseline, **one at a time — this matters, see §1**:

```bash
swift test -c release
```

```bash
xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
```

Expect **291 SPM + 307 Xcode**, green. If `swift test` dies with `missing required module
'SwiftShims'`, that is a stale module cache from the repo's old `~/Desktop` path — `rm -rf .build`
fixes it. It looks exactly like a corrupt checkout and is not.

### Read before touching code

| file | why |
|---|---|
| `docs/agent/01_RULES.md` | §3 verification is the non-advisory part |
| `docs/agent/02_STATE.md` | single source of truth for right now |
| `docs/agent/04_DECISIONS.md` **D-056/057/058** | what S-019 learned. **D-056 changes how you read S-018.** |
| `docs/agent/audits/scratch/s019_*.md` | six designs, **each with a hostile review appended at the bottom — read the review FIRST** |
| `docs/agent/11_ASSETS.md` | binds D-3 completely, and §4.1 conflicts with it |
| `PrismRush/Meta/CharacterGeometry.swift` | the spec you author into; the rig now genuinely reads it |

---

## 1. **The trap that cost session 019 an hour**

**Never run `swift test` and `xcodebuild test` at the same time.** The Warden solvability test
(`testNoFixedStanceCanWinAFight`, 9 loops × up to 400,000 ticks) is the slowest in the repo; under
CPU contention its host is SIGTERM'd and `xcodebuild` reports:

```
Failing tests:
	WardenTests.testNoFixedStanceCanWinAFight()
** TEST FAILED **
```

with **no assertion message**. That is indistinguishable from an inherited red test. The truth is
only in the xcresult — `xcrun xcresulttool get test-results tests --path <...>.xcresult --format json`
says *"Test crashed with signal term."* `CLAUDE.md` warns about `simctl` + `xcodebuild`; it does not
warn about this one.

**Same family, second trap: do not edit files an investigation is reading.** S-019 enlarged the crest
constants while six agents were mid-flight and invalidated the assets agent's flagship visual
evidence. Freeze the tree or finish the fan-out first.

---

## 2. What is still open, in the order I would do it

### A · Correct the designs before building them — not optional

**All six verifiers returned PARTIALLY REFUTED**, and unlike S-018's refutations these are mostly
*arithmetic in constants a builder would type in verbatim*:

- **`s019_bodyshapes.md`** — the cluster's bounding box uses the AABB formula for a rotated
  **rectangle** applied to a shape its own recipe defines as a **diamond**. Corrected, the cluster's
  aspect ratio is **1.0095 — within 0.95% of the sphere it is supposed to be distinguished from**, so
  the design's headline separation claim fails. The eye-seating σ likewise applies a circular formula
  to a box and an octahedron; the `capsule` justification and its proposed test collapse with it.
- **`s019_props.md`** — headline survives; "eleven other things wrong, five in geometry a builder
  would type verbatim".
- **`s019_motion.md`** — four load-bearing numbers wrong, one specified test does not compile, and
  its physics table is computed against geometry that **no longer exists** (S-019 changed it).
- **`s019_assets.md`** — three of its 24 rendered previews are visibly cropped and all 24 mis-sized.

**Treat these as drafts with a review attached, not as specs.**

### B · D-2 — body shapes + the prop slot

`s019_consumers.md` is the most reliable of the six; its §7 is a dependency-ordered edit list. Three
things it establishes that you must not lose:

1. Widening `BodyShape` produces only **two** compile errors CI can see
   (`CharacterGeometry.bodyTop`/`bodyHalfWidth`). **Five more sites fail SILENTLY.** S-019 fixed the
   worst (`crestAnchor`'s ternary → exhaustive `switch`) and PR-0488 files another. Make
   `BodyShape: CaseIterable` and replace the literal `[.sphere, .cube, .crystal]` arrays at
   `CharacterParityTests:101,124` — they are named "for every shape" and would silently cover 3 of 7.
2. **`Skin.Prop` has no forcing function into `extent(for:)`.** `extent` switches exhaustively on
   `crest`, so a new *crest* is a compile error there — a new *field* is not. You can wire a prop
   into both layers and `extent` will keep returning the old box. **That is PR-0312's exact failure
   mode, one axis over.** Write the "did you teach `extent`" test in the SAME commit: for every
   non-`.none` prop, a synthetic skin's extent must differ from the bare one on some axis.
3. The growth budget before a shipped slot must be re-derived is **side +0.0774 / up+down +0.1648**
   size-units (4.33 pt and 9.23 pt at the 56 pt grid card, which binds both axes). If a proposal
   needs more, **re-derive `.selectGrid.bleedAllowance` from the card geometry quoted in its own
   comment — never raise the number until it passes.**

**Do NOT enlarge the aura.** It sets `side` on all four legendaries and is the one crest-family change
that would actually cost canvas (D-057).

### C · D-4 — run cycles

`advanceVisuals` genuinely has **zero** coverage — confirmed, not assumed. It lives in `Render/`,
which `Package.swift` does not compile, so `s019_motion.md` §7's plan (extract the pure math into a
Foundation-only `Meta/` type that IS in `Package.swift`) is the right shape. Check its numbers against
the working tree first.

### D · D-3 — and see §4

**D-058 answers the crux the last handoff left open: headless RealityKit works.**
`RealityFoundation.RealityRenderer` renders offscreen with no app bundle, no `NSApplication`, no
window — 24 PNGs in 0.32 s, 169 KB total, proven twice.
⚠️ The app declares its **own** `RealityRenderer` (`RealityRenderer.swift:11`), which shadows Apple's
inside the app module. Any tool must write `RealityFoundation.RealityRenderer` in full.

`s019_assets.md` §6.2 proposes a genuinely good minimum increment: **the tool + the hash gate + the 24
committed PNGs, consumed by nothing.** It ships the pipeline and converts decree 2 into a build gate,
changes zero pixels in the running app, and is a clean revert. **Do not start the model half without
Rayan** — §4.

---

## 3. Hard constraints

- **Decree 1** — a character never changes identity, in space or in time. Prism's static six-band
  rainbow (D-011) survives verbatim; `testEverySkinHoldsOneFixedIdentity` stays green **unedited**.
- **Decree 2** — previews never lie. **And verify the seam rather than trusting it.** D-056 is the
  whole lesson: *"there is a shared spec"* and *"both layers read it"* are different claims, and only
  the second is worth anything.
- **Determinism** — the spawn path was not touched. `layoutVersion` stays **12**; the v13 pin
  `0x9E49_3424_C18A_59C5` is still **UNSPENT**. If something forces a change, iron rule 3 in full.
- **Nothing economic moves.** Every id, name, flavor, hex, price and unlock rung is frozen.
- **G3**, **iron rule 7**, **Swift 6 strict concurrency `complete`** — as always.
- **Never make a gate pass by weakening it.** S-019 repinned four tests; each moved to a **measured**
  value, and each anti-regression bound was **re-anchored to the old-swatch value it exists to
  prevent** rather than deleted.

---

## 4. **Needs Rayan, not another session's guess**

1. **D-3's scope conflict — the live one.** `11_ASSETS.md:149`, committed policy, says of
   character-select art: *"That is already correct and already satisfies decree 2. Do not replace it
   with 24 textures."* D-3 requires exactly that, because a 2-D Canvas cannot redraw a textured 3-D
   model. D-3 **invalidates the policy's premise** rather than contradicting it — but that makes D-3
   *"replace the preview system S-018 just built"*, and `11_ASSETS.md:249` puts the player model at
   **step 7 of 10**, after the particle-billboard work that explicitly *"buys the frame budget the
   rest of the plan spends."* And **24 imported character models are art-weeks, not a session**: the
   roster is spheres, cubes and octahedra and no CC0 pack ships that family. His call: baked previews
   only (cheap, ships now), or commit to authored character art as its own project.
2. **THE AUDIO BLOCKER, nine sessions old.** A landed Warden hazard plays `.shieldBreak` — one buffer
   for five meanings, three opposite in valence. Costed in `s014_audio.md`. He listens and directs, or
   says "ship your best guess".
3. **One Instruments trace on his actual 16 Pro Max.** Everything measured so far is on the simulator.
4. **The `RealityView`-per-window measurement** that would reverse D-054. Still unmeasured, and it
   decides every future "can we put 3-D here" question.
5. **The mission reward curve** — the board pays 663 coins/day, 34% of the whole meta faucet.
6. Never confirmed by a human: the stumble, the slide SFX, the hub redesign (PR-0452), the
   `Double Coins` App Store Connect description.

---

## 5. How to work

Fan out — this is still wide enough to deserve it. **Every agent writes to
`docs/agent/audits/scratch/s020_<label>.md` BEFORE returning**; a workflow's intermediate results live
in script variables and die with the run. **Have findings adversarially verified** — S-018 and S-019
both ran every verifier to PARTIALLY REFUTED and every refutation changed the build. Never end a
session with a workflow in flight.

**Run the app and open the screenshots.** S-019's own lesson on top of that: **for an ANIMATION claim,
screenshots are not evidence.** Three attempts to catch a 320 ms lid hinge with stills failed and
twice produced a confident false "it works". What settled it was `xcrun simctl io recordVideo` +
`ffmpeg` frame extraction + a pixel measurement of the object's bounding box. Also: the screenshot you
are shown is downscaled **non-uniformly** from the true 1206×2622 @3x buffer — reading tap coordinates
off it is how S-019 bought a Shield Pack by accident. Use `xcrun simctl io … screenshot` and divide
by 3.

Finish by updating `02_STATE.md`, filing/updating backlog items, writing
`docs/agent/sessions/SESSION_020.md`, appending to `04_DECISIONS.md` (append-only, never edit an
entry), overwriting this file, and pushing.

Report back in three lines: what got done, what's next, what needs Rayan.
