# S-017 · HOSTILE VERIFICATION of `s017_missions-plan.md`

## VERDICT: **PARTIALLY REFUTED**

Read-only at HEAD `8af1814`, tree clean. Nothing built, run, installed, or edited except this file.

**Citation audit: 61 `file:line` cites opened and read verbatim. 5 wrong, 2 stale-by-inheritance,
1 self-contradicting.** That is a good hit rate for a 553-line plan and better than most in this
program — the plan's *skeleton* is sound. But its **single load-bearing design claim (§1.5, "missions
pay boxes") is refuted on the plan's own arithmetic**, and one open SEV1 is quietly made cut-able.

---

## A · WHAT SURVIVES (re-derived independently, not checked)

### A1 · Every number in §0 is correct. All of it.

`python3` from the raw literals in `MissionCatalog.swift`, not from the plan's table:

| plan claim | my derivation | verdict |
|---|---|---|
| perRun = 970 lifetime | `150+100+120+150+200+250` = **970** | ✅ |
| daily mean 115, 3 slots = 345/day | `[120,120,100,100,140,140,120,80]`/8 = **115.0**; ×3 = **345.0** | ✅ |
| weekly mean 743, amortised 318/day | `[700,800,600,900,900,600,700]`/7 = **742.857**; ×3/7 = **318.367** | ✅ |
| achievements = 11,350 | 1250+2150+1400+1150+2600+1900+900 = **11,350** | ✅ |
| recurring 663/day | 345 + 318.367 = **663.367** | ✅ |
| 34.1 % of the 1,943 meta faucet | 663.367/1943 = **34.141 %** | ✅ |
| 21.3 % of a 15 min/day player's 3,118 | 663.367/3118 = **21.275 %** | ✅ |
| one-time 12,320 = 83.7 % of one-time meta | 12,320/**14,720** (`s016_coins-economy.md:138`) = **83.696 %** | ✅ |
| 14.8 % of the 83,500 catalogue | 12,320/83,500 = **14.754 %** | ✅ |

Both denominators check out against the source doc (`:85` gives `1,000+280+345+318 = 1,943`; `:136`
gives 3,118 and 26.8 days; `:109` gives 83,500). **The plan did not launder its inputs.** Its thesis
sentence — *"the owner looked at a system paying 21 % of his income and said 'does nothing'"* — is
arithmetically earned, and its inference from that (the defect is the sink, not the size of the
number) is the correct reading. **This is the strongest part of the document and I could not dent it.**

One honest caveat the plan should state: 663/day assumes **full completion of all 3 dailies and all
3 weeklies every single day**. It is a *ceiling* on the recurring faucet, not a measured player rate.
The plan calls it "Recurring missions = 663 coins/day" without the qualifier.

### A2 · Structural findings that survive intact

- **PR-0006 extends to `MissionsView` and that is genuinely unrecorded.** Traced the whole path
  myself: `MissionsView.swift:41` → `ProfileStore.swift:378` → `:385` `refreshDailyMissions` →
  `:389` `mutate` → `:655` `save()` → `:660` `cloud.synchronize()`. The backlog's blast radius
  (`03_BACKLOG.md:112`) names only `UI/MenuView.swift` + `Meta/ProfileStore.swift`. **Novel, real.**
- **`GameOverView` has zero missions surface.** `grep -rni "mission" PrismRush/UI/GameOverView.swift`
  → no output, re-run at HEAD. Step 6a's premise holds.
- **The Mystery Box has exactly one player-facing surface.** `showMysteryBox` is set at
  `ShopView.swift:539` (the card) and `:64` (a `PR_MYSTERYBOX` debug env hook — not player-facing).
  The card does sit under `kicker("POWER-UP PACKS")` at `:529`, describing something else. ✅
- **The SEV1 odds mismatch is real and worse than the plan says.** `ShopValue.swift:157` renders
  jackpot **3 %**; `:150` rolls `[0.975,1.0)` = **2.5 %**. `:158` renders **7 %**; `:149` rolls
  **7.5 %**. `grep -rn "mysteryOdds" Tests/` → NOT FOUND, re-run. The comment at `:155` — *"the
  percentages match `mysteryReward`'s bands exactly"* — is itself false. ✅
- **`ShopView.swift:547` and `:560` both say "1,200-coin jackpot"** against a real 1,400. Decree 2
  violation, and `:560` is the *accessibility* string, so it lies to VoiceOver too. ✅
- **`05_GAME_DESIGN.md:350` is factually wrong** — verbatim *"coin EV 192 … 19% house edge"*. I
  compute coin EV = `.42·200+.22·350+.075·600+.025·1400` = **241.0**; full EV 300.5
  (`s016_coins-economy.md:180`). ✅ cite is exact.
- **Aurora is the only unearnable item.** `grep -n "unlock: .iap" SkinCatalog.swift` → **one hit,
  line 223**, and `:219` confirms it is `id: "aurora"`. ✅ Q5's premise holds.
- **The scope fence is rule-correct.** `DailyChallenge.swift:61` confirms
  `layoutVersion: UInt64 = 12`; the v13 pin `0x9E49_3424_C18A_59C5` is unspent. Fencing out in-run
  box pickups is the right call and correctly priced (goldens in two files + 200-seed re-run).
- **§6.3's three rollback rules are the best-reasoned section in the plan.** New IDs never
  re-targeted; schema commit alone and first; a `Profile` field tombstoned not deleted. All three are
  correct against iron rule 7 and `MissionCatalog.swift:87`. No objection.
- **I settled the one thing the plan deferred.** It flagged the 18→19 row reconciliation as
  *"inference, not proof — nobody ran `git show`"*. One command:
  `git log -S'run.warden1' -- PrismRush/Meta/MissionCatalog.swift` → **`21dacc8 [S-009]`**. The
  inference is **CORRECT**. It was one command away and the plan handed it to a sibling instead.

---

## B · WHAT IS REFUTED

### B1 · **REFUTED — the load-bearing claim. Paying missions in boxes RAISES the faucet ~2× and
### accelerates the exact clock §0 calls the root defect.**

§1.5 is the plan's stated *"load-bearing design claim"*. §0 is the plan's stated thesis:

> *"Raising mission rewards would make every one of the four complaints worse, not better — it
> accelerates the 26.8 days."*

Q1 then proposes **dailies pay a box, weeklies pay coins + a box**. A Mystery Box is **EV 300.5**
(`s016_coins-economy.md:180`) — and **74 % of a box is literally coins** (`ShopValue.swift:145,146,
149,150` = 42+22+7.5+2.5 %). A *granted* box has no 300-coin cost, so its full EV is net faucet.

My derivation, not theirs:

| | board coin-equivalent/day | player income/day | days to 83,500 |
|---|---|---|---|
| today | 663 | 3,118 | **26.8** |
| Q1 proposal, full EV 300.5 | **1,349** (+685) | 3,803 | **22.0** |
| Q1 proposal, coin bands only (EV 241) | **1,145** (+481) | 3,599 | **23.2** |

**The proposal doubles the board and cuts the catalogue clock by 4.8 days.** Swapping a 115-coin
daily for a 300.5-EV box is not "converting coins into variance" — it is a **+161 % raise per daily
slot**, and the weekly leg (`coins + a box`) is purely additive. The plan's own §0 says that is the
one thing that makes all four complaints worse.

Worse, **Q2 asks the owner the wrong question.** It offers *"(a) down · (b) flat — replace coins with
boxes of equal stated value · (c) up"* — but (b) is not what Q1 proposes, and Q1 as written is (c)
without saying so. An owner answering "flat" would believe he had ruled out an income rise and would
have authorised a 22 % acceleration. That is the plan's single most consequential defect.

**Corrected version.** If Step 4 ships, the box must be **priced against the coins it replaces, not
added to them**, and the plan must state the delta *before* Q1 is sent:
1. A daily slot paying a box must **drop its coin reward to 0** *and* the board's other legs must
   absorb the difference — 3 boxes/day at EV 300.5 = 901.5, so to hold 663/day flat the weeklies
   must fall from 318 to **~0**, i.e. **weeklies cannot also pay boxes**. Q1's mix cannot be flat.
2. Or grant boxes at a **rate below 1/day** (≈0.7 boxes/day holds the board at ~663 with dailies
   still paying ~150 coins each) — the arithmetic the ledger in Step 1 is supposed to produce.
3. Either way **§0's own delta table must be computed and put in Q1's body**, not deferred to Q2.
   Rewrite Q1 as: *"this raises the board from 663 to N coin-equivalent/day and moves the catalogue
   clock from 26.8 to M days — ship it, or hold flat at 663?"*

### B2 · **REFUTED — `pre-s017` already exists, at a different commit. Following §2/§6.1 as written
### destroys the recovery point.**

The plan states it **twice**, both in bold: *"`pre-s017` does **not** exist yet"* (§2) and
*"Verified: `git tag` lists `pre-s001 … pre-s016` and `post-s003`; **`pre-s017` does not exist
yet**"* (§6.1). At HEAD:

```
git for-each-ref refs/tags/pre-s017
→ pre-s017  8af1814  2026-08-03 14:46:36 -0400
```

It exists, and it points at **`8af1814`**, not the plan's `ba9655d`. `git tag pre-s017` will fail
`already exists`; `git tag -f pre-s017 ba9655d` would move the recovery point **behind four commits**,
including `Tools/workflows/s017_missions.js` (336 L) and `Tools/workflows/s017_missions-plan.md` —
**the workflow that runs this very pass** — plus the reconciled `HANDOFF.md` (+398/−128).
`git reset --hard pre-s017` in §6.4 would then delete the pass's own harness.

**Corrected:** *"The recovery point already exists: `pre-s017` = `8af1814`. Verify with
`git rev-list -n1 pre-s017`; do not create it, do not force it."* The plan's own `ba9655d` header is
stale — it was written before those four commits landed and was never re-based on HEAD.

### B3 · **REFUTED — Step 2's verification gate cannot see Step 2's headline fix. The plan
### contradicts its own §3.1.**

Step 2 says: *"**Verified by:** `swift test` (all three touch Linux-compiled files — `ProfileStore.swift`
and `MissionCatalog.swift` are both in the SPM target)"*, and §3.3 marks Step 2 SPM **"✅ primary"**.

But PR-0006's fix is *"split the daily/weekly query into a pure read for `body` and an explicit
refresh on `.task`/`.onAppear`"* — and the `body` in question is in **`MissionsView.swift`** and
**`MenuView.swift`**. The plan's own §3.1 says of `swift test`: *"**Every line of `MissionsView.swift`,
… `MenuView.swift`.** A green run says nothing about this pass's headline screen."*

A green SPM run can pin that a new `dailyMissionsRead(now:)` is pure. **It cannot prove `body` stopped
calling the mutating one** — that is the entire defect. Marking the gate "primary" is precisely the
false-confidence failure §3.1 was written to prevent, and it is how S-015 shipped
`Theme.Role.warning` past 266 green tests.

**Corrected:** Step 2's PR-0006 leg is verified by **`./Tools/build.sh` + an explicit grep gate** —
enumerate every `body`-reachable `ProfileStore` call and assert none reaches `mutate` (which is
`03_BACKLOG.md:113`'s *actual* Verification line, the one the plan misquotes; see B4). SPM is primary
for PR-0172 only.

### B4 · **REFUTED — 5 wrong line numbers.** Tree is clean, so these are errors, not drift.

| plan cite | plan says it is | what is actually there | correct |
|---|---|---|---|
| `MissionsView.swift:26-29` (twice: §1.3, Step 5) | the four section tints | `:25 todayTint :26 weekTint :27 featTint :28 ladderTint`; `:29` is blank | **`:25-28`** |
| `MissionCatalog.swift:35` | the `revives` `CaseIterable` case | `:35` = `case gems, distance, nearMisses, slides, slickBonuses, runsFinished` | **`:36`** |
| `03_BACKLOG.md:113` | *"the fix sketch at `:113`"* | `:113` = **Verification**; `:111` = Fix sketch | **`:111`** |
| `03_BACKLOG.md:108-115` | the PR-0006 entry | `:108` = Repro (entry starts ~`:104`); **`:115` is the PR-0007 header** | **`:104-113`** |
| `InteractionUITests.swift:257-292` / `:261-292` | the missions XCUITest | func body ends `:289`; `:291-292` is the *next* test's doc comment | **`:257-289`** |

Also **arithmetic, minor:** §1.3 says `CoinFlyUp` *"rises 38 pt"*. `MissionsView.swift:569` is
`.offset(y: risen ? -38 : -4)` — start −4, end −38 = **34 pt of travel**. The 13 pt and 0.8 s are
both exact (`:564`, `:571`).

Two the plan got **right** where the backlog is stale, and deserves credit for: PR-0172's
`ProfileStore.swift:460-464` vs `:481-489` (backlog `:655` still says `:455-459` cf `:476-484` — the
plan silently re-derived at HEAD and is correct). It should have *flagged* the 5-line backlog drift.

### B5 · **REFUTED — "266 tests green at HEAD" is stated as measured and was not measured.**

§3.1 asserts it in **bold** in a table cell, and §3.3's Xcode row asserts **"285 tests (273 unit +
12 XCUITest)"**. §7 ("what I did not verify") lists neither, and the plan's own last row says
*"**not attempted.** Read-only pass; no build, no simctl."*

Both numbers are **S-015's**, lifted from `SESSION_015.md:147` and `:165` via `02_STATE.md:61`. And
S-016 shipped a **code** commit after them — `f441348 [S-016][PR-0465]`, touching
`PrismRush/UI/GameView.swift` and `PrismRush/UI/RewardBurstView.swift`. The Xcode figure therefore
predates live code in the two files **Step 3 is about to edit**. Meanwhile `CLAUDE.md:44,50` still
says **228 / 209**. Three test counts live in this repo and none was re-run at HEAD.

**Corrected:** move both to §7 as *derived from `SESSION_015.md:147,165`, not re-run at HEAD; note
`CLAUDE.md:44,50` disagrees (228/209) and one of the two is stale* — and make Step 0 re-run both, so
the pass owns a real baseline before it edits `RewardBurstView.swift`.

### B6 · **REFUTED (severity) — an open SEV1 is made conditional on an owner ruling about
### something else. This is the "weakened gate" catch.**

Step 4d: *"the SEV1 odds fix, **mandatory if 4a-c ship**"*. §1.5: *"a mission board that advertises a
box makes that misstatement more prominent, so the odds fix rides along."* Step 4 is marked
**SHOULD**, *"cut if §4 Q1 = no"*.

But `s016_coins-economy.md` §2.3 says the opposite, verbatim: *"**Fix (small, and it should land
regardless of anything else in S-016)**"*. It is an **App Store Guideline 3.1.1** exposure that
exists today, in shipped code, whether or not a mission ever pays a box. Bolting it to a cut-able
SHOULD step means **"owner says no to boxes" silently ships a known-false disclosed-odds table for
another pass.** Nothing in the plan is deleted or widened — but an existing SEV1's urgency is
downgraded by attachment, which is the same class of harm.

**Corrected:** promote 4d to its own **MUST** step between Step 2 and Step 3 (it is a truth fix, it
belongs with the other truth fixes), independent of Q1. It is ~15 lines in `ShopValue.swift` +
`ShopView.swift:547,560` + one test, all Linux-compiled, and it needs no owner input at all.

---

## C · WHAT IS MISSING (edge cases and seams the plan does not handle)

### C1 · **The `MissionReward` enum's reader list is incomplete — and the misses are decree-2 lies.**

Step 4b enumerates the readers of `rewardCoins`/`MissionState.reward` as `ProfileStore` `:546,:553,
:586-587,:531,:537` and `MissionsView` `:120,:445,:461`. All eight verified correct. **Three are
missing, and every one renders a coin claim for a box:**

| missed site | what it renders |
|---|---|
| `MissionsView.swift:103-105` `summarySpoken` | *"N rewards claimable, **\(coins) coins waiting**"* — the a11y string behind `missionsSummary`, the identifier the XCUITest waits on (`InteractionUITests.swift:267`) |
| `MissionsView.swift:531-537` `rowA11y` | *"Complete — **\(state.reward) coins** ready to claim"* / *"Reward \(state.reward) coins"* |
| `MissionsView.swift:144, :449, :465` | a literal **`CoinGlyph`** beside every reward number, in CLAIM ALL, the claim button, and the dimmed pill |

`ProfileStore.MissionBoardSummary`'s associated value is *named* `coins:` (`:530,:531,:537`) — the
type itself is denominated in coins. Ship 4b without these and **every box mission advertises coins,
in text, in VoiceOver, and with a coin icon.** That is decree 2 ("previews never lie") failing on the
reward the whole step exists to introduce.

### C2 · **Step 3's `RewardBurstView` reroute is under-priced, and it will turn the XCUITest red for
a reason the plan does not anticipate.**

*"Cost to fix: one call site plus a `RewardBurst.kind` case. Economy risk: zero."*

Z-order is fine — I checked: `GameView.swift:1483` renders the sheet, `:1531-1532` renders
`RewardBurstView` **later in the same stack**, so a burst does overlay the missions sheet. But that
is exactly the problem for the gate:

`testMissionsClaimAllCascadeAndSingleClaim` asserts, in order:
`claim_ach.gems`.**waitForNonExistence** (`:273`) → `claim_ach.slick`.waitForNonExistence (`:275`) →
`claimAll`.waitForNonExistence (`:277`) → then **`claim_ach.chests`.waitForExistence** (`:283`) and
`single.tap()` (`:286`).

With Step 3 shipped, a full-screen burst is up over the board for the whole cascade. The three
`waitForNonExistence` assertions will pass — **for the wrong reason** (occluded, not retired) — and
`:283`/`:286` will then fail or flake because the burst must be dismissed
(`GameView.swift:588-593 dismissReward()`) first. The cheapest way to make that green is to delete
the `waitForNonExistence` lines. **§6.5 forbids exactly that, and the plan never warns Step 3 will
put a maintainer in front of that temptation** — §3.3 marks Step 3's XCUITest column a bare "✅".

**Corrected:** Step 3 must add an explicit burst dismissal to the XCUITest *in the same commit*, and
§3.3's Step-3 XCUITest cell should read **"✅ will need updating — dismissal step, not deletion."**

### C3 · **Step 5 will break the XCUITest structurally, not just by renaming.**

The plan's trap warning is *"a rebuild that **renames** them turns that test red"* — five identifiers
listed, all five verified present (`railMissions` `:263`, `missionsSummary` `:267`, `claimAllButton`
`MissionsView.swift:153`, `claim_<id>` `:457`, `missionCard_<id>` `:364`).

But the real break is `InteractionUITests.swift:284`:
`for _ in 0..<10 where !single.isHittable { app.swipeUp() }` — the test reaches `claim_ach.chests`
**by scrolling the flat 19-row list**. Step 5 item 4 proposes *"a segmented control … or collapse the
two lifetime sections behind a summary row"* and states *"the flat 19-row scroll does not survive."*
Either option puts `ach.chests` behind a **tab or a disclosure**, where ten `swipeUp()`s will never
find it. The identifiers can be perfectly preserved and the test still goes red.

**Corrected:** add to Step 5's trap — *"the test navigates by scroll (`:284`). Any segmentation or
collapse must ship with the matching navigation step in the test, in the same commit."*

### C4 · **PR-0006's frequency is overstated, which mis-prices the fix.**

Step 2 says flatly: *"`body` mutates and saves the profile."* `ProfileStore.swift:387` is
`if let last = profile.dailyMissionDate, Self.utcDayKey(min(last, now)) == today { return }` — an
early return. So `body` mutates **only** on (a) a profile whose `dailyMissionDate` is `nil`, i.e.
**brand-new, exactly once**, and (b) the **first body pass after a UTC day/week rollover**. It is
not a per-evaluation disk + iCloud write. The SwiftUI reentrancy hazard is real and worth fixing
(the repo has shipped three bugs from this family — iron rule 5), but at once-per-day it is not the
performance problem the phrasing implies.

The plan also **never connects its own two observations**: `MissionsView.swift:35` is
`TimelineView(.periodic(from: .now, by: 60))`, which is precisely the mechanism that *guarantees* the
mutation fires inside `body` when the sheet is open across UTC midnight — the same mechanism as
`MenuView.swift:334`, which the plan quotes in the very next paragraph as the thing not to break.
The two screens have the identical defect from the identical cause; the plan treats them as separate.

### C5 · **Edge cases the plan never walks.** Six were requested; the plan walks none of them.

| case | what happens today | plan coverage |
|---|---|---|
| **brand-new profile** | `dailyMissionDate == nil` → `refreshDailyMissions` mutates+saves on first `body` (C4); Step 0's `01_fresh` capture triggers it | capture named, behaviour not |
| **untouched for a week** | daily *and* weekly both roll; two `mutate`→`save()`→`cloud.synchronize()` in one `body` pass (`:389` + `:413`) | **not named** |
| **unclaimed mission at reset** | `refreshDailyMissions:391-394` **wipes `missionProgress` and `claimedMissions` for the whole daily pool** — a completed-but-unclaimed daily is silently destroyed at UTC midnight. Under Step 4 that is a **destroyed box**, not 120 coins. Decree 5: *advertised bonuses are always delivered* | **not named — and Step 4 raises its cost 2.5×** |
| **completed on the death frame** | `applyRunSummary` banks progress once (iron rule 9); the board is only claimable on next open. Fine today; **Step 6a's game-over surface must read post-`applyRunSummary` state or it shows stale progress** | 6a proposed, ordering not specified |
| **clock rollback** | `min(last, now)` clamps at `:387` and `:411`; `clamped()` at `:329`. A free daily box (Step 4c) mirroring `chestReady` inherits the clamp — ✅ compliant | correct by inheritance, not stated |
| **UTC boundary mid-session** | CLAIM ALL freezes `now` (`:126-129`, AUDIT D5-2) so the cascade cannot under-pay — ✅ already handled. But a **single** claim uses a live `Date()` (`MissionsView.swift:478`), so a claim tapped one second after midnight silently returns `nil` and the card just… stops | **not named** |

Row 3 is the important one: **the plan proposes paying boxes into a board that deletes unclaimed
rewards at midnight**, and never notices.

### C6 · **Iron rule 5 (G3) is not fenced for Step 5's file split.**

Step 5 proposes splitting `MissionsView.swift` into `MissionsView` + `MissionCard` + `MissionSection`.
Today's code is compliant — `:31` does `let store = ProfileStore.shared` (the *object*, not
`store.profile`), so observation still tracks. A split that passes `store.profile` or a
`MissionState` **value** down into `MissionCard.swift` is exactly the anti-pattern CLAUDE.md says
*"shipped three v1.0 bugs."* `MissionCard` already takes `state:` as a value (`:177-178`) and
re-reads `ProfileStore.shared` directly in `claim()` (`:478`) — the split must preserve that shape.
The plan names iron rule 7 for Step 4a and iron rule 3 for the fence, but **never names iron rule 5
for the one step that restructures views.**

### C7 · Smaller misses

- **Step 4d's fix is not type-compatible as written.** `mysteryOdds` is
  `[(label: String, pct: **Int**, hex: UInt32)]` (`ShopValue.swift:156`). Rendering `2.5 %` needs
  `pct` to become `Double`/`String` **and** touches the second consumer the plan never lists,
  `MysteryBoxView.swift:71-72`.
- **The 135-font figure was inherited, not recounted.** `s016_design-system.md:137` says 135; at HEAD
  `grep -rc "\.font(\.system(size:" PrismRush/UI/` sums to **139**. So Step 5 leaves **133**, not the
  plan's 129. (The source doc's own `:144` says "~133 remaining", so the plan mis-copied its own
  source.) MissionsView's **6** is exact ✅.
- **§0's "the board is 34 % of the meta faucet" double-counts against Q2.** The 1,943 faucet at
  `s016_coins-economy.md:85` *already includes* the 345 + 318. Saying the board "is 34 % of it" is
  correct; saying income "falls" if boxes replace coins requires netting the box EV back in, which
  Q2 does not do (B1).
- **Decree 3 is unaddressed for the rebuilt board.** `MissionBoardSummary.allClear`
  (`ProfileStore.swift:525`) is the "normal but empty" state the S-007 audit already fixed once
  (`s007_missions.md:201`). Step 5 rebuilds the summary strip and never says the all-clear state must
  survive intact.

---

## D · CHECKED AGAINST THE DECREES AND IRON RULES

| rule | verdict |
|---|---|
| Core/ never imports a renderer; seed determines a run; `layoutVersion` fence | ✅ **clean.** `DailyChallenge.swift:61` = 12 confirmed, v13 pin unspent, in-run boxes correctly fenced to their own pass with the full cost (two golden files + 200-seed + 12,000 m soak) stated |
| Iron rule 2 (seeded RNG) | ✅ `openMysteryBox` uses `Double.random` and `ProfileStore.swift:132-133` says so explicitly — Meta, never Core. A free daily box inherits this correctly |
| Iron rule 5 (G3) | ⚠️ **not fenced for Step 5's split** — see C6 |
| Iron rule 7 (`decodeIfPresent ?? default`) | ✅ named explicitly in 4a, and the non-merge policy correctly mirrors `ProfileStore.swift:719-720` |
| Iron rule 9 (per-death deltas, once per run) | ✅ untouched by any step |
| Swift 6 strict concurrency | ✅ the cascade is already `Task { @MainActor in }` (`:130`); adding `present(...)` inside it is main-isolated |
| **Decree 2 — previews never lie** | ❌ **violated by Step 4b as specified** — C1 (three coin-denominated render sites, incl. VoiceOver). Also already violated today at `ShopView.swift:547,560`, which the plan catches ✅ |
| Decree 3 — no broken states | ⚠️ all-clear state not carried into Step 5 — C7 |
| Decree 4 — everything leads somewhere | ✅ Step 6a is the right read |
| **Decree 5 — no dark patterns, bonuses always delivered** | ❌ **two exposures.** (i) Step 3's "one burst carrying the TOTAL" uses the pre-computed `:120` value, but the cascade only counts successful claims (`:132`) — burst the **accumulated actual return**, not the advertised total. (ii) `refreshDailyMissions:391-394` destroys a completed-unclaimed daily at midnight; Step 4 makes that a destroyed **box** — C5 row 3. Q3's default (a) is correct ✅ |
| Decree 6 — clarity beats spectacle | ✅ §1.3 Attack 3 is right that the four tints + `.trim` arc *are* the legibility defect |
| **Third-party art / names / trademarks** | ✅ **none proposed.** §5 caps the pass at "at most ONE new object — the box", D-046 is read correctly (revoked, replaced by a budget + licensing floor), and no asset, name or mark from another product appears anywhere in the plan |
| Weakened gates | ❌ one — B6 (SEV1 made conditional). No deleted assertion, no widened band, no skipped test |

---

## E · CORRECTED PLAN — the seven edits

1. **§2 / §6.1 — delete the tag step.** `pre-s017` exists at `8af1814`. Verify, never create, never
   force. Re-base the plan's header off `ba9655d`.
2. **§1.5 / §4 Q1 — compute the faucet delta and put it in the question.** As written the proposal
   is +685 coin-equivalent/day and 26.8 → **22.0 days**. Either price the box against the coins it
   replaces (≈0.7 boxes/day holds flat) or tell the owner it is a raise. Q2's option (b) is currently
   unreachable from Q1's mix.
3. **Promote 4d to its own MUST step**, before Step 3, unconditional on Q1. Add
   `MysteryBoxView.swift:71-72` and the `pct: Int` → `Double` change to its blast radius.
4. **Step 2 — swap the gate.** PR-0006 is verified by `./Tools/build.sh` + a `body`-reachability
   grep, not by `swift test`. SPM stays primary for PR-0172 only. Quote `03_BACKLOG.md:111` (Fix
   sketch), not `:113` (Verification).
5. **Step 4b — extend the reader list** by `MissionsView.swift:103-105`, `:531-537`, and the three
   `CoinGlyph` sites `:144,:449,:465`; rename `MissionBoardSummary`'s `coins:` associated value.
6. **Steps 3 and 5 — name the two XCUITest breaks that are not renames**: burst occlusion of the
   three `waitForNonExistence` assertions (`:273,:275,:277`), and scroll-based reachability at
   `:284`. Both get a deliberate in-commit test update; neither gets a deleted assertion.
7. **§7 — move "266 tests green" and "285 tests" into the not-verified table**, note that
   `CLAUDE.md:44,50` says 228/209, and make Step 0 re-run both so the pass owns its own baseline
   before it edits `RewardBurstView.swift` (which S-016 changed in `f441348` after those runs).

Add to §7: the 18→19 reconciliation is now **proven**, not inferred —
`git log -S'run.warden1'` → `21dacc8 [S-009]`.

---

## F · METHOD

- **61 `file:line` citations opened and read verbatim at HEAD `8af1814`.** 5 wrong (B4), 2 stale
  inherited-as-measured (B5), 1 self-contradicting (B3). **54 exact.**
- **Every economy figure re-derived from scratch in `python3`** from the literals in
  `MissionCatalog.swift` and the bands in `ShopValue.swift:143-152` — not by checking the plan's
  arithmetic. All of §0 reproduced to 3 decimal places (A1). The refutation in B1 comes from the same
  script applied to the plan's own proposal, which the plan never ran on itself.
- Files read in full: `MissionCatalog.swift` (177 L), `MissionsView.swift` (regions 24-50, 100-279,
  355-576), `ProfileStore.swift` (40-48, 130-150, 320-420, 450-600, 645-670, 705-730),
  `ShopValue.swift:138-170`, `ShopView.swift:525-565`, `GameView.swift` (160-172, 305-315, 570-600,
  1483/1531 z-order), `MenuView.swift:325-350`, `InteractionUITests.swift:255-295`,
  `SkinCatalog.swift:214-224`, `03_BACKLOG.md:105-118,650-663`, `05_GAME_DESIGN.md:346-356`,
  `s016_coins-economy.md` (§2.3, §3.6, §4.1, and every figure cited), `s016_design-system.md`
  section anchors, `s007_missions.md:35,121,201`.
- Greps re-run, not re-cited: `mysteryOdds` in `Tests/` (NOT FOUND ✅), `mission` in
  `GameOverView.swift` (NOT FOUND ✅), `unlock: .iap` in `SkinCatalog.swift` (1 hit ✅),
  `.font(.system(size:` in `PrismRush/UI/` (139, not 135).
- Git archaeology: `git log -S'run.warden1'`, `git log pre-s016..HEAD -- PrismRush/`,
  `git for-each-ref refs/tags/pre-s017`.
- **Nothing built, installed, launched, or edited.** No `simctl`, no `xcodebuild`, no `swift test` —
  so this review makes **no claim about test counts**, which is the mistake it is refuting in B5.
