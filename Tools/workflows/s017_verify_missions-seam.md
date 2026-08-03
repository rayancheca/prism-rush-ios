# S-017 · VERIFY missions-seam — hostile read

## Verdict: **PARTIALLY REFUTED**

The architecture, the writer census, the determinism analysis, the G3 audit and the economy
arithmetic all survive. **Four substantive claims do not**, one of them the only evidence row for the
"ugly" defect. Three proposals (T8, §6.1 option (a), R7's mitigation) are wrong in ways that would
cost the pass a day or weaken a live gate.

**Citations audited: 66. Wrong: 15 (23%).** Eleven are ±1–3-line range drift on a clean tree; four
are substantive. Full list in §5.

---

## 1 · What survives (verified at file:line, independently)

| claim | verdict |
|---|---|
| **Writer census (§2.1)** — 7 write sites, `Core/` writes none | **CONFIRMED.** `grep -rn "achievementTier" PrismRush` returns exactly the 7 sites named (`ProfileStore.swift:550` is a read). `grep -rn "missionProgress" PrismRush/Core` → empty. `GameCore` mentions missions only at `:135,:160,:453,:626,:1054` — all comments, all present. |
| **§2.3(a) mutation during `body`** | **CONFIRMED, and it is the report's best finding.** `refreshDailyMissions:385-396` → `mutate:90` → `save():655-662` (`JSONEncoder().encode` + `UserDefaults.set` + `cloud.set` + `cloud.synchronize()`), reached from `MissionsView.body` at `:37,:39,:41,:43` and `MenuView.body` at `:345`. Every hop verified. |
| **§2.3(b) hub ticks with no sheet** | **Structurally CONFIRMED** (still correctly labelled UNVERIFIED for the frame count). `GameCore.advance:301-311` calls `rebuildSnapshot()` at `:310` with **no mode guard** — `.menu` rebuilds too; `snapshot` is the only observed property (`GameCore.swift:60`); `GameView.body` reads `snapshot.mode` (`:1421`) and builds `MenuView(best: model.core.snapshot.best)` (`:1426`) when `activeSheet == nil` (`:1423`); the D-051 freeze at `:332` requires `activeSheet != nil`. The chain holds. |
| **§3.3 the `CodingKeys` trap** | **CONFIRMED by my own count: 46 stored properties, 46 `CodingKeys` cases (`:118-131`), 46 decode lines (`:137-182`).** The Swift semantics are right — a struct property with an inline default is initialised before the `init(from:)` body, so omitting its decode line compiles silently. |
| **§4.1 missions are RNG-clean** | **CONFIRMED.** `dailyTag :148`, `weeklyTag :165`, docstring `:162-165` verbatim. No `startRun`/`Spawner` reference anywhere in `Meta/`. Content edits cost zero `layoutVersion`. |
| **§5.1/§5.2 G3** | **CONFIRMED.** The five `@State`s (`:16,:342,:343,:344,:559`) are `Int`/`Bool`. `:31` binds the singleton reference, not a `profile` snapshot. |
| **§6.1 claim→character coupling** | **CONFIRMED — and understated.** `unlockProgress` tints the bar `Theme.Role.reward` and the label `Theme.Role.reward` at `fraction >= 1` (`CharacterSelectView.swift:159,:164`). So a finished-but-unclaimed ladder renders a **gold** (= money) full bar directly above a `lock.fill` + `RUN 10,000 M LIFETIME` pill (`:245-254`). Three skins: `SkinCatalog.swift:168,:174,:211` ✓. |
| **All economy numbers** | **CONFIRMED by independent re-derivation** — §2 below. |

---

## 2 · Economy, re-derived from the Swift (not from their arithmetic)

```
daily pool  [120,120,100,100,140,140,120,80]  Σ=920  mean=115.0  ×3 = 345.00 /day
weekly pool [700,800,600,900,900,600,700]     Σ=5200 mean=742.86 ×3 = 2228.57/wk ÷7 = 318.37/day
missions/day = 663.37          perRun Σ = 970    achievements Σ = 11,350 over 18 tiers
one-time = 12,320              663/6641 = 10.0%   663/3118 = 21.3%   663/1943 = 34.1% of meta
```

Every figure in §0 reproduces exactly. `s016_coins-economy.md:73,:74,:81,:85,:134-136` all say what
they are cited as saying (83,500 sink, 13–27 days, 14,720 one-time).

**But — flag under rule 7.** 663/day is a **perfect-completion ceiling**, not a rate: it assumes 3/3
daily *and* 3/3 weekly claimed every single day, and `s016_coins-economy.md:134-136` holds it
constant across all three play-time rows *including 15 min/day*, where `wk.dist20k` alone needs
2,857 m/day. §0 states it flatly as "Missions contribute 663 coins/day". **This weakens R2**: doubling
a ceiling nobody reaches moves the real number by less than "~2 days off a 13-day game" claims.

---

## 3 · REFUTED, with my derivation

### R-1 · §0 "17 SF-Symbol call sites, 6 raw hex literals" — **the numbers are from the wrong column**

`s016_design-system.md:133` is `| MissionsView.swift | 17 | 6 |` in a table whose columns are stated
at `s016_design-system.md:137`: **"124 `typeScale` sites, 135 raw `.font(.system(size:` sites"**. I
counted at HEAD: `typeScale(` → **17**, `.font(.system(size:` → **6**. Exact match. Those are
typography counts, not symbols or hexes.

Actual counts at HEAD: `systemName:` → **5**. `Theme.color(0x` → **5** (`:25,:26,:27,:28,:502`).

**Corrected row:** *"ugly" lives in `UI/MissionsView.swift` (576 L) — 4 bespoke section tints at
`:25-28` plus a 5th stray hex at `:502`, 5 SF-Symbol call sites, and **17 `typeScale` sites against 6
raw `.font(.system(size:` sites** (`s016_design-system.md:133`; the design direction is at `:442`,
which is cited correctly).* The line count is **576**, not 577 — `s016_design-system.md:215` also
says 576.

### R-2 · §2.3/§5.4 "4 × `refreshDaily` + 4 × `refreshWeekly` per body pass" — **it is 3 × each**

Only four call sites reach the boards, and two of them are one-sided:

- `:37` → `claimableMissions:164` → `activeMissions:159-161` → **1 daily + 1 weekly**
- `:39` → `summaryStrip:69` → `activeStates:110-111` → `activeMissions` → **1 daily + 1 weekly**
- `:41` `store.dailyMissions` → **1 daily only**
- `:43` `store.weeklyMissions` → **1 weekly only**

**3 daily + 3 weekly.** The report appears to have counted its own 4-row table as 4-of-each; rows 3
and 4 are single-sided.

### R-3 · §5.4 "~76 `missionState` calls, ~4× reduction" — **57 + |claimables|, ~3×**

- `:165` filter over 19 → 19
- `:111` map over 19 → 19
- `:178` in `sectionBlock`, four sections → 3+3+6+7 = 19
- `:120` `claimAllRow` reduce is over **`claimables`, not all 19**, and only when `count >= 2`

= **57 + c**, c ∈ [0,19]. 76 is the impossible worst case (every one of 19 claimable at once).
Typical board: 57–60. The refactor is a **~3×** reduction, still worth doing.

### R-4 · R7's mitigation "**Append-only pool edits**" — **appending does not help; it re-rolls everything**

`dailySlots:157` draws `rng.int(0, pool.count - 1)`, and `RNG.swift:27` is
`a + Int(unit() * Double(b - a + 1))` — the **range is a multiplier on `unit()`**. Appending a 9th
daily entry changes the first draw from `×8` to `×9`, so the same `unit()` selects a different index
and **every past and future board re-rolls**. The report says exactly this in R7's "why" column and
then contradicts it in the "mitigation" column.

**Corrected mitigation:** there is no safe pool edit. Either (i) accept and announce a global
re-roll, or (ii) version the draw — `let pool = day < cutoverDay ? legacyDailyPool : dailyPool` —
which is the only shape that preserves in-flight progress. Pruning unknown ids in `refresh*` is still
right and still missing.

---

## 4 · Proposals that do not survive

**T8 (§6.3) is founded on a false premise and would weaken a live gate.** It says `PR_UITEST`
"already does this shape". It does the **deliberate inverse**: `GameView.swift:191-192` pin
`ach.dist`/`ach.close` to tier 0 with the comments *"Drift stays locked"* / *"Wisp stays locked"*, and
`:197-198` states outright that *"ach.gems' skin needs tier 2, so claiming tier 1 here can never
auto-grant a character."* The fixture is engineered so **no claim grants a skin**, because
`testMissionsClaimAllCascadeAndSingleClaim` (`InteractionUITests.swift:261`) depends on "exactly ONE
re-arms after the sweep" (`:283`) and two `waitForNonExistence` assertions (`:273-276`). T8 as written
requires editing that fixture → the most valuable catch available (a gate weakened to let a new test
pass). **Corrected T8:** ship a *separate* env fixture (`PR_UITEST_LADDER=1`) that never touches
`PR_DEMOPROFILE`, or drop T8.

**§6.1 option (a) "auto-claim" is not the simple one.** Moving the payout into `applyRunSummary`
(i) deletes the claim moment the owner's "not rewarding" complaint is *about*, (ii) empties the
ACHIEVEMENTS section of claimables permanently — the exact section the only mission XCUITest sweeps
— and (iii) must not bypass `claimMission`'s slot gate (`ProfileStore.swift:567-576`). Option (b)
costs nothing structurally. The report presents them as equal-cost; they are not. Pick (b).

**§6.1 "no surface says so" overstates.** `unclaimedCount:596-597` includes
`MissionCatalog.achievements`, so a finished-unclaimed ladder **does** badge the Missions rail
(`MenuView.swift:345`). The defect is narrower and sharper than stated: the *Characters card* shows a
gold full bar next to a lock and never names the claim. Fix the card; the hub already routes.

**§7 "surfacing the 8-entry daily pool so '3 of 8' is legible" risks decree 4.** All 8 pool entries
accumulate progress (`applyRunSummary:465`) but `claimMission:567-571` refuses the 5 off-board ones.
Rendering them puts five rows on screen that fill up and can never pay — dead affordances with a
progress bar. Show the *count* ("3 of 8 rotating"), never the rows.

**Decree/iron-rule sweep of everything else: clean.** §4.2's "ship zero spawn-path mission types" is
the correct call and keeps iron rules 2/3/4 untouched. §3.4's four-step field recipe matches
`Profile.swift:117-132/:134-183` exactly and honours iron rule 7. Nothing proposed touches `Core/`
(rule 1), `@State`s an `@Observable` (rule 5), or breaks strict concurrency (rule 8). **No
third-party art, names or trademarks are proposed anywhere.**

---

## 5 · Citation audit — 15 of 66 wrong

**Substantive (4):** `s016_design-system.md:133` misread (R-1) · "577 L" ×3 → **576** ·
"4 × refresh" → 3 (R-2) · "~76 `missionState`" → 57+c (R-3).

**Range drift (11):** `mutate` `:88-91` → **:90-93** (and `save()` cited `:90` → **:92**) ·
`sanitized` "the **four** clamps `:71-76`" → **five**, at `:72-76` · counter reset `:503-506` →
**:502-507** · `core.flowSurges` `GameView.swift:948` → **:951** · `.revives` `:1013` → **:1012** ·
PR_UITEST `:199-205` → mission writes span **:191-192 + :199-210** · MenuView 60 s TimelineView
`:331` → **:334** · `snapshot.mode :1420` → **:1421**, `MenuView(best:) :1423` → **:1426** ·
lock pill `CharacterSelectView.swift:244-252` → **:245-254** · goldens `MissionsTests.swift:190-204`
→ **:191-205**, roundtrip `:253-268` → **:253-267**, summary suite `:276-307` → **:276-309** ·
XCUITest `:257-280`/`:261-280` → **:261-290** (`:257-260` is the docstring).

**Verified correct and worth saying so:** every `MissionCatalog.swift` cite (`:6-24`, `:33-84`,
`:43-48`, `:51-66`, `:90-97`, `:100-109`, `:114-122`, `:125-140`, `:142-144`, `:148`, `:152-160`,
`:165`, `:168-176`), every `ProfileStore.swift` mission cite (`:339-348`, `:359-373`, `:377-380`,
`:385-396`, `:400-403`, `:408-420`, `:426-479`, `:481-489`, `:492-498`, `:501-509`, `:518-539`,
`:541-558`, `:562-590`, `:593-599`, `:711-712`), `Profile.swift:62-67/:124/:129/:157-160/:176`,
`SkinUnlocks.swift:12/:24-28`, `SkinCatalog.swift:168/:174/:211`, `Package.swift:20`,
`GameView.swift:98-105/:332/:887-889/:991/:999-1016`, `s016_design-system.md:442`, and all six
`Models.swift` FXEvent cites (`:217,:218,:224,:234,:237`).

---

## 6 · What is missing

1. **The third Codable trap, and it is the silent one.** §3.3 names two cases. A property added with
   **neither** a `CodingKeys` case **nor** an `init(from:)` line compiles with *no* error, is never
   encoded, is never decoded, and never persists. T1's memberwise-init shape does catch it — the test
   is right, the analysis is incomplete. Say so, or someone will "fix" T1 into a subset test.

2. **A stale docstring inside the seam the pass will edit.** `ProfileStore.swift:383-384` says
   *"setting the clock back simply re-rolls the board"*. It does the opposite: the guard at `:387` is
   `utcDayKey(min(last, now)) == today`, and when `now < last` that is `utcDayKey(now) == utcDayKey(now)`
   — **always true**, so a rollback early-returns and the board and its claims are *kept*, exactly
   like the weekly path whose docstring (`:405-407`) describes it correctly. There is a weekly test
   (`ProgressionTests.testWeeklyClockRollbackBlocked:305`) and **no daily equivalent**. Add
   `testDailyClockRollbackBlocked` and fix the comment.

3. **No test, and no proposed test, for a run that straddles UTC midnight.** `applyRunSummary:428`
   refreshes the daily board *before* banking the run, so a run started 23:59 and ended 00:01 credits
   the **new** day. That is the right behaviour and nothing pins it. Add it to the T-list.

4. **The 8-entry pool leaks progress forever.** `applyRunSummary:465` bumps all 8 daily ids every
   run, but `refreshDailyMissions:391-394` only wipes ids currently in `dailyPool` — so an id removed
   from the pool keeps a `missionProgress` entry for the life of the save, in a grow-only iCloud KVS
   payload. R7 mentions this in passing; it belongs in §3.4's checklist as a required prune.

---

## 7 · Corrected version of §0's first table row

| complaint | where it lives | is it a UI problem? |
|---|---|---|
| **"ugly"** | `UI/MissionsView.swift` (**576 L**) — 4 bespoke section tints at `:25-28` + a stray 5th hex at `:502`; **5** SF-Symbol call sites; **17 `typeScale` vs 6 raw `.font(.system(size:` sites** (`s016_design-system.md:133`, direction at `:442`) | **yes**, and only this one |
