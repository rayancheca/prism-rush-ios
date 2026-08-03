# S-017 · missions-craft

Investigator report for pass 017. Scope: **"its ugly"** + **"its not easy to understand"** — the
visual and information-architecture half of the owner's four-part complaint.

Read-only. Nothing built, run, edited or launched outside this file. Every claim carries a
`file:line`; where I looked and found nothing I say NOT FOUND and give the grep.

Files read in full: `PrismRush/UI/MissionsView.swift` (576 L), `PrismRush/UI/Theme.swift` (309 L),
`PrismRush/UI/MetaScreenScaffold.swift` (60 L), `PrismRush/UI/CoinBadge.swift` (56 L),
`PrismRush/UI/RewardBurstView.swift` (303 L), `PrismRush/Meta/MissionCatalog.swift` (177 L),
`PrismRush/Meta/ProfileStore.swift:340-600`. Cross-referenced
`docs/agent/audits/scratch/s016_design-system.md` (F1–F12, §4, §5) and `s016_coins-economy.md:73-77`.

---

## 0 · Executive findings, ranked

| # | Finding | Evidence |
|---|---|---|
| **C1** | **The screen cannot say "I finished today."** The summary is computed over `perRun + daily + weekly + achievements` — one flat pool. A player who clears all three dailies still reads `16 OPEN · UP TO 5,510 COINS`. `ALL CLEAR` requires every lifetime ladder's *final* tier too (100,000 m, 1,000 runs), so it is dead copy for hundreds of hours. **The single most common success moment on this screen has no representation.** | `MissionsView.swift:159-162`, `:70`, `ProfileStore.swift:527-538` |
| **C2** | **19 rows, one row type, 13 of them below the first fold.** 6 feats + 3 daily + 3 weekly + 7 ladders = 19 identical 72 pt cards on a 1,818 pt scroll into a 721 pt viewport. No collapse, no priority sort, no filter. A claimable card can sit at scroll offset 1,150. | `MissionsView.swift:41-48`, `:172-184`; heights derived in §1.4 |
| **C3** | **Progress is a 44 pt ring with a 4 pt stroke.** 92/150 and 118/150 are ~11° apart on that arc — unreadable. The card *also* prints the number, so the ring is 44 × 44 pt of the row's 342 pt width spent on a redundant, less legible copy of the text beside it. s016 §4.5 already prescribed the fix ("Ring progress → a segmented bar (countable)") and it was never done. | `MissionsView.swift:404-422`, `:380` |
| **C4** | **The reward — the entire reason to do a mission — is the dimmest element on the row.** `+120 ◉` at `.caption` (11 pt) in `white 0.55` on `white 0.05`. The mission *title*, which the player already knows, is 13 pt bold pure white. | `MissionsView.swift:459-471` vs `:373-377` |
| **C5** | **Daily/weekly progress is silently DELETED at rollover and the screen never says so.** `refreshDailyMissions` wipes `missionProgress` and `claimedMissions` for every daily id. The only warning is `· RESETS 7H 12M` at **9 pt `.micro`, `textTertiary` (white 50 %)** — the smallest, lowest-contrast text on the screen carries the most time-critical information, and never escalates. 148/150 gems at 23:58 UTC evaporates. | `ProfileStore.swift:385-396`, `:408-419` vs `MissionsView.swift:207-210`, `:235-238` |
| **C6** | **Four bespoke section tints on one screen — more hues than the rest of the app combined**, and all four collide with an existing owner. `#FFB13D` = world 2's grid hue; `#B26BFF` = the Epic rarity tint; `#00F5FF` = `Role.interactive` (THE tap accent, used here on a *non-tappable* label); `#00FF88` = the doubler power-up. This is s016's F5 repeating on a new screen. | `MissionsView.swift:25-28` vs `Theme.swift:25`, `CharacterSelectView.swift:488`, `Theme.swift:154`, s016 §1.5 |
| **C7** | **TODAY's header wears two golds one hue apart.** The timer ring is `Theme.Role.reward` `#FFD23D`; the word `TODAY` beside it is `#FFB13D`. Same 15 pt cluster. This is s016's F9 with a new instance. | `MissionsView.swift:197-200` vs `:206` |
| **C8** | **The screen does not use the app's card system.** `MissionCard` hand-rolls `.ultraThinMaterial` + `cornerRadius: 18` + `.white.opacity(0.12)` instead of `.neonCard()`; the receipt row uses `cornerRadius: 14` + `white 0.04`. **18 and 14 are not `Theme.Radius` values** (s 12 / m 16 / l 20) and `white 0.04` is not a `Role` surface. Four token bypasses in two modifier stacks. | `MissionsView.swift:391-396`, `:507` vs `Theme.swift:203-207`, `:251-261` |
| **C9** | **The metric is communicated by a generic SF Symbol buried inside the ring**, and the vocabulary collides: `sparkles` is *slickBonuses* here AND the claimable-summary symbol two rows above; `gift.fill` is *chestsOpened* here AND the Mystery Box on the shop card (s016 F7); `wind` = near-misses, `multiply` = multiplier, `arrow.down.to.line` = slides. None are learnable. `PowerUpGlyph` — the app's proof that bespoke glyphs work — is not used. | `MissionsView.swift:514-529`, `:313` vs `PowerUpGlyph.swift:1-5`, `ShopView.swift:541-543` |
| **C10** | **"CHALLENGES" is already the name of a different feature.** The section header calls per-run feats CHALLENGES; the seeded daily run is called `CHALLENGE` in `CharacterSelectView.swift:301` ("PLAY TODAY'S CHALLENGE") and `GameOverView.swift:284` ("CHALLENGE TIER n"), and DAILY RUSH on the hub. Three names, two features. | `MissionsView.swift:251` vs `CharacterSelectView.swift:301`, `GameOverView.swift:284`, `ClaimRibbon.swift:160` |
| **C11** | **Claimed feats and maxed ladders become permanent strikethrough tombstones.** Per-run and lifetime ids are never cleared, so the end-state board is 13 dim receipt rows the player must scroll past forever. Decree 4 — nothing on screen should be dead. | `MissionsView.swift:489-510`; only daily/weekly ids are wiped (`ProfileStore.swift:388`, `:412`) |
| **C12** | **Six gold-gradient objects can be on screen at once** (CLAIM ALL + one ring + one pill per claimable row × up to 5). s016 §4.1's countable restatement of decree 6 is "one E3 per screen, maximum." | `MissionsView.swift:149`, `:411`, `:453` |
| **C13** | **The payoff for a claim is a 13 pt `+N` that rises 34 pt over 0.8 s and vanishes.** `RewardBurstView` — scrim, rays, hinged chest, confetti, rolling count, ladder — was built in S-016 for the daily bonus and the free chest and is **not wired to missions at all**. The most-repeated reward in the game has the weakest celebration in the app. | `MissionsView.swift:548-576` vs `RewardBurstView.swift:5-11`, `:45` |
| **C14** | **The mission title duplicates its own section.** "Collect 150 gems **today**" sits under a header that says TODAY; "Collect 1,000 gems **this week**" under THIS WEEK. The redundant suffix eats ~35 % of a 213 pt title column that is already tight enough to wrap. | `MissionCatalog.swift:101-108`, `:115-121`; width derived in §1.4 |
| **C15** | 6 raw `.font(.system(size:` sites survive in this file (12 / 11 / 11 / `ringSize*0.3` / 15 / 13 pt), and `Theme.color(0x00FF88)` is re-declared inline at `:493` instead of using the file's own `ladderTint` constant at `:28`. | `MissionsView.swift:74`, `:249`, `:267`, `:415`, `:492`, `:564`, `:493` |

**Not found (checked, absent by design or by omission):**
- A **locked** mission state — `grep -n "lock\|Lock" PrismRush/UI/MissionsView.swift` → no matches. Nothing on this board is ever gated.
- An **expired / expiring** state — same grep for `expir` → no matches. See C5.
- Any **route out** of the board other than the scaffold's coin badge → Shop (`MissionsView.swift:33`). No link to Game Center achievements, no "how do I earn near-misses?", no deep link from a mission to the thing that satisfies it. Decree 4.
- Any use of `.neonCard()`, `Theme.Radius`, `Theme.Space.m/l/xl` inside `MissionCard` —
  `grep -n "neonCard\|Theme.Radius\|Theme.Space" PrismRush/UI/MissionsView.swift` returns only
  `Theme.Space.s` (`:72`, `:195`, `:220`, `:247`, `:265`, `:387`) and `Theme.Radius.m` (`:85`, `:86`).

---

## 1 · The current screen, precisely enough to redraw

### 1.1 Frame and chrome

Presented as a **full-screen ZStack overlay**, not a UIKit sheet — `GameView.swift:1483-1485`
renders `metaSheet(sheet)` with `.transition(.move(edge: .bottom))`. So: no grab handle, no
inset corners, full 402 × 874.

`MetaScreenScaffold` (`MetaScreenScaffold.swift:16-58`) supplies:

| Element | Spec |
|---|---|
| Background | `Theme.Role.bg` `#05010E` + `RadialGradient([Role.interactive @ 6 %, clear], center: .top, r 10→520)`, `.ignoresSafeArea()` (`:51-58`) |
| Back button | `chevron.left` 17 pt bold white, 40 × 40, `.ultraThinMaterial` circle, `Role.hairline` stroke (`:19-26`) |
| Title | `"Missions"` — **sentence case**, `.typeScale(.title)` = **22 pt heavy rounded**, tracking 0 (`:29-31`, `Theme.swift:168-178`) |
| Coin badge | `CoinGlyph(16)` + amount 15 pt bold monospaced, pad h12/v8, `.ultraThinMaterial` capsule, hairline (`:33-38`) |
| Header padding | h 16, top 12, bottom 8 (`:40-42`) |
| Content | `ScrollView` → `.padding(16)` + `.padding(.bottom, 40)` (`:44-48`) |

Content column width = **370 pt**. On iPhone 16 Pro (402 × 874, top safe 59, bottom safe 34) the
scroll viewport is **y 119 → y 840 = 721 pt**.

### 1.2 Body stack (`MissionsView.swift:35-56`)

`TimelineView(.periodic(by: 60))` → `VStack(spacing: 22)`:

1. `summaryStrip`
2. `claimAllRow` (renders nothing when < 2 claimable — `:119`)
3. TODAY section — `store.dailyMissions(now:)`, tint `#FFB13D`
4. THIS WEEK — `store.weeklyMissions(now:)`, tint `#B26BFF`
5. CHALLENGES — `MissionCatalog.perRun`, tint `#00F5FF`
6. ACHIEVEMENTS — `MissionCatalog.achievements`, tint `#00FF88`

Each section is `VStack(alignment: .leading, spacing: 10)` = header + N cards (`:174-183`).

Spring `.spring(duration: 0.45, bounce: 0.15)` on `claimedMissions` and `achievementTier`
(`:52-55`); `nil` under Reduce Motion.

### 1.3 Every element, with hexes and sizes

**SUMMARY STRIP** (`:69-91`) — 370 × ~34, `Radius.m` = 16.

| State | Text | Fill | Stroke | Foreground | Coin glyph |
|---|---|---|---|---|---|
| `.claimable` | `2 CLAIMABLE · 340 COINS WAITING` | `#FFD23D @ 8 %` | `#FFD23D @ 40 %` | `#FFD23D` | yes, 13 pt |
| `.open` | `19 OPEN · UP TO 5,510 COINS` | `Role.surface` white 6 % | `Role.hairline` white 12 % | `textSecondary` white 70 % | no |
| `.allClear` | `ALL CLEAR · NEW BOARD IN 7H 12M` | white 6 % | white 12 % | `textTertiary` white 50 % | no |

Leading SF Symbol 12 pt bold: `sparkles` / `target` / `checkmark.circle` (`:311-317`). Text
`.typeScale(.caption)` = 11 pt, overridden to `.heavy`, tracking 1.5, monospaced. Pad h14/v10.

**CLAIM ALL** (`:118-155`) — only when `claimables.count >= 2`. Full-width capsule, `padding(.vertical, 12)`
→ ~40 tall. `Theme.goldGradient` `#FFD23D → #FF9F1C` L→R. Label `CLAIM ALL +340` at `.typeScale(.body)`
= 13 pt, `.heavy`, monospaced, **black**, + `CoinGlyph(13)`. `shadow(#FFD23D @ 45 %, r 12)`.
Cascade: one `claimMission` per **80 ms** with a haptic each (`:130-137`).

**TODAY header** (`:193-215`) — 15 pt ring (`@ScaledMetric headerRingSize`), `lineWidth 2.5`,
track `#FFD23D @ 18 %`, arc `#FFD23D` trimmed to `secondsUntilUTCMidnight / 86_400`, rotated −90°.
Then `TODAY` 11 pt heavy tracking 1.5 in `#FFB13D`, then `· RESETS 7H 12M` at **9 pt `.micro`,
tracking 2, `textTertiary` white 50 %**.

**THIS WEEK header** (`:218-243`) — seven 6 pt dots, spacing 3. `day < today` → `#B26BFF @ 45 %`;
`day == today` → `#B26BFF` @ 100 % + white-75 % 1 pt ring; future → `white 14 %`. Then `THIS WEEK`
11 pt heavy in `#B26BFF`, then `· RESETS 3D` 9 pt tertiary.

**CHALLENGES header** (`:246-261`) — `bolt.fill` 11 pt bold `#00F5FF`, `CHALLENGES` 11 pt heavy
`#00F5FF`, `· ONE-RUN FEATS` 9 pt tertiary.

**ACHIEVEMENTS header** (`:264-279`) — `trophy.fill` 11 pt bold `#00FF88`, `ACHIEVEMENTS` 11 pt heavy
`#00FF88`, `· EVERY TIER PAYS` 9 pt tertiary.

**MISSION CARD — active** (`:369-400`). `HStack(spacing: 12)`, `.padding(14)`,
`.ultraThinMaterial` in `RoundedRectangle(cornerRadius: 18)`, stroke `white 12 % @ 1 pt` (or
`#FFD23D @ 55 % @ 1.5 pt` when claimable).

- **Ring** (`:404-422`): 44 pt (`@ScaledMetric`), `lineWidth 4`. Track `white 10 %`. Arc = `tint`,
  or `Theme.goldGradient` when claimable. Fills `0 → fraction` over `.easeOut(0.7)` on appear.
  Centre: SF Symbol at `44 × 0.3 = 13.2 pt`, `white 70 %` (or `#FFD23D` when claimable).
- **Title** (`:373-377`): `.typeScale(.body)` 13 pt overridden `.bold`, pure white, wraps.
- **Progress line** (`:380-384`): `92/150` at 11 pt heavy monospaced, `white 60 %`. `compactCount`
  (`:539-543`) prints `10k` ≥ 10,000 and `1.0k` ≥ 1,000 — so a weekly reads `0.6k/1.0k`.
- **Tier ladder**, tiered only (`:425-439`): N capsules 4 pt tall, spacing 3 — paid = 16… no: paid
  tiers are `#FFD23D @ 80 %` at **8 pt wide**, the CURRENT tier is `tint` at **16 pt wide**, future
  is `white 14 %` at 8 pt. Then `T2` at 9 pt micro in `tint`.
- **Reward pill** (`:441-472`): claimable → `CLAIM +120` 11 pt heavy black + `CoinGlyph(12)`, gold
  gradient capsule, pad h12/v8, shadow `#FFD23D @ 45 %` r10. Not claimable → `+120` 11 pt heavy
  **`white 55 %`** + `CoinGlyph(11)`, `white 5 %` capsule, hairline stroke, pad h10/v6.

**MISSION CARD — receipt** (`:489-510`). `checkmark.circle.fill` 15 pt bold `#00FF88 @ 80 %`
(hardcoded, `:493`), title 13 pt semibold `white 45 %` **strikethrough** `white 30 %`, optional
`ALL TIERS` 9 pt `white 35 %`. Pad h14/v9, `white 4 %` in `cornerRadius: 14`.

**COIN FLY-UP** (`:548-576`). `+120` at 13 pt heavy monospaced + `CoinGlyph(12)` in `#FFD23D`,
top-trailing, trailing pad 18, rises `y −4 → −38` over `.easeOut(0.8)` fading to 0. Suppressed
under Reduce Motion (`:480`).

### 1.4 Derived geometry (the numbers behind C2, C3, C14)

Card content height = `max(ring 44, title 16 + 5 + line 14 = 35)` = 44 → **card = 44 + 28 = 72 pt**.

Title column = `370 − 28 (card pad) − 44 (ring) − 12 (spacing) − ~65 (reward pill) − 8 (min spacer)`
= **213 pt**. At 13 pt bold `.rounded` ≈ 6.5 pt/char → **~32 characters before wrap**. Six catalog
titles are 28–31 characters (`MissionCatalog.swift:94`, `:105`, `:106`, `:115`, `:118`, `:119`), so
the column is one word from wrapping and every card would grow to 89 pt. C14 costs ~7 of those 32.

Full scroll, "2 claimable" state:

| Block | y | Height |
|---|---|---|
| summary | 135 | 34 |
| CLAIM ALL | 191 | 40 |
| TODAY hdr + 3 cards | 253 | 16 + 10 + 3×72 + 2×10 = 262 |
| THIS WEEK hdr + 3 | 537 | 262 |
| CHALLENGES hdr + 6 | 821 | 16 + 10 + 6×72 + 5×10 = 508 |
| ACHIEVEMENTS hdr + 7 | 1351 | 16 + 10 + 7×72 + 6×10 = 590 |
| **total** | | **1,818 pt** (incl. 16 top + 40 bottom pad) |

Viewport = 721 pt → **2.5 screens**. The fold lands mid-THIS-WEEK. **13 of 19 rows (68 %) are never
seen without scrolling**, and ACHIEVEMENTS — 7 rows and 11,350 lifetime coins
(`s016_coins-economy.md:77`) — begins at scroll offset **1,232**.

### 1.5 States, exhaustively

| State | Where it lives | What renders |
|---|---|---|
| **In progress** | `missionState.claimable == false, claimed == false` (`ProfileStore.swift:546`) | tinted partial ring, `92/150`, dim `+120` pill |
| **Claimable** | `!claimed && progress >= target` (`:547`) | gold-gradient ring, gold 1.5 pt card stroke, gold `CLAIM +120` pill, row counted into summary + CLAIM ALL |
| **Claimed (per-run / daily / weekly)** | `claimedMissions.contains(id)` (`:545`) | receipt row: strikethrough title, green check |
| **Tier claimed (ladder)** | `achievementTier[id] += 1` (`:584`) | card stays; ladder pip goes gold; ring resets to next tier's target; new reward shown |
| **Ladder exhausted** | `tier >= targets.count` (`:551`) | receipt row + `ALL TIERS` |
| **First launch / empty** | `.open(19, ~5510)` (`:535-537`) | summary in **white 70 % on white 6 %**, plus 19 cards each with a **0 % ring** (`white 10 %` track only — effectively an empty circle on frosted grey) and a dim `+N`. No onboarding copy, no illustration, no "play a run to start". PR-0304 fixed the *sentence*; the *board* is still 19 empty circles. |
| **All complete** | `.allClear` (`:536`) | `✓ ALL CLEAR · NEW BOARD IN 7H 12M` in white 50 %. **Requires all 7 ladders maxed** (10,000 gems, 100,000 m, 1,000 runs, world 12…) **and** all 6 feats claimed **and** both boards claimed. Effectively unreachable in the first several hundred hours — see C1. |
| **Locked** | — | **does not exist** |
| **Expired** | — | **does not exist**; progress is deleted with no notice (C5) |

---

## 2 · Why it is hard to understand — the mechanical yes/no

| Question | Answer | Evidence | Why it still fails |
|---|---|---|---|
| Is the **target value** shown? | **YES** | `MissionsView.swift:380` | But `compactCount` (`:539-543`) rounds it: `3.0k/3.0k` for 3,000 m, `0.6k/1.0k` for a weekly. The player cannot tell 950 from 1,000. |
| Is progress a **number**? | **YES** | `:380` | 11 pt at `white 60 %` — smaller and dimmer than the title it sits under. |
| Is progress a **bar**? | **NO — it is a 44 pt RING** | `:404-422` | 4 pt stroke on a 44 pt circle. See C3. |
| **Both?** | **YES, redundantly** | `:371` + `:380` | Two encodings of one value; the worse one is 3× the visual area. |
| Can you tell a **daily from a weekly at a glance**? | **NO, not from the card** | headers `:193`, `:218`; cards `:369-400` | Cards are identical except a 4 pt ring stroke hue (`#FFB13D` vs `#B26BFF`). The only real signal is the section header — 11 pt, no divider, no background — which scrolls away after 3 rows. The redundant title suffix ("today" / "this week", `MissionCatalog.swift:101`, `:115`) is doing the work the design should. |
| Is the **reward visible before completion**? | **YES** | `:459-471` | At the lowest contrast on the card. See C4. |
| Is the **reset time shown**? | **YES, for daily and weekly** | `:207-210`, `:235-238` | 9 pt `.micro`, tracking 2, `textTertiary` white 50 %, appended after a `·`. Weekly granularity is whole **days** (`weeklyCountdown`, `:297-300`) until the last day. It never escalates and never says what expiry *costs*. See C5. |
| Is the **consequence of reset** stated? | **NO** | grep `expir\|lose\|reset.*progress` in `MissionsView.swift` → only the two `· RESETS` strings | Progress is silently wiped (`ProfileStore.swift:391-394`). |
| Can you tell **what metric** a mission tracks without reading the title? | **NO** | `:514-529` | A 13.2 pt generic SF Symbol inside the ring, from a colliding vocabulary. See C9. |
| Can you tell **how close the board is to done**? | **NO** | `:70`, `:159-162` | The summary counts a pool that mixes today's chores with lifetime ladders. See C1. |
| Is there a **path from a mission to the thing that satisfies it**? | **NO** | `:33` is the only route (coins → Shop) | "Thread 8 CLOSE calls" does not explain what a CLOSE call is, and `HowToPlayView` covers it (`HowToPlayView.swift:157`) but is unreachable from here. Decree 4. |

---

## 3 · Craft defects, ranked, against the repo's own law

| Rank | Defect | Decree / rule broken | file:line |
|---|---|---|---|
| 1 | Summary pools daily chores with lifetime ladders → the daily success state is unrepresentable | **decree 3** (a finished board reads as an unfinished one; PR-0304's cousin) | `:70`, `:159-162`, `ProfileStore.swift:527-538` |
| 2 | 19 undifferentiated rows, 68 % below the fold, no priority sort | **decree 6** (clarity beats spectacle) | `:41-48`, §1.4 |
| 3 | 44 pt ring as the primary progress encoding | **decree 6** ("readable in a single frame") | `:404-422` |
| 4 | Reward is the dimmest thing on the row | **decree 4** (this is what the screen is *for*) | `:459-471` |
| 5 | Silent expiry of accumulated progress, warned only at 9 pt | **decree 5** (this is the closest thing to a dark pattern on the screen — the player loses value with no notice) | `ProfileStore.swift:385-396` vs `:207` |
| 6 | Four bespoke section tints, all colliding with existing owners; cyan used on a non-tappable label | **decree 6** (role-based colour) · s016 F5 | `:25-28` |
| 7 | Two golds in one 15 pt cluster (`#FFD23D` ring + `#FFB13D` label) | **decree 6** · s016 F9 | `:197-200` vs `:206` |
| 8 | Six gold-gradient objects possible on one screen | **decree 6** ("one gradient family" → s016 §4.1 "one E3 per screen") | `:149`, `:411`, `:453` |
| 9 | Card bypasses `NeonCard`, `Theme.Radius`, `Role.surface` (r18 / r14 / white 4 %) | iron **token layer**; s016 F11 | `:391-396`, `:507` vs `Theme.swift:203-207`, `:251-261` |
| 10 | Generic, colliding SF Symbols where a bespoke glyph system exists | **decree 2**-adjacent (owner rule P3, s016 F8) | `:514-529` vs `PowerUpGlyph.swift:1-5` |
| 11 | Permanent strikethrough tombstones (13 at end state) | **decree 4** | `:489-510` |
| 12 | Claim payoff is a 0.8 s `+N` while a full celebration component sits unused | **decree 6** + M11's standing "things need to be rewarding" | `:548-576` vs `RewardBurstView.swift:45` |
| 13 | "CHALLENGES" names a feature that already has a name | consistency | `:251` vs `GameOverView.swift:284` |
| 14 | Empty board = 19 empty rings with no onboarding | **decree 3** | derived, §1.5 |
| 15 | 6 raw `.font(.system(size:` + a re-declared `#00FF88` literal | s016 F11 hard rule (§4.3) | `:74`, `:249`, `:267`, `:415`, `:492`, `:564`, `:493` |

**What is already right and must survive the rebuild:**
- `MissionBoardSummary` as a **three-case enum, not a Bool** (`ProfileStore.swift:518-539`) — the
  PR-0304 fix, pinned by `MissionsTests.testUntouchedBoardIsOpenNotAllClear:278-283`. Keep the
  type; C1 is fixed by changing what you feed it, not by weakening it.
- `.claimMission` lands on the store **before** any FX (`:476-484`), and the CLAIM ALL cascade
  resolves every claim against the **same** `now` that rendered the board (`:126-136`, AUDIT D5-2).
  Both are load-bearing correctness. Do not touch.
- The `CoinFlyUp` overlay lives on the `Group`, not on `activeCard`, so it survives the
  active→receipt swap (`:354-363`). A rebuild that moves it will silently kill the last claim's
  feedback.
- G3 compliance: `ProfileStore.shared` is read inside `body` (`:31`), never `@State`d.
- Decree-6 gradient discipline: this screen uses **only** `goldGradient`, no `actionGradient`
  (s016 F4 lists it as holding). Keep it single-family.
- Accessibility is genuinely good: every row has `accessibilityIdentifier("missionCard_\(id)")`
  (`:364`), spoken labels distinguish claimable from in-progress (`:531-537`), and Reduce Motion
  kills the rings, the springs and the fly-up (`:52`, `:419`, `:480`). **`missionsSummary`,
  `claimAllButton`, `claim_<id>` and `railMissions` are asserted by
  `UITests/InteractionUITests.swift:261-267`** — a rebuild must carry those identifiers forward.

---

## 4 · BEFORE / AFTER — the mockup spec

Canvas **402 × 874 pt** (iPhone 16 Pro point space, per `memory/simulator-mcp-cannot-drive-toggles`).
Top safe inset 59, bottom 34. Format follows `s016_design-system.md` §5.
AFTER adopts the s016 §4.2 revised palette: `surface-0 #0B0818` · `surface-1 #14101F` ·
`surface-2 #1D1830` · `hairline #2E2842` · `text-1 #F2EEFF` · `text-2 #A79FC4` · `text-3 #6D6690` ·
`action #00E5FF` · `money #FFB020` · `gem #FFD84D` · `danger #FF3355`.

### 4.1 BEFORE (state: two rewards ready)

```
y   0 ┌──────────── safe area 59 ─────────────────────┐
y  71 │  ‹40        Missions  22pt heavy    [◉ 1,240] │  scaffold; title SENTENCE CASE
y 111 │  ultraThin circle                   ultraThin  │  bg #05010E + cyan@6% radial from top
y 119 ├──────────── ScrollView top ───────────────────┤  viewport 721pt
y 135 │ ┌ SUMMARY  370 × 34, r16 ──────────────────┐  │  fill #FFD23D@8%
      │ │ ✦  2 CLAIMABLE · 340 COINS WAITING    ◉ │  │  stroke #FFD23D@40%
      │ └──────────────────────────────────────────┘  │  11pt heavy /1.5, #FFD23D
y 191 │ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │  370 × 40 capsule
      │ ┃      CLAIM ALL +340   ◉                  ┃ │  goldGradient #FFD23D→#FF9F1C
      │ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │  13pt heavy BLACK, shadow r12
y 253 │  ◐15  TODAY · RESETS 7H 12M                   │  ring #FFD23D  ← gold #1
      │       11pt   9pt white-50%                     │  label #FFB13D ← gold #2  (C7)
y 279 │ ┌──────────────────────────────────────────┐  │  370 × 72, r18(!), ultraThinMaterial
      │ │ ◯44  Collect 150 gems today     [+120 ◉]│  │  ring track white-10%, arc #FFB13D
      │ │ ◈13   92/150   11pt white-60%    white-55%│  │  reward = DIMMEST thing here (C4)
      │ └──────────────────────────────────────────┘  │  stroke white-12%
y 361 │ ┌──────────────────────────────────────────┐  │  CLAIMABLE variant:
      │ │ ◯44  Travel 3,000 m today  ┏CLAIM +120◉┓│  │  ring = goldGradient
      │ │ ➤     3.0k/3.0k   ← rounded (C-2 in §2)  │  │  card stroke #FFD23D@55% 1.5pt
      │ └──────────────────────────────────────────┘  │  pill = goldGradient, black text
y 443 │ ┌ ◯44  Open 2 free chests today   [+80 ◉] ┐  │  glyph = gift.fill = ALSO the
      │ └──────────────────────────────────────────┘  │  Mystery Box glyph (C9)
y 537 │  ●●●●○○○  THIS WEEK · RESETS 3D               │  dots 6pt #B26BFF (= Epic tint)
y 563 │ ┌ ◯44  Collect 1,000 gems this week [+700◉]┐  │  "0.6k/1.0k"
y 645 │ ┌ ◯44  Travel 20,000 m this week    [+800◉]┐  │
y 727 │ ┌ ◯44  Finish 30 runs this week     [+600◉]┐  │
y 809 │  ⚡ CHALLENGES · ONE-RUN FEATS  ← #00F5FF     │  cyan = tap accent, on a LABEL (C6)
y 840 └──────────── FOLD ─────────────────────────────┘
      ⋮   6 feat cards  (508pt)
      ⋮   🏆 ACHIEVEMENTS · EVERY TIER PAYS  ← #00FF88
      ⋮   7 ladder cards, each with a T-pip row  (590pt)
y1818     end of scroll — 2.5 screens, 13 of 19 rows unseen
```

**Diagnosis to show in the mockup:** four hues, two golds, one ring nobody can read, the reward
whispered, the reset time whispered, and a 1,818 pt list where the only structure is four 11 pt
labels with no dividers.

### 4.2 AFTER

**Direction: THE BOARD IS A SET, NOT A LIST.** The daily three become one objective with one
terminal prize; everything else collapses into a segmented archive. This is a *revision* — it keeps
`MissionCatalog`'s 3-daily/3-weekly draw (`MissionCatalog.swift:152-176`), `MissionBoardSummary`,
`claimMission`, the CLAIM ALL cascade, `CoinFlyUp` and every accessibility identifier.

```
y   0 ╔══════════ safe area 59 ═══════════════════════╗
y  71 ║ ‹44    MISSIONS 26pt      ◆ 214   ⬤ 1,240    ║  status shelf (s016 §5.1): opaque
y 115 ║ #14101F, bottom hairline #2E2842, top bezel   ║  #14101F, BOTH currencies pinned
      ╠═══════════════════════════════════════════════╣  title UPPERCASE 26pt heavy
y 127 ║ ┌ TODAY'S SET — 370 × 306, #0B0818, r26 ────┐ ║  the hero. one card, not a section.
      ║ │▓▓▓▓▓▓▓▓▓▓ 4pt SET BAR ▓▓▓▓░░░░░░░░░░░░░░│ ║  fills L→R with SET completion
      ║ │  #00E5FF filled / #2E2842 empty          │ ║  (2 of 3 → 66 % lit)
      ║ │                                          │ ║
      ║ │  TODAY'S SET        2 / 3      ⏱ 7H 12M  │ ║  kicker 10pt/1.6 text-3;
      ║ │  10pt/1.6 text-3    19pt bold  chip      │ ║  "2 / 3" 19pt #F2EEFF;
      ║ │                                          │ ║  countdown chip 74×24 #14101F r8,
      ║ │ ┌ ROW — 370-32 = 338 × 66 ──────────────┐│ ║  13pt text-2 tabular.
      ║ │ │ ◈36  COLLECT 150 GEMS                 ││ ║  ► <2H AND progress>0 → chip fill
      ║ │ │ gem  ████████████░░░░░░░  92 / 150    ││ ║    #FF3355@18%, text #FF3355,
      ║ │ │      bar 210 × 8, r4                  ││ ║    label "ENDS IN 1H 40M" (C5)
      ║ │ │                            ⬤ 120      ││ ║
      ║ │ └───────────────────────────────────────┘│ ║  ROW anatomy, fixed:
      ║ │ ┌ ROW — CLAIMABLE ──────────────────────┐│ ║   [36pt bespoke glyph]
      ║ │ │ ➤36  TRAVEL 3,000 M                   ││ ║   [title 15pt semibold #F2EEFF,
      ║ │ │ dist ██████████████████ 3,000 / 3,000 ││ ║    NO "today"/"this week" suffix]
      ║ │ │                   ┏ CLAIM  ⬤ 120  ┓  ││ ║   [bar 210×8 + "n / N" 13pt
      ║ │ └───────────────────────────────────────┘│ ║    tabular text-2, EXACT, no k]
      ║ │ ┌ ROW ──────────────────────────────────┐│ ║   [reward 17pt bold #FFB020 +
      ║ │ │ ▣36  OPEN 2 FREE CHESTS      ⬤ 80    ││ ║    22pt coin object, right-aligned]
      ║ │ │      ██████████░░░░░░░░░░  1 / 2      ││ ║  row fill: in-progress #14101F,
      ║ │ └───────────────────────────────────────┘│ ║  claimable #1D1830 + 1pt #FFB020
      ║ │ ──────── 1px #2E2842 ────────────────────│ ║  edge + shadow #FFB020@25% r10
      ║ │  FINISH ALL 3   →    ▣  SILVER BOX       │ ║  ── THE SET PRIZE ──
      ║ │  10pt/1.6 text-3     3D crate 34pt       │ ║  the structural answer to
      ║ └──────────────────────────────────────────┘ ║  "does nothing / not rewarding"
y 433 ╠═══════════════════════════════════════════════╣  (economy pass sizes the box tier)
y 445 ║ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ ║  370 × 52, r26
      ║ ┃   CLAIM ALL   ·   ⬤ 340                  ┃ ║  money fill #FFB020, BLACK 15pt
y 497 ║ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ ║  ← the ONE E3 on this screen.
      ║   2pt inner bezel white-30%, shadow r18      ║    the ring + the pill lose theirs.
y 509 ╠═══════════════════════════════════════════════╣
y 521 ║ [ WEEK  1/3 ] [ FEATS  2/6 ] [ CAREER 4/19 ]  ║  370 × 44 segmented, #14101F r12
y 565 ║  active seg #1D1830 + 2pt #00E5FF underline   ║  labels 13pt: active #F2EEFF,
      ╠═══════════════════════════════════════════════╣  rest #A79FC4. Counts ARE the IA.
y 577 ║  ● ● ● ● ○ ○ ○    DAY 4 OF 7 · RESETS IN 3D   ║  28pt context line, dots 6pt
      ║  dots #00E5FF / #2E2842      13pt text-2      ║  #00E5FF (one accent, not purple)
y 613 ║ ┌ ◈36  COLLECT 1,000 GEMS         ⬤ 700    ┐ ║  IDENTICAL row component to the
      ║ │      ████████░░░░░░░░░░░  612 / 1,000     │ ║  hero's. One row type in the app.
y 691 ║ ┌ ➤36  TRAVEL 20,000 M            ⬤ 800    ┐ ║  74 tall + 8 gap
y 773 ║ ┌ ⚑36  FINISH 30 RUNS             ⬤ 600    ┐ ║
y 840 ╚═══════════════════════════════════════════════╝  only 3 rows below the segment —
                                                          nothing important below the fold
```

**Changes, in order of impact:**

1. **The daily three become a SET with a terminal prize.** The board stops being a to-do list and
   becomes one objective. This is the only change that answers *"does nothing"* and *"not rewarding"*
   at the same time, and it costs no new catalog content — `dailySlots` already draws exactly 3
   (`MissionCatalog.swift:152-160`). The prize tier is the economy pass's call, not mine.
2. **Rings → segmented bars with exact numbers.** 210 × 8 pt with 15 segments beats a 44 pt ring at
   every progress value, and it frees 44 pt of row width for the glyph and the reward. Delete
   `compactCount` (`:539-543`) — a mission target is never wider than 6 characters.
3. **Reward becomes the row's loudest element**: 17 pt bold `#FFB020` + a 22 pt drawn coin object,
   right-aligned so all rewards line up into a readable column. Today it is 11 pt at 55 % white.
4. **One accent, one structural rail.** The four tints (`:25-28`) die. Section identity moves from
   colour to *structure*: TODAY is a card, everything else is a segment. `#00E5FF` is the only
   accent; `#FFB020` is money; `#FF3355` is expiry. That is three hues where there were seven.
5. **Expiry gets a real state.** The countdown is a 13 pt chip on the hero, not a 9 pt suffix, and
   when `< 2 h` with `progress > 0 && !claimable` it goes `#FF3355` and says `ENDS IN 1H 40M`. This
   is the first honest representation of `ProfileStore.swift:391-394`.
6. **`MissionBoardSummary` gets fed the right pool.** Same enum, same three cases, same test
   (`MissionsTests:278-283`) — but computed **per segment**. The hero's `2 / 3` IS the daily summary;
   `.allClear` on the daily pool becomes reachable daily and finally means something. The old
   19-mission strip is deleted, not weakened.
7. **CLAIM ALL is the only E3.** The ring gradient (`:411`) and the per-row pill gradient (`:453`)
   become flat `#FFB020` fills. Six gradient objects → one.
8. **Claim fires `RewardBurstView`, not a 0.8 s `+N`.** Single claim → `PackRewardBurst`-weight
   ring+spark reveal. **Set completion → the full `RewardBurstView`** with a new
   `RewardBurst.Kind.missionSet(day:)` beside `.daily(streak:)` and `.chest`
   (`RewardBurstView.swift:6-11`) — scrim, rays, hinged lid, confetti, rolling count. The ladder
   renderer (`:219-241`) draws the 7-day set streak with zero new code.
9. **Bespoke 36 pt metric glyphs** in the `PowerUpGlyph` Canvas idiom: gem octahedron, distance
   chevron-pair, near-miss wind-slash past a bar, slide arrow under a bar, warden helm, chest,
   flag, world ring, flame, ×. Twelve glyphs, one file. Kills C9 and the `gift.fill` collision.
10. **Tombstones stop accumulating.** Claimed feats and maxed ladders leave the live board and move
    behind the CAREER segment as a compact 3-up trophy grid — present, countable (`4/19`),
    not 13 strikethrough lines you scroll past forever.
11. **Empty state gets copy.** First launch, the hero reads `TODAY'S SET · 0 / 3` with the three rows
    at zero and a `text-2` line: `PLAY A RUN TO START THE SET`. Not 19 empty circles.
12. **Title case + naming.** `Missions` → `MISSIONS` (matches every other scaffold title after
    s016 §5). `CHALLENGES` → `FEATS` so the word stops colliding with Daily Rush (C10).

---

## 5 · Shipped references, and exactly what to take

**1 · Subway Surfers (SYBO) — the owner's named reference.**
Its mission system runs **sets of three**: complete all 3 and your score multiplier increments —
the set, not the individual mission, is the unit of progress and the unit of reward. Daily
Challenges layer a separate 24-hour goal on top, paying coins plus an event currency, with a
day-ladder that reaches a **Super Mystery Box at day 5**.
**Take:** (a) the *set of three with a terminal prize* — this is §4.2 change 1, and it is the exact
structure our `dailySlots` already draws; (b) the *day-ladder above the set*, so the reason to come
back tomorrow is visible today; (c) the persistent top shelf with both currencies (already in
s016 §5.1). **Do not take** its art or the word "Mystery Box" styling — trademark.

**2 · Alto's Adventure / Odyssey (Snowman) — the runner-native model, and the readability benchmark.**
Every level is **exactly three goals**, hand-authored, shown as one card; completing all three levels
you up and unlocks characters and power-ups. 180 goals across 60 levels. Progression is the goal
card, not a scrolling ledger — you are never shown 19 objectives at once.
**Take:** (a) *the board is one card, not a list* — the strongest argument for collapsing our four
sections into a hero + segments; (b) goals that *teach mechanics* ("backflip over a chasm") rather
than count them — our `Thread 8 CLOSE calls` is the right instinct with no explanation attached;
(c) its UI restraint, which s016 §6 already cites as the argument for a chip budget.

**3 · Duolingo — the best-measured daily-quest UI in mobile.**
Three daily quests, a progress bar per quest, a **chest that opens when all three are done**, and
tiered chests (bronze / silver / gold) whose contents differ. Publicly: introducing Daily Quests
moved DAU +25 %, and the treasure-chest reward moved lesson completion +15 %.
**Take:** (a) **complete-all-three → one extra chest** — the precise mechanic in §4.2 change 1, with
a published effect size; (b) *bar, never ring* — Duolingo's quest rows are horizontal bars with the
literal `n / N` beside them, which is C3's fix; (c) *the chest is the icon in the tab bar*, i.e. the
reward is the navigation affordance — our nav rail uses a `target` SF Symbol
(`MenuView.swift:343`); the box should be the badge.

**4 · Clash Royale (Supercell) — the claim moment.**
Quest cards slide off the board when claimed and the reward animates *into its counter*. s016 §6.3
already broke down its four-beat opening (anticipation → break → reveal → collect) and noted our
`MysteryBoxView` has beats 1–3 and no beat 4.
**Take:** *beat 4 — the reward terminates at the balance*. Our `CoinFlyUp` (`:548-576`) rises 34 pt
and dissolves in mid-air; it should fly to the coin badge in the status shelf and bump it. That is a
~20-line change to an existing component and it is most of what "rewarding" means.

**5 · Marvel Snap (Second Dinner) — the archive.**
Missions are tabbed (Daily / Season / Featured) and the completed ones do not stay in the live list.
**Take:** the **segmented archive with live counts in the segment label** (`WEEK 1/3`, `CAREER 4/19`)
— it is what lets 19 objectives live on one screen without a 1,818 pt scroll.

Sources: [Subway Surfers Missions (Fandom)](https://subwaysurf.fandom.com/wiki/Missions) ·
[Subway Surfers Daily Challenge (AppGamer)](https://www.appgamer.com/subway-surfers/daily-challenge) ·
[Game UI Database — Subway Surfers](https://www.gameuidatabase.com/gameData.php?id=1311) ·
[Alto's Adventure Goals (Fandom)](https://altosadventure.fandom.com/wiki/Goals) ·
[Alto's Adventure (Wikipedia)](https://en.wikipedia.org/wiki/Alto's_Adventure) ·
[Duolingo Quests guide](https://duoplanet.com/duolingo-challenges/) ·
[Duolingo Chests](https://duoplanet.com/duolingo-chests/) ·
[Duolingo gamification effect sizes (Orizon)](https://www.orizon.co/blog/duolingos-gamification-secrets) ·
[Mobile game UI best practices (Justinmind)](https://www.justinmind.com/ui-design/game)

---

## 6 · Reuse map — this is a revision, not a second design language

**Reuse as-is (do not rewrite):**

| Component | Where | Role in the rebuild |
|---|---|---|
| `MetaScreenScaffold` | `MetaScreenScaffold.swift:7-59` | Keep; swap its header for the s016 §5.1 opaque status shelf **once, app-wide** — not a missions fork. |
| `RewardBurstView` + `RewardBurst` | `RewardBurstView.swift:5-11`, `:45` | **The single biggest win available.** Add `Kind.missionSet(day:)`; `title`/`subtitle` (`:19-36`) and `ladder(streak:)` (`:219-241`) need only new cases. Set completion gets the chest, rays, confetti and rolling count for free. |
| `PackRewardBurst` | `PackRewardBurst.swift:9-40` | The lighter ring + 12-spark + spring-in reveal — correct weight for a **single** mission claim. Already tint-parameterised (`:18`) and Reduce-Motion-safe. |
| `CoinFlyUp` | `MissionsView.swift:548-576` | Keep the component, change its destination (Clash Royale beat 4). Note the overlay-placement comment at `:354-357` — it is load-bearing. |
| `CoinBadge` / `CoinGlyph` | `CoinBadge.swift:7`, `:43` | The reward numerals. `CoinGlyph` is s016 F2 (a featureless disc) and s016 §5.5 already specs the struck-coin redraw — take that redraw, don't invent a third coin. |
| `ClaimRibbon` two-state law | `ClaimRibbon.swift:21-60` | The hub already solved "claimable vs idle must differ in **size** as well as colour". The summary strip should adopt that law verbatim instead of the current three same-size variants (`:82-87`). |
| `StateNotice.ShortfallRow` | `StateNotice.swift:31+` | The four-slot NAME / QUANTIFY / ROUTE / ALTERNATIVE sentence — the shape for "you're 58 gems short, PLAY ›". |
| `PowerUpGlyph` | `PowerUpGlyph.swift:1-5` | **The template** for the 12 bespoke metric glyphs (§4.2 change 9). Same Canvas idiom, same hex-per-kind table. |
| `NeonCard` / `.neonCard()` | `Theme.swift:251-261`, `:273-275` | Adopting it *is* the fix for C8 — the current card is a hand-rolled near-miss of it. |
| `.buttonStyle(.neon)` | `Theme.swift:280-292` | Already used at `:152`, `:456`. Keep. |
| `ShakeEffect` | `Theme.swift:297-309` | Available for a denied claim; currently unused on this screen. |
| `MissionBoardSummary` | `ProfileStore.swift:518-539` | **Pure, Linux-tested, correct.** Reuse the type; change only the pool fed to `.of(...)` at `MissionsView.swift:70`. |

**Do NOT build new:** a second card treatment, a second progress primitive, a second celebration
overlay, a second coin glyph, a second countdown formatter. All five exist.

**Build new, minimally:** (a) `MissionRow` — one row component used by both the hero and the archive
(replaces `MissionCard`'s two variants); (b) `SegmentedTargetBar` — 210 × 8, N segments, exact
`n / N`; (c) `MetricGlyph` — 12 Canvas glyphs in the `PowerUpGlyph` idiom; (d) `SetPrizeSlot` — the
hero's terminal-prize footer, which is a `MysteryBoxView` crate at 34 pt.

---

## 7 · Constraints the builder must respect

- **Carry the accessibility identifiers forward**: `missionsSummary` (`:89`), `claimAllButton`
  (`:153`), `claim_<id>` (`:457`), `missionCard_<id>` (`:364`), `railMissions`
  (`MenuView.swift:346`). `UITests/InteractionUITests.swift:261-267` asserts them. A rebuild that
  renames them turns the suite red without a regression — and **never make the gate pass by
  weakening it**.
- **No Core/ or spawn-path involvement.** Missions live entirely in `Meta/` + `UI/`;
  `MissionCatalog`'s SplitMix64 use is meta-only and explicitly carries **zero `layoutVersion`
  implications** (`MissionCatalog.swift:162-166`). Nothing here touches iron rule 3.
- **`Profile` fields stay `decodeIfPresent ?? default`** (iron rule 7) if the set-prize mechanic
  needs a new field (e.g. `dailySetPrizeClaimedDate`).
- **G3**: keep `ProfileStore.shared` read inside `body` (`:31`); never `@State` it.
- The set-prize **tier and payout are the economy pass's ruling**, not this one — cost it against
  `s016_coins-economy.md:73-77` (3 dailies ≈ 345 coins/day, 3 weeklies ≈ 318/day equivalent),
  never invent it fresh.

---

*Read-only investigation. No builds, no simulator, nothing edited outside this file.*
