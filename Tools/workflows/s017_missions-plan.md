# S-017 · MISSIONS-PLAN — the skeleton for pass 017

**Read-only pass at HEAD `ba9655d`, working tree clean. Nothing was built, run, or edited except
this file.** Every claim carries a `file:line`. Where a figure is *derived* from constants rather
than measured, it says so. Where I looked and found nothing, it says NOT FOUND and gives the grep.

This is the **plan skeleton**, not the findings. Six sibling investigators fill in the craft, the
economy numbers, the legibility audit and the review bots. My job is the **shape, the order, the
verification and the fences**. Where a sibling's finding would change a step, the step says which
one and how.

Grounding read first: `docs/agent/01_RULES.md` (all), `docs/agent/02_STATE.md` (all),
`docs/agent/sessions/SESSION_015.md` (the log format this pass should match),
`CLAUDE.md`, `HANDOFF.md`, `s016_mandate.md`, `s016_coins-economy.md`, `s016_design-system.md`,
`s007_missions.md`, plus the shipped source: `PrismRush/UI/MissionsView.swift` (576 L),
`PrismRush/Meta/MissionCatalog.swift` (177 L), `PrismRush/Meta/ProfileStore.swift:370-599`,
`UITests/InteractionUITests.swift:257-292`.

---

## 0 · THE NUMBER THAT SHOULD DECIDE THE WHOLE PASS

Derived from `MissionCatalog.swift` literals and `s016_coins-economy.md §1.2`:

| board | payout | cite |
|---|---|---|
| 3 daily slots, mean 115 each | **345 / day** | `MissionCatalog.swift:100-109` |
| 3 weekly slots, mean 743 each, amortised | **318 / day** | `MissionCatalog.swift:114-122` |
| 6 per-run feats | **970 lifetime** | `MissionCatalog.swift:90-97` |
| 7 achievement ladders | **11,350 lifetime** | `MissionCatalog.swift:125-140` |

- Recurring missions = **663 coins/day**. The whole meta faucet is 1,943/day
  (`s016_coins-economy.md §1.2`), so the board is **34.1 %** of it.
- A 15 min/day player earns 3,118 coins/day total (`s016_coins-economy.md §1.5`), so the board is
  **21.3 %** of everything they earn.
- One-time missions = 970 + 11,350 = **12,320 coins = 83.7 %** of all one-time meta income, and
  **14.8 %** of the entire 83,500-coin permanent catalogue.

**The owner looked at a system paying 21 % of his income and said "does nothing."**

That single sentence is the pass's thesis. It rules out the obvious reading of the complaint
("the numbers are too small") and forces the real one: the board pays a currency whose sink is
finite and already free in 26.8 days (`s016_coins-economy.md §1.5`), and it pays it through a
0.8 s `+N` label. **The defect is downstream of the source. Raising mission rewards would make
every one of the four complaints worse, not better** — it accelerates the 26.8 days and it makes
the invisible claim moment carry a bigger number.

---

## 1 · THE SEQUENCING ARGUMENT

### 1.1 The prior, stated fairly

> "does nothing" and "not rewarding" are the same root problem and must be fixed before any pixel
> moves, because a beautiful screen for a system that pays nothing is still a screen nobody opens.

### 1.2 Where it is right

The second clause is correct and it is the thing most likely to be got wrong. Every instinct in a
"redo the missions screen" session pulls toward `MissionsView.swift` because that is the file whose
name matches the complaint, and `s016_design-system.md §4.5` even hands you three ready-made craft
changes for it. A pass that spends itself there ships a nicer-looking board that pays the same
coins into the same dead sink, and the owner's *first* word — "ugly" — gets answered while his
*last* word — "not rewarding at all" — does not. The prior is a correct guard against that.

### 1.3 Where it is wrong — three attacks

**Attack 1: "not rewarding" is two defects with a 20× cost difference, and collapsing them costs
you the cheap one.**

- **(4a) the reward is not FELT.** `MissionsView.swift:548-576` — `CoinFlyUp` is a 13 pt "+N" that
  rises 38 pt over 0.8 s and fades. Meanwhile S-016 shipped `RewardBurstView` two sessions ago
  (D-049) — scrim, ray fan, hinging lid, confetti under gravity, a count rolling from zero,
  three-layer audio — and wired it to exactly two callers: `GameView.swift:579` (daily) and
  `:585` (chest). **Missions were not one of them.** So the repo already contains a finished,
  owner-visible reference implementation of a reward moment, and the mission board is the one
  reward surface that does not use it. Cost to fix: one call site plus a `RewardBurst.kind` case.
  Economy risk: zero.
- **(4b) the reward is not WORTH WANTING.** Coins into a finite sink. Fix cost: an economy the
  owner must price.

Treating these as one problem means (4a) — a same-afternoon, zero-risk, immediately visible win —
gets queued behind an owner ruling. That is the prior's real cost.

**Attack 2: the economy half is not completable in one session, and the prior's ordering makes the
session end with it half-built.**

`s016_coins-economy.md §4.1` ranks the fixes that make coins worth wanting. #2 is "an infinite,
non-arbitrage sink" (medium cost, hard-constrained by D-026 — no rung may grant a coin multiplier).
#4 is a premium currency (**high** cost; touches `Profile`, the cloud merge at
`ProfileStore.swift:711-713`, every shop surface, StoreKit, and the honest-pricing story), and it
sits in `s016_coins-economy.md §5(b)` as **owner-gated**. Neither is a missions session. If pass 017
adopts "economy before pixels" literally, it opens the largest system in the game, does not finish
it, and delivers nothing on a screen the owner named four defects in. `01_RULES.md §2` — *"one clear
goal per session"* — and the mandate's *"It gets its own session"* both cut against that.

**Attack 3: "ugly" and "not easy to understand" are ONE fix, and on this screen the pixels ARE the
information architecture — so calling them "pixels" and deferring them mis-prices them.**

The board renders **19 rows** in one scroll: 6 per-run + 3 daily + 3 weekly + 7 achievements
(`MissionsView.swift:41-48`, counts from `MissionCatalog.swift:90,100,114,125`). Those 19 rows carry
**four different reset semantics** — never (`:254` "ONE-RUN FEATS"), UTC day (`:207` "RESETS 3H 32M"),
UTC week (`:235` "RESETS 3D"), lifetime (`:272` "EVERY TIER PAYS") — signalled by **four bespoke
tints declared in this one file** (`MissionsView.swift:26-29`: `#FFB13D`, `#B26BFF`, `#00F5FF`,
`#00FF88`), which is more hues than the rest of the app combined
(`s016_design-system.md §2`, screen 6). Progress is a `.trim` arc (`:404-422`) — a shape you cannot
count. **"Not easy to understand" is not a copy problem sitting on top of an ugly screen; it is the
same defect measured with a different instrument.** Fixing one fixes the other, and the fix is
visual work.

*(Reconciliation, flagged as inference not proof: `s007_missions.md` states a fresh board shows
"18 OPEN". At HEAD the count is 19. The most likely explanation is that `run.warden1`
(`MissionCatalog.swift:96`) was added by S-009 after that doc was written, taking per-run from 5 to
6. I did not verify this against `git show`; a sibling should.)*

### 1.4 The corrected principle

> **Decide the reward LEDGER before the first line of code. Then build in whatever order keeps the
> app green, and never rebuild a component twice.**

Not "economy before pixels." The binding constraint is not *when* the economy is built, it is that
**a mission card cannot be drawn until you know what a mission pays** — a card that renders a coin
amount and a card that renders a box object are different components. Build the ledger first because
it is the *input to the drawing*, not because economy outranks craft.

### 1.5 The move that makes the economy half fit in one session

There is a reward that is neither coins nor a new currency and that already ships:
**the Mystery Box.**

- `openMysteryBox` exists and is pure meta (`ProfileStore.swift:135-144`), rolls `Double.random`,
  never touches the Core seeded RNG.
- A free-on-a-timer grant is ~20 lines mirroring `chestReady` / `openFreeChest`
  (`ProfileStore.swift:328-331`, `:339-348`) — a shape the codebase already proves.
- The box is surfaced in **exactly one place in the entire app** (`ShopView.swift:530`, under a
  kicker that describes something else — `s016_coins-economy.md §2.4`), and M7 is
  *"getting boxes should be more prominent."*

**A mission that pays a BOX instead of coins converts the mission board from the fourth-biggest coin
faucet into the game's primary box faucet.** That answers "does nothing" (the reward is now a thing
with variance and a ceremony, not a number added to a pile that is already too big), it answers M7
on a surface the owner was already going to open, and it costs a `Profile` field and a reward-kind
enum rather than a currency. It is the only same-session-sized change I can find that moves
consequence, and it is the load-bearing design claim of this plan. **If the owner rejects it
(§4 Q1), Steps 4 and 6b are cut and the pass becomes craft + moment only** — still a real answer to
three of four complaints, and the plan is built to degrade that way.

**Hard consequence if Step 4 ships:** `s016_coins-economy.md §2.3` is a **SEV1 shipping blocker** —
the box displays a 3 % jackpot and rolls 2.5 % (`ShopValue.swift:157-158` vs `:149-150`;
`grep -rn "mysteryOdds" Tests/` → **NOT FOUND**). Guideline 3.1.1 requires disclosed odds to be the
real odds. A mission board that *advertises* a box makes that misstatement more prominent, so the
odds fix rides along in the same commit. It is not scope creep; it is the price of the step.

---

## 2 · THE PLAN

Every step ends with a commit, a green `swift test -c release`, and a green `./Tools/build.sh`.
The app is installable and shippable at every numbered boundary. **MUST / SHOULD / CUT-FIRST** marks
what survives if the session runs short — cut from the bottom.

Recovery tag first: **`git tag pre-s017`** at `ba9655d`. `git tag` shows `pre-s001 … pre-s016`;
`pre-s017` does **not** exist yet.

---

### STEP 0 · Baseline — capture and measure before touching anything · MUST

**Changes:** nothing in `PrismRush/`. Writes `docs/agent/scratch/s017/` captures.

**Do:**
1. `./Tools/build.sh`, install, and capture the board in **four states** (§3.2 names them). The
   `PR_SCREEN=missions` hook already exists at `GameView.swift:309`.
2. Print today's board headlessly: the 3 daily + 3 weekly slots for the current UTC day/week via
   `MissionCatalog.dailySlots` / `weeklySlots` (`MissionCatalog.swift:152`, `:168`) so the after-shots
   can be compared against a known board rather than a mystery one.
3. Record the §0 payout arithmetic in the session log.

**Depends on:** nothing.
**Verified by:** four PNGs on disk, opened and looked at. `01_RULES.md §3` — *"a captured PNG nobody
read is not evidence."*
**Why first:** every "after" claim in this pass is a comparison, and S-015/S-016 both had to
re-shoot baselines because they started editing first.

---

### STEP 1 · The reward ledger — design, not code · MUST

**Changes:** one new file `docs/agent/audits/scratch/s017_ledger.md` + the owner questions in §4
sent as a single message.

**Do:** write, as a table, for all 19 missions: metric → target → **reward KIND** → reward amount →
window → whether it is completable at 15 min/day. Cost every row against
`s016_coins-economy.md §1.2` so the pass can state its delta on the 663 coins/day and on the 26.8-day
catalogue clock. **Do not invent the curve fresh — cost it against that file.**

**Depends on:** Step 0's measured board; the economy sibling's findings.
**Verified by:** the table sums to a stated daily faucet delta and a stated new
days-to-83,500 figure. Owner's answer to §4 Q1/Q2 either confirms or replaces it.
**Why here:** §1.4. This is the input to every card drawn in Step 5.

---

### STEP 2 · The truth fixes — bug-shaped, ship alone, no design input needed · MUST

Three live backlog items sit inside the code this pass is about to rewrite. Fixing them **after** a
rebuild means re-deriving them inside a bigger diff; fixing them first means the rebuild inherits
correct plumbing.

| item | what | cite |
|---|---|---|
| **PR-0006** (SEV1, OPEN) | `body` mutates and saves the profile. `MissionsView.swift:41` calls `store.dailyMissions(now:)` inside `body` → `ProfileStore.swift:378` `refreshDailyMissions` → `:389` `mutate` → `save()` (`:655`) + `cloud.synchronize()` (`:660`). Same at `:43` → `:401` → `:413`. The backlog filed this against the *menu badge*; **the missions screen itself does it, and that is not recorded anywhere.** | `03_BACKLOG.md:108-115` |
| **PR-0172** | `applyRunSummary`'s per-run loop has no `v > 0` guard and writes permanent zero entries on the first run. `ProfileStore.swift:460-464` vs the guarded `bump` at `:481-489`. | `03_BACKLOG.md:655` |
| **PR-0176** | `Mission.Metric.revives` is structurally unsatisfiable — no mission uses it today, but it is a live `CaseIterable` case (`MissionCatalog.swift:35`) rendering a glyph at `MissionsView.swift:526`. | `03_BACKLOG.md:659` |

**Do:** split the daily/weekly query into a pure read for `body` and an explicit refresh on
`.task`/`.onAppear` (the fix sketch at `03_BACKLOG.md:113`). Add the `v > 0` guard. Decide `revives`:
remove the case or fix the capture point — **removing a `Metric` case is a `Profile` key question,
so read §6 first.**

**Depends on:** Step 0.
**Verified by:** `swift test` (all three touch Linux-compiled files — `ProfileStore.swift` and
`MissionCatalog.swift` are both in the SPM target), plus a new unit test per item.
**Blast radius:** `Meta/ProfileStore.swift`, `Meta/MissionCatalog.swift`, `UI/MissionsView.swift`,
`UI/MenuView.swift:343`.
**Trap:** PR-0006's fix must not break the badge. `MenuView.swift:331` deliberately runs a slow
`TimelineView` tick *so the badge survives a UTC rollover* — the refresh has to move, not disappear.

---

### STEP 3 · The reward MOMENT — route mission claims through `RewardBurstView` · MUST

**Changes:** `UI/GameView.swift` (a `RewardBurst.kind` case + a presenter beside `:579` / `:585`),
`UI/RewardBurstView.swift` (copy/art for the new kind), `UI/MissionsView.swift` (delete `CoinFlyUp`
at `:548-576`, call the presenter from `claim()` at `:476-484` and from the CLAIM ALL cascade at
`:130-137`).

**Design question this step must answer, not dodge:** CLAIM ALL fires up to 19 claims at 80 ms
apart (`MissionsView.swift:135`). Nineteen full ceremonies is a hostage situation.
**Recommendation: the cascade produces ONE burst carrying the TOTAL** — which is what the button
already promises (`"CLAIM ALL +\(total)"`, `:140`) — while a single claim gets its own burst.

**Depends on:** Step 2 (the claim path is touched by both).
**Verified by:** `./Tools/build.sh` — `RewardBurstView` and `MissionsView` are **not** compiled by
`swift test`. Then a **12-frame simulator burst** of one claim and one CLAIM ALL (§3.2). A still
cannot prove a ceremony.
**Owner gate:** the *sound*. `s016` shipped the daily burst on `.newBestFanfare` and flagged that it
"may be the wrong colour for a daily bonus" (`HANDOFF.md` action item 2). Nobody here can hear it.
Mark `VERIFY-PENDING`.
**Why this early:** zero economy risk, ships alone, and it is the single most visible answer to
"not rewarding at all" that does not need an owner ruling.

---

### STEP 4 · The reward CONTENT — missions pay boxes · SHOULD *(cut if §4 Q1 = no)*

**Changes, in this order and in SEPARATE commits (see §6):**

**4a — the `Profile` schema commit, alone.** `var pendingMysteryBoxes: Int = 0` on `Profile`
(`Profile.swift`, the `:6-25` field block) **with a `CodingKeys` entry and
`decodeIfPresent ?? default`** (iron rule 7), and an explicit merge policy: **device-local, NOT
merged** — mirror the consumable counters that `ProfileStore.merged` deliberately omits
(`ProfileStore.swift:719-720`), because a `max()` merge on a spendable counter resurrects spent
inventory. `s016_coins-economy.md §3.6` reaches the same conclusion for the same reason.

**4b — the reward kind.** `Mission.rewardCoins: Int` (`MissionCatalog.swift:80`) becomes a
`MissionReward` enum (`.coins(Int)` / `.box(Int)` / `.coinsAndBox`). This is the invasive edit:
`rewardCoins` is read by `ProfileStore.missionState` (`:546`, `:553`), `claimMission` (`:586-587`),
`MissionBoardSummary.of` (`:531`, `:537`), and `MissionsView` (`:120`, `:445`, `:461`).
`MissionState.reward: Int` (`ProfileStore.swift:503`) has to carry the kind too.

**4c — the free daily box**, mirroring `chestReady`/`openFreeChest`
(`ProfileStore.swift:328-331`, `:339-348`).

**4d — the SEV1 odds fix**, mandatory if 4a-c ship (§1.5). Make `mysteryOdds`
(`ShopValue.swift:156-163`) derive from — or assert against — the same band constants
`mysteryReward` switches on (`:143-152`), render `2.5 %`, and add the test that walks the band edges
and reconstructs the table. Also `ShopView.swift:547`/`:560`'s "1,200-coin jackpot" → 1,400
(decree 2).

**Depends on:** Step 1's ledger, owner Q1.
**Verified by:** `swift test` — all of `Profile`, `ProfileStore`, `MissionCatalog` and `ShopValue`
are Linux-compiled. New tests: (i) an old save without the field decodes with `pendingMysteryBoxes
== 0`; (ii) a box-paying mission's claim increments it exactly once; (iii) `merged` does not raise it
from a stale cloud copy; (iv) the odds table reconstructs from the roll bands. Then a simulator
capture of a box-reward card.
**Explicitly NOT in this step:** in-run box pickups. That is `s016_coins-economy.md §3`, it costs a
`DailyChallenge.layoutVersion` **12 → 13** bump, re-derived goldens in **two** files, and a 200-seed
solvability re-run. **See §5.**

---

### STEP 5 · The board rebuild — craft and information architecture · MUST

**Changes:** `UI/MissionsView.swift` (576 L today), possibly split into
`UI/missions/MissionsView.swift` + `MissionCard.swift` + `MissionSection.swift`.

**Do not re-derive the craft spec.** `s016_design-system.md §4.5` already prescribes the three
highest-leverage changes for this exact screen, and the design-system sibling is extending them:

1. four section tints (`MissionsView.swift:26-29`) → one `action` accent + rarity-neutral rules;
2. ring progress (`:404-422`) → a **segmented** bar (countable);
3. CLAIM ALL becomes the screen's single E3 (the emission ladder, `s016_design-system.md §4.1`).

Add the two the design system does not name, both aimed at "not easy to understand":

4. **19 rows in one scroll is the legibility defect.** Either a segmented control (the pattern
   `s016_design-system.md §5.3` proposes for the Shop) or collapse the two lifetime sections behind
   a summary row. Whichever a sibling recommends — but the flat 19-row scroll does not survive.
5. **Each section must state its own rule once, in words.** Four reset semantics currently arrive as
   four micro-captions in four hues (`:207`, `:235`, `:254`, `:272`). A player cannot learn four
   mental models from tracking-2 captions.

**Depends on:** Steps 1, 3, 4 (the card renders whatever a mission pays).
**Verified by:** `./Tools/build.sh` (the only thing that type-checks this file — SourceKit in this
checkout resolves against macOS, so `Cannot find 'Theme' in scope` is noise, per `HANDOFF.md`), then
`xcodebuild test`, then all four after-captures.
**The trap that will bite:** `UITests/InteractionUITests.swift:261-292` drives this screen by
accessibility identifier — `railMissions` (`:263`), `missionsSummary` (`:267`), `claimAllButton`
(`MissionsView.swift:153`), `claim_<id>` (`:457`), `missionCard_<id>` (`:364`). **A rebuild that
renames them turns that test red.** That is the suite working. Keep the identifiers or update the
test deliberately — never delete an assertion to make it pass (`01_RULES.md §3`).

---

### STEP 6 · The surfaces — missions must appear where the player already is · SHOULD

**6a — game over.** `grep -rn "mission\|Mission" PrismRush/UI/GameOverView.swift` → **NOT FOUND.**
The screen that knows exactly which missions the run just advanced says nothing about them. The
insertion band `s016_coins-economy.md §3.6` names for the box row (`GameOverView.swift:389-425`) is
the same band. This is decree 4 — *everything on screen leads somewhere* — and it is probably the
largest single contributor to "does nothing": **the board is a destination you have to remember to
visit** (`MenuView.swift:343`, one nav-rail cell, `03_BACKLOG.md` PR-0006 context).

**6b — the hub.** If Step 4 ships, the box the board pays needs a place to live between earning and
opening. `s016_design-system.md §5.1` already draws a "box podium" beside the hub hero.

**Depends on:** Steps 3–5.
**Verified by:** `./Tools/build.sh` + a game-over capture with an advanced mission visible.
**CUT-FIRST candidate:** 6b. 6a is cheap and answers the complaint directly.

---

### STEP 7 · Tests, docs, handoff · MUST

- New unit tests land with their step, not here. Here: confirm `MissionsTests.swift` (309 L) still
  pins what it pinned, and add the XCUITest for whatever navigation Step 5 introduces.
- **`MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens` pins the daily-challenge goldens from
  the meta layer** (CLAUDE.md iron rule 3 calls it *"the one people forget"*). This pass must not
  move it — if it goes red, something touched the spawn path and the pass has left its lane.
- `02_STATE.md`, `03_BACKLOG.md` (close PR-0006/0172/0176 if fixed; file the new items — **the next
  free ID is PR-0473**; PR-0472 is the highest in use), `04_DECISIONS.md` (**next free is D-052**;
  D-051 is the highest), `docs/agent/sessions/SESSION_017.md`, `HANDOFF.md`.
- `05_GAME_DESIGN.md:350-353` is **factually wrong** about the Mystery Box (says 19 % house edge and
  EV 192; it has been EV 300.5 since S-012 — `s016_coins-economy.md §7` finding 5). If Step 4 ships,
  fix that line in the same commit.

---

## 3 · THE VERIFICATION PLAN

### 3.1 What each layer can and cannot see

| gate | command | covers | does NOT cover |
|---|---|---|---|
| SPM | `swift test -c release` | `Core/`, 7 `Meta/` files, `Audio/Synth.swift` → `MissionCatalog`, `Profile`, `ProfileStore` mission logic, `MissionBoardSummary`, `ShopValue`. **266 tests green at HEAD.** | **Every line of `MissionsView.swift`, `RewardBurstView.swift`, `GameOverView.swift`, `MenuView.swift`.** A green run says nothing about this pass's headline screen. |
| iOS build | `./Tools/build.sh` | the **only** thing that type-checks `UI/`. S-015 shipped `Theme.Role.warning` (does not exist) past 266 green SPM tests; the build caught it in one line (`SESSION_015.md:136-139`). | behaviour |
| Xcode suite | `xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO` | 285 tests (273 unit + 12 XCUITest), incl. `testMissionsClaimAllCascadeAndSingleClaim` | anything visual |
| simulator | `PR_SCREEN=missions` (`GameView.swift:309`) | what it looks like | what it sounds like; what it feels like |
| owner | — | feel, sound, whether the reward is worth wanting | — |

**Never run `simctl` / screenshots on the dev sim while `xcodebuild test` is running** — concurrent
installs crash the test host and produce a false "TEST FAILED" (CLAUDE.md).

### 3.2 The screenshots that must be taken — named

Store under `docs/agent/scratch/s017/`. Every one gets a `before_` and an `after_`.

| name | how | proves |
|---|---|---|
| `01_fresh` | `simctl uninstall` → `install` → `SIMCTL_CHILD_PR_FIRSTRUN=1 SIMCTL_CHILD_PR_SCREEN=missions` | the 0/19 first-launch board. **`PR_FIRSTRUN` does NOT reset the profile — uninstall/install is the only honest reset** (`01_RULES.md §3`; `MEMORY.md` "simctl install keeps the profile"). |
| `02_progress` | `SIMCTL_CHILD_PR_DEMOPROFILE=1 SIMCTL_CHILD_PR_SCREEN=missions` (`GameView.swift:166`) | the normal mid-progress board |
| `03_claimable` | as 02, with ≥2 claimable | the CLAIM ALL state (`MissionsView.swift:119`) |
| `04_tail` | as 02, scrolled to the achievements section | the 19-row scroll — **the "not easy to understand" complaint is only visible below the fold** |
| `05_claim_f01..f12` | 12-frame burst across one single claim | Step 3's ceremony. A still cannot prove motion (S-015 used exactly this at 12 fps, `SESSION_015.md:130-134`) |
| `06_claimall_f01..f12` | 12-frame burst across the cascade | that 19 claims do not produce 19 ceremonies |
| `07_box_card` | a mission whose reward is a box | Step 4b renders |
| `08_gameover` | force a death with a mission advanced | Step 6a |

Every capture gets **opened and looked at**. `01_RULES.md §3` again.

### 3.3 Per-step assignment

| step | SPM | iOS build | XCUITest | capture | owner |
|---|:-:|:-:|:-:|:-:|:-:|
| 0 baseline | — | ✅ | — | **01–04 before** | — |
| 1 ledger | — | — | — | — | **✅ Q1/Q2** |
| 2 truth fixes | **✅ primary** | ✅ | ✅ | — | — |
| 3 reward moment | — | **✅ primary** | ✅ | **05, 06** | **✅ the sound** |
| 4 reward content | **✅ primary** | ✅ | ✅ | 07 | **✅ Q1** |
| 5 board rebuild | — | **✅ primary** | **✅ primary** | **01–04 after** | **✅ the look** |
| 6 surfaces | — | ✅ | ✅ | 08 | ✅ |
| 7 docs | ✅ | ✅ | ✅ | — | — |

### 3.4 What CANNOT be verified here — say so, do not fake it

- **Sound.** Nobody in this program can hear audio. Six sessions of standing audio requests are
  already queued (`02_STATE.md` "Needs Rayan on a device"). Any claim about the claim chime is
  `VERIFY-PENDING`.
- **Whether the reward feels worth it.** That is the complaint. A capture cannot answer it.
- **Device performance.** Everything measured here is on a Mac. M5 is open and the simulator is not
  the phone (`HANDOFF.md` action item 4).

### 3.5 Command output goes in the log verbatim

`01_RULES.md §3`: *"No output, no credit."* `SESSION_015.md:145-168` is the format — pasted
`swift test` and `xcodebuild test` tails, plus a note on how build currency was confirmed (S-015
grepped the dylib for strings only the change introduces, **not by mtime** — copy that).

---

## 4 · WHAT THE OWNER MUST DECIDE

Send as **one message**, before Step 4 and ideally before Step 1 closes. Each is a yes/no or a pick.

**Q1 — What should a mission pay?** Today every one pays coins (`MissionCatalog.swift:80`).
Proposal: **dailies pay a Mystery Box, weeklies pay coins + a box, achievements pay coins, per-run
feats pay coins.** Rationale in §1.5.
*(a) ship it · (b) coins only, keep it as is · (c) something else — name it.*
**Why it is his:** a box is worth ~300 coins of value but converts coins into variance rather than
adding to the pile; it trades directly against coin IAP revenue, and it is the mechanic M7 asked for.

**Q2 — Should total coin income go DOWN, or stay FLAT?** The board is 663 coins/day = 34 % of the
meta faucet (§0). If boxes replace some coin rewards, income falls. `s016_coins-economy.md §5(b)`
flags "cutting the faucet again" as needing his call: S-011 already cut it ~7× and *"another cut
reads as a nerf to existing players."*
*(a) down — scarcity is the point · (b) flat — replace coins with boxes of equal stated value ·
(c) up.* **This is the reward curve and it is his call, not mine.**

**Q3 — Do missions get timed offers?** D-050 ruled that real countdown offers ship, and decree 5
survives — *"a countdown must be real and enforced in code."* Does that extend to the mission board
(e.g. "claim within 2 h for a bonus")?
*(a) no timed offers on missions · (b) yes, and the deadline is enforced server-lessly in code and
never resets.* Default if unanswered: **(a)** — the cheapest way to not violate decree 5 is to not
build the mechanism.

**Q4 — Are weekly missions allowed to be un-completable?** `wk.dist20k` is 20,000 m in a UTC week
(`MissionCatalog.swift:116`). At the measured ~3,300 m good run that is ~6 runs — fine. But
`wk.close75` (75 CLOSE bonuses, `:118`) and `wk.slick35` (`:119`) are skill metrics with no measured
per-run rate in the repo (`grep -rn "closes\b" docs/agent/audits/scratch/s016_coins-economy.md` →
only the faucet formula, no rate). `s016_coins-economy.md §5(a)` sets the honesty rule: a set is
honest **iff** completable at normal play rates inside its window.
*(a) every weekly must be completable at 15 min/day · (b) weeklies are stretch goals and may not be.*

**Q5 — May a mission ever pay a CHARACTER?** Today exactly one item in the game cannot be earned
(Aurora, `.iap`, `SkinCatalog.swift:223`). A terminal cosmetic prize is the single strongest "does
nothing" answer available, and `s016_coins-economy.md §4.1 #5` prices it as a full live-ops system.
*(a) not this pass · (b) yes — and then §5's fence moves.* Default: **(a)**.

**Q6 (informational, answer at leisure) — is he willing to look at 8 screenshots?** The whole
verification plan assumes the after-shots reach him. If not, the pass should build a single
side-by-side artefact instead, as S-016 did.

---

## 5 · THE SCOPE FENCE

Pass 017 **does not**:

| out of scope | why | where it belongs |
|---|---|---|
| **In-run mystery box pickups** | costs `DailyChallenge.layoutVersion` **12 → 13**, goldens re-derived in Python and pinned in **two** files (`DailyChallengeTests` **and** `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`), and a 200-seed × 6,000 m solvability re-run plus the 12,000 m soak. `s016_coins-economy.md §3.2` specifies it fully. | its own pass |
| **Any spawner / pattern / RNG change at all** | same reason. **This pass must leave `layoutVersion` at 12 and the v13 pin (`0x9E49_3424_C18A_59C5`) unspent.** If a golden test goes red, the pass has left its lane. | — |
| **A second (premium) currency** | `s016_coins-economy.md §5(b)` — owner-gated, high cost, touches `Profile`, the cloud merge, every shop surface and StoreKit | its own pass |
| **The infinite non-arbitrage sink** (upgrade track) | `s016_coins-economy.md §4.1 #2`, hard-constrained by D-026 | its own pass |
| **The world-ladder forfeiture repair** | `s016_coins-economy.md §6`. D-050 already ruled *keep the forfeit* | closed by ruling |
| **R1 / R2, the Warden** | blocked on D-047 (the designed fix breaks determinism) | its own pass |
| **The character preview seam** — should menu previews be live rig renders | **PASS 018.** It is the highest-value open question in the program (`02_STATE.md`, D-050 note). Missions must not touch `CharacterSwatch.swift` or `ProceduralMesh.swift` | **018** |
| **New character art** | **PASS 019.** D-050 ordered new art for all 24 | **019** |
| **General asset import** | D-046 revoked the decree, but a mission board is the wrong place to prove an asset pipeline. **Cap: at most ONE new object this pass — the box — and only if Step 4 ships.** `s016_assets.md`'s headline (assets can pay for themselves by replacing 560 particle spheres) is a *render* argument, not a missions one | 018/019 |
| **The rest of the design-system migration** | 135 raw `.font(.system(size:` sites app-wide (`s016_design-system.md §1.6`). This pass fixes the **6** in `MissionsView.swift` and leaves the other 129 | a design-system pass |

**The fence that will actually be tested:** Step 5 will make it obvious that `MenuView`,
`GameOverView` and `ShopView` share the missions screen's problems. **File, do not fix**
(`01_RULES.md §2`), except the two named exceptions: the Step 6a game-over surface (it *is* the
"does nothing" fix) and the Step 4d odds/copy fix (it is the price of paying in boxes).

---

## 6 · THE ROLLBACK STORY

### 6.1 Recovery point

`git tag pre-s017` at `ba9655d`, before the first commit. Verified: `git tag` lists
`pre-s001 … pre-s016` and `post-s003`; **`pre-s017` does not exist yet.**

### 6.2 The largest irreversible step, precisely

**Not the UI. The `Profile` schema (Step 4a).**

`git revert` restores code. It does **not** restore a player's save. `Profile` is persisted to
`UserDefaults` **and** synced to iCloud KVS (`ProfileStore.swift:44`, `:655-660`), and
`ProfileStore.merged` is **monotone** — grow-only `max` merges across `missionProgress`,
`claimedMissions` and `achievementTier` (`:711-713`). Once a field has been written and synced, a
code rollback leaves the data behind, and a wrong merge policy on that field is permanent for that
account.

**Second-largest: mission IDs.** `MissionCatalog.swift:87` states it — *"IDs are persistence keys —
never reuse one for different semantics."* They are the keys of `profile.missionProgress`,
`profile.claimedMissions` and `profile.achievementTier`. Re-targeting `day.gems150` to a different
target silently re-pays or silently locks a player who already claimed it.

### 6.3 The three rules that make this pass revertible

1. **New semantics get NEW IDs. Never re-target an old one.** Orphaned old keys are harmless — they
   sit unread in a dictionary. A re-targeted key is a money bug. This makes the failure mode of a
   revert "some dead keys" instead of "wrong payouts."
2. **The `Profile` schema change ships in its OWN commit, first among the persistent ones**
   (Step 4a alone, before 4b). Then everything above it can be reverted while the field stays.
3. **A `Profile` field is never deleted, only tombstoned.** Iron rule 7 — `decodeIfPresent ??
   default` — means keeping an unused field is free and forever safe. Deleting it is what breaks old
   saves. If the owner hates Step 4, `pendingMysteryBoxes` stays in `Profile` with a comment saying
   why, and nothing reads it.

### 6.4 How a future session undoes it if the owner hates it

| what he hates | undo |
|---|---|
| the look (Step 5) | `git revert` the UI commits. Zero persistence involved. Clean. |
| the ceremony (Step 3) | `git revert`. `CoinFlyUp` comes back with it. Clean. |
| **the reward mix (Step 4)** | revert 4b/4c/4d (the enum, the free box, the odds display). **Keep 4a's field, tombstoned.** Players who banked boxes keep them; the board goes back to paying coins. **Not clean, but bounded** — and bounded is what the commit split buys. |
| the whole pass | `git reset --hard pre-s017` for the code; every player who ran a Step-4 build keeps a `pendingMysteryBoxes` count that nothing reads, which is exactly the harmless state rule 3 is designed to leave behind. |

### 6.5 The rule that is not negotiable

**Never make a gate pass by weakening it.** If `MissionsTests`, the XCUITest identifiers, or the
daily-challenge goldens go red, that is information. Deleting an assertion, widening a band, or
skipping a test is a finding to log, not a fix to apply (`01_RULES.md §3`; the session prompt
repeats it). The XCUITest at `UITests/InteractionUITests.swift:261` **will** go red during Step 5 if
identifiers move — update it deliberately, in the same commit, with the reason in the message.

---

## 7 · WHAT I DID NOT VERIFY, AND THE GREPS

| claim | status |
|---|---|
| `GameOverView` has no missions surface | `grep -rn "mission\|Mission" PrismRush/UI/GameOverView.swift` → **NOT FOUND** |
| No test pins the Mystery Box display odds | `grep -rn "mysteryOdds" Tests/` → **NOT FOUND** (`s016_coins-economy.md §2.3`, re-cited not re-run) |
| Fresh board shows 19 rows, not `s007_missions.md`'s 18 | **derived** from `MissionCatalog.swift:90,100,114,125` (6+3+3+7). The 18→19 reconciliation via `run.warden1` is **inference, not proof** — nobody ran `git show` on it. |
| 663 coins/day, 21.3 % of a casual player's income | **derived** from `MissionCatalog.swift` literals × `s016_coins-economy.md §1.2, §1.5`. Not independently measured this pass. |
| PR-0006 applies to `MissionsView` and not only `MenuView` | **traced in source**: `MissionsView.swift:41` → `ProfileStore.swift:378` → `:389` `mutate` → `:655` `save()` → `:660` `cloud.synchronize()`. Not observed at runtime. |
| Steps 3–6 build | **not attempted.** Read-only pass; no build, no simctl, per the brief. |
