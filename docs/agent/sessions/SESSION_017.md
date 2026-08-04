# Session 017 — PASS 017: MISSIONS

**Date:** 2026-08-03 → 2026-08-04. **Recovery tag:** `pre-s017` = `8af1814`.
**Commits:** `1f1c5ab`, `5924198`, `91379cd`, `27889ea`. **Pushed to GitHub.**
**Decisions:** D-052, D-053. **`DailyChallenge.layoutVersion` untouched at 12; the v13 pin
(`0x9E49_3424_C18A_59C5`) is still UNSPENT.** Nothing this session touched the spawner, the
patterns, or RNG consumption.

**Gates: 274 SPM tests green; 293 Xcode tests green (`xcodebuild` exit 0).**

---

## The job

The owner's complaint, verbatim (2026-08-03):

> add into memory that we need a dedicated session to redo the mission section of the app. its
> ugly. does nothing. its not easy to understand. not rewarding at all. need a million review
> bots. judge, think , test implement

Four defects, four different fixes. The failure mode this pass existed to avoid was collapsing
them into "make the screen prettier".

---

## What happened to the review fleet

S-016 launched seven investigations and the account rate limit killed six of their *returns*.
The handoff therefore said only one file survived. **That was wrong — five were on disk**, because
the workflow's contract makes every agent write its file *before* returning. Checking beat
believing.

I launched a 14-agent workflow to close the gap: the two genuinely missing digs
(`missions-economy`, `missions-references`), hostile verification of all seven, four judges on the
load-bearing design question, and a synthesizer.

**The account hit its WEEKLY limit mid-run.** The two digs and six verifiers landed. **All four
judges and the synthesizer died, so there is no `s017_RULING.md`.** I made the ruling myself from
the verified material (D-052) and kept building. No further agents were available for the rest of
the session.

On disk now, and worth more than re-deriving: 7 investigations + **6 hostile verifications**
(`docs/agent/audits/scratch/s017_*.md`). Every verifier returned PARTIALLY REFUTED — none of the
seven survived intact, which is the point of running them.

---

## The ruling (D-052) — the pass's own headline proposal was refuted

`s017_missions-plan.md §1.5` proposed missions pay **Mystery Boxes**, calling it "the load-bearing
design claim of this plan". A hostile verifier re-derived it in Python and killed it:

- **74 % of a Mystery Box is literally coins**, and a *granted* box has no 300-coin cost, so its
  full EV (300.5) is net faucet.
- The board goes **663 → 1,349 coin-equiv/day**; the 83,500-coin catalogue clock goes
  **26.8 → 22.0 days**.
- The plan's own §0 thesis says raising mission rewards *"makes every one of the four complaints
  worse"*. The proposal is a **+161 % raise per daily slot** — a raise wearing a costume.
- Independently: `ProfileStore.swift:619` is `guard state.claimable, state.reward > 0` — a mission
  paying only a box is **silently unclaimable**. The proposal never opened that line.

**So the pass answers all four complaints without touching the ledger.** The faucet is unchanged at
663 coins/day. Re-pricing the board trades against coin-IAP revenue and is Rayan's call; the numbers
are in `s017_missions-economy.md` and in D-052.

---

## What shipped

### 1 · `1f1c5ab` — PR-0006: the board wrote to disk and iCloud from inside `body`

`MissionsView.body` → `store.dailyMissions(now:)` → `refreshDailyMissions` → `mutate` → `save()` +
`cloud.synchronize()`. The hub badge did it too, from inside a `TimelineView`
(`MenuView.swift:345`). The backlog had filed only the badge half; **the missions screen itself was
unrecorded**, and a verifier confirmed that independently.

The refresh had to **move, not disappear** — both surfaces must survive a UTC rollover that lands
while the screen is open. So the read side now applies the rollover rule itself:
`dailyMissionSlots` / `weeklyMissionSlots` are pure, and `missionState` reports a stale daily/weekly
as zero progress and unclaimed. The wipe happens once on `.task`. `unclaimedCount` is now pure
outright.

Four tests, including the one a too-broad staleness rule would fail: **per-run feats and achievement
ladders are lifetime state and must not reset at a rollover.**

### 2 · `5924198` — PR-0473: a claimed mission is a moment

S-016 shipped `RewardBurstView` (D-049) and wired it to two callers — the daily bonus and the free
chest. **Missions were not one of them.** The mission board was the one reward surface in the app
that did not use the app's own reward moment; its entire answer to "you completed a mission" was a
13 pt `+N` that rose 38 pt and faded.

`RewardBurst.Kind` gains `.mission(title:)` and `.missionSet(count:)`. A chest is a container you
open; a mission is a goal you met — so mission kinds get their own centerpiece, a struck medallion
stamped with **the same glyph the mission's card shows** (decree 2), sealed by a ring that sweeps
closed on the `lid` beat so `GameModel.present`'s existing audio timeline stays in sync without
knowing which object is on screen. CLAIM ALL resolves to **one** burst carrying the total (19
ceremonies would be a hostage situation) and reports what was **actually paid**, not what was
advertised.

**Found and fixed a pre-existing breakage:** `testDailyAndChestRewards` had been red since S-016
shipped the burst without re-running the XCUITest suite — the modal scrim lands between the rewards
rail's two taps, so the second tap dismissed the burst instead of opening the chest. Confirmed by
stashing and running at `pre-s017`: **it fails identically there.** Both tests now assert the burst
fires — they gained assertions, not lost them.

### 3 · `91379cd` — PR-0474: the board is countable, and a finished section can say so

- **The daily success state did not exist** (D-053) — the verifier's "strongest finding". New
  `MissionSectionProgress` gives each section its own denominator: pips + `0/3` / `2 READY` /
  `ALL DONE`. `isComplete` requires *collected*, not merely finished.
- **Progress was unreadable.** Every card drew a `.trim` arc around its glyph — a shape you cannot
  read a fraction off, and below ~10 % visually identical to the plain circle it sits on, so a
  fresh board (all 19 rows at 0/N) was nineteen rows of decoration. The arc is gone; the badge is
  identity only; progress is a segmented bar that is **literally countable** where the target is
  small enough to count ("Score 6 SLICK" renders 6 segments) and degrades to a proportional
  12-segment bar for 3,000 m. `s016_design-system.md:442` prescribes exactly this swap.
- **Two glyphs lied.** `sparkles` was drawn by both SLICK missions *and* the Limbo Legend ladder —
  one glyph, three rows, one screen. `multiply` rendered a bare ✕ beside a button, which reads as
  CANCEL, on a mission about hitting a ×5 multiplier.

### 4 · `27889ea` — PR-0475: game over says what the run did to today's missions

`grep -i mission GameOverView.swift` → nothing. The screen that knows exactly which missions the run
advanced said nothing about them, which is most of what "does nothing" means (decree 4). A
TODAY'S MISSIONS row now sits between FULL STATS and CONTINUE, gold when something is claimable.
Hidden on challenge runs — Daily Rush does not advance the daily board, so an unchanged 0/3 there
would read as a bug rather than as the rule.

---

## Command output

```
$ swift test -c release
   Executed 274 tests, with 0 failures (0 unexpected) in 51.325 (51.369) seconds

$ xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
   exit=0
   293 test cases passed

$ ./Tools/build.sh
   BUILD OK
```

Baseline attribution for the pre-existing XCUITest failure:

```
$ git stash && xcodebuild test -only-testing:.../testDailyAndChestRewards
   InteractionUITests.swift:112: error: XCTAssertTrue failed - chest should go on cooldown after opening
   ** TEST FAILED **        # ← at pre-s017, WITHOUT this session's changes
```

## Captures — all opened and looked at, `docs/agent/scratch/s017/`

`before_01_fresh` · `before_02_progress` · `before_03_claimable` · `before_04_tail` ·
`after_01_fresh` · `after_05_claim_single` · `after_06_claimall_f01..f04` · `after_08_gameover`

---

## Traps worth inheriting

- **`PR_SCREEN=missions` still leaves the app on the SPLASH.** Tap (201, 437) in the 402×874 point
  space first. Cost S-016 a whole measurement pass and nearly cost me one.
- **`xcodebuild test` shuts the simulator down.** Any `simctl` work afterwards needs an explicit
  `boot` + ~12 s.
- **Backticks in a `git commit -m` heredoc get shell-substituted.** `` `lid` `` ran as a command
  and silently emptied itself out of the message. Use `-F` with a quoted heredoc.
- **`RewardBurstView` ignores taps until its entrance animation completes** (that is what the
  "TAP TO CONTINUE" fade-in signals). A test that taps the instant it appears does nothing. The
  bounded `dismissBurst` helper in `InteractionUITests` is the honest fix.
- **The plan's `pre-s017` instructions were stale** — it said the tag did not exist and told you to
  create it at `ba9655d`. It exists at `8af1814`; forcing it back would have deleted the pass's own
  workflow harness. Verify with `git rev-list -n1 pre-s017`, do not create it.
- **A dead agent still leaves its file.** Six of S-016's seven "lost" investigations were on disk
  the whole time. Check the directory before re-running anything.
