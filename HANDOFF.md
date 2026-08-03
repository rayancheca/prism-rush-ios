# HANDOFF → Session 017

## Paste this to start the next session

```
You are session 017 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

THE OWNER REWROTE THE PROGRAM'S CONSTRAINTS IN S-016. Read
docs/agent/audits/scratch/s016_mandate.md FIRST — it is verbatim, decomposed into M1-M12, and it
governs everything below. Headlines:

  * D-046 — **"zero binary assets" IS REVOKED.** "why are you not importing real assests. delete
    that code only decree." Iron rule 6 is why every mesh is procedural, every material is an
    UnlitMaterial, there is not one texture, and the audio layer is DSP behind a 1.82 s loop. It is
    gone. Two things replace it: a MEMORY BUDGET (same message: "the app becomes slow at points.
    this can never happen") and a LICENSING FLOOR — AI-generated or CC0 only; "ciopy subway surfers"
    ships as its design language and box choreography with OUR art, never theirs.
  * D-050 — four rulings he gave on the S-016 review: **new art for ALL 24 characters** (not just
    the duplicated silhouettes); **all three** flagged monetization mechanics ship (near-miss
    reveals, real countdown offers, post-death starter bundle); **keep** the deep-world leaderboard
    forfeit; and the slowdown is **"just browsing the characters and catalog ... mostly just regular
    scrolling not even in gameplay"**, sometimes during the Warden.
  * M12 — **the missions screen gets its own dedicated session.** "its ugly. does nothing. its not
    easy to understand. not rewarding at all. need a million review bots." Do NOT fix it piecemeal
    inside a session about something else. That is reserved scope.

YOUR JOB THIS SESSION, in priority order. Pick one and finish it; do not spread.

  A. **THE ONE QUESTION HE DIDN'T ANSWER, and ruling 1 made it load-bearing.** Every character is
     built TWICE — a RealityKit rig for the run (`RealityRenderer.swift:1185-1209`) and a hand-drawn
     SwiftUI Canvas cartoon for every meta surface (`CharacterSwatch.swift:76-147`). They agree only
     where a human kept them agreeing, there is ZERO test coverage of the crest/aura half of that
     seam, and 23 of 24 are cropped at the top of the swatch today. He just asked for new art for
     all 24, which multiplies that seam by 24. Making the preview a RENDER OF THE RIG fixes decree 2
     structurally instead of by hand. Ask him, or decide and document it — but do not import 24
     assets into the two-implementation world. Detail: `s016_characters.md`, `s016_design-system.md`.

  B. **PERFORMANCE — M5, and he has now told us where.** S-016 landed one guard (D-051): the sim ran
     at full rate behind every opaque meta sheet, because `GameCore.snapshot` is the only observed
     property on an `@Observable` and `advance()` rewrote it every frame in every mode. Measured A/B
     with the characters sheet open: 23.9% -> 19.7% CPU. **That does not close M5.** The big one is
     narrowing snapshot observation itself, and it is NOT simple — `EffectsOverlay` and `HUDView`
     read the snapshot every frame too, so fixing only `GameView.body` leaves the hub invalidating at
     frame rate (the hostile verifier caught exactly this). "Sometimes during the warden" is a THIRD
     symptom nothing has touched: prime suspect is `RealityRenderer.boxEntity` calling
     `.generateBox` on every call so no two obstacles share geometry, with mesh builds landing
     synchronously mid-run as act-two density lifts pool high-water marks.
     **NOTHING IN THIS APP HAS EVER BEEN INSTRUMENTED** — zero signposts, zero perf tests, repo-wide.
     `s016_perf.md` §4 specifies exactly what to add. Land instrumentation BEFORE the next fix, or
     the D-046 asset import will get blamed for a stutter that predates it.
     Read `s016_perf.md` AND `s016_verify_perf.md` — the verifier refuted ~9 of its claims.

  C. **THE ASSET PIPELINE** now that the decree is gone. `s016_assets.md` has it, and its headline
     is counter-intuitive and important: **memory is not what makes this app slow — entity count is,
     and 560 of ~1,000 entities are particle spheres.** One alpha sprite sheet turns 560 spheres
     into 560 two-triangle billboards, so assets can PAY FOR THEMSELVES. Do that first. Also
     UNVERIFIED and highest-leverage: nobody has ever printed `MeshResource.generateSphere`'s
     triangle count; the one-line recipe is in that file. Measure it before anything else.

DO NOT start R1/R2 (the Warden dead air + placement) unless you have read D-047. S-016 designed the
fix in full and then TWO INDEPENDENT AGENTS KILLED IT: gating suppression on encounter liveness makes
the fight's end distance player-dependent, so the deck stops being a pure function of the seed. That
is iron rule 2's headline sentence AND the Daily Challenge's entire shipped promise.
`WardenTests.testAFightCanNeverPerturbTheSpawnStream` goes red by construction and is right to.
D-048 settles the separable half: the arena offset is **200 m**, reachable with `wardenMaxSeconds`
and `wardenArenaLength` both untouched, via an option neither S-015 doc had — capture `arenaStart`
as encounter state at arm time instead of re-deriving it from `floor(d/800)`. Both prior budget
numbers (41.6 m and 11.6 m) were wrong as general ceilings; the real one is 740 m.

FIRST COMMAND. docs/agent/scratch/ and docs/agent/audits/scratch/ are gitignored and hold ~1.3 GB.
Git does NOT move them between worktrees. No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Sixteen for sixteen. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. SourceKit in this checkout resolves against macOS, so "Cannot find 'Theme' in scope" and
"No such module 'UIKit'" are NOISE — believe ./Tools/build.sh, nothing else.

PUSH TO GITHUB. Standing instruction since S-015.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 016 did

Two commits, `fb7a833` and `f441348`. **266 SPM tests green, iOS build green**,
`DailyChallenge.layoutVersion` untouched at **12** (v13 still pre-armed and unspent). Decisions
**D-046 … D-051**. Recovery tag `pre-s016`.

The session opened on the S-015 handoff (R1+R2, the Warden) and was redirected **three times** by
the owner mid-flight. 27 agents ran across two workflows; 21 investigation files are on disk at
`docs/agent/audits/scratch/s016_*.md`, nine of them adversarially verified.

## Shipped and verified on the simulator

| | What | Decision |
|---|---|---|
| **M11** | **A reward is a moment, not a sentence.** Both reward paths were `showToast(...)` + one chime — fourteen lines total. Now `RewardBurstView`: scrim, ray fan, a chest whose lid hinges back, confetti under gravity, a count that rolls from zero, and the seven-rung daily ladder with today ringed. Three-layer audio on the same clock as the motion. Verified on both paths (+100 daily, +185 chest). | D-049 |
| **M5 (partial)** | **The sim ran at full rate behind every opaque meta sheet.** `GameCore.snapshot` is the only observed property on an `@Observable`; Observation fires on writes, not changes, so the whole SwiftUI root invalidated 60–120×/s while the player scrolled a list. One guard. **A/B measured: 23.9% → 19.7% CPU** on the characters sheet. | D-051 |
| **M2** | **The zero-binary-assets decree revoked and tombstoned**, with the memory budget and licensing floor that replace it. | D-046 |

## Delivered to the owner

**The review artefact** — <https://claude.ai/code/artifact/1217ced6-2d10-406a-a787-4d730f60b964> —
the game photographed this session next to the proposed revision, ten ranked findings, the
decree-5 sort of every monetization mechanic into ship / your-call / needs-a-revocation, the honest
performance report, and five questions. **He answered four (D-050). Question 2 is still open.**

## Root-caused, NOT fixed

- **R1 + R2 — the fix as designed breaks determinism (D-047).** The dead air *is* the containment
  margin. Three properties — containment, no dead air, determinism — and you may have any two.
  Recommendation, not yet ruled on: keep determinism, offset the arena 200 m (D-048), shrink
  `wardenArenaLength` toward the realistic worst as an explicit product decision, and fill what
  remains with the victory outro W3 (`s016_outro.md`, no layout risk, ships alone).
- **`Tuning.swift:793-798` contains an arithmetic error in the unsafe direction.** It advertises the
  `wardenMaxSeconds` ceiling as 18.1 s; the real pinned ceiling is **17.822 s**. A future session
  raising `T` to 18.0 on that comment's advice turns `WardenTests:628` red. Fix it in whatever PR
  touches those constants.
- **The magnet is a cyan donut, and fixing the mesh alone would be wasted work** — every pickup spins
  at ~4.7 rev/s and goes edge-on ~9.5 times a second. Spin and mesh must change together.
  `s016_magnet-pickups.md`.
- **The Mystery Box is `Image(systemName: "gift.fill")`** — the highest-margin object in the game.
- **Gold means six things** and collides with the obstacle colour on warm worlds, so a lethal bar and
  a collectible gem are close to the same hue there. Seen on screen in Ashfall.

# Things you would otherwise rediscover the hard way

- **`PR_AUTOPLAY` leaves the app on the SPLASH.** The run advances *behind* it, so a screenshot burst
  measures a splash overlay, not gameplay. Tap (201, 437) in the 402×874 point space first. I lost a
  measurement pass to this.
- **Do not hand-edit the profile plist to re-arm a reward.** A `plistlib` + `json.dumps` round-trip
  wiped the sim profile back to first-run. Uninstall/reinstall is the honest reset;
  `simctl install` alone KEEPS the profile.
- **A zsh glob that matches nothing aborts the whole script** (`rm -f dir/*.png` with no PNGs).
  Cost me a full capture run. Use `find … -delete`, or run the script under `bash`.
- **Foreground `sleep` is blocked by the harness.** Use `run_in_background: true`, or Monitor.
- **The A/B that proves a perf fix is cheap and worth it:** copy the file, strip the change with a
  python slice, rebuild, measure, restore. Three minutes, and it turns "should be faster" into
  "23.9% → 19.7%".
- Inherited and still true: `Tools/build.sh` writes to `.dd/Build/Products/`, NOT
  `~/Library/Developer/Xcode/DerivedData` (both exist, the latter is stale);
  `while core.warden != nil` does not terminate after a Warden kill — add `&& core.mode == .play`.

# Rayan action items

1. **Question 2 from the review — the only one you didn't answer, and your "new art for all 24"
   ruling made it the biggest decision in the project.** Should menu previews become live renders of
   the actual rig? Answering "later" is fine; answering nothing means 24 new assets land in a world
   where every character is drawn twice and nothing tests that they match.
2. **Play the new reward.** Claim the daily bonus and open a free chest. Two things to judge: the
   **feel** of the burst, and the **sound** — which is composed from existing SFX because nobody here
   can hear one. `.newBestFanfare` may be the wrong colour for a daily bonus.
3. **THE AUDIO BLOCKER, now six sessions old and still only you can unblock it.** A landed Warden
   hazard plays `.shieldBreak` — the same buffer as a wall clip, a shield break, an armour break and
   a blast. One buffer, five meanings, three opposite in valence. Costed design in
   `s014_audio.md`. Either listen and direct, or say "ship your best guess and I'll judge it".
4. **The slowdown needs one trace on your actual phone.** Everything measured this session was on the
   simulator, which is a Mac and far faster than your 16 Pro Max. If you can catch it once while
   scrolling characters and tell me roughly how long it hangs, that turns a hunt into a measurement.
5. Carried, still never confirmed by a human: the stumble (seven sessions), the slide SFX (S-006),
   the hub redesign (PR-0452), and the `Double Coins` IAP description in App Store Connect
   (`Every run pays 2x coins. Forever.`) before submission.

# Open questions for Rayan (carried until answered)

- **Review question 2** — live rig previews. See action item 1. Now the highest-value open question
  in the program.
- **PR-0040** — boss-fight music is a different axis from the per-world-bed decree and would not
  violate it. Needs a yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? (D-050 ruled on the
  *checkpoint* half — the forfeit stays — but the revive half is still open.)
