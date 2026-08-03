# S-017 HOSTILE VERIFY — `s017_missions-does-nothing.md`

# PARTIALLY REFUTED

Findings **A–E survive on substance** — I re-derived the economy from the Swift literals in Python
without looking at their arithmetic and reproduced every figure to the decimal. What fails is the
**citation layer into `docs/`** (eight wrong line numbers, one inherited stale Swift line), two
**internal numeric contradictions**, and **two §7 proposals with unhandled cases — one of which
requires deleting an existing assertion.**

Note: HEAD is **`8af1814`**, not `ba9655d` as the mandate states. `git diff ba9655d..HEAD` touches
only `HANDOFF.md` + `Tools/workflows/*`; **zero `*.swift` changed**, so every source line number in
the file is still evaluable at HEAD. I verified against HEAD.

---

## 1. WHAT SURVIVES (verified, not agreed with)

### 1.1 The economics — CONFIRMED, independently re-derived

I re-implemented SplitMix64 from `Core/RNG.swift:11-14` + `:27` and the draw loops from
`MissionCatalog.swift:152-160` / `:168-176` in Python, seeded from the literals, and did **not**
read their script's outputs first. Result:

| quantity | mine | theirs | |
|---|---|---|---|
| `daysSinceEpoch` 2026-08-03 | 20668 | 20668 | ✓ |
| daily board, 365 d: min / max / mean | 280 / 400 / **345.10** | 280 / 400 / 345.1 | ✓ |
| today's board (day 20668) | slick6 140 + runs5 100 + dist3k 120 = **360** | 360 | ✓ |
| weekly, 52 wk: min / max / mean | 1900 / 2500 / **2228.85** | 1900 / 2500 / 2228.8 | ✓ |
| this week (`weeksSinceEpoch = d/7 = 2952`) | slide60+streak25+slick35 = **2200** | 2200 | ✓ |
| weekly amortised | 2228.85 / 7 = **318.41** | 318.4 | ✓ |
| **recurring total** | **663.51** | 663.5 | ✓ |
| one-time | 970 + 11,350 = **12,320** | 12,320 | ✓ |

Two things I specifically tried to break and could not:
- The **max 2,500** looked wrong — the arithmetic maximum 3-subset of the weekly pool is **2,600**
  (900+900+800). It is right: that combination simply never lands in those 52 draws. Their number
  is the *observed* max, correctly labelled.
- The **345.1 vs theoretical 345.00** gap is sampling noise on 365 draws, not an error.

Downstream arithmetic, all re-run: 663.5/78.3 = **8.474 min**; shares **21.28 / 15.46 / 9.99 %**;
1000/345.1 = **2.898×**; 83,500/663.5 = **125.9 d**; 12,320/83,500 = **14.75 %**;
11,350/12,320 = **92.13 %**; 4 chests = **560**; board = 6+3+3+7 = **19 cards**. All confirmed.
Only nit: **8 min 28.4 s, not "8 min 29 s"** — and they already note 78.3 is a floor, so the
finding is conservative in the right direction anyway.

### 1.2 The code claims — CONFIRMED verbatim at HEAD

Every one of these I opened at the cited line and matched character-for-character:

- `ProfileStore.swift:577-590` claimMission tail — the quoted block starts at **577** exactly.
  Four writes; `achievementTier` at **:584**; `totalCoinsEarned` at **:587**. ✓
- **`claimMission` has exactly two production call sites** — `MissionsView.swift:132`, `:478`.
  Grep confirms nothing else. **No auto-claim path.** ✓ (Their strongest structural claim.)
- `SkinUnlocks.swift:12` reads the *receipt*, not progress ✓. Writers of `achievementTier` across
  the whole tree: `ProfileStore:584`, `:713`, `GameView:191-192, 206-210` (launch-arg fixtures) —
  exactly as stated; `ProfileStore:550` and `MissionsView:55` are reads, correctly excluded. ✓
- Drift `SkinCatalog.swift:163` gate `:168`; Facet gate `:174`; Wisp `:206` gate `:211`. ✓
- `grep GKAchievement PrismRush/` → **empty**. ✓  `grep -n mission GameOverView.swift` → **empty**. ✓
- `grep MissionCatalog PrismRush/Core/` → **empty** — iron rule 1 holds, §3.6 confirmed. ✓
- `totalCoinsEarned`: writers `ProfileStore:192,324,344,442,587,642` + `GameView:983`; **zero
  production readers** (Profile.swift hits are the decl/CodingKey/decode; IAPCatalog:34 and
  ProfileStore:106,176 are comments). ✓
- `refreshDailyMissions:385-396` removes **both** `missionProgress` and `claimedMissions` for the
  daily pool → §8.2's silent-midnight-destruction is real. ✓
- `GameView:887-889` `closeSheet()` → `checkSkinUnlocks()`; the source comment itself says
  *"popup lands on the menu"*. Finding C's mechanism is confirmed **by the code's own comment**. ✓
- `RewardBurst` has exactly two callers: `GameView:579` (daily), `:585` (chest). ✓
  z-order: burst `:1531-1535` `.zIndex(9)` vs `metaSheet` `:1483-1484` implicit 0 — claim holds. ✓
- `purchaseChime` is genuinely shared with the shop purchase path (`ShopView:595`, `:816`). ✓
- Reduce Motion kill-list: `MissionsView:52-55`, `:419`, `:480-483`, `CoinBadge:34`. All four ✓.
- `Tuning.swift:149` `streakPerMult = 5, multCap = 5` ✓; `MissionsTests:113`,`:120` pin 150 ✓;
  `ProgressionTests:285` asserts against `slot.rewardCoins` (no independent curve pin) ✓;
  `02_STATE.md:279` mutate-from-`body` ✓; `s016_design-system.md:215`, `:442`, `:503` ✓.

`SkinCatalog.swift` **is** in `Package.swift:18`, so §7.1's "pure function, Linux-testable" claim
for the character-name lookup stands. I tried to refute that one and it held.

---

## 2. WHAT IS REFUTED

### 2.1 REFUTED — `GameView.swift:895` does not consume `coinMultiplier` (§1.4)

They write: *"`profile.coinMultiplier` is consumed at exactly one site (`GameView.swift:895`, per
`s016_coins-economy.md:56-59`)"*. **Both halves are wrong.**

- At HEAD, `GameView.swift:895` is a comment inside `buyOrEquipSkin` (*"stray call site must never
  turn `spendCoins(0)` into a free legendary"*). The actual consumption is
  **`GameView.swift:936`**: `let mult = store.profile.coinMultiplier * (coinSurgeActiveThisRun ? 2 : 1)`.
- `s016_coins-economy.md:56-59` is the **coins/min table**, not the multiplier note. The multiplier
  note is at **`s016_coins-economy.md:45-46`** — and *that* file says `GameView.swift:895`, which
  was true before PR-0465 (`f441348`) inserted the RewardBurst block and shifted GameView by ~41
  lines. **They carried a stale cite forward without re-opening it at HEAD.** The mandate for this
  program is that a cite is checked where it points, today.

The *conclusion* (mission claims are not doubled) is still correct — `IAPCatalog.swift:33-34` says
so in a comment, verified. Only the cites are dead.

### 2.2 REFUTED — the design-bible citations are wrong by 3 to 8 lines (§6)

Their §6 is the load-bearing "the bible already said this" argument. Five of its six cites miss:

| quoted text | they cite | **actual** |
|---|---|---|
| "One question per hook: does it give a reason to return tomorrow" | `:498` | **`:501`** (`:498` is blank) |
| "Daily / weekly missions \| **Weak**" | `:508` | **`:508`** ✓ *(the one that lands)* |
| "Achievements \| **Decoration** \| One-time, no cadence." | `:509` | **`:512`** (`:509` is the Free-chest row) |
| "#2 A meta purchase that changes play" | `:566` | **`:562`** (`:566` is the leaderboard-viewer row) |
| "3. Make one purchasable thing change how the game plays" | `:592-594` | **`:601`** (`:592-594` is the §12 header) |
| "What ends it: boredom … does not change how the next run plays" | `:459-461` | **`:459-461`** ✓ |

Every quotation is a real quotation of real bible text — nothing is fabricated. But four of six
pointers land on a blank line, a section header, or **a different row of a different table**.

### 2.3 REFUTED — the owner-quote attribution in §2.1

They attribute *"after the reward it says open chest and it just says chest opened"* to
`s016_mandate.md:41-43`. **`:41-43` is a different complaint** — the M12 *"its ugly"* mission
quote. The chest quote is at **`s016_mandate.md:28`** (summary row) and **`:34-35`** (verbatim).

Worse for their framing: **`s016_mandate.md:37` says "Shipped in S-016 — see D-049. There was no
literal 'chest opened' string."** Their claim that the complaint "survived S-016 because S-016 only
fixed the two paths that route through `RewardBurst`" is *substantively right* (missions were not
wired — I verified only two callers), but it is presented as re-quoting the owner when the mandate
line they point at records the opposite disposition. Re-cite it or the reader will not trust it.

### 2.4 REFUTED — six more `s016_coins-economy.md` cites drift by 1–5 lines

| content | they cite | **actual** |
|---|---|---|
| 3,300 m = 179 coins / 137.2 s = **78.3 coins/min** | `:60` | **`:59`** (`:60` is the 12,000 m row, 100.9/min) |
| "the bot … never chases gems" | `:62-63` | **`:64-65`** |
| the 345 / 318 mission rows | `:71-72` | **`:73-74`** (`:71-72` are login + chest) |
| denominators 3,118 / 4,292 / 6,641 | `:127-131` | **`:134-136`** |
| ranked-#2 "infinite, non-arbitrage sink" + the D-026 no-coin-multiplier constraint | `:456` | **`:454`** (`:456` is #4, premium currency) |
| "the core monetization problem … finding C" | `:26` | **`:25`** (`:26` is finding **D**) |

Consumable-pack cite `:101-103` ✓ and the 83,500 range `:108-110` ✓ do land. Again: every *number*
carried across is correct — I checked each against the target file. It is purely the pointers.

### 2.5 REFUTED — `RewardBurstView` ladder cite, and a file that does not exist

§2.4 point 3: *"`RewardBurstView` draws the login ladder with the claimed rung highlighted
(`RewardBurst.swift:15-17`, `:30-32`)"*. There is **no `RewardBurst.swift`** in the tree — the file
is `RewardBurstView.swift`. And `:15-17` is the `ladder` *property declaration*, `:30-32` is a
*subtitle string*. The ladder is actually **drawn** at `RewardBurstView.swift:84-85` (the
`if case let .daily(streak)` gate) and `:218-220+` (`private func ladder(streak:)`).

The underlying point — a tier ladder is shaped like a login ladder, so reuse is near-free —
**survives**; I read the real drawing code and it generalises. Fix the pointer.

### 2.6 REFUTED — two internal numeric contradictions

- §0 finding B calls it a **"34 pt nav-rail glyph"**; §2.3 calls the same thing a **"19 pt glyph"**.
  The truth: `MenuView.navItem` sets `.font(.system(size: 19, …))` inside a `.frame(width: 34,
  height: 26)`. **§2.3 is right, §0 misread the frame width as a type size.** Corroborated by
  `s016_design-system.md:503` ("19pt symbols in FOUR hues").
- §7.3 calls the badge **"a 12 pt purple digit"**. It is **`size: 10`**, `minWidth: 16`.
- §3.7's heading says `totalCoinsEarned` is **"written by 6 sites"**; its own body then lists
  **seven** (six in ProfileStore + `GameView:983`). Seven is correct.

### 2.7 MISSED — `PackRewardBurst.swift` exists and is never mentioned

There is a **second** reward-celebration view, `PrismRush/UI/PackRewardBurst.swift`, mounted at
`ShopView.swift:57`. It matters two ways the file does not acknowledge: (a) any "missions are the
only surface without a reward moment" phrasing needs qualifying, and (b) it is **prior art for a
second burst shape**, which is directly relevant to §7.2's cost estimate. Not a refutation of a
stated claim — a gap in the survey that a plan would trip over.

---

## 3. THE CASES THEIR PROPOSALS DO NOT HANDLE

### 3.1 §7.5 would require **weakening an existing gate** — the most serious item here

§7.5 offers *"rotate the per-run feats like the daily pool does"* as a remedy for the tombstone
section. That directly collides with a shipped assertion:

```swift
// Tests/CoreTests/MissionsTests.swift:124-125
XCTAssertNil(store.claimMission("run.mult5", now: now.addingTimeInterval(86_400 * 3)),
             "per-run claims never reset")
```

Rotating per-run feats means per-run claims **do** reset, so that assertion must be deleted or
inverted. The file itself sets the rule in §8.4 — *"adding a pin is the only legal direction;
weakening `MissionsTests`/`ProgressionTests` to make a new curve pass is out of bounds"* — and then
proposes something that breaks it three sections later. **Ship §7.5's other two options (retire the
section, or fold the feats into the ladder on-ramp); rotation is out of bounds as written.**

Mechanically it also does not work as described: `refreshDailyMissions:388` clears only
`Set(MissionCatalog.dailyPool.map(\.id))`, so per-run ids are never cleared. Rotation needs a new
refresh path, not "like the daily pool does".

### 3.2 §7.1's power-up upgrade breaks daily-challenge comparability — unaddressed

*"Terminal tiers grant a permanent power-up upgrade (magnet radius, shield count, slow-mo
duration)."* `magnetRange` is a **`Core/Tuning` constant** (`Tuning.swift:73`). Making it
profile-dependent is plumbable through `startRun` without breaking iron rule 1, and it does not
touch the spawn stream, so `layoutVersion` is safe — I checked both and they are not the problem.

The problem is the **daily challenge**: a shared seeded run submitted to the `prismrush.daily`
recurring leaderboard (`GameCenterService.swift:12`). A player holding Marathoner III would run the
**same seed with a bigger magnet** than a player who has not claimed it. The whole point of that
leaderboard is that the seed is equal for everyone; iron rule 10 already goes out of its way to
keep challenge runs clean (no revive, no checkpoint). §7.1 never mentions it. Any earned-upgrade
design must either exclude challenge runs from the upgrade or exclude upgraded players from
submission — and that is a design decision, not an implementation detail.

### 3.3 §7.2's death-panel band can advertise a bonus the app then destroys — decree 5

§7.2 wants a game-over band listing *"the missions this run advanced or completed"*. §8.2 already
establishes that `refreshDailyMissions:385-396` **destroys unclaimed daily progress and claims at
UTC midnight, silently**. The file never connects its own two sections: a run that ends at 23:57
UTC would show `DAILY COMPLETE · +140` on the death panel, and three minutes later the mission and
its 140 coins are gone. **That is decree 5 — "advertised bonuses are always delivered."** The band
must either carry the deadline, or the rollover must stop destroying *claimable* state, before the
band ships. Their own §8.2 is the fix; it is filed as a "loose end" instead of as a blocker on §7.2.

### 3.4 §7.1's "UNLOCKS DRIFT" line needs an owned-state branch — decree 3

The card label proposal has no story for the player who already owns Drift — including via cloud
max-merge (`ProfileStore.swift:713`) on a fresh install where the tier is already claimed. A
claimed tier still reading `UNLOCKS DRIFT` is a stale promise on a normal, expected state. Needs an
owned/claimed branch (`profile.ownedSkins.contains`), which is a trivial add but must be specified.

### 3.5 Edge cases I walked that they **do** survive

- **Brand-new profile:** `Profile` fields are `decodeIfPresent ?? default` (`Profile.swift:147` for
  `totalCoinsEarned`) — iron rule 7 intact; adding a per-source counter (§3.7) is safe if given a
  default. No violation.
- **A week away:** `pendingDailyStreak:305-313` resets to 1 on a gap; missions do not interact.
  Their §3.3 "fully independent" ruling holds.
- **Clock rollback:** `refreshDailyMissions:387` uses `min(last, now)`, and
  `ProgressionTests.swift:317` pins "no double pay after rollback". Their §1.3 four-writes claim is
  not weakened by rollback. Confirmed.
- **Completed on the death frame:** `applyRunSummary` is called once per run (iron rule 9) and
  bumps progress; the mission becomes *claimable*, never *auto-claimed*. Confirmed — this is
  exactly why finding B bites.
- **Decrees 2 / 6, iron rules 1, 2, 3, 5, 7, 8:** no proposal in §7 violates any of them as
  written. **No third-party art, names or trademarks are proposed anywhere in the file.**

---

## 4. CORRECTED VERSIONS

Apply these before the plan quotes this file.

```
§1.4   GameView.swift:895                    → GameView.swift:936
       s016_coins-economy.md:56-59           → s016_coins-economy.md:45-46
§2.1   s016_mandate.md:41-43                 → s016_mandate.md:28 (summary), :34-35 (verbatim)
       + note :37 records it as shipped (D-049); missions were simply never a caller
§2.4   RewardBurst.swift:15-17, :30-32       → RewardBurstView.swift:84-85 and :218-220
§0 B   "34 pt nav-rail glyph"                → 19 pt glyph in a 34×26 frame (badge digit 10 pt)
§7.3   "12 pt purple digit"                  → 10 pt
§3.7   "written by 6 sites"                  → 7 sites
§4.2   "8 min 29 s"                          → 8 min 28 s
§4.4   s016_coins-economy.md:26, finding C   → :25 (finding C; :26 is finding D)
§4.1   s016_coins-economy.md:71-72           → :73-74
§4.2   s016_coins-economy.md:60              → :59
§4.2   s016_coins-economy.md:127-131         → :134-136
§7.1   s016_coins-economy.md:456             → :454
§9     s016_coins-economy.md:62-63           → :64-65
§6     05_GAME_DESIGN.md :498 → :501 · :509 → :512 · :566 → :562 · :592-594 → :601  (:508 ✓)
§7.5   DELETE "rotate the per-run feats like the daily pool does" — it requires inverting
       MissionsTests.swift:124-125 ("per-run claims never reset"), which §8.4 forbids
§7.1   ADD: a mission-earned power-up upgrade must rule on daily-challenge parity
       (prismrush.daily is a shared seed; iron rule 10's spirit)
§7.2   ADD: the death-panel band is blocked on §8.2 — advertising a daily that
       refreshDailyMissions destroys at UTC midnight violates decree 5
§7.1   ADD: the "UNLOCKS DRIFT" label needs an owned/claimed branch (decree 3)
§2.4   ADD: PackRewardBurst.swift (ShopView.swift:57) is a second, unmentioned burst surface
```

## 5. BOTTOM LINE

The **investigation is right and the paperwork is not.** Findings A–E are load-bearing and
survived every attack I could mount: I re-derived the whole economy from scratch and hit their
numbers to the decimal, and every claim rooted in `PrismRush/*.swift` is verbatim at HEAD. The
single best thing in the file is finding **C** — the only non-fungible output of the entire mission
system is three characters, and the screen never names them — and it is confirmed by the code's own
comment at `GameView.swift:887-889`.

But **twelve cites into `docs/` are wrong**, one Swift cite is stale from a pre-PR-0465 audit, one
referenced file does not exist, and three numbers contradict other numbers in the same document.
The plan can trust the findings; it cannot trust the pointers without re-opening them.

And **§7 must not ship as written**: §7.5's rotation option requires weakening
`MissionsTests.swift:124-125`, §7.2's death-panel band is a decree-5 hazard until §8.2's silent
midnight destruction is fixed, and §7.1's earned-upgrade track has no answer for the shared-seed
daily leaderboard.
