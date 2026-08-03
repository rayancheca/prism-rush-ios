# HANDOFF → Session 017 · **PASS 017: MISSIONS**

## Paste this to start the next session

```
You are session 017 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file in full.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

## YOUR ONE JOB: REBUILD THE MISSIONS SURFACE. Do not touch anything else.

This is a BOOKED PASS, not a suggestion. Rayan asked for it directly and then caught S-016 for
reserving it without scheduling it. The pass order is 017 missions → 018 character preview seam +
asset pipeline → 019 the new character art. Do not start 018's work here.

His complaint, verbatim (2026-08-03):

  > add into memory that we need a dedicated session to redo the mission section of the app. its
  > ugly. does nothing. its not easy to understand. not rewarding at all. need a million review
  > bots. judge, think , test implement

**Those are FOUR different defects with FOUR different fixes. Do not collapse them into "make the
screen prettier" — that is the failure mode this pass exists to avoid.**

  ugly              → visual craft
  does nothing      → missions don't visibly affect anything the player cares about
  not easy to       → you cannot tell what a mission asks or how close you are
    understand
  not rewarding     → THE PAYOUT IS AN ECONOMY PROBLEM, NOT A UI ONE

## READ THESE BEFORE TOUCHING CODE

  docs/agent/audits/scratch/s016_coins-economy.md   ← the whole economy, measured. Non-negotiable.
  docs/agent/audits/scratch/s016_design-system.md   ← the visual system + 10 ranked craft findings
## THE INVESTIGATION IS ALREADY WRITTEN — RUN IT FIRST, DON'T RE-DERIVE IT

S-016 launched seven agents on missions and **they hit the account rate limit before any of them
returned.** Zero `s017_*.md` files exist. That work is NOT done, but the brief for it is, and it is
committed:

    Workflow({ scriptPath: "Tools/workflows/s017_missions.js" })

Seven parallel investigations — inventory, "does nothing", economy, craft, code seam, references,
plan — four of them adversarially verified. **Run this as your first real action.** It writes to
`docs/agent/audits/scratch/s017_<label>.md`. Do not resume the old run: `resumeFromRunId` is
same-session-only and S-016's run id is dead.

Everything below is what S-016 established by hand and by looking, so you are not starting cold even
if the workflow fails again.

## WHAT S-016 ALREADY PROVED BY LOOKING (screenshots in docs/agent/scratch/s016/missions/)

  1. **Three different progress idioms on ONE screen, and the rows you look at most get the worst.**
     Daily and weekly missions show progress as a bare text fraction — "0/6", "0/5", "0/3.0k".
     No bar. No ring. Achievements on the SAME screen get a segmented tier bar AND a progress arc
     on the icon. So the machinery for legible progress already exists and is not used where it
     matters.
  2. **Icons are generic SF Symbols and they collide.** "Score 6 SLICK bonuses" and "Score 35 SLICK
     bonuses" and "Limbo Legend" all use the same sparkle. "Hit a x5 multiplier in one run" uses a
     glyph that reads as a close/cancel X.
  3. **Nine rows, identical visual weight.** A +140 daily and a +900 weekly are the same card. There
     is no hierarchy, no "you're close to this one", no sense of a set being completed.
  4. **The header already says "19 OPEN · UP TO 4,380 COINS"** — the number is right there and it
     is not small. Which points hard at the real problem below: the board's payout is not the
     defect.

## THE ECONOMIC READING — the spine of the pass, and it is NOT what you would guess

**One agent survived the rate limit and its finding overturns the obvious reading. Read
`docs/agent/audits/scratch/s017_missions-plan.md` §0 and §1 before anything else.**

Measured from `MissionCatalog.swift` literals against `s016_coins-economy.md`:

  3 daily slots, mean 115      →   345 coins/day
  3 weekly slots, amortised    →   318 coins/day
                                  ------------
  recurring board              →   663 coins/day  =  34.1 % of the whole meta faucet
                                                  =  21.3 % of EVERYTHING a 15-min/day player earns
  one-time (6 feats + 7 ladders) → 12,320 coins   =  83.7 % of all one-time meta income

> **The owner looked at a system paying 21 % of his income and said "does nothing."**

That sentence is the thesis. It **rules out** "the numbers are too small", and it means
**raising mission rewards would make all four complaints worse** — it accelerates a catalogue that
is already free in 26.8 days, and it makes an invisible claim moment carry a bigger number.
*(An earlier draft of this handoff said missions were 4.5 % of daily earn and told you to bring
Rayan a bigger reward curve. That was wrong — it compared one +140 daily against the whole day.
Do not act on it.)*

**The defect is downstream of the source.** The board pays a currency whose sink is finite and
nearly free, and it pays it through a 13 pt "+N" that rises 38 pt over 0.8 s and fades
(`MissionsView.swift:548-576`).

### The corrected principle — not "economy before pixels"

> **Decide the reward LEDGER before the first line of code. Then build in whatever order keeps the
> app green, and never rebuild a component twice.**

The binding constraint is not that economy outranks craft — it is that **a mission card cannot be
drawn until you know what a mission pays.** A card rendering a coin amount and a card rendering a
box object are different components.

### "Not rewarding" is TWO defects with a 20× cost difference — do not collapse them

- **(4a) the reward is not FELT.** S-016 shipped `RewardBurstView` (D-049) — scrim, hinging lid,
  confetti, a count rolling from zero, three-layer audio — and wired it to exactly two callers:
  `GameView.swift:579` (daily) and `:585` (chest). **Missions were not one of them.** The mission
  board is the one reward surface in the app that does not use the app's own reward moment.
  **Cost: one call site plus a `RewardBurst.kind` case. Economy risk: zero.** Do this early; it is a
  same-afternoon, immediately visible win, and collapsing it into (4b) queues it behind an owner
  ruling for no reason.
- **(4b) the reward is not WORTH WANTING.** Coins into a finite sink. This one the owner must price.

### The move that makes the consequence half fit in ONE session

**A mission that pays a MYSTERY BOX instead of coins.** `openMysteryBox` already exists, is pure
meta (`ProfileStore.swift:135-144`), and never touches the Core seeded RNG. A free-on-a-timer grant
is ~20 lines mirroring `chestReady`/`openFreeChest` (`ProfileStore.swift:328-331`, `:339-348`) — a
shape this codebase already proves.

That converts the board from the fourth-biggest coin faucet into **the game's primary box faucet**:
it answers "does nothing" (the reward becomes a thing with variance and a ceremony, not a number
added to a pile that is already too big), it answers M7 *"getting boxes should be more prominent"*
on a surface the owner was going to open anyway, and it costs a `Profile` field and a reward-kind
enum rather than a new currency. **This is the load-bearing design claim of the plan — put it to
Rayan as question 1.** If he rejects it, cut those steps and the pass becomes craft + moment only,
which still answers three of the four complaints. The plan is built to degrade that way.

**If that ships, one thing becomes blocking:** the Mystery Box **displays odds it does not roll** —
3 % jackpot shown, 2.5 % rolled (`ShopValue.swift:157-158` vs `:149-150`), with
`grep -rn "mysteryOdds" Tests/` → NOT FOUND. Guideline 3.1.1 requires disclosed odds to be the real
odds and the error favours the house. Fix it and pin it in the same pass.

### "Ugly" and "not easy to understand" are ONE fix, and it is visual work

19 rows in one scroll carrying **four different reset semantics** — never / UTC day / UTC week /
lifetime — signalled by **four bespoke tints declared in that one file** (`MissionsView.swift:26-29`),
more hues than the rest of the app combined. Progress is a `.trim` arc (`:404-422`) — a shape you
cannot count. On this screen the pixels **are** the information architecture, so deferring them as
"just craft" mis-prices them.

## WHAT THE OWNER MUST RULE ON

1. **Do missions pay boxes?** (the load-bearing claim above)
2. **Anything that changes the coin ledger** — it trades against coin IAP revenue. Bring numbers,
   never ship a curve as if it were a bug fix. But note the finding above: the answer is probably
   *not* "pay more coins".

## HARD CONSTRAINTS

  - **Decree 5 still stands and was NOT revoked**: no dark patterns, no fake urgency, advertised
    bonuses always delivered. Expiring missions and streak pressure are legitimate ONLY if the
    deadline is real and enforced in code. Sort anything borderline into ship / owner-must-rule /
    needs-a-revocation, the way s016_coins-economy.md does.
  - **Decree 3**: no broken-looking states for expected situations. PR-0304 is filed — the board
    says "ALL CLEAR" on an 0/N first launch. A brand-new player's first view of this screen is a
    wall of zeros; that is the state to design FIRST, not last.
  - **Iron rule 7**: any new `Profile` field is `decodeIfPresent ?? default`. Old saves must never
    wipe. Pinned by decode tests.
  - **G3**: never `@State` a shared `@Observable`; never snapshot `store.profile` into a `let` at the
    top of `body`. There is a filed defect saying mission claiming mutates and persists the profile
    from inside `body` — verify it and fix it while you are in there.
  - **Determinism**: a mission that changes what spawns costs a `DailyChallenge.layoutVersion` bump
    (12 → 13, pre-armed at `0x9E49_3424_C18A_59C5`) AND a solvability-bot re-run. "Collect N gems in
    a run" is free; "spawn a special pickup" is not. Prefer free ones.
  - **Never make a gate pass by weakening it.** No deleted assertions, no widened bands.

## REUSE, DON'T REINVENT

S-016 shipped `PrismRush/UI/RewardBurstView.swift` (D-049) — a real reward moment with a scrim, a
chest whose lid hinges open, confetti, a rolling count and a progress ladder. **Missions do not use
it.** Claiming a mission should almost certainly fire that same burst. That is the cheapest possible
fix for "not rewarding" and it is already built and verified.

## VERIFICATION — not advisory

`swift test` compiles ONLY Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/,
Render/, IAP/, StoreKit or GameKit, so a green SPM run says NOTHING about this screen. Only
`./Tools/build.sh` plus the simulator does. SourceKit here resolves against macOS — "Cannot find
'Theme' in scope" and "No such module 'UIKit'" are NOISE.

Run the app. Screenshot every state: first-launch 0/N board, partial progress, one complete and
claimable, all claimed, post-reset. Paste real command output into the session log. No output, no
credit.

FIRST COMMAND. docs/agent/scratch/ and docs/agent/audits/scratch/ are gitignored, hold ~1.3 GB, and
git does NOT move them between worktrees. No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

Tag `git tag pre-s017` before you start. PUSH TO GITHUB at the end — standing instruction.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# The pass schedule

Rayan's standing process, given 2026-08-03: **every idea he gives gets captured verbatim, thought
about by many agents, turned into a real plan, and then BOOKED as a numbered pass — ordered by
importance.** A "reserved for its own session" note is a fence, not a booking; he caught S-016 doing
exactly that to missions.

| Pass | Surface | Why here |
|---|---|---|
| **017** | **Missions — full rebuild** | His most recent complaint, four separate defects, and completely independent: nothing blocks it, nothing waits on it. |
| **018** | Character preview seam + asset pipeline + perf instrumentation | Coupled, and both are **prerequisites** for the art he ordered. Every character is currently built twice (3D rig + hand-drawn 2D copy, matched by hand, untested); "new art for all 24" multiplies that seam by 24 unless it is fixed first. |
| **019** | The new character art itself | Blocked on 018. Earlier means building 24 assets twice. |
| **020+** | Warden R1/R2 (see D-047), in-run mystery boxes, the three approved monetization mechanics, the magnet + pickup meshes | All have written designs; none is blocking. |

---

# What session 016 did

Three commits: `fb7a833`, `f441348`, `ba9655d`. **266 SPM tests green, iOS build green**,
`DailyChallenge.layoutVersion` untouched at **12** (v13 pre-armed, unspent). Decisions
**D-046 … D-051**. Recovery tag `pre-s016`. Pushed to GitHub.

Opened on the S-015 Warden handoff and was **redirected four times** by the owner mid-flight.
27 agents ran across two workflows; **21 investigation files are on disk** at
`docs/agent/audits/scratch/s016_*.md`, nine adversarially verified. Do not re-derive them.

## Shipped and verified on the simulator

| | What | Decision |
|---|---|---|
| **M11** | **A reward is a moment, not a sentence.** Both reward paths were `showToast(...)` + one chime — fourteen lines covering the daily bonus AND the free chest. Now `RewardBurstView`: near-opaque scrim, ray fan, a chest whose lid hinges back off the body, confetti thrown upward under gravity, a count that rolls from zero, and the seven-rung daily ladder with today ringed. Three-layer audio on the same clock as the motion. Verified on both paths: +100 daily (2,200 → 2,300) and +185 chest (2,300 → 2,485). | D-049 |
| **M5 (partial)** | **The simulation ran at full rate behind every opaque meta sheet.** `GameCore.snapshot` is the only observed property on an `@Observable` and `advance()` rewrote it every frame in every mode — Observation fires on writes, not changes — so the whole SwiftUI root invalidated 60–120×/s while the player scrolled a list. One guard, mirroring the existing `paused` early-out. **A/B measured, 36 samples each: 23.9% → 19.7% CPU** on the characters sheet. | D-051 |
| **M2** | **"Zero binary assets" revoked and tombstoned**, with the memory budget and licensing floor that replace it. | D-046 |

## Delivered to the owner

**The review artefact** — <https://claude.ai/code/artifact/1217ced6-2d10-406a-a787-4d730f60b964> —
the game photographed this session beside the proposed revision, ten ranked craft findings, every
monetization mechanic sorted against decree 5, the honest performance report, and five questions.
**He answered four (D-050). Question 2 is still open and is now the highest-value question in the
program.**

## Root-caused, NOT fixed

- **R1 + R2 — the Warden fix as designed breaks determinism (D-047).** Gating obstacle suppression on
  encounter liveness makes the fight's end distance player-dependent, so the deck stops being a pure
  function of the seed — iron rule 2's headline AND the Daily Challenge's shipped promise. Two
  independent agents found it. **The dead air *is* the containment margin.** Three properties —
  containment, no dead air, determinism — pick two. **D-048** settles the separable half: arena
  offset **200 m**, with `wardenMaxSeconds` and `wardenArenaLength` both untouched, via an option
  neither S-015 doc had (capture `arenaStart` at arm time instead of re-deriving from
  `floor(d/800)`). Both prior budget figures — 41.6 m and 11.6 m — were wrong as general ceilings;
  the real one is 740 m.
- **`Tuning.swift:793-798` has an arithmetic error in the unsafe direction.** It advertises the
  `wardenMaxSeconds` ceiling as 18.1 s; the real pinned ceiling is **17.822 s**. A session raising
  `T` to 18.0 on that comment's advice turns `WardenTests:628` red with no idea why.
- **The Mystery Box displays odds it does not roll.** Jackpot shown 3%, actually 2.5%; the 600-coin
  band shown 7%, actually 7.5% (`ShopValue.swift:157-158` vs `:149-150`). **Guideline 3.1.1 requires
  disclosed odds to be the real odds, and the error is in the house's favour. This is a shipping
  blocker** and nothing in `Tests/` pins the display table against the roll function.
- **The magnet is a cyan donut**, and fixing the mesh alone would be wasted work — every pickup spins
  at ~4.7 rev/s and goes edge-on ~9.5 times a second. Spin and mesh must change together.
- **The Mystery Box is `Image(systemName: "gift.fill")`** — the highest-margin object in the game.
- **Gold means six things** and collides with the obstacle colour on warm worlds, so a lethal bar and
  a collectible gem are nearly the same hue there. Seen on screen in Ashfall.

# Things you would otherwise rediscover the hard way

- **`PR_AUTOPLAY` leaves the app on the SPLASH.** The run advances *behind* it, so a screenshot burst
  measures a splash overlay, not gameplay. Tap (201, 437) in the 402×874 point space first. Cost me
  a full measurement pass.
- **Do not hand-edit the profile plist to re-arm a reward.** A `plistlib` + `json.dumps` round-trip
  wiped the sim profile back to first-run. Uninstall/reinstall is the honest reset; `simctl install`
  alone KEEPS the profile.
- **A zsh glob matching nothing aborts the whole script** (`rm -f dir/*.png` with no PNGs). Use
  `find … -delete`, or run the script under `bash`.
- **Foreground `sleep` is blocked by the harness.** Use `run_in_background: true`.
- **The A/B that proves a perf fix is cheap and worth it:** copy the file, strip the change with a
  python slice, rebuild, measure, restore. Three minutes, and it turns "should be faster" into
  "23.9% → 19.7%".
- Inherited and still true: `Tools/build.sh` writes to `.dd/Build/Products/`, NOT
  `~/Library/Developer/Xcode/DerivedData` (both exist; the latter is stale). `while core.warden !=
  nil` does not terminate after a Warden kill — add `&& core.mode == .play`.

# Rayan action items

1. **Review question 2 — the only one you didn't answer, and your "new art for all 24" ruling made it
   the biggest decision in the project.** Should menu previews become live renders of the actual rig?
   "Later" is a fine answer; silence means 24 new assets land in a world where every character is
   drawn twice and nothing tests that they match. **Pass 018 is blocked on this.**
2. **The mission reward curve is a revenue decision only you can make.** Missions are 4.5% of a day's
   income against a baseline that hands you 62% of it for free. Raising missions devalues the coin
   IAPs; lowering the baseline makes the game stingier. Pass 017 will bring you the numbers.
3. **Play the new reward.** Claim the daily bonus, open a free chest. Judge the **feel** and the
   **sound** — the audio is composed from existing SFX because nobody here can hear one.
   `.newBestFanfare` may be the wrong colour for a daily bonus.
4. **THE AUDIO BLOCKER, six sessions old, only you can clear it.** A landed Warden hazard plays
   `.shieldBreak` — the same buffer as a wall clip, a shield break, an armour break and a blast.
   One buffer, five meanings, three opposite in valence. Costed design in `s014_audio.md`. Either
   listen and direct, or say "ship your best guess and I'll judge it".
5. **The Mystery Box odds mismatch is a shipping blocker** and the error favours the house. It needs
   fixing before submission regardless of which pass picks it up.
6. **One trace on your actual phone for the slowdown.** Everything measured was on the simulator,
   which is a Mac and far faster than your 16 Pro Max.
7. Carried, never confirmed by a human: the stumble (seven sessions), the slide SFX (S-006), the hub
   redesign (PR-0452), and the `Double Coins` App Store Connect description
   (`Every run pays 2x coins. Forever.`).

# Open questions for Rayan

- **Review question 2** — live rig previews. Blocks pass 018.
- **The mission reward curve** — pass 017 will put numbers in front of you.
- **PR-0040** — boss-fight music is a different axis from the per-world-bed decree and would not
  violate it. Needs a yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid *revive* be leaderboard-eligible? (D-050 ruled the
  *checkpoint* half — the forfeit stays — but the revive half is still open.)
