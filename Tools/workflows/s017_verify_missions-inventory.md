# S-017 · HOSTILE VERIFY of `s017_missions-inventory.md`

## PARTIALLY REFUTED

The inventory work is strong: ~95% of its `file:line` cites are exact and every catalogue number
re-derives. But its **central economic claim (P2) is refuted by a correction committed after the
HEAD it pins**, its **clock-rollback paragraph is wrong in a way that hides a live exploit**, and
**N1 walks the harmless direction of a two-direction bug**.

Verified at HEAD `e17337d` (clean). The doc pins `ba9655d` — three commits stale. Those three
commits touch only `HANDOFF.md` and `Tools/workflows/s017_missions.js` (`git diff --stat
ba9655d..HEAD`), so **every Swift `file:line` in the doc is still valid**. The doc's *conclusion* is
not, because the tip commit is `[S-016] docs: correct the missions economic reading — I had it
backwards`.

> **Provenance update (second pass).** True HEAD is now `8af1814`, two commits past `e17337d`
> (`s017_missions-plan.md` + `HANDOFF.md`). `git diff e17337d..HEAD -- PrismRush/ Tests/ UITests/`
> is empty — docs only — so nothing below is invalidated. A second hostile pass at `8af1814` is
> appended at the end of this file; it confirms R1–R4 independently and adds five catches.

---

## WHAT SURVIVES

**Every economy number re-derives.** I recomputed from the `MissionCatalog.swift` literals in
python3 rather than checking their arithmetic:

| claim | doc | mine |
|---|---|---|
| daily mean × 3 | 115 → 345/day | 115.0 → 345.0 ✓ |
| weekly mean × 3, amortised | 743 → 2,229/wk → 318/day | 742.857 → 2,228.57 → 318.37 ✓ |
| perRun lifetime | 970 | 970 ✓ |
| achievements | 11,350 / 18 tiers | 11,350 / 18 ✓ |
| mission+ach forever | 12,320 | 12,320 ✓ |
| % of 83,500 catalogue | 14.8% | 14.754% ✓ |
| % of 59,400 world ladder | 20.7% | 20.741% ✓ |
| 345 / 1,943 | 17.8% | 17.756% ✓ |

**P1 is confirmed by execution.** I ran the doc's grep verbatim against `PrismRush/UI/GameView.swift`
→ **zero hits**. Missions have no in-run or post-run presence. This is the doc's best finding.

**Exact cites I opened and confirmed verbatim:** `ProfileStore.swift` `:385-396`, `:408-420`,
`:460-464`, `:465-470`, `:481-489`, `:492-498`, `:518-539`, `:541-558`, `:562-590`, `:593-599`,
`:692-726`, `:693`, `:711-712`, `:70-76` (`sanitized`), `:83-86` (`clamped`).
`GameView.swift` `:979`, `:991`, `:1000-1003`, `:1006`, `:1008`, `:1009`, `:1012`, `:1016` — all
exact. `MissionsView.swift` `:37/:39/:41/:43` (the four in-`body` mutation sites), `:89`, `:111`,
`:119`, `:120`, `:124-129`, `:130-137`, `:140`, `:153`, `:160-161`, `:164-166`, `:285-289`,
`:297-300`, `:348-352`, `:358-363`, `:364`, `:404-422`, `:425-439`, `:476-484`, `:478`, `:539-543`.
`SkinUnlocks.swift:12` and `CharacterSelectView.swift:191` — PR-0318 confirmed real (bar reads raw
`missionProgress`, gate reads `achievementTier`). `Tuning.swift:8` and `:149` correct;
`run.mult5` at 20 gems of streak checks out (`min(5, 1+20/5) = 5`). `MissionsTests.swift` has
exactly **22** tests. `Package.swift` lists exactly **7** `Meta/` files.

**§3.3 is confirmed and the doc is right that it is worse than PR-0006 as filed** — four
`body`-reachable `mutate`→`save()`→`cloud.synchronize()` paths inside `MissionsView.body`, all under
a 60 s `TimelineView`. Iron rule 5 family.

**N3 survives, and I confirmed the mechanism rather than the claim.** `claim()` passes `Date()`
(`:478`); the board's `now` is a `TimelineView` entry date up to 60 s stale. Across UTC midnight the
live `Date()` makes `refreshDailyMissions` wipe *inside* `claimMission`, the slot gate then tests the
new day's slots, and the guard returns `nil` with no feedback. Had it passed the rendered `now`, the
early-return at `:387` would have fired and the claim would have **paid**. So the divergence is not
cosmetic: it converts a paying tap into a silent no-op. Decree 3 violation, real.

**N2 survives as behavior.** `UITests/InteractionUITests.swift:257-260` states the dependency in its
own docstring ("exactly one claimable re-arms after the sweep"). It is load-bearing. Note the
advertised `+total` is honest for that press, so there is **no decree-5 violation** — this is a UX
wrinkle, not a dark pattern, and the doc is right to call it a product call rather than a defect.

**P4 confirmed:** 8−3 daily + 7−3 weekly = 9 of 15. **`Metric.revives` confirmed structurally 0** —
`summary.revives = core.revivesUsed` (`:1012`) only ever executes at the first death.

---

## WHAT IS REFUTED

### R1 · P2 is the exact reading the repo committed a correction to reject — MOST IMPORTANT

The doc's thesis (§4.2, P2): *"The reward curve loses to the idle faucet… Any 'prettier board' that
does not move these numbers will not answer the complaint."*

`HANDOFF.md:82-98` at real HEAD says the opposite, with numbers:

```
  recurring board  =  663 coins/day  =  34.1 % of the whole meta faucet
                                     =  21.3 % of EVERYTHING a 15-min/day player earns
  one-time         = 12,320 coins    =  83.7 % of all one-time meta income
```
> *"raising mission rewards would make all four complaints worse"* … *"An earlier draft said missions
> were 4.5 % of daily earn and told you to bring Rayan a bigger reward curve. That was wrong… **Do
> not act on it.**"*

**My derivation of where the doc went wrong.** It computes `345 / 1,943 = 17.8%` and calls that the
board's share. But `1,943` is the *sum that already contains the weekly line* — the doc's own §1.3
derives `318/day` from weeklies and then drops it from the numerator:

- correct recurring share: `(345 + 318.37) / 1943 = **34.1 %**`, not 17.8%
- correct one-time share: `12,320 / (970 + 11,350 + 2,400) = **83.7 %**` of one-time meta income

`14.8 % of the catalogue` is arithmetically true but is the wrong denominator for a one-time faucet
and is deployed to argue smallness. Likewise "one chest tap (140) beats the mean daily mission (115)"
compares one chest against **one of three** slots; the board pays 663/day against a chest a realistic
player opens two or three times.

**Corrected P2:** *The board is 34.1 % of the recurring meta faucet and 83.7 % of all one-time meta
income. The reward curve is NOT the defect and must not be raised — it accelerates a catalogue
already free in 26.8 days. The defect is that a 21 %-of-income system is invisible (P1) and pays a
currency whose sink is nearly exhausted.* P1, P3, P5, P6 are unaffected and stand.

### R2 · §2.2's clock-rollback paragraph is wrong, and a live farm sits behind it

The doc: *"setting the clock back keeps the current board and its claims… Forward clock is NOT
defended."*

Only the **ledger** is kept. The **gated board is not**. Both `dailyMissions`/`weeklyMissions`
(`:379`, `:402`) and — decisively — `claimMission`'s slot gates (`:569`, `:574`) derive slots from
`daysSinceEpoch(now)`, **never** from the stored `dailyMissionDate`/`weeklyMissionDate`. So a
backward clock makes `refreshDailyMissions` early-return (no wipe, `:387`) while the claim gate
re-rolls to the *past* period's three slots. Layer P4's finding — the whole pool accumulates quietly
— and any already-complete pool mission landing on the rolled-back board pays in full.

I re-derived the draws in python3 from the SplitMix64 constants (`RNG.swift:11-15`, `:27`) rather
than reading Swift, reproducing day-0 `[day.streak18, day.chest2, day.slick6]` and week-0
`[wk.runs30, wk.gems1k, wk.slick35]`:

```
one-step rollback exposes >=1 slot absent from the current board:
  days   2962 / 3000  = 98.7 %
  weeks  2911 / 3000  = 97.0 %
```

`ProgressionTests.testWeeklyClockRollbackBlocked` (`:305-318`, doc says `:306-318`) **does not cover
this**: it re-tests only the one slot it already claimed, and its board assertion is
`weeklyMissionDate == w0` — the *stored date*, never the board `weeklyMissions(now: past)` returns.
The gate's name overstates what it holds. This also settles the PR-0035 / `state.md:475` "which
direction is open" question the doc leaves hanging: **both are**.

### R3 · N1 is real but not new, cites a false supporting claim, and misses the worse direction

- **False sub-claim.** The doc says the merge docstring *"does not mention the daily one at all."*
  `ProfileStore.swift:677` reads: `(missionProgress already merges by max; same accepted risk class
  as the daily board)`. The daily board is named and the risk is explicitly **accepted**. N1 is a
  documented trade-off, not an undiscovered defect.
- **Wrong direction walked.** The doc describes a *loss* (a receipt row blocks one claim). The **gain**
  direction is strictly worse and unmentioned: `missionProgress.merge { max }` (`:711`) imports device
  A's day-N completed progress onto device B's freshly-wiped day-N+1 board. If that id sits in N+1's
  slots and A never claimed it, **B claims it instantly, in full, without playing** — no clock change
  needed. That is the finding worth filing.
- **"No test covers merge × rollover" overstates.** `ProgressionTests.testCloudMergeKeepsMaxXPAndWatermark`
  (`:424-452`) already merges divergent `weeklyMissionDate`s and pins `:449` *"weekly board is
  device-local — not merged"*. Only the `claimedMissions`/`missionProgress` leg is missing — extend
  that test, do not write a new one.

### R4 · Citation and quotation errors (clean tree, so these are real)

| doc says | actual |
|---|---|
| `let queue = claimables` at `MissionsView:121` | **`:123`** (`:121` is `Button {`) |
| fly-up reasoning at `:355-357` | **`:354-357`** |
| `s016_coins-economy.md:53` → "3,300 m pays 179" | **`:59`** |
| `s016_coins-economy.md:88-89` → the 1,943/day sum | **`:85`** |
| `ach.worlds` T3 = "world 12 = 9,600 m" | `worldsCrossed = reachWorld + 1` (`GameView:1009`) ⇒ needs `maxWorld ≥ 11` = **8,800 m** |
| `ClaimRibbon.swift:5-7` quoted as *"Missions is a BOARD YOU VISIT"* | **no such sentence.** `:5-8` says the cells are "a way to start a run, coins waiting for you, and a board you visit", then "Missions is a nav-rail exit". Paraphrase set in quotes and capitalised. |

Two code blocks labelled as source are **not verbatim**: §2.3 (`// ProfileStore.swift:460-473`)
replaces the real `:461` comment with the author's own `// no v > 0 guard — PR-0172` and compresses
three 3-line loops to one line each; §3.1's `claim()` collapses the `if !reduceMotion` block. Both
are semantically faithful, but a doc whose contract is "verified verbatim at that line" should not
edit inside a fenced block.

---

## WHAT IS MISSING

1. **A vacuous gate presented as coverage.** §2.1 cites `ProgressionTests.swift:269-271` as proving
   "day-0 and week-0 boards are disjoint". Every `dailyPool` id is prefixed `day.` and every
   `weeklyPool` id `wk.` (`MissionCatalog.swift:100-108`, `:115-121`), so `day0.isDisjoint(with:
   week0)` holds for **any** RNG, tag, or pool ordering. It cannot fail. It proves nothing about
   stream isolation and must not be counted as protection.
2. **§7 names the wrong goldens — re-pooling is currently UNPROTECTED.** §7 says the slot goldens are
   "order- and count-sensitive". They are not goldens: `testDailySlotsAreDeterministicPerDay` (`:42`)
   and `testWeeklySlotsDeterministic` (`:252`) assert only self-consistency, `count == 3`,
   distinctness, and scope/prefix — **no literal ids anywhere**. Adding or removing a pool entry
   silently changes every future board with a green suite. If S-017 re-pools, land literal-id goldens
   **first**, derived in python3 from the SplitMix64 constants (my script reproduces day-0/week-0),
   never read off the Swift they pin — same discipline as iron rule 3.
3. **An edge case the doc does not walk: the profile that has not opened the app in a week.** On the
   first read after a gap, `refreshDaily` + `refreshWeekly` both fire inside `body` (§3.3) while
   `MenuView:345` computes `unclaimedCount` on that same pass — badge and board can disagree for one
   tick, and the wipe lands in a frame the user did not initiate. This is the strongest argument for
   N4 (split pure `board(now:)` from explicit `refresh(now:)`) and the doc does not make it.

## DECREES / IRON RULES — clean

I checked every proposal in §5–§7 and found **no violation**. Neither mission RNG stream reaches
`startRun(seed:)` (confirmed: dedicated domain tags, results consumed only by the meta layer), so
§7's "no `layoutVersion` exposure, no solvability bot" is **correct** — no `DailyChallenge` bump is
owed by anything in this doc. Core/ imports nothing new. §6.3's six proposed tests are all additive.
**No gate is weakened anywhere** — no deleted assertion, no widened band, no skip. No third-party
art, names, or trademarks appear. §7's `Profile` guidance correctly names all three obligations
(`decodeIfPresent ?? default`, `CodingKeys`, and the `merged()` rule that gets forgotten).

## FIX LIST FOR THE DOC

1. Replace §4.2's framing and P2 with R1's corrected numbers; delete "any prettier board that does
   not move these numbers will not answer the complaint" — it is the reverted reading.
2. Rewrite §2.2's clock bullet per R2 and file the backward-clock farm as a new finding.
3. Re-file N1 as the **gain** direction; strike the "does not mention the daily one" claim; retarget
   the test gap at `testCloudMergeKeepsMaxXPAndWatermark`.
4. Correct the six cites in R4; unquote the ClaimRibbon line; label the two edited blocks as
   paraphrase.
5. Add §6.3 item 7: literal-id slot goldens before any re-pool. Demote the `:269-271` disjointness
   assertion from "coverage" to "vacuous".
6. Restate HEAD as `e17337d`.
