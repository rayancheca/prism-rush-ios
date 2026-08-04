# HANDOFF → Session 019 · **PASS 019: THE CHARACTER ART**

## Paste this to start the next session

```
You are session 019 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file in full.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

## YOUR ONE JOB: THE NEW CHARACTER ART. The seam is built; this is what it was built for.

D-050 ordered new art for ALL 24 CHARACTERS. Session 018 spent itself making that affordable: a
character's proportions now live in ONE place instead of two, with tests that fail if the two
layers ever disagree again. **You author in `PrismRush/Meta/CharacterGeometry.swift` and both the
in-run rig and all 24 previews follow.** That did not exist before 018.

### START HERE — the design problem is NOT "the art is ugly"

`docs/agent/audits/scratch/s016_characters.md` §2 measured it: **the roster is 24 names on 15
silhouettes.** Three body shapes x seven crests is the entire geometric vocabulary. Nine of the
24 share a silhouette with at least two others. Prism/Ember/Bolt are ONE character in three
colours — same sphere, no crest, same antenna — and two of them cost money. So are Void/Blossom/
Fang, and so are Midas/Nebula/Tempo.

**More colours will not fix this. More AXES will.** That file's §5.3 proposes them and §7 says
what four shipped runners did about the same problem. Read it before drawing anything.

### WHAT 018 CHANGED THAT YOU MUST KNOW

**The previews got LESS flattering, on purpose.** The 2-D swatch had been drawing horns at 2.0x,
crowns at 2.1x and ears at 1.6x the size the in-run rig actually builds. Those are now the rig's
real numbers everywhere. So if the crowns look small to you — they were always this small in the
game, and the shop was overselling them. **If you want a bigger crown, make it bigger in the spec
and BOTH layers get it.** That is the whole point of the pass you inherited.

**The canvas is derived, not tuned.** `CharacterGeometry.extent(for:)` computes what a skin needs;
the swatch sizes its Canvas from the roster-wide worst case and wraps it in the historic layout
slot. Add a taller crest or a new body shape and the canvas grows for it automatically. **If you
add a new feature to a character, add it to `extent` in the same edit** — otherwise the box stops
telling the truth and cropping comes back.

Two pinned numbers will move when you change the roster, and that is correct — they exist so the
move is deliberate and visible in a diff:
  `CharacterParityTests.testTheRosterEnvelopeIsPinned`     side 0.923 / up 1.111 / down 0.724
  `CharacterParityTests.testNoCallSiteBleedsOntoItsNeighbours`
**Update the pin to the new measured value. Never widen an accuracy band to make it pass.**

## READ THESE BEFORE TOUCHING CODE

  docs/agent/audits/scratch/s016_characters.md      <- the 24-character inventory, §2 and §5 and §7
  docs/agent/11_ASSETS.md                           <- the memory budget + licence floor (committed)
  docs/agent/audits/scratch/s018_geometry-spec.md   <- the rig/swatch parity derivation
  docs/agent/audits/scratch/s018_verify_geometry-spec.md  <- and the refutation that reshaped it
  docs/agent/sessions/SESSION_018.md                <- the traps list at the bottom is load-bearing

## HARD CONSTRAINTS

  - **Decree 1 — a character NEVER changes identity, in space OR in time.** No `followsWorld`, no
    time-varying hue. Prism wears a STATIC rainbow (D-011) and a test pins that no clock is in the
    resolution path. New art must not reintroduce either.
  - **Decree 2 — previews never lie.** This is now enforced by tests rather than by care. Keep it
    that way: if you add a feature to one layer, add it to the spec, not to the other layer.
  - **D-055 — the rig's rest pose is not the rig.** The player rig is `isEnabled = false` outside a
    live run and leans forward by `-0.16 * speedNorm` while running. Any parity work on a
    z-bearing feature (the face, the crown ring, the aura ring) must say WHICH POSE it matches.
    The eyes were deliberately left alone for exactly this reason — do not "fix" them without
    picking a canonical pose first.
  - **D-046 / 11_ASSETS.md** — real assets are wanted now. Two things are not the owner's to waive:
    we ship only AI-generated or CC0/public-domain work ("copy subway surfers" is its design
    language, never its art or names), and every asset is charged against the stated memory budget.
  - **Iron rule 7** — any new `Profile` field is `decodeIfPresent ?? default`.
  - **G3** — never `@State` a shared `@Observable`; never snapshot `store.profile` into a `let`.
  - **Determinism** — this pass should not touch the spawn path. `layoutVersion` stays at **12**;
    the v13 pin `0x9E49_3424_C18A_59C5` is still UNSPENT.
  - **Never make a gate pass by weakening it.** No deleted assertions, no widened bands.

## VERIFICATION — `./Tools/build.sh` is a COMPILE, not a test run

    ./Tools/build.sh                                          # compiles UI/ and Render/
    swift test -c release                                     # 286 tests
    xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
                                                              # 290 unit + 12 XCUITest — RUN THIS

SourceKit in this checkout resolves against macOS: "Cannot find 'Theme' in scope" and "No such
module 'UIKit'" are NOISE. Run the app and open the screenshots. A captured PNG nobody read is not
evidence. Capture a BASELINE test run before your first edit — S-018 did, and it is the only way
to prove you did not inherit a red test (S-016 shipped one and it sat undiscovered for a session).

FIRST COMMAND. docs/agent/scratch/ and docs/agent/audits/scratch/ are gitignored, hold ~1.4 GB, and
git does NOT move them between worktrees. No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

Tag `git tag pre-s019` — VERIFY IT DOES NOT EXIST FIRST (`git rev-list -n1 pre-s019`).
PUSH TO GITHUB at the end — standing instruction.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 018 did — PASS 018: THE CHARACTER PREVIEW SEAM

Three commits: `c81d32a`, `e6ca8dc`, `968dbb0`. **286 SPM + 302 Xcode tests green** (274 + 293 at
session start). Decisions **D-054, D-055**. Recovery tag `pre-s018` = `d88728a`. `layoutVersion`
untouched at **12**, v13 pin still unspent.

**The stated problem was "every character is built twice". The measured problem was that only the
BODY was shared** — the crest, antenna and aura were two hand-tuned number sets with no shared
constant and no test, and they had drifted by up to **2.0×**:

| feature | rig | swatch | |
|---|---|---|---|
| horns apex reach | 0.680 | **1.370** | the swatch drew horns twice as wide as the game |
| crown centre spike | 0.290 | **0.620** | 2.14×; outer spikes 1.45× — one crest, two factors |
| ears / fin | 0.581 / 0.677 | 0.920 / 1.050 | ≈1.55× |
| antenna stem | 0.677 | **0.560** | the one pointing the other way — 17 % short, all 24 skins |
| aura node count | 1 | **2** | the second node was never in the game |

PR-0312 (23 of 24 cropped) and PR-0453 are **closed by construction**: the Canvas is sized from the
roster's extent and wrapped in the historic slot — `.frame` does not clip — so the figure bleeds
past its slot instead of being cut inside it, and **no `.frame` moved**. Verified on the simulator:
all four legendary auras render complete for the first time.

Three rig defects were corrected rather than copied: the antenna socket had no shape branch (buried
0.360 bodyR inside a crystal, floating clear of a cube), floppy ears hard-coded a world y instead
of hanging off `crestY`, and the crown's five spikes started at angle 0 — lopsided from the only
angle the player ever sees them from.

**Why it survived sixteen sessions:** `Package.swift` compiles neither `UI/` nor `Render/`, so
`CharacterParityTests` was UIKit-gated and invisible to CI. The spec and the six call-site slots
are now in `Meta/`, and the pins run on Linux on every push.

**D-054 answers review question 2** (open three sessions): previews do NOT become live
`RealityView` renders — they become two projections of one spec now, and pictures of the real rig
in 019. **D-055** records why the face was deliberately left alone: the investigation's headline
finding was refuted by its own verifier, because the figure it rested on is a rest pose the rig
never renders.

Also: `docs/agent/11_ASSETS.md` is committed (an iron rule had been citing gitignored scratch), and
three charter sites plus the root `/prompt` file that would have told a future agent to re-enforce
the revoked "zero binary assets" decree are struck or bannered.

# Rayan action items

1. **Look at the characters screen and tell me if the honest version is too plain.** This is the
   one that most needs your eyes. The previews were flattering the characters — horns at 2×,
   crowns at 2.1× what the game actually renders — and they now show the truth. If the crowns look
   small, **they were always this small in the run**; the shop was overselling. Session 019 can
   make them genuinely bigger now, in one place, and both the run and the shop will agree. Say
   whether you want that — it is the first question 019's art brief has to answer.
2. **The measurement that would reverse D-054, and only a device answers it.** Whether iOS 18
   shares one renderer per window across `RealityView` instances. If it does, live 3-D previews
   become affordable and the honest answer flips to live heroes + baked cards. Nobody in this
   program has ever measured it, and it decides every future "can we put 3-D here" question.
3. **One Instruments trace on your actual 16 Pro Max for the slowdown.** Everything measured so far
   is on the simulator, which is a Mac and far faster than your phone. S-018 shipped one real fix
   here (the shop rail was building all 13 cards eagerly and animating ~9 off-screen ones at 30 Hz).
4. **THE AUDIO BLOCKER, eight sessions old, only you can clear it.** A landed Warden hazard plays
   `.shieldBreak` — the same buffer as a wall clip, a shield break, an armour break and a blast.
   One buffer, five meanings, three opposite in valence. Costed in `s014_audio.md`. Either listen
   and direct, or say "ship your best guess and I'll judge it".
5. **The Mystery Box odds mismatch is still a shipping blocker.** It displays a **3 %** jackpot and
   rolls **2.5 %** (`ShopValue.swift:157-158` vs `:149-150`). Guideline 3.1.1 requires disclosed
   odds to be real, **and the error favours the house.** `ShopView.swift:547`/`:560` also both say
   "1,200-coin jackpot" against a real 1,400, and `:560` is the VoiceOver string.
6. **The mission reward curve is yours and the numbers are measured** (S-017). The board pays 663
   coins/day = 34 % of the whole meta faucet. If you want it moved, say which direction.
7. Carried, never confirmed by a human: the stumble, the slide SFX, the hub redesign (PR-0452), and
   the `Double Coins` App Store Connect description.

# Open questions for Rayan

- **Is the honest preview too plain?** (new — item 1 above; it gates 019's art brief)
- **PR-0485** — the legendary aura's node is white in the rig and the trail hue in the preview.
  A taste call, not a derivation. Filed rather than guessed at.
- **PR-0040** — boss-fight music is a different axis from the per-world-bed decree. Yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid *revive* be leaderboard-eligible? (D-050 ruled the
  *checkpoint* half; the revive half is still open.)

# The pass schedule

| Pass | Surface | Why here |
|---|---|---|
| ~~017~~ | ~~Missions~~ | **DONE (S-017).** |
| ~~018~~ | ~~Preview seam + asset foundation~~ | **DONE (S-018).** One spec, both layers, CI can see it. |
| **019** | **The character art** | Unblocked. Author once, both layers follow. Start from `s016_characters.md` §2 — the problem is 15 silhouettes for 24 names, not colour. |
| **020+** | Warden R1/R2 (D-047), in-run mystery boxes, the three approved monetization mechanics, the magnet + pickup meshes, the Mystery Box odds blocker | All have written designs; none is blocking. |
