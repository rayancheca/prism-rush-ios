# HANDOFF → Session 018 · **PASS 018: THE CHARACTER PREVIEW SEAM + ASSET PIPELINE**

## Paste this to start the next session

```
You are session 018 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file in full.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

## YOUR ONE JOB: THE CHARACTER PREVIEW SEAM, THEN THE ASSET PIPELINE.

This is the booked pass. Order is 017 missions (DONE, S-017) → 018 preview seam + assets → 019 the
new character art. Do not start 019's work here; 018 exists precisely so 019 does not cost 24x.

**Every character is currently built TWICE** — a 3D rig and a hand-drawn 2D copy, matched by hand,
with nothing testing that they agree. D-050 ordered new art for ALL 24 characters. Landing 24 new
assets on top of a doubled, untested seam multiplies the problem by 24. Fix the seam first.

**REVIEW QUESTION 2 IS STILL OPEN AND IT SHAPES THIS PASS:** should menu previews become live
renders of the actual rig? Rayan has not answered across three sessions. It is the highest-value
open question in the program. **Do not block on it** — Rayan is autonomous-mode by standing
instruction ("Never ask the user clarifying questions. Make the best decision available and
document it in state.md. Keep building"). Decide, document it as a decision, build it reversibly,
and put the numbers in front of him. That is what S-017 did with the mystery-box question (D-052)
and it worked.

## READ THESE BEFORE TOUCHING CODE

  docs/agent/audits/scratch/s016_characters.md      <- the 24-character inventory
  docs/agent/audits/scratch/s016_assets.md          <- the asset mandate + memory budget (D-046)
  docs/agent/audits/scratch/s016_design-system.md   <- the visual system + 10 ranked craft findings
  docs/agent/audits/scratch/s016_renderer.md        <- the render seam
  docs/agent/sessions/SESSION_017.md                <- the traps list at the bottom is load-bearing

## HARD CONSTRAINTS

  - **Decree 1 — a character NEVER changes identity, in space OR in time.** No `followsWorld`, no
    time-varying hue. Prism wears a STATIC rainbow (D-011) and a test pins that no clock is in the
    resolution path. New art must not reintroduce either.
  - **Decree 2 — previews never lie.** This pass IS decree 2. Menu hero, select swatches, shop
    cards and tease renders must match the in-game character.
  - **D-046 revoked "zero binary assets"** — real meshes/textures/models are wanted now. Two things
    survive and are not the owner's to waive: (a) we must have the right to ship it — AI-generated
    or CC0/public-domain only; "copy subway surfers" means its design language, never its art,
    names or trademarks; (b) **the memory budget is load-bearing** — "the app becomes slow at
    points. this can never happen." Charge every asset against a stated budget.
  - **Iron rule 7** — any new `Profile` field is `decodeIfPresent ?? default`.
  - **G3** — never `@State` a shared `@Observable`; never snapshot `store.profile` into a `let` at
    the top of `body`.
  - **Determinism** — this pass should not touch the spawn path at all. `layoutVersion` stays at
    **12**; the v13 pin `0x9E49_3424_C18A_59C5` is still UNSPENT.
  - **Never make a gate pass by weakening it.** No deleted assertions, no widened bands.

## VERIFICATION — not advisory, and S-016 got this wrong

`swift test` compiles ONLY Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/,
Render/, IAP/, StoreKit or GameKit. **`./Tools/build.sh` is a COMPILE, not a test run.** S-016
reported "iOS build green" and shipped a red XCUITest that sat undiscovered until S-017 found it.

    ./Tools/build.sh                                          # compiles UI/ and Render/
    swift test -c release                                     # 274 tests
    xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
                                                              # 293 tests — RUN THIS ONE

SourceKit in this checkout resolves against macOS: "Cannot find 'Theme' in scope" and "No such
module 'UIKit'" are NOISE. Run the app and open the screenshots. A captured PNG nobody read is not
evidence.

FIRST COMMAND. docs/agent/scratch/ and docs/agent/audits/scratch/ are gitignored, hold ~1.3 GB, and
git does NOT move them between worktrees. No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

Tag `git tag pre-s018` before you start — VERIFY IT DOES NOT EXIST FIRST (`git rev-list -n1
pre-s018`). The S-017 plan hard-coded a stale claim that its own tag was absent; following it would
have moved the recovery point behind four commits. PUSH TO GITHUB at the end — standing instruction.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 017 did — PASS 017: MISSIONS

Four commits, all pushed: `1f1c5ab`, `5924198`, `91379cd`, `27889ea`. **274 SPM + 293 Xcode tests
green.** Decisions **D-052, D-053**. Recovery tag `pre-s017` = `8af1814`. `layoutVersion` untouched
at **12**, v13 pin still unspent.

The owner's complaint was four defects, not one: **ugly · does nothing · not easy to understand ·
not rewarding at all.** All four are answered, and **the coin ledger was not touched.**

## The ruling that shaped the pass (D-052)

The inherited plan's self-described "load-bearing design claim" was that **missions should pay
Mystery Boxes**. A hostile verifier re-derived it in Python and killed it:

- **74 % of a Mystery Box is literally coins**, and a *granted* box has no 300-coin cost, so its
  full EV (300.5) is net faucet.
- The board goes **663 → 1,349 coin-equiv/day**; the catalogue clock **26.8 → 22.0 days**.
- The plan's own thesis says raising mission rewards *"makes every one of the four complaints
  worse"*. The proposal is a **+161 % raise per daily slot** — a raise wearing a costume.
- Independently: `ProfileStore.swift:619` is `guard state.claimable, state.reward > 0`, so a
  mission paying only a box is **silently unclaimable**. Nobody had opened that line.

So the pass answers all four complaints **without touching the ledger**. The faucet is unchanged.

## What shipped

| | What | Complaint answered |
|---|---|---|
| **PR-0006** | The board wrote to disk **and iCloud** from inside `body` (`MissionsView` → `refreshDailyMissions` → `mutate` → `save()` + `cloud.synchronize()`), and the hub badge did it from a `TimelineView`. The refresh **moved** to `.task`; the read side now applies the rollover rule itself, so a UTC rollover still displays correctly with zero writes. | correctness — the backlog had filed only the *badge* half |
| **PR-0473** | **A claimed mission is now a moment.** S-016 shipped `RewardBurstView` and wired it to two callers; missions were not one of them. Mission claims now fire it, with a bespoke **medallion** (a chest is a container you open; a mission is a goal you met) stamped with the mission's own glyph. CLAIM ALL = **one** burst carrying the total. | **not rewarding** (4a — not FELT) |
| **PR-0474** | The `.trim` arc was **invisible below ~10 %**, so a fresh board was 19 rows of decoration. Replaced with a **countable segmented bar**. Each section gained its own standing (`0/3` / `2 READY` / `ALL DONE`) — D-053. Two colliding glyphs fixed. | **ugly + not easy to understand** |
| **PR-0475** | Game over now says **TODAY'S MISSIONS · 2/3 ›**. `grep -i mission GameOverView.swift` previously returned nothing. | **does nothing** (decree 4) |

## The bug S-016 left behind

**`testDailyAndChestRewards` had been red since S-016** and nobody knew, because S-016 reported
"iOS build green" — which is a *compile*, not a test run. The `RewardBurstView` scrim lands between
the rewards rail's two taps, so the second tap dismissed the burst instead of opening the chest.
Confirmed by stashing and running at `pre-s017`: it fails identically there. Fixed, and both tests
now **assert the burst fires** — they gained assertions rather than losing them.

## The fleet, and what is on disk

S-016's handoff said one investigation survived the rate limit. **Five were on disk** — agents write
their files before returning. I launched 14 more agents; **the account hit its WEEKLY limit
mid-run**, so the two missing digs and six hostile verifiers landed but **all four judges and the
synthesizer died. There is no `s017_RULING.md`** — S-017 ruled from the verified material instead.

**7 investigations + 6 hostile verifications** are at `docs/agent/audits/scratch/s017_*.md`. Every
verifier returned PARTIALLY REFUTED. `s017_missions-references.md` was never hostile-verified.

# Rayan action items

1. **Review question 2 — still unanswered after three sessions, and it shapes pass 018.** Should
   menu previews become live renders of the actual rig? Your "new art for all 24" ruling made this
   the biggest decision in the project. "Later" is a fine answer; silence means 24 new assets land
   in a world where every character is drawn twice and nothing tests that the two agree.
2. **The mission reward curve is yours and the numbers are now measured.** The board pays 663
   coins/day = **34 % of the whole meta faucet** and **21 % of everything a 15-min/day player
   earns**. S-017 deliberately did NOT change it — raising it accelerates a catalogue that is
   already free in 26.8 days, and it trades against coin-IAP revenue. If you want it moved, say
   which direction; `s017_missions-economy.md` has the variants costed.
3. **Play the missions board and the claim.** Claim one mission, then use CLAIM ALL. Judge the
   **feel** and the **sound** — the audio is composed from existing SFX because nobody here can
   hear one, and `.newBestFanfare` may be the wrong colour for a mission claim.
4. **THE AUDIO BLOCKER, seven sessions old, only you can clear it.** A landed Warden hazard plays
   `.shieldBreak` — the same buffer as a wall clip, a shield break, an armour break and a blast.
   One buffer, five meanings, three opposite in valence. Costed in `s014_audio.md`. Either listen
   and direct, or say "ship your best guess and I'll judge it".
5. **The Mystery Box odds mismatch is still a shipping blocker.** It displays a **3 %** jackpot and
   rolls **2.5 %** (`ShopValue.swift:157-158` vs `:149-150`); `grep -rn "mysteryOdds" Tests/` finds
   nothing. Guideline 3.1.1 requires disclosed odds to be real, **and the error favours the house.**
   S-017 fenced it out once the box proposal died (D-052) — it needs an owner-blessed home.
   `ShopView.swift:547`/`:560` also both say "1,200-coin jackpot" against a real 1,400, and `:560`
   is the VoiceOver string.
6. **One trace on your actual phone for the slowdown.** Everything measured is on the simulator,
   which is a Mac and far faster than your 16 Pro Max.
7. Carried, never confirmed by a human: the stumble (eight sessions), the slide SFX (S-006), the hub
   redesign (PR-0452), and the `Double Coins` App Store Connect description.

# Open questions for Rayan

- **Review question 2** — live rig previews. Shapes pass 018.
- **The mission reward curve** — measured now; direction is yours.
- **PR-0040** — boss-fight music is a different axis from the per-world-bed decree. Yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid *revive* be leaderboard-eligible? (D-050 ruled the
  *checkpoint* half; the revive half is still open.)

# The pass schedule

| Pass | Surface | Why here |
|---|---|---|
| ~~017~~ | ~~Missions — full rebuild~~ | **DONE (S-017).** All four complaints answered, ledger untouched. |
| **018** | **Character preview seam + asset pipeline + perf instrumentation** | Coupled, and both are **prerequisites** for the art Rayan ordered. Every character is built twice today. |
| **019** | The new character art itself | Blocked on 018. Earlier means building 24 assets twice. |
| **020+** | Warden R1/R2 (D-047), in-run mystery boxes, the three approved monetization mechanics, the magnet + pickup meshes, the Mystery Box odds blocker | All have written designs; none is blocking. |
