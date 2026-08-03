# Session 015 — the owner opened the scope, and four of his defects were run to ground

**Date:** 2026-08-03 · **Recovery tag:** `pre-s015` · **Commits:** `1ad384c` (`PR-0463`),
`2513c30` (`PR-0464`) · **Decisions:** D-042, D-043, D-044, D-045

---

## How the session actually went

It began as S-014's handoff asked: build, play the Warden at all three ranks, report back. That
part happened and is written up below. Then, roughly forty minutes in, the owner sent two messages
that changed the session:

1. **"make sure youre pushing to github"** — acted on immediately. The repo had **17 commits going
   back to S-010 that had never been pushed**. `git push origin main` → `e42ac8b..b95f6d4`. S-014's
   handoff described this as "the repo's existing rhythm, not an oversight"; that reading was wrong
   and it is now standing instruction to push.

2. The broad mandate, kept verbatim at `docs/agent/audits/scratch/s015_mandate.md`, naming four
   concrete defects and asking for many passes on the Warden. Everything after that point was
   organised around it.

---

## Part 1 — playing it (the job S-014 handed over)

Built, installed, played rank 1 and rank 3 with real touch input via
`mcp__Claude_Code_iOS_Simulator__control`, reviewed as contact sheets. Captures in
`docs/agent/scratch/s015/`.

**S-014's work holds up and I could not fault its headline claims.**

- **D-039 lethality reads exactly as designed.** On a rank-3 encounter the escalation was legible
  frame by frame: `HIT — IT SHRUGS IT OFF` with a violet ring (strike 1) → `HIT — ONE MORE ENDS IT`
  in red with a red ring (strike 2, the brink) → `THE WARDEN GOT YOU` (strike 3). Budget 2 at rank
  3, confirmed by counting. `r3_transition.png`.
- **D-041 holds.** The red appears exactly once per encounter, at the brink, and the death panel is
  the only other place it lands. It is spent, not sprayed.
- **D-040's arena reads.** Ribs, posts, the lattice mouth gate and the kerb are all clearly
  present and the arena does look like a structure rather than open track.

**Three things I saw that the handoff had predicted, and one it had not:**

- Predicted, and worse at full resolution than described: **the boss does not own the frame.** At
  rank 3 the pink-and-gold halo fills the top third and the craft is drawn on it in pale grey. See
  Part 3 for the measurement.
- Predicted: **hazard violet on world violet.** World 9's grid is violet and the thrown hazard is
  `0xC77BFF`.
- Not predicted: at rank 1 the Warden lands hazards *constantly* on a barely-active player —
  `HIT — IT SHRUGS IT OFF` fired at least 7 times in ~120 m. Correct behaviour at a non-lethal rank,
  but it makes the message itself feel like noise.
- **Anomaly, unexplained and filed rather than guessed at:** a rank-3 run ended and the app landed
  on the **Profile screen ~0.3 s after the death panel appeared**, without a plausible tap. Too fast
  to be one of my queued swipes. Worth 10 minutes in S-016 — if a swipe can skip the death panel,
  that is a real bug.

---

## Part 2 — the four named defects

Six read-only investigations were fanned out (`Workflow`, 12 agents, every finding adversarially
re-read by a hostile verifier instructed to default to *refuted*). All twelve returned; results in
`docs/agent/audits/scratch/s015_*.md`. The simulator was kept exclusively for me — agents were
barred from `xcrun simctl` and `xcodebuild`.

### R1 — "theres a good 15 seconds after the warden where nothing happens" · ROOT-CAUSED, OPEN

**14.75 s.** The arena is 770 m, the fight uses ~297 m, and `Warden.suppresses` gates on
`isArena(d)` — a pure distance function blind to whether the encounter is alive. The remaining
473.3 m of deck is deliberately swept and stays that way.

Independently confirmed on the simulator before the agent reported: withdrawal at **2,851 m**, first
obstacle at **~3,121 m** — 270 m of gems-only track in that particular (short) fight.

The cursor is *not* stale — `Spawner.fill` advances in lockstep throughout; the commands are simply
thrown away at `GameCore.swift:1220`. `docs/agent/audits/scratch/s015_r1_deadair.md`.

### R2 — "the warden shouldnt come at the very beggining of a world" · ROOT-CAUSED, OPEN

Offset **0.0 m**, by construction. `Warden.arenaWorld`'s own comment: *"Arenas sit at the START of
every `wardenEveryWorlds`-th world."* Real play, not a debug artefact.

**R1 and R2 are one bug**, and the constraint that binds them is arithmetic: a worst-case fight is
698 m and a world is 800 m, leaving 41.6 m of slack for any delay. `s015_r2_placement.md`.

### R3 — the hole does not cover the ground · FIXED (D-044)

Found from source in one comparison: chasm parts **7.6** wide, deck rungs **9**. 0.7 u of lit rung
survived on each shoulder of the void for its whole 8 m. `RealityRenderer.swift:214` says why —
*"3.8 either side, matching the bar mesh"* — which is the width an obstacle needs, not a hole.

The hostile verifier confirmed the mechanism and added two things I had missed: the well geometry is
**completely invisible** (unbroken ground plane above it, plus the chasm's own opaque lid over the
mouth), and the lid at `0x07060E` is chromatically identical to the deck at `white 0.02`. Both are
recorded in D-044 and left for a pass that can be judged on screen.

**I never got a chasm on screen.** Six attempts, documented in the handoff. The fix is proven by
arithmetic and by a green build; it is not proven by a picture, and I am not claiming otherwise.

### R4 — "the pyramid renders in fron of the ground" · FIXED (D-045)

Not a depth bug. The only floor was a 16-wide ribbon while the frustum sees to |x| ≈ 23, and all
twelve skies are authored against an infinite floor at y = 0. Fixed with an invisible 70-wide
occluder apron 0.01 below the deck.

**Verified A/B** at 1,600 m in Solar Sands (`w2_compare.png`): before, the pyramids and a spire hang
past the dune line into the void; after, they terminate on it.

Class-A offenders (straddling y = 0 *inside* the lanes, genuinely nearer than the deck) are not
fixed by an occluder and are named in D-045: Ashfall's volcano and Orbital's planet limb.

---

## Part 3 — the Warden work

`s015_r5a_fightdesign.md` is a 697-line inventory plus thirteen ranked changes W1–W13. Two shipped.

### W1 (D-042) — the flinch

The finding that justified the whole exercise: **`Tuning.wardenHitRecoil` was documented as the
damage recoil and wired to the muzzle flash.** The only recoil in the game fired when the Warden
*attacked*. Answering a hazard — the entire win condition — moved nothing on screen.

Split into `wardenThrowKick` (2.2, rides `throwFlash`, v2.2 behaviour preserved exactly) and
`wardenHitRecoil` (3.4, rides a new `hitFlash`). Rig banks the hull on **roll**.

**Verified at 12 fps on a recorded rank-3 encounter** (`flinch2.png`): the craft visibly banks on
contact across frames 5–9 and returns level between throws. The spars shed alongside it.

### W2 (D-043) — the stake, drawn

`WARDEN · III`, a draining clock, and the strike budget as dots. Verified on the same capture
(`r3b_a.png`): rank shows, the clock drains, and two dots appear at rank 3 — correct, since
`wardenStrikesSurvivedByRank[2] == 2`.

One build failure worth recording, because it is exactly the class `swift test` cannot see: I wrote
`Theme.Role.warning`, which does not exist. 266 SPM tests were green over it. The iOS build caught it
in one line. The replacement is better anyway — the clock's last quarter now takes the **Warden's
violet**, keeping D-041's red spent on lethality alone.

---

## Verification

```
$ swift test -c release
Executed 266 tests, with 0 failures (0 unexpected) in 53.638 (53.660) seconds
```

Goldens included, so no RNG moved and `layoutVersion` stays at 12.

```
$ ./Tools/build.sh
BUILD OK

$ xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
Test Suite 'PrismRushTests.xctest' passed
     Executed 273 tests, with 0 failures (0 unexpected) in 271.682 seconds
Test Suite 'PrismRushUITests.xctest' passed
     Executed 12 tests, with 0 failures (0 unexpected) in 152.770 seconds
** TEST SUCCEEDED **
```

**285 Xcode tests** (273 unit + 12 XCUITest), zero failures — run AFTER both commits, so the HUD
change and the renderer changes are both covered.

Build currency confirmed by grepping the dylib for strings only the change introduces, not by mtime.

Everything claimed above about on-screen behaviour was read off a capture, and every capture was
opened and looked at.

---

## What I deliberately did not do

**I did not start R1's layout change.** It needs `layoutVersion` 12 → 13, goldens re-derived in
Python and pinned in two files, a 200-seed solvability re-run over 473 m per Warden world that was
previously guaranteed-clear, `DifficultyCurveTests` re-baselined, and an `arenaLive` flag threaded
into the renderer or `ArenaShell` starts lying. `01_RULES.md §2` says not to start a
determinism-affecting change on fumes, and it is right. It is session 016's single job, fully
specified.

I also did not touch the audio (needs the owner's ears — five sessions now) or the world-9 sky
(it is a look the owner chose; the measurement is his to act on).
