# S-017 INVESTIGATION — "MISSIONS DOES NOTHING": THE FULL CONSEQUENCE CHAIN

**Read-only pass at HEAD `ba9655d`, branch `main`, tree clean. No source file was modified.**
Every claim carries a `file:line`. Economy figures are either quoted from
`docs/agent/audits/scratch/s016_coins-economy.md` (with its own cite carried through) or derived
here in Python from the literals in `MissionCatalog.swift` — the derivation script is inlined in
§4.1 so it can be re-run.

Scope: the owner's **second** complaint only — *"does nothing"*. Craft ("ugly") and legibility
("not easy to understand") are other agents' lanes; where a legibility fact is load-bearing for
consequence it is stated and marked as out-of-lane.

---

## 0. THE VERDICT, UP FRONT

**Missions do exactly one thing that running does not: they are the only way to obtain three
characters.** Everything else they pay is coins, and coins are the same coins running already
pays — at a rate that makes the entire recurring mission system worth **8.5 minutes of ordinary
running per day**.

| # | finding | severity |
|---|---|---|
| **A** | **The whole recurring mission system pays 663.5 coins/day** (345.1 daily board + 318.4 weekly amortised; derived §4.1). At the measured faucet of 78.3 coins/min (`s016_coins-economy.md:60`, S-011 headless probe) that is **8 min 29 s of running**. One tap on the daily-login button at streak ≥7 pays **1,000** (`ProfileStore.swift:296`) — **2.9× the entire daily mission board**. The board that requires you to play well is worth a third of the button that requires you to exist. | **SEV1 — this IS "not rewarding"** |
| **B** | **Mission completion has no moment.** `GameOverView.swift` contains **zero** occurrences of "mission" (grep in §2.2). A run that finishes *"Travel 3,000 m today"* AND *"Score 15 CLOSE bonuses today"* ends on a death panel that shows score, coins, XP, level-up, "NEW CHARACTER UNLOCKED", challenge tier — and says nothing about either mission. The only signal is a purple `2` on a 34 pt nav-rail glyph (`MenuView.swift:343-346`). | **SEV1 — this IS "does nothing"** |
| **C** | **The one non-fungible consequence is invisible on the missions screen itself.** Claiming `ach.dist` T1 / `ach.gems` T2 / `ach.close` T1 is the *only* way to unlock **Drift**, **Facet** and **Wisp** (`SkinUnlocks.swift:12` reads the claim receipt; `ProfileStore.swift:584` is the only writer). `MissionCard` renders title + ring + tier pips + a coin pill and **never names the character** (`MissionsView.swift:369-472`). The link is one-directional: CharacterSelect routes *to* missions (`CharacterSelectView.swift:293`), missions never point back. | **SEV1 — the highest-value fix on the board** |
| **D** | **Missions feed nothing else. Ruled on all seven threads (§3): XP no, Game Center no, streaks no, worlds no, leaderboards no, difficulty no, run content no.** `claimMission` writes exactly four things (`ProfileStore.swift:579-589`) and one of them (`totalCoinsEarned`) is read by **no production code anywhere** (§3.7). | SEV2 |
| **E** | **The 6-card "CHALLENGES" section is a graveyard by day two and stays on screen forever.** All six per-run feats are claim-once-forever (`MissionCatalog.swift:90-97`); `run.mult5` completes in roughly the first ten seconds of the first real run (`Tuning.swift:149` + the bible's measurement, §5.2). After week one, **6 of the board's 19 cards are struck-through receipt rows** (`MissionsView.swift:489-510`) that will never change again. | SEV2 |

**The one-sentence answer to the mandate's killer question:** a player who never opens the missions
screen loses **≈663 coins/day (10–21% of income depending on session length), 12,320 lifetime
coins, and three of the twenty-four characters.** The coins are fungible with 8½ minutes of
running. The characters are not. **That asymmetry is the whole defect: the system's only
irreplaceable output is the one it never advertises.**

---

## 1. Q1 — WHAT DOES A MISSION ACTUALLY PAY?

### 1.1 Coins. Only coins. Never anything else.

`Mission` carries a single reward field and it is typed `Int` coins:

```swift
// PrismRush/Meta/MissionCatalog.swift:76-82
let id: String
let title: String
let metric: Metric
let target: Double       // perRun/daily target (tiered missions use the tier targets)
let rewardCoins: Int     // perRun/daily reward (tiered missions use the tier rewards)
let scope: Scope
```

There is no XP field, no item field, no skin field, no charge field. `Scope.lifetimeTiered`
(`:73`) carries `rewards: [Int]` — again coins.

### 1.2 The complete reward table, quoted

**Per-run feats — 6 missions, 970 coins, claim-once-forever** (`MissionCatalog.swift:90-97`):

| id | title | reward | cite |
|---|---|---|---|
| `run.mult5` | Hit a ×5 multiplier in one run | 150 | `:91` |
| `run.slide5` | Slide under 5 bars in one run | 100 | `:92` |
| `run.gems60` | Collect 60 gems in one run | 120 | `:93` |
| `run.close8` | Thread 8 CLOSE calls in one run | 150 | `:94` |
| `run.dist2k` | Travel 2,000 m in one run | 200 | `:95` |
| `run.warden1` | Defeat a Warden | 250 | `:96` |

**Daily pool — 8 missions, 3 drawn per UTC day** (`MissionCatalog.swift:100-109`): 120, 120, 100,
100, 140, 140, 120, 80. Mean 115/mission.

**Weekly pool — 7 missions, 3 drawn per UTC week** (`MissionCatalog.swift:114-122`): 700, 800, 600,
900, 900, 600, 700. Mean 742.9/mission.

**Achievement ladders — 7 ladders, 18 tiers, 11,350 coins lifetime** (`MissionCatalog.swift:125-140`):

| id | title | tiers | rewards | subtotal |
|---|---|---|---|---|
| `ach.gems` | Gem Hoarder | 100 / 1,000 / 10,000 | 50 / 200 / 1,000 | 1,250 |
| `ach.dist` | Marathoner | 10k / 50k / 100k m | 150 / 500 / 1,500 | 2,150 |
| `ach.close` | Needle Threader | 100 / 1,000 | 200 / 1,200 | 1,400 |
| `ach.slick` | Limbo Legend | 50 / 500 | 150 / 1,000 | 1,150 |
| `ach.runs` | Veteran Runner | 25 / 250 / 1,000 | 100 / 500 / 2,000 | 2,600 |
| `ach.worlds` | World Walker | 3 / 6 / 12 | 100 / 300 / 1,500 | 1,900 |
| `ach.chests` | Chest Hunter | 10 / 100 | 100 / 800 | 900 |

### 1.3 The crediting code, quoted in full

```swift
// PrismRush/Meta/ProfileStore.swift:577-590 (claimMission, tail)
let state = missionState(m, now: now)
guard state.claimable, state.reward > 0 else { return nil }
mutate {
    switch m.scope {
    case .perRun, .daily, .weekly:
        $0.claimedMissions.insert(id)
    case .lifetimeTiered:
        $0.achievementTier[id] = state.tier + 1
    }
    $0.coins += state.reward
    $0.totalCoinsEarned += state.reward
}
return state.reward
```

**Four writes, and that is the entire consequence of completing a mission in this game:**
1. `claimedMissions.insert(id)` **or** `achievementTier[id] += 1` — the receipt.
2. `coins += reward` — the payout.
3. `totalCoinsEarned += reward` — a lifetime counter **read by no production code** (§3.7).

`claimMission` is called from exactly two sites, both in `MissionsView`:
`MissionsView.swift:132` (CLAIM ALL cascade) and `:478` (single card). **There is no auto-claim
path.** A completed, unclaimed mission pays nothing until the player opens the screen and taps.

### 1.4 The payout is NOT doubled by the Double Coins IAP

`profile.coinMultiplier` is consumed at exactly one site (`GameView.swift:895`, per
`s016_coins-economy.md:56-59`). Mission claims, the daily reward, the chest, the level grant and the
challenge tier are all outside it. The blurb states this correctly (`IAP/IAPCatalog.swift:35`).
Not a defect — recorded so the plan does not "fix" it.

---

## 2. Q2 — WHERE DOES IT LAND, AND DOES THE PLAYER SEE IT LAND?

### 2.1 On the missions screen: yes, thinly — and not at all under Reduce Motion

A single-card claim (`MissionsView.swift:476-484`) produces, in order:

| beat | what | cite |
|---|---|---|
| store write | coins + receipt, **before** any FX (deliberate — a mid-animation dismissal must not lose coins) | `MissionsView.swift:478` |
| haptic | `.success` (gated on `profile.hapticsEnabled`) | `:58-60`, `:187-190` |
| sound | `Synth.SFX.purchaseChime` — **the same chime as buying a skin in the shop** | `:189` |
| coin fly-up | `+N ⬤` gold, rises 38 pt over 0.8 s, top-trailing of the card, then vanishes | `:546-576`, `:568-570` |
| row collapse | card → slim struck-through receipt row, spring 0.45/0.15 | `:52-55`, `:489-510` |
| header count | `CoinBadge` `.contentTransition(.numericText)` + `.snappy(0.4)` | `CoinBadge.swift:32-34` |

**Under Reduce Motion every one of those visual beats is disabled:**
- fly-up: `if !reduceMotion { flyAmount = reward; flyTrigger += 1 }` — `MissionsView.swift:480-483`
- row collapse: `.animation(reduceMotion ? nil : …)` — `:52-55`
- header count: `.animation(reduceMotion ? nil : .snappy(0.4), value: amount)` — `CoinBadge.swift:34`
- ring: `.animation(reduceMotion ? nil : .easeOut(0.7), value: shown)` — `MissionsView.swift:419`

A Reduce Motion player claiming a 1,500-coin achievement tier gets **one chime, one haptic, and an
instantaneous state change.** That is precisely the shape of the owner's S-016 complaint —
*"after the reward it says open chest and it just says chest opened"* (`s016_mandate.md:41-43`) —
re-instantiated on a different screen. **It survived S-016 because S-016 only fixed the two paths
that route through `RewardBurst`.**

### 2.2 At the moment of COMPLETION: nothing, anywhere

```
$ grep -n "mission\|Mission" PrismRush/UI/GameOverView.swift
(no output)
```

The death panel renders (`GameOverView.swift`): score + NEW BEST (`:149-183`), coins earned with
the ×2 chip (`:192-243`), the challenge tier line (`:284`), the XP band with `+N XP` / `▸ LVL n` /
level-up coin grant (`:303-331`), `NEW CHARACTER UNLOCKED · TAP` (`:345`), two stat chips + FULL
STATS (`:387-399`), and the continue/revive block (`:425-462`).

**Not one word about missions.** The run that just satisfied three mission targets ends silent.

There is no in-run mission surface either — grep across `PrismRush/UI/*.swift` for `mission`
(§ tool log) returns only `MissionsView.swift`, `CharacterSelectView.swift:187,191,293`,
`MenuView.swift:38,331,343-346`, `ProfileView.swift:185,194,207`, `GameView.swift` (routing +
UI-test fixtures) and two comments. **NOT FOUND: any HUD element, popup, toast or FX tied to
mission progress or mission completion.**

### 2.3 On the hub: missions are the only reward surface demoted below navigation

| hub element | treatment | cite |
|---|---|---|
| daily login + free chest | **full-width gold bar** with a black CTA pill — "the only gold on the hub" | `ClaimRibbon.swift:11-14, 40-44` |
| Daily Rush | its own launcher beside PLAY | `ClaimRibbon.swift:7` |
| **Missions** | **19 pt glyph in a 4-cell nav rail under a hairline, with a small purple count badge** | `MenuView.swift:343-346`; design-system audit `s016_design-system.md:503` |

`ClaimRibbon`'s own docstring says the split was deliberate — *"Missions is a nav-rail exit"*
(`:7`). That was the right call for a **destination**; it is the wrong call for the surface that
holds 663 coins/day of unclaimed money. The player's coins currently sit behind an icon that looks
like Settings.

### 2.4 The `RewardBurstView` seam — it exists, it is clean, and missions should use it

`RewardBurst` is a `Sendable` value type with a two-case kind enum:

```swift
// PrismRush/UI/RewardBurstView.swift:5-17
struct RewardBurst: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case daily(streak: Int)
        case chest
    }
    var kind: Kind
    var coins: Int
    var ladder: [Int] = []
}
```

`title` (`:19-24`) and `subtitle` (`:27-36`) are pure switches over `kind`. The presenter
`GameModel.present(_:)` (`GameView.swift:598-618`) sets `rewardBurst`, fires `haptics.levelUp()`,
`.flowSurge`, then `.newBestFanfare` at +220 ms and a 10-step rising `.gem(streak:)` cascade.

**The seam works over the missions sheet with no z-order change:** the overlay is mounted at
`GameView.swift:1531-1535` with `.zIndex(9)`; `metaSheet(sheet)` is mounted at `:1483-1484` with
**no explicit zIndex (implicit 0)**. A burst raised from `MissionsView` renders above the board.

**Should missions use it? Yes — but not per claim.** Three concrete reasons, and one place it must
NOT go:

1. **Per-claim is wrong for CLAIM ALL.** `MissionsView.swift:130-137` fires claims one per 80 ms.
   Nine modal bursts in 720 ms is a lockout, not a celebration. The burst belongs on the **CLAIM
   ALL total** and on **single high-value claims** (achievement tiers, weekly slots), not on an
   80-coin daily.
2. **The economically correct trigger is the tier that unlocks a character**, not the coins.
   A `.missionTier(name:unlocks:)` kind whose subtitle reads `MARATHONER I · DRIFT UNLOCKED` is the
   single change that makes finding C visible.
3. **The `ladder: [Int]` field already generalises.** `RewardBurstView` draws the login ladder
   with the claimed rung highlighted (`RewardBurst.swift:15-17`, `:30-32`); an achievement's
   `targets`/`rewards` arrays are the same shape. **A tier ladder is a login ladder.** Near-zero
   view work.

**Where it must not go:** the death panel. A modal burst between dying and `RUN AGAIN` taxes the
one-tap restart the bible calls correct (`05_GAME_DESIGN.md:454-456`). Mission completion at
game-over needs an **inline band**, not a modal — see §7.2.

---

## 3. Q3 — EVERY OTHER THREAD MISSIONS COULD FEED, RULED ON

### 3.1 XP / levels — **NO. Ruled: missions grant zero XP.**

```swift
// PrismRush/Meta/XPCurve.swift:47-54
static func xp(for s: RunSummary) -> Int {
    let distanceXP = Int(s.distance / 10)
    let gemXP = s.gems * 2
    let styleXP = (s.nearMissCloses + s.slicks) * 5
    let comboXP = s.bestMult * 10
    let worldXP = max(0, (s.worldsCrossed - 1) - s.startWorld) * 25
    return min(max(distanceXP + gemXP + styleXP + comboXP + worldXP, 0), 2_000)
}
```

Pure `f(RunSummary)`. `claimMission` (`ProfileStore.swift:579-589`) never touches `totalXP`.
**Consequence:** the level ladder — which gates 6 characters (`XPCurve.swift:111`) and grants
slow-mo / speed-up / shield / coin-surge charges (`:96-106`) — is completely deaf to missions.
Every mission target is a thing you did in a run, and the run already paid its XP. The mission
adds nothing to the ladder.

### 3.2 Game Center achievements — **NO. There are none.**

```
$ grep -rn "GKAchievement" PrismRush/
(no output)
```

`GameCenterService.swift` submits **leaderboards only**: `submitRun` (`:62-65`), `submit` (`:67-76`,
`GKLeaderboard.submitScore`), `submitDailyChallenge` (`:78-90`). **NOT FOUND: any
`GKAchievement`, `GKAchievementDescription`, or achievement report.** The app ships seven
achievement ladders that Game Center has never heard of.

### 3.3 Login streak — **NO.** `loginStreak` moves only in `claimDailyReward`
(`ProfileStore.swift:320-326`); `pendingDailyStreak` (`:305-313`) reads `lastDailyClaim` alone.
Missions and the streak are fully independent systems that happen to share a currency.

### 3.4 World unlocks — **NO.** Startable = `index <= maxWorldReached || purchasedWorlds.contains(index)`
(`ProfileStore.swift:260-263`). `purchasedWorlds` is written only by `unlockWorld`
(`:274-280`), which is a coin spend. `maxWorldReached` is written only by `recordRun` (`:198`).
**A mission can influence a world only by paying coins the player then spends** — i.e. exactly the
way running influences it.

### 3.5 Character unlocks — **YES, and this is the only one.**

```swift
// PrismRush/Meta/SkinUnlocks.swift:12
case .achievement(let id, let tier): return (profile.achievementTier[id] ?? 0) >= tier
```

The predicate reads the **claim receipt**, not the progress. `achievementTier` writers across the
whole tree: `ProfileStore.swift:584` (`claimMission`), `ProfileStore.swift:713` (cloud max-merge),
and `GameView.swift:191-192, 206-210` (UI-test fixtures only, behind a launch-arg branch).
**Grinding the metric to 10,000× the target grants nothing without the tap.**

Three characters hang off it (`SkinCatalog.swift`):

| skin | rarity | gate | tier target | cite |
|---|---|---|---|---|
| **Drift** | rare | `ach.dist` T1 | 10,000 m lifetime | `SkinCatalog.swift:168` |
| **Facet** | rare | `ach.gems` T2 | 1,000 gems lifetime | `:174` |
| **Wisp** | epic | `ach.close` T1 | 100 CLOSE calls | `:211` |

Grant path: `refreshSkinUnlocks` (`ProfileStore.swift:224-231`) → `checkSkinUnlocks`
(`GameView.swift:861-868`) → a `celebrateMilestone` text popup. It fires on `closeSheet()`
(`GameView.swift:887-889`), so the "NEW CHARACTER — DRIFT" popup lands **on the menu, after you
have left the missions screen** — a 1.6 s in-world text popup at `worldX: 0`
(`GameView.swift:1081-1086`, prune window `:1077`), which is the same treatment a `+5 CLOSE`
gets mid-run. **The single most valuable thing the missions system produces is celebrated on a
different screen, one second after you stopped looking.**

### 3.6 Run content / difficulty / patterns — **NO.** `MissionCatalog` is a `Meta/` type and
`Core/` never imports it (iron rule 1; grep: no `MissionCatalog` reference anywhere under
`PrismRush/Core/`). The spawner reads only distance, seed and `Tuning`. **No mission can change
what spawns, how fast it comes, or what a run contains.**

### 3.7 `totalCoinsEarned` — **written by 6 sites, read by ZERO production code**

Writers: `ProfileStore.swift:192, 324, 344, 442, 587, 642` and `GameView.swift:983`.
Readers across `PrismRush/`: none. Only `Tests/CoreTests/ProgressionTests.swift:145,383` and
`EconomyTests.swift:205,551,572` read it.

**Consequence for this session:** the one number that could tell a player *"missions have paid you
9,340 coins"* is already computed, already cloud-merged, and thrown away. `ProfileView` renders
`totalGems` / `totalDistance` (per the prior audit, `verify-catalog-missions-consequence.md`) but
not this. Cheapest possible "missions did something" surface in the app — but note it aggregates
**all** faucets, so proving the mission share needs a new per-source counter.

---

## 4. Q4 — THE KILLER QUESTION, COSTED

### 4.1 What the mission system pays, derived

Derivation (re-runnable; SplitMix64 constants from `PrismRush/Core/RNG.swift:11-14`, `int(a,b)`
from `:27`, tags from `MissionCatalog.swift:148` and `:165`, slot algorithm from `:152-160`
and `:168-176`):

```python
M=(1<<64)-1
class SM:
    def __init__(s,seed): s.st=seed&M
    def next(s):
        s.st=(s.st+0x9E3779B97F4A7C15)&M; z=s.st
        z=((z^(z>>30))*0xBF58476D1CE4E5B9)&M; z=((z^(z>>27))*0x94D049BB133111EB)&M
        return (z^(z>>31))&M
    def unit(s): return (s.next()>>11)*(1.0/9007199254740992.0)
    def rint(s,a,b): return a+int(s.unit()*(b-a+1))
def slots(pool,key,tag):
    r=SM((key&M)^tag); p=list(pool); out=[]
    for _ in range(3): out.append(p.pop(r.rint(0,len(p)-1)))
    return out
DTAG=0x4D495353494F4E53; WTAG=0x5745454B4C593133
```

| window | result |
|---|---|
| daily board, 365 days from `daysSinceEpoch` 20668 (2026-08-03) | min **280**, max **400**, mean **345.1** coins/day |
| today's actual board (day 20668) | `day.slick6` 140 + `day.runs5` 100 + `day.dist3k` 120 = **360** |
| weekly board, 52 weeks | min **1,900**, max **2,500**, mean **2,228.8**/wk = **318.4**/day |
| this week's actual board | `wk.slide60` 600 + `wk.streak25` 700 + `wk.slick35` 900 = **2,200** |
| **recurring total** | **663.5 coins/day** |
| one-time: per-run feats + all 18 achievement tiers | 970 + 11,350 = **12,320 coins, ever** |

(The 345 / 318 figures reproduce `s016_coins-economy.md:71-72` exactly, which used means rather
than the actual seeded draw. Confirmed, not merely inherited.)

### 4.2 What that is worth, three ways

**As time.** Measured faucet, S-011 headless probe through the real `GameCore`
(`s016_coins-economy.md:60`): a 3,300 m run = **179 coins in 137.2 s = 78.3 coins/min**.

> **663.5 ÷ 78.3 = 8 min 29 s of running.**
> Doing every daily and weekly mission, every day, is worth **eight and a half minutes** of just
> playing the game normally.

**As a share of income** (denominators from `s016_coins-economy.md:127-131`):

| play pattern | total coins/day | missions' 663.5 | share |
|---|---|---|---|
| 15 min/day (casual) | 3,118 | 663.5 | **21.3%** |
| 30 min/day | 4,292 | 663.5 | **15.5%** |
| 60 min/day (engaged) | 6,641 | 663.5 | **10.0%** |

The harder you play, the *less* the mission board matters — which is exactly backwards for a system
whose entire content is "play harder".

**Against the competing one-tap faucets** (`ProfileStore.swift:296` `dailyTiers`,
`:297` `chestInterval`, `:339-348` `openFreeChest`):

| faucet | pays | work required |
|---|---|---|
| daily login, streak ≥7 | **1,000** | one tap |
| free chest | mean **140** every 30 min, **no daily cap** | one tap, ×N |
| **entire daily mission board** | **345** | six-plus missions' worth of actual play |

**The daily login button pays 2.9× the whole daily mission board for one tap.** Four chest opens
across a day (≈ 560 coins) also beat it. The mission board is the *hardest* faucet in the game and
the *third*-largest of the meta faucets.

### 4.3 Against the sink

`s016_coins-economy.md:108-110`: permanent catalogue = **83,500 coins** (24,100 characters +
59,400 worlds).

- lifetime mission one-times: **12,320 = 14.75%** of the catalogue — real, but it arrives over
  months and 92% of it (the 11,350 achievement half) is back-loaded behind 100,000 m / 1,000 runs /
  10,000 gems.
- recurring 663.5/day against 83,500: **126 days** to buy the catalogue on missions alone, versus
  **12.6–26.8 days** on the full faucet (`s016_coins-economy.md:127-131`). Missions are a **21%
  accelerant on a clock that already runs out in under a month.**

### 4.4 The ruling

**"Almost nothing" is the correct reading of the coin half, and it IS the defect.** A player who
never opens the screen loses 8½ minutes of running per day and delays the catalogue by roughly
three weeks out of a four-week clock that the economy audit already calls the core monetization
problem (`s016_coins-economy.md:26`, finding C).

**But the coin half is not the whole answer, and the plan must not treat it as such.** The same
player also **permanently loses Drift, Facet and Wisp** — three of twenty-four characters, two
rare and one epic, unobtainable by any other route (§3.5, `SkinUnlocks.swift:12`). That is the only
thing the missions system produces that running cannot. It is worth more than all 12,320 coins put
together, and the screen never mentions it.

---

## 5. Q5 — DOES ANY MISSION CHANGE HOW THE GAME PLAYS?

### 5.1 Ruling: **no mission changes play. Not one. They are 100% pure payout.**

The chain is closed by three facts already established:
- The only outputs are coins + a claim receipt (`ProfileStore.swift:579-589`, §1.3).
- The receipt gates only cosmetics (`SkinUnlocks.swift:12` → `SkinCatalog` skins).
- Skins reach only the renderer: `renderer.applySkin(SkinCatalog.skin(store.equippedSkinID))`
  (`GameView.swift:853-855`). `Core/` never sees a `Skin` (iron rule 1) — **no skin can alter the
  hitbox, speed, or any predicate.** `Skin.scale` (`SkinCatalog.swift:166` etc.) is render-only.

The **indirect** path is coins → `buyConsumablePack` (`ProfileStore.swift:122-129`) → slow-mo /
speed-up / shield / head-start, which genuinely alter play (`s016_coins-economy.md:101-103`). But
that is not a mission consequence; it is a coin consequence, and running pays the same coins faster.

### 5.2 The corollary — the CHALLENGES section dies in week one

`Tuning.swift:149`: `streakPerMult = 5, multCap = 5` → `bestMult = min(5, 1 + bestStreak/5)`, so
`run.mult5` needs a 20-gem streak. `05_GAME_DESIGN.md:440-443` measured the multiplier chip at
**×5 in all 20 sampled frames from 143 m onward** — i.e. the first ~10 seconds of any run where
gems are collected. `run.slide5` counts slide **taps**, not bars (prior audit
`verify-catalog-missions-consequence.md`, CLAIM 3, confirmed against `GameCore.slide()`) — five
taps, trivial. `run.gems60` ≈ 1.5 km. `run.dist2k` = 2 km.

So five of six per-run feats fall inside the first hour. The board then renders those five as
permanent struck-through receipt rows (`MissionsView.swift:489-510`), under a header that still
reads `CHALLENGES · ONE-RUN FEATS` (`:246-261`). **19 cards on the board; 6 of them are
tombstones with a section header.**

*(Out of lane but load-bearing for the rebuild: that header also collides with the app's other
"challenge" — the Daily Rush / daily challenge (`ProfileStore.swift:601-651`), which has nothing
to do with this section. Two unrelated things named CHALLENGE, one screen apart.)*

---

## 6. Q6 — THE BIBLE VS THE SHIPPED SYSTEM

`docs/agent/05_GAME_DESIGN.md` never states what missions are *for*. It states what they **fail to
be**, four separate times. Quoted:

**§9, the retention table (`:508`):**

> | Daily / weekly missions | **Weak** | Real rotation, but claimable whenever; nothing decays. |

and one row below (`:509`):

> | Achievements | **Decoration** | One-time, no cadence. |

**§9 preamble (`:498`)** sets the test the table is scoring against:

> One question per hook: **does it give a reason to return tomorrow specifically?**

**§8 (`:459-461`)** names the exit condition:

> **What ends it:** boredom … the run stops escalating at 3,300 m and **the meta loop's payout does
> not change how the next run plays.**

**§10 (`:566`)**, ranked #2 of eight missing systems, D7 impact:

> | 2 | **A meta purchase that changes play** | D7 | The economy buys colours (§1). One permanent
> unlock altering a verb converts a decoration loop into a progression loop. |

**§12 (`:592-594`)**, third of the three things that should change first:

> 3. **Make one purchasable thing change how the game plays** (PR-0410). 83,500 coins of sink
> currently buy zero mechanical change; this is what makes the meta a decoration loop (§1).

### 6.1 The gap, stated exactly

The bible does not say missions are broken. **It says missions are a payout system feeding a
decoration loop, and it says that twice at SEV-equivalent priority.** Every finding in this file is
the missions-shaped instance of that one diagnosis:

| bible claim | this file's confirmation |
|---|---|
| "claimable whenever; nothing decays" (`:508`) | confirmed — `claimMission` has no expiry; `refreshDailyMissions` (`ProfileStore.swift:385-396`) wipes *progress and claims* on rollover, so an unclaimed daily is silently destroyed at UTC midnight with no warning anywhere. |
| "Achievements — decoration, one-time, no cadence" (`:509`) | confirmed and understated: they are also invisible to Game Center (§3.2) and the only ones with a real consequence (3 characters) never say so (§3.5). |
| "the meta loop's payout does not change how the next run plays" (`:460`) | confirmed at file:line — §5.1. |
| "the economy buys colours" (`:566`) | confirmed for missions specifically: the terminal reward of the entire achievement system is three **cosmetic** skins. |

**The gap that is the plan's spine:** the bible's remedy for the decoration loop is *"one permanent
unlock altering a verb"* (`:566`). **Missions are the single best-shaped delivery vehicle for that
remedy already in the codebase** — 18 authored tiers with progress tracking, deterministic UTC
rotation, cloud-merged state, a claim ceremony and a badge — and every one of those tiers currently
terminates in coins. The system's problem is not that it is missing; it is that **its output port
is wired to the wrong socket.**

---

## 7. WHAT THIS MEANS FOR THE PLAN

Ordered by (consequence restored) / (implementation cost). Cost is my estimate; none of it was
built or measured.

### 7.1 Wire the achievement ladders to something that is not coins — **highest value**

The bible's §10 #2 and §12 #3 both ask for one unlock that alters a verb. The 18 achievement tiers
already exist, already track, already merge. Candidates that respect the iron rules:

- **Terminal tiers grant a permanent power-up upgrade** (magnet radius, shield count, slow-mo
  duration) — this is exactly `s016_coins-economy.md:456`'s ranked-#2 "infinite non-arbitrage
  sink", except earned rather than bought. **Hard constraint carried forward from D-026: no rung
  may grant a coin multiplier.**
- **Name the character on the card.** `ach.dist` T1 must read `MARATHONER I · UNLOCKS DRIFT` with
  the skin's `bodyHex` swatch. One-directional today (§3.5, C). Cost: a lookup from
  `SkinCatalog.all` filtered on `.achievement(id:tier:)` — a pure function, Linux-testable,
  ~15 lines. **Decree 2 applies:** the swatch must be the real character, not an approximation.

### 7.2 Give completion a moment at the moment it happens

Two surfaces, both needed, and they are different shapes:

- **Death panel — an inline band, never a modal.** `GameOverView` already has the band idiom
  (`:192` coins+XP, `:284` challenge tier, `:303-345` XP/level/character). A fourth band listing
  the missions this run advanced or completed sits naturally beside them and does not tax the
  one-tap `RUN AGAIN` the bible calls correct (`05_GAME_DESIGN.md:454-456`).
  **Seam:** `applyRunSummary` (`ProfileStore.swift:427-479`) already computes every before/after
  value; it currently returns only `LevelUpResult`. Extending that return type with the crossed
  mission ids is a pure-Meta change and pins in Linux tests.
- **Claim ceremony — `RewardBurst`, on the right triggers.** §2.4. Add
  `.missionTier(name:unlocks:)` and `.claimAll(count:)`; keep the 80 ms cascade for small dailies.
  Reuse `ladder: [Int]` for tier ladders — the view already draws a highlighted rung.

### 7.3 Promote the surface on the hub

Missions is the only reward surface behind a nav glyph while a 1,000-coin login tap gets a
full-width gold bar (§2.3). Whatever the rebuild does visually, **an unclaimed 1,500-coin
achievement tier cannot stay a 12 pt purple digit.**

### 7.4 The economy fix is a *shape* fix, not a *number* fix

Do **not** simply raise `rewardCoins`. Raising the daily board from 345 to 1,000 makes missions
match the login button and does nothing about §5.1 — the payout still cannot change play, and it
accelerates the "whole catalogue free in 12–27 days" problem the economy audit calls SEV1
(`s016_coins-economy.md:26`). The defensible moves are (a) reward in something that is not coins
(§7.1), (b) make the recurring board pay a **rate multiplier on things the player is already
doing** rather than a flat lump, or (c) leave the coin numbers alone and fix visibility. **(a) is
the one the bible asks for.**

### 7.5 Retire the graveyard

Six permanent tombstones (§5.2). Options: retire the section once exhausted, rotate the per-run
feats like the daily pool does, or convert them into the on-ramp tier of the achievement ladders.
Any of these is better than a header that permanently reads `CHALLENGES · ONE-RUN FEATS` above six
struck-through lines.

---

## 8. LOOSE ENDS FOUND ALONG THE WAY

1. **`Mission.Metric.revives` is a dead case.** No mission in any pool uses it
   (`MissionCatalog.swift:90-140`, read in full). It has a glyph (`MissionsView.swift:526`) and a
   test arm (`MissionsTests.swift:34`) and pays nothing to anyone. Prior audit reached the same
   conclusion at SEV4 (`verify-catalog-missions-consequence.md`, CLAIM 1) — recorded so S-017 does
   not re-file it.
2. **An unclaimed daily is destroyed silently at UTC midnight.** `refreshDailyMissions`
   (`ProfileStore.swift:385-396`) removes both `missionProgress` and `claimedMissions` for the
   whole pool. Nothing warns the player, and the summary strip's countdown
   (`MissionsView.swift:97`) frames it as *"NEW BOARD IN 4H 12M"* — an arrival, not a deadline.
   **This is the one place the system has real stakes and it reads as a refresh.** Adjacent to
   D-050's "a countdown must be real and enforced in code" — here it already is real and is not
   presented as such.
3. **`day.chest2` and `ach.chests` are the only missions completable without playing.**
   `Metric.chestsOpened.value(in:)` returns 0 (`MissionCatalog.swift:61`); they are bumped by
   `openFreeChest` (`ProfileStore.swift:345`). `ach.chests` T2 = 100 chests × 30 min = **50 hours
   of elapsed app-open time** for 800 coins.
4. **Only one mission reward value is pinned by a literal in tests** — `run.mult5 == 150`
   (`MissionsTests.swift:113`, `:120`). Everything else asserts against `slot.rewardCoins`
   (`ProgressionTests.swift:285`), i.e. against the catalogue itself. **The reward curve has no
   regression guard.** If the rebuild re-costs the table, that is the moment to add one — and per
   the mandate, adding a pin is the only legal direction. Weakening `MissionsTests` /
   `ProgressionTests` to make a new curve pass is out of bounds.
5. **`unclaimedCount` mutates and persists the profile from inside `body`** — `MenuView.swift:345`
   → `ProfileStore.swift:593-599` → `refreshDailyMissions`/`refreshWeeklyMissions` → `mutate` →
   `save()` → `UserDefaults.set` + `cloud.synchronize()` on the main thread, once per minute per
   `TimelineView` tick. Known (`02_STATE.md:279`, `verify-catalog-missions-consequence.md` CLAIM 5).
   Not a "does nothing" finding; flagged because any rebuild touching the badge will meet it.

---

## 9. WHAT I DID NOT VERIFY

- **Nothing was built or run.** Read-only per the mandate: no `xcodebuild`, no `swift test`, no
  `simctl`. Every behavioural claim is read from source, and the two measured figures (78.3
  coins/min; ×5 within ~10 s) are carried from S-011's headless probe and the design bible's
  screenshot pass respectively, cited at both ends.
- **The 8 min 29 s figure inherits the S-011 bot's faucet.** The bot never chases gems
  (`s016_coins-economy.md:62-63`), so 78.3 coins/min is a **floor** for a human — meaning the true
  "missions are worth N minutes of running" number is **lower** than 8.5, not higher. The finding
  is conservative in the direction that matters.
- **I did not audit the missions screen's visual craft or its information hierarchy.** Those are
  complaints 1 and 3; `s016_design-system.md:215` (four bespoke tints on one screen) and `:442`
  (its proposed remedy) are the standing prior art.
- **I did not price any proposed replacement reward.** §7 names shapes, not numbers. Any new curve
  has to be costed against `s016_coins-economy.md` §1.5 before it ships.
