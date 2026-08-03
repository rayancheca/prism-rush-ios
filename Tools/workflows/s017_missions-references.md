# S-017 — `missions-references`: how shipped mobile games actually structure missions

Investigator output for pass 017 (the MISSIONS rebuild). **READ-ONLY session**: nothing outside this
file was edited, no build, no `simctl`, no test run. Every Prism Rush claim carries `file:line`
against HEAD `ba9655d`. Every reference claim carries a URL. Anything I looked for and could not
source is marked **NOT FOUND** with the query that failed.

This file is the *reference* half of pass 017. It deliberately does **not** re-derive the economy
(that is `s016_coins-economy.md`) or the visual system (`s016_design-system.md`), and it builds on
rather than repeats `s016_subway-reference.md` — which covered the *run loop and the box*, not the
mission system. Where the two overlap I say so and cite the earlier file.

---

## 0. THE LEGAL LINE — STATED EXPLICITLY, AS INSTRUCTED

The owner said *"ciopy subway surfers"* (`docs/agent/audits/scratch/s016_mandate.md:11`). For the
mission system specifically, that resolves as:

**WE COPY — structure and pacing only:**
- the **set-of-three** unit of work, and the fact that a *set*, not a single task, is what pays;
- the **permanent power** payout shape (a number that makes every future run better);
- the **inline-on-the-hub** surfacing (missions live where you already stand, not behind a door);
- the mission-*type* vocabulary: single-run vs cumulative, self-constraint, cross-surface, social;
- the **skip** valve, the **streak ladder**, the **honest countdown**;
- the reward-moment beat structure.

**WE DO NOT COPY, EVER — and this is not negotiable by the owner or by any downstream ticket:**
Subway Surfers' art, models, textures, animations, sounds, music, fonts, UI iconography, mission
*wording*, the words "Subway", "Surfers", "Word Hunt", "Season Hunt", "Mystery Box"† as a branded
name, "Hoverboard", "Super Sneakers", "Jetpack", "Pogo Stick", "Headstart", "Score Booster",
character names (Jake, Tricky, Fresh, Yutani, Spike…), the graffiti logo, or any SYBO/Kiloo
trademark. Not as a placeholder, not "for the mockup", not "we'll rename before ship". The mission
tables reproduced in §1.3 below are **evidence of a structure**, not copy to paste. Every string
Prism Rush ships must be written fresh in Prism Rush's own voice.

† `MysteryBoxView.swift` already ships the term "Mystery Box". That predates this session and is a
standing risk item, not something S-017 introduced; it is a generic descriptive phrase in wide use
across the industry, but it is worth a deliberate naming decision before ship. Flagging, not fixing.

Also surviving and non-waivable: App Store guideline **3.1.1 loot-box odds disclosure** applies to
anything a mission *pays out* as a randomised box (`MysteryBoxView.swift:67-81`,
`ShopValue.swift:156-163` already comply). And the Epic/ACM precedent in §5.4 makes a *fake*
mission countdown a regulatory problem, not merely a taste problem.

---

## 1. SUBWAY SURFERS — THE MISSION SYSTEM, IN FULL

Source for everything in §1 unless otherwise noted:
[Missions wiki](https://subwaysurf.fandom.com/wiki/Missions), read 2026-08-03 through the browser
pane. (`WebFetch` on `subwaysurf.fandom.com` returns HTTP 402 and on `sybo.helpshift.com` HTTP 403 —
same as recorded at `s016_subway-reference.md:486-488`. The browser pane reads them fine.)

### 1.1 The four answers the brief asked for

| Question | Answer | Source |
|---|---|---|
| **How many missions are active at once?** | **Exactly 3.** "Each mission set has 3 missions." One set is live; you never see set N+1 until set N is done. | [Missions wiki](https://subwaysurf.fandom.com/wiki/Missions) |
| **How are they surfaced?** | **Inline, on the hub, always visible.** "You can find it at the top-left part of your screen when not playing. Pausing your game can also lead you to it." Not a screen you navigate to — a persistent corner widget, plus a second entry point *inside the pause menu mid-run*. | [Missions wiki](https://subwaysurf.fandom.com/wiki/Missions) |
| **What do they pay relative to a run?** | **They pay no currency at all.** A completed *set* pays **+1 permanent score multiplier**. Not coins, not keys. | [Missions wiki](https://subwaysurf.fandom.com/wiki/Missions), [Multiplier wiki](https://subwaysurf.fandom.com/wiki/Multiplier) |
| **What happens when you complete a set?** | Multiplier +1, capped at **×30** (**×34** with Collections). Past the cap the set reward is **replaced by a Super Mystery Box** — the ladder never dead-ends. | [Missions wiki](https://subwaysurf.fandom.com/wiki/Missions), [Multiplier wiki](https://subwaysurf.fandom.com/wiki/Multiplier) |

**This is the single most important finding in the whole file.** The complaint the owner filed —
*"not rewarding at all"* — has a structural cause and Subway solved it by **not paying currency**.
A currency payout is worth whatever the currency is worth, and `s016_coins-economy.md:117-152`
already proved Prism Rush's currency is worth very little (whole catalogue affordable in 13–27 days;
62% of a casual player's income requires no skill). Subway's mission reward is denominated in a thing
that **cannot be saturated and cannot be bought**: the score curve itself.

### 1.2 The multiplier maths — why the curve feels good early and still works late

The multiplier is permanent meta progression, raised **only** by mission sets, the Score Booster, the
2× Multiplier pickup and the Super Mysterizer ([Multiplier wiki](https://subwaysurf.fandom.com/wiki/Multiplier)).
Set N takes you from ×N to ×(N+1), i.e. **+1/N of all future score**:

| set completed | multiplier | marginal gain to every future run |
|---|---|---|
| 1 | ×1 → ×2 | **+100%** |
| 4 | ×4 → ×5 | +25% |
| 10 | ×10 → ×11 | +10% |
| 29 | ×29 → ×30 | +3.4% |
| 30+ | capped | **a Super Mystery Box per set** |

Decelerating but never zero, and the *cap has a successor reward*. Contrast Temple Run 2, which pays
**+1 per individual objective** off a **×10 base** to a **×67 max** — a shallower per-step gain but
three times as many payout events
([Objectives (Temple Run 2)](https://templerun.fandom.com/wiki/Objectives_(Temple_Run_2)),
[Temple Run 2 Objectives support](https://templerun2.zendesk.com/hc/en-us/articles/1500009158462-Objectives) —
support page 403s to `WebFetch`, figures taken from the search-index summary of both pages and the
wiki, so treat the ×67 as **corroborated-but-not-primary**).

### 1.3 The mission list — evidence of the type vocabulary (NOT copy)

Sets 1–29, verbatim from the wiki, reproduced here **only** to show the distribution of mission
*kinds*. Do not ship these strings.

| Set | M1 | M2 | M3 |
|---|---|---|---|
| 1 | Pick up 100 Coins | Score 500 points in one run | Complete 1 Word Hunt |
| 2 | Pick up 100 Coins in one run | Jump 15 times | Pick up 2 Pogo Sticks |
| 3 | Score 10000 points | Roll 15 times | **Spend 500 Coins** |
| 4 | Pick up 200 Coins in one run | Pick up 3 Magnets | Score 6000 points in one run |
| 5 | Pick up 2500 Coins | Jump 30 times in one run | **Buy 1 Mystery Box** |
| 6 | Use 1 Hoverboard | Pick up 5 Magnets | **Beat your own high score** |
| 7 | Pick up 2 Jetpacks | Pick up 50 Coins with Jetpack | **Use 1 Headstart** |
| 8 | **Stumble into 3 trains in one run** | Pick up 40 Coins with Magnet | **Get caught in 10 seconds** |
| 9 | Use 2 Hoverboards | Pick up 2 Mystery Boxes | Roll 30 times in one run |
| 10 | Score 20000 points in one run | Pick up 12 Powerups | Collect 2000 Coins |
| 11 | **Score 4000 points without picking up any Coins** | **Roll 50 times while on the middle lane** | Pick up 5000 Coins |
| 12 | Complete 2 Word Hunts | Dodge 40 barriers | Pick up 5 Super Sneakers |
| 15 | Score 100000 points | Pick up 5 Jetpacks | **Stumble into 12 light signals** |
| 23 | **Pick up 50 Coins while in the air** | Collect 10000 Coins | Pick up 15 Jetpacks |
| 25 | Pick up 15000 Coins | Score 120000 points in one run | **Pick up 15 Powerups while on the left lane** |
| 26 | Roll 50 times in one run | Collect 30000 Coins | **Score 12000 points without picking up any Coins** |

Sorting those into kinds gives the design vocabulary:

| Kind | Example | What it does to the player |
|---|---|---|
| **Cumulative** | "Pick up 5000 Coins" | ambient; completes itself |
| **Single-run** | "Score 20000 points in one run" | forces a *good* run, not just runs |
| **Self-constraint** | "Score 4000 points **without picking up any Coins**"; "Roll 50 times **while on the middle lane**"; "Pick up 15 Powerups **while on the left lane**"; "Pick up 50 Coins **while in the air**" | **changes how the game is played** |
| **Deliberate failure** | "**Get caught in 10 seconds**"; "Stumble into 3 trains in one run"; "Stumble into 12 light signals" | inverts the goal; comic; trivially completable so it is a free win in a hard set |
| **Cross-surface** | "**Spend** 500 Coins"; "**Buy** 1 Mystery Box"; "Use 1 Headstart"; "Complete 1 Word Hunt" | routes traffic into the shop and the daily |
| **Social** | "Beat a friend's score"; "Beat your own high score" | the wiki notes the friend one is a common **forced skip** — see §5.2 |
| **Meta-referential** | past the cap, a mission that asks you to **skip a mission** | the wiki notes the exploit: skip a *different* one in the same set and clear two for one |

The wiki additionally lists mission kinds not in the table above: collect N of a specific power-up,
use N hoverboards, collect N keys, collect N Word-Hunt tokens, run in one lane for N seconds.

Also: **the further you go, the harder and longer they get** ("The further you progress through the
missions, the harder they become. As well they'll cost more time to accomplish"). The wiki gallery
shows sets up to **182**, so the ladder is ≥546 authored missions and the total is "currently unknown".

### 1.4 The skip valve

"It's possible to skip a mission by paying with collected coins or watching an ad"
([Missions wiki](https://subwaysurf.fandom.com/wiki/Missions)). **NOT FOUND:** the coin price of a
skip, and whether it scales with set number. Searched
`Subway Surfers missions list examples "set" skip missions cost coins` — every result restates that a
skip exists without a number; the official help centre (`sybo.helpshift.com/hc/en/5-subway-surfers/faq/143-missions/`)
403s. Do not let a downstream ticket invent a figure and attribute it.

The skip matters more than its price. It is the release valve for the failure mode in §5.2: without
it, one impossible mission ("beat a friend's score" with no friends) **hard-blocks the entire
progression ladder** because the multiplier only advances on a *complete set*.

### 1.5 Subway's mission surface is DISTRIBUTED, not one screen

This is the second big structural finding. "Missions" is one of at least six overlapping objective
systems, each with its own cadence, its own reward *class*, and its own home:

| System | Cadence | Where | Reward class | Source |
|---|---|---|---|---|
| **Missions** | untimed ladder, sets of 3 | hub top-left + pause menu | permanent multiplier → Super box past ×30 | [Missions](https://subwaysurf.fandom.com/wiki/Missions) |
| **Word Hunt** (was "Daily Challenge") | daily, ~5 min | Hunt tab + **pause menu** | streak ladder, see below | [Word Hunt](https://subwaysurf.fandom.com/wiki/Word_Hunt) |
| **Season Hunt** | ~3-week event | Hunt tab | characters, boards, outfits, **and gameplay upgrades** | [Season Hunt](https://subwaysurf.fandom.com/wiki/Season_Hunt) |
| **Collections** | untimed sets of characters/boards | Collections screen | coins (10,000 / 25,000), keys (30 / 15), **permanent ×3 and ×1 score multipliers** | [Collections](https://subwaysurf.fandom.com/wiki/Collections) |
| **Daily Rewards** | daily login | modal | fixed 5-step ladder | `s016_subway-reference.md:318` |
| **Season Pass** (SYBO's *Subway Surfers City*) | seasonal | pass screen | token ladder; premium track is an IAP that **adds bonus daily and seasonal missions** | [Season Pass](https://subway-surfer-city.fandom.com/wiki/Season_Pass) via search index — direct browser nav to that origin was denied, see §8 |

**Word Hunt streak ladder** ([Word Hunt](https://subwaysurf.fandom.com/wiki/Word_Hunt)):
day 1 (or after a break) → a Mini box; day 2 → a box; **day 3 → 1,050 coins; day 4 → 1,500 coins;
day 5+ → a Super Mystery Box, every day**. The ladder pays *boxes at the top and coins in the
middle*, which is the opposite of Prism Rush's all-coin ladder.

**Word Hunt also carries a negative-reinforcement hook that is worth naming even though we should
not copy it**: *"If the player does not want to complete the Word Hunt, they will have a lower chance
of finding any power-ups unless they use a Headstart (except the Pogo Stick and Jetpack) until they
collect all the letters."* That is a **penalty for not doing the daily** — a nerf to the core loop
until you comply. It is effective and it is exactly the "obligation/chore" pattern the CHI PLAY work
in §5.1 identifies as harmful. **Recommendation: do not port this.** It is the clearest case in the
whole reference set of a mechanic that boosts a metric and damages the player.

The Word Hunt letters are also a masterclass in *interaction* design: letters spawn in-run, the
**Coin Magnet does not attract them** (so the daily can't be trivialised by a power-up), but **Super
Sneakers can jump-collect them** (so a *different* power-up is rewarded). One collectible, wired
deliberately into two power-ups with opposite answers.

---

## 2. CONTRAST — WHERE OTHER GAMES PUT MISSIONS IN THE UI HIERARCHY

| Game | Active at once | Where in the hierarchy | Reward | Source |
|---|---|---|---|---|
| **Subway Surfers** | **3** | **corner of the hub, and in the pause menu mid-run** | permanent ×1 multiplier per set | [Missions](https://subwaysurf.fandom.com/wiki/Missions) |
| **Temple Run 2** | **3** ("three objectives will appear in the queue… a player can only complete three goals at any given time") | objectives queue on the main screen | **+1 multiplier per objective**, ×10 base → ×67 max; also coins, gems, power-up unlocks | [Objectives (TR2)](https://templerun.fandom.com/wiki/Objectives_(Temple_Run_2)), [TR2 support](https://templerun2.zendesk.com/hc/en-us/articles/1500009158462-Objectives) |
| **Alto's Odyssey** | **3** (per level) | **goals ARE the progression spine** — 60 levels × 3 hand-crafted goals = **180 goals**; the level gates the next tier | no currency for the goal itself; levels unlock characters/features | [Team Alto press kit](http://altosodyssey.com/press/sheet.php?p=altos_odyssey), [Goals (Alto's Odyssey Wiki)](https://altosodyssey.fandom.com/wiki/Goals) |
| **Candy Crush Saga** | **3 or 5 sets per day** | **a side rail on the home page** — "the quests are located on the side of the home page. To see the list of quests, click the icon to open" | boosters/items | [Daily quests (Candy Crush Jelly Wiki)](https://candycrushjelly.fandom.com/wiki/Daily_quests), [Quests (Soda Wiki)](https://candycrushsoda.fandom.com/wiki/Quests) |
| **Crossy Road** | daily challenge is a **mode**, not a mission list ("Pecking Order") | its own mode entry; resets every 24 h; global rank ladder | tokens → token-only mascots; converts to coins once exhausted | [Pecking Order](https://crossyroad.fandom.com/wiki/Pecking_Order) |
| **Disney Crossy Road** | daily missions exist as a distinct system | — | — | [Daily Missions](https://disneycrossyroad.fandom.com/wiki/Daily_Missions) — **NOT FOUND**: the count and reward. `appsupport.disney.com` 403s and the fandom origin could not be opened in the browser pane |

**Four of the five converge on THREE.** Nobody shows nineteen. Alto's is the extreme case: the goal
triplet is not a side-feature at all, it *is* the game's progression — 180 goals in triplets, and the
game ships with **no ads and no IAP** ([Alto's Odyssey](https://en.wikipedia.org/wiki/Alto%27s_Odyssey)),
so the goals cannot be paying for anything except themselves. That is the existence proof that a
mission system can be motivating with **zero** currency attached.

Alto's goals are also almost entirely **self-constraint** missions — "Backflip through a waterfall",
"Wallride to grind 3 times in one run", "Rock bounce onto a grind", "Land 2 double backflips in one
run", "Wallride to grind to backflip"
([Alto's Odyssey guide, appunwrapper](https://www.appunwrapper.com/2018/02/21/altos-odyssey-walkthrough-guide-tips-and-tricks/) —
the goals-list page 403s to `WebFetch`; wording is from the search index of that page and the wiki,
so treat individual strings as **corroborated-but-not-primary**). They function as a **trick
curriculum**: the goal list is how you learn the verb vocabulary exists.

---

## 3. THE PATTERNS WORTH STEALING — the five questions, answered

### 3.1 How is progress shown so it is legible in under a second?

The convergent answer across all five references is **three cards, one screen region, one visual
grammar** — legibility comes from *count*, not from the individual widget.

- Subway: three rows, per-row completion marks. The wiki's own gallery captions read
  *"Mission Set 79 - 1&2 completed"*, *"Mission Set 160 - 1 and 3 completed"*, *"Mission Set 92 - 1
  completed"* — i.e. the state a screenshotter reads off the card is *which of the three are done*,
  a 3-bit read.
- Temple Run 2: a queue of exactly three; you cannot hold a fourth.
- Candy Crush: a collapsed side rail with an icon — closed by default, expanded on tap. The board is
  **not** competing with the play button for attention until you ask for it.
- Deconstructor of Fun's rule, from the canonical industry write-up: Destiny succeeds through
  "clear messaging" with **"categories"** so "players can quickly process and choose"; Vainglory
  failed on "confusing surfacing"
  ([The Making Of A Mechanic: Daily Goals](https://www.deconstructoroffun.com/blog//2016/07/the-making-of-mechanic-daily-goals.html)).

The supporting psychology, if a ticket wants it: the **goal-gradient effect** (Hull) — effort
accelerates as the goal nears, "the last 10% of a progress bar feels extra motivating" — and the
**endowed progress effect**, where starting a bar at non-zero measurably raises completion
([Goal Gradient Effect, Learning Loop](https://learningloop.io/plays/psychology/goal-gradient-effect),
[Endowed progress effect, UX Collective](https://uxdesign.cc/endowed-progress-effect-give-your-users-a-head-start-97d52d8b0396)).
Both argue for **fewer bars, further along** rather than many bars near zero.

### 3.2 How do they make a mission feel worth doing?

Ranked by how often it appears in the reference set:

1. **Permanent power, not currency.** Subway (+1 mult/set → ×30), Temple Run 2 (+1 mult/objective →
   ×67), Collections (permanent ×3 / ×1), Sonic Dash (per-character permanent multiplier), Temple
   Run 2's purchased global upgrades (Coin Value +250%, Utility Belt −50% recharge)
   (`s016_subway-reference.md:349-354, 366-372`). **All five references have a permanent power curve.
   Prism Rush is the only one with none** — a point `s016_subway-reference.md:378-380` already made
   about the game as a whole, and which lands hardest here because missions are where the others
   *pay* it.
2. **The SET, not the task, is the payout unit.** Subway and Alto both refuse to pay per-mission.
   Three completions buy one meaningful thing instead of three forgettable things. This is the
   cheapest available fix for "not rewarding": the same total value, delivered once instead of thrice.
3. **The cap has a successor.** Past ×30 a Subway set pays a **Super Mystery Box** — the best box in
   the game. The ladder never becomes pointless.
4. **Reward magnitude is benchmarked against real play.** Deconstructor of Fun cites Hearthstone,
   where a quest reward equals **"a dozen wins or more"**, and flags Heroes of the Storm as the
   failure case because completion took "multiple hours"
   ([DoF](https://www.deconstructoroffun.com/blog//2016/07/the-making-of-mechanic-daily-goals.html)).
   The rule is a ratio, not an absolute.
5. **Unlocks, not just numbers.** Alto's levels gate features; Season Hunt tiers pay characters,
   boards, outfits **and gameplay upgrades** — the Season Hunt "List of Hunt Upgrades" is literally
   *Super Speed, Double Jump, Smooth Drift* ([Season Hunt](https://subwaysurf.fandom.com/wiki/Season_Hunt)).

### 3.3 How do they handle the empty / first-launch state?

- **Subway set 1 is deliberately trivial**: "Pick up 100 Coins", "Score 500 points in one run",
  "Complete 1 Word Hunt". You clear it in two or three runs, and the reward is the **largest single
  multiplier gain in the game (+100%)**. First-launch is where the payout curve is at its steepest —
  the opposite of a ramp.
- Apple's own guidance: *"During your initial onboarding efforts, show players the benefit of
  routinely returning to your game… Make sure the benefits are compelling and reinforce your game's
  main objectives"* and *"Introduce gameplay objectives so that they intuitively build on one
  another. Begin with basic elements and allow players to demonstrate competency before moving on to
  advanced objectives"*
  ([Onboarding for Games, Apple Developer](https://developer.apple.com/app-store/onboarding-for-games/)).
- General empty-state doctrine: an empty state should *say why it is empty and invite an action* —
  it is a teaching surface, not a blank.

The reference answer to "what does a brand-new mission board look like" is therefore: **not a full
board at 0%. A first set that is nearly free, with the biggest reward attached.**

### 3.4 Do missions ever change how the game PLAYS, or are they always payout?

**They routinely change how it plays — this is the norm, not the exception.** Three distinct
mechanisms in the reference set:

1. **Self-constraint missions** (§1.3): "Score 4000 points without picking up any Coins", "Roll 50
   times while on the middle lane", "Pick up 15 Powerups while on the left lane", "Pick up 50 Coins
   while in the air". These re-define the win condition for a run.
2. **Deliberate-failure missions**: "Get caught in 10 seconds", "Stumble into 3 trains in one run".
   The wiki notes these are trivially completable — *"just swiping your character towards a train"* —
   which makes them a free win deliberately planted inside an otherwise hard set.
3. **Missions that award new verbs**: Season Hunt upgrades are **Super Speed, Double Jump, Smooth
   Drift** ([Season Hunt](https://subwaysurf.fandom.com/wiki/Season_Hunt)); Temple Run 2 objectives
   "unlock new powerups and abilities"
   ([Objectives (TR2)](https://templerun.fandom.com/wiki/Objectives_(Temple_Run_2))). Alto's entire
   goal list is a trick curriculum (§2).

There is also a fourth, **negative** mechanism — Word Hunt's power-up-drought penalty (§1.5) — which
I recommend explicitly against porting.

### 3.5 How is reset/expiry communicated without manufacturing fake urgency?

The line the references draw is: **a countdown is honest if and only if the thing actually stops when
it hits zero.** The regulatory anchor is real — the Dutch ACM fined Epic Games over a 24-hour
countdown on items that *remained available after expiry*, finding that false claims of limited
availability exploit FOMO, particularly in children
([Stibbe on the ACM/Epic decision](https://www.stibbe.com/publications-and-insights/game-over-for-dark-patterns-acm-fines-epic-for-unfairly-targeting)).
The deceptive-patterns taxonomy names exactly two offences: **fake countdown timers** (a timer that
reaches zero without the offer ending) and **fake limited-time messages**
([Deceptive Patterns — Fake urgency](https://www.deceptive.design/types/fake-urgency),
[Chapter 15: Urgency](https://www.deceptive.design/book/contents/chapter-15)).

The permissive half of the same guidance: *"If your offer is only available for a limited time, tell
the user when it ends."* Stating a real deadline is not a dark pattern; it is the honest alternative.

The structural version of this is Subway's: **the untimed ladder carries the value.** Missions have
no clock at all — only the Word Hunt and the Season Hunt do. Nothing that matters expires, so there is
nothing to fake.

---

## 4. WHAT PRISM RUSH DOES TODAY — the baseline, with cites

### 4.1 The board

Nineteen cards on one scroll, in four tinted sections:

| Section | Count | Cite |
|---|---|---|
| CHALLENGES (per-run feats) | **6** | `PrismRush/Meta/MissionCatalog.swift:90-97` |
| TODAY (daily slots) | **3** drawn from a pool of 8 | `MissionCatalog.swift:100-109`, `:152-160` |
| THIS WEEK (weekly slots) | **3** drawn from a pool of 7 | `MissionCatalog.swift:114-122`, `:168-176` |
| ACHIEVEMENTS (tiered ladders) | **7** ladders, 2–3 tiers each | `MissionCatalog.swift:125-140` |
| **Total rendered at once** | **19** | `PrismRush/UI/MissionsView.swift:41-48`, `:159-162` |

Four section tints compete on that one scroll: gold `0xFFB13D`, purple `0xB26BFF`, cyan `0x00F5FF`,
green `0x00FF88` (`MissionsView.swift:25-28`).

Entry point: a nav-rail item, one of four exits under a hairline on the hub, with an unclaimed count
badge (`MissionsView` reached via `MenuView.swift:343-346`; sheet case at `GameView.swift:1236`;
also reachable from `ProfileView.swift:185` and `CharacterSelectView.swift:293`). **It is a door you
walk through, not a widget you stand next to** — the opposite of Subway's hub corner and Candy
Crush's side rail. There is **no in-run/pause entry point**.

### 4.2 The payout — this is the "not rewarding" defect, quantified

`claimMission` does exactly one thing: `$0.coins += state.reward`
(`PrismRush/Meta/ProfileStore.swift:585-586`). No multiplier, no box, no unlock, no collection
progress. Coins, and nothing else, from every one of the 21+ missions.

Against the measured economy in `s016_coins-economy.md:57` (headless Autopilot probe, 24 seeds,
mult = 1) and the meta faucet at `:67-89`:

| thing | coins | notes |
|---|---|---|
| **mean daily mission** | **115** | 80–140, `MissionCatalog.swift:100-109` |
| **one tap on the free chest** | **140** (mean of 60…220) | every 30 min, **no daily cap**, `ProfileStore.swift:297`, `:339-348` |
| a 3,300 m run (2 min 17 s) | 179 | `s016_coins-economy.md:57` |
| **day-7 login bonus** | **1,000** | for opening the app, `ProfileStore.swift:296`, `:315-317` |
| mean weekly mission | 743 | 600–900, `MissionCatalog.swift:114-122` |

**A single tap on a chest, requiring no play at all, out-pays the average daily mission (140 > 115).
The day-7 login bonus alone out-pays the entire daily mission board (1,000 > 345) and beats the mean
weekly mission (1,000 > 743).** That is the arithmetic behind "not rewarding at all", and no amount
of visual craft moves it.

Lifetime scale: per-run feats 970 + achievement ladders 11,350 = **12,320 coins**, i.e. **14.8% of
the 83,500-coin permanent catalogue** (`s016_coins-economy.md:80-89`, `:107-109`) — earned over the
whole life of the account, in a catalogue that `s016_coins-economy.md:129-140` shows is fully
affordable in **13–27 days** anyway.

### 4.3 The "does nothing" defect

Of the 21 catalogued missions, **19 are passively observed** from `RunSummary` — every metric in
`Mission.Metric.value(in:)` reads a field the run already counted
(`MissionCatalog.swift:51-66`). The player is never asked to do anything they would not do by
playing normally, which is precisely the Vainglory failure mode Deconstructor of Fun names: quests
that are "things that the player will do just by playing the game as they regularly do".

- **Zero self-constraint missions.** No "without", no "only in lane N", no "without using the Blast".
  There is no metric that could express one: the `Metric` enum has no lane, no blast-count, no
  gem-abstinence, no damage-taken field (`MissionCatalog.swift:34-41`).
- **Exactly two cross-surface missions** in the whole catalogue — `day.chest2` "Open 2 free chests
  today" (`MissionCatalog.swift:108`) and `ach.chests` (`:138-139`), both pointing at the same
  surface. Nothing points at the shop, the Mystery Box, the character select, the daily challenge,
  or a world.
- **Nothing references the Warden's existence beyond a kill count** (`run.warden1`,
  `MissionCatalog.swift:96`).
- **`chestsOpened` returns a hardcoded `0` from `value(in:)`** (`MissionCatalog.swift:61`) — it is
  bumped out-of-band by `ProfileStore.openFreeChest`. Worth noting as a seam if new metrics are added
  the same way.

### 4.4 The "not easy to understand" defect

The card itself is competent: a 44 pt progress ring, a metric glyph, `progress/target` in monospaced
digits, a reward pill (`MissionsView.swift:369-422`, `:441-472`). The legibility failure is at board
level, not card level:

1. **Nineteen rings, four tints, one scroll.** The under-a-second read has 19 competing targets.
2. **Every ring animates from 0 on appear** — `appeared` starts `false`, the ring shows `0` until
   `.onAppear` fires and then eases over **0.7 s** (`MissionsView.swift:342`, `:397`, `:405-406`,
   `:419`). For the first ~0.7 s of the screen, *every mission reads as untouched*. This is an actual
   defect against the "legible in under a second" test, and it is one line to fix.
3. **Two different countdown formats on the same screen**: TODAY says `RESETS 7H 12M`, THIS WEEK says
   `RESETS 3D` (`MissionsView.swift:285-289`, `:297-300`).
4. `compactCount` renders 20,000 m as `20k` and 3,000 m as `3.0k` (`MissionsView.swift:539-543`) —
   two different precisions in the same column.

### 4.5 What is already RIGHT — do not regress these

Named explicitly so a rebuild does not throw them away:

- **The countdown is honest.** It states a real UTC deadline and the deadline is *enforced in code*:
  `claimMission` refreshes the boards first and rejects a claim whose mission is not in today's /
  this week's slots (`ProfileStore.swift:568-578`). That is the compliant side of the ACM/Epic line
  in §3.5. Tick is per-minute, not per-second (`MissionsView.swift:35`), which deliberately demotes
  the clock rather than dramatising it.
- **The three-state summary strip.** `MissionBoardSummary` distinguishes `claimable` / `open` /
  `allClear` precisely because a fresh board used to render `ALL CLEAR` — the comment at
  `ProfileStore.swift:513-517` records the bug (PR-0304). The empty-state problem was already
  diagnosed once here; the rebuild must not reintroduce it.
- **Gold means money.** The coin glyph appears only where coins are actually waiting
  (`MissionsView.swift:308-309`) — consistent with decree 6's role-based colour.
- **CLAIM ALL resolves every claim against the same `now`** that rendered the board, so a UTC
  rollover mid-cascade cannot pay less than the button promised (`MissionsView.swift:125-137`).
- **A11y is complete** — every card, header and summary has a spoken label
  (`MissionsView.swift:88-90`, `:213-214`, `:398-399`, `:531-537`).

---

## 5. ANTI-PATTERNS — what players actually complain about

### 5.1 "It's a chore" — the peer-reviewed version

*Daily Quests or Daily Pests? The Benefits and Pitfalls of Engagement Rewards in Games*, CHI PLAY /
PACM HCI, 2022 ([ACM DL](https://dl.acm.org/doi/10.1145/3549489),
[Utrecht University portal](https://research-portal.uu.nl/en/publications/daily-quests-or-daily-pests-the-benefits-and-pitfalls-of-engageme)).
178 participants, mixed-methods survey with validated motivation-regulation and passion-orientation
scales. Findings, in the authors' framing: players perceive engagement rewards **as beneficial (e.g.
motivation), as negative (e.g. promoting fear of missing out), or as an obligation or chore**;
**natural interaction with engagement rewards was associated with more intrinsically motivated play
and lower amotivation**; the paper explicitly frames these as potential **dark patterns**.

The operative word is **natural**. A mission you complete *by playing the way you wanted to play*
correlates with healthy motivation. A mission that redirects your session into tasks correlates with
obligation. Note the tension with §3.4: self-constraint missions *do* redirect play. The resolution
the references support is **opt-in redirection** — a set of three where at least one is naturally
satisfied, so the player chooses whether to chase the constrained ones.

### 5.2 The blocking mission

Subway's own wiki documents this against Subway: the "beat a friend's score" mission "may look easy
but it is actually hard especially for people who don't have any friends in the game or being the top
score among his friends, **forcing them to skip it with coins**"
([Missions](https://subwaysurf.fandom.com/wiki/Missions)). A set-gated ladder turns any single
unachievable mission into a **hard stop on all progression**. The skip valve exists because of this
failure, not as a monetisation flourish.

**Direct implication for Prism Rush:** `run.warden1` ("Defeat a Warden", `MissionCatalog.swift:96`)
is exactly this shape for a weak player. Today it is harmless because the board is flat and one stuck
card blocks nothing. **The moment sets gate progression, it becomes a wall — so a set design must
ship with a skip, or with per-mission independence, in the same PR.**

### 5.3 Rewards that don't justify the time

Deconstructor of Fun's failure case is Heroes of the Storm, where quest completion took "multiple
hours", creating a frustrating imbalance; the success case is Hearthstone, where the reward equals "a
dozen wins or more"
([DoF](https://www.deconstructoroffun.com/blog//2016/07/the-making-of-mechanic-daily-goals.html)).
The general complaint pattern in player forums is "insane grind for the sake of grind with very
little payout", and — relevant to weeklies specifically — that time-locked weekly bonus missions
**punish players who cannot play as much**.

**Prism Rush's weeklies are on the wrong side of this**: `wk.dist20k` is 20,000 m for 800 coins
(`MissionCatalog.swift:116`), i.e. ~6 runs of 3,300 m ≈ 14 minutes of play for less than one day-7
login bonus.

### 5.4 Fake urgency

Covered in §3.5. The enforcement precedent (ACM v. Epic) makes this a compliance item, not a taste
item, and decree 5 already forbids it. **Prism Rush is currently clean here** (§4.5) and the rebuild
must stay clean — in particular, if pass 017 adds the "real countdown offers" that D-050 authorises,
the mission board is the wrong place to host them.

### 5.5 Confusing surfacing

Vainglory is DoF's named failure for "confusing surfacing"; Destiny is the named success, via
categories that let "players quickly process and choose". Prism Rush's board has categories
(`MissionsView.swift:41-48`) — it has *too many things inside them*.

### 5.6 The negative-reinforcement daily

Word Hunt's power-up drought (§1.5). Effective, ships in a 4.5-billion-download game, and is the
purest available example of a mechanic that raises a metric by making the game worse for
non-compliers. **Named here so nobody rediscovers it in three weeks and calls it a good idea.**

---

## 6. SYNTHESIS — RANKED, WITH (a) reference (b) Prism Rush today (c) change (d) cost

Cost key, same as `s016_subway-reference.md:383`: **S** ≈ under a day, **M** ≈ 1–2 days,
**L** ≈ 3+ days or a `layoutVersion` bump.

### 1. Pay a permanent score multiplier for a completed SET — stop paying coins per task
- **(a)** Subway: 3 missions → **+1 permanent multiplier**, cap ×30 (×34 with Collections), and past
  the cap each set pays a Super Mystery Box. Temple Run 2: +1 per objective, ×10 → ×67. Collections:
  permanent ×3 / ×1. Sonic Dash: permanent per-character multiplier. **All five references pay
  permanent power; none pays a coin drip.**
- **(b)** `claimMission` adds coins and nothing else (`ProfileStore.swift:585-586`). The only
  multiplier in the game is the in-run gem streak, **capped at ×5 and reset every run**
  (`Tuning.swift:149`). `Profile.coinMultiplier` is an IAP coin doubler, not a score multiplier
  (`Profile.swift:91`). A chest tap out-pays a daily mission (§4.2).
- **(c)** Add `Profile.scoreMultiplier` (**iron rule 7: `decodeIfPresent ?? 1`**). Group missions into
  sets of three; a completed set pays +1, capped; past the cap a set pays a Mystery Box. Feed the
  multiplier into the score.
- **(d)** **M–L, and it carries two real risks that must not be waved through.** (i) **Core/ cannot
  read `Profile`** (iron rule 1) — the multiplier has to be *passed in* at `startRun`, alongside the
  seed, or applied at the meta boundary in `GameView.recordRunResults`. (ii) **A permanent multiplier
  makes historical scores incomparable**, which is a Game Center problem: `prismrush.best` would mix
  pre- and post-change scores, and `prismrush.daily` even more so. Decide explicitly — reset the
  board, version the leaderboard, or apply the multiplier to a *separate* meta stat and leave score
  alone. This is the one item in this list that can quietly corrupt a shipped leaderboard.

### 2. Show THREE missions, not nineteen
- **(a)** Subway 3; Temple Run 2 3 (you literally cannot hold a fourth); Alto 3 per level; Candy
  Crush a collapsed side rail. Nobody shows 19.
- **(b)** 19 cards, four competing tints, one scroll (`MissionsView.swift:41-48`, `:25-28`, §4.1).
- **(c)** One active set of 3 on the board. Everything else (achievements, completed feats) moves to
  a secondary "records" view or collapses behind a disclosure. The set advances when it is cleared.
- **(d)** **S–M.** Pure UI + a `Profile.missionSetIndex` field. No Core involvement, no RNG, no
  `layoutVersion`. This is the cheapest large win in the file.

### 3. Put the board where the player already stands
- **(a)** Subway: hub top-left, **and inside the pause menu mid-run**. Candy Crush: home-page side
  rail. Alto: goals are the progression screen itself.
- **(b)** A nav-rail door with a count badge (`MenuView.swift:343-346`); no in-run or pause surface
  anywhere.
- **(c)** A three-line mission strip on the hub itself, and the same strip in the pause overlay so a
  player can see mid-run that they are 2 gems short. This is also what makes a self-constraint
  mission (item 4) *playable* — you cannot honour a constraint you cannot see.
- **(d)** **M.** Two new call sites on existing state; the pause surface needs a live read of
  in-progress run values, which today only exist in `GameCore`/`RunSummary` at run end.

### 4. Add self-constraint missions — the ones that change how the game plays
- **(a)** "Score 4000 points **without picking up any Coins**", "Roll 50 times **while on the middle
  lane**", "Pick up 50 Coins **while in the air**"; Alto's entire 180-goal trick curriculum;
  Season Hunt upgrades that grant new verbs (Super Speed, Double Jump, Smooth Drift).
- **(b)** Zero. All 19 non-chest metrics are passive reads of `RunSummary`
  (`MissionCatalog.swift:51-66`); the `Metric` enum has no lane, blast, damage or abstinence field
  (`:34-41`).
- **(c)** Extend `RunSummary` with the fields a constraint needs — e.g. `blastsUsed`,
  `lowestLaneSeconds` / per-lane time, `gemsCollected == 0` reachability, `hitsTaken`,
  `wardenNoHit` — and author missions over them. Prism Rush's verbs (jump / slide / lane / **THE
  BLAST**) are richer than Subway's, so this is a natural fit.
- **(d)** **M.** `RunSummary` is a pure value type in the Linux-testable layer
  (`MissionCatalog.swift:6-24`), so new fields are cheap and testable — but they must be *counted*
  somewhere in `GameView.recordRunResults` / the `FXEvent` stream, and **iron rule 9 applies**:
  per-death deltas, never cumulative re-pays. **No RNG, no spawn change, no `layoutVersion` bump.**

### 5. Add cross-surface missions — make the board a router
- **(a)** "Spend 500 Coins", "Buy 1 Mystery Box", "Use 1 Headstart", "Complete 1 Word Hunt" — Subway
  points missions at the shop, the box and the daily.
- **(b)** Two missions, both pointing at the free chest (`MissionCatalog.swift:108`, `:138-139`).
- **(c)** Author missions against: open a Mystery Box, complete today's daily challenge, run a world
  you own, equip a character you have never used, defeat a Warden without being hit. Each one is also
  a tap-through: the card should navigate to the surface it names (decree 4 — everything leads
  somewhere).
- **(d)** **S.** Meta-layer only; the counters mostly exist already on `ProfileStore`.

### 6. Ship a skip valve in the same PR as sets
- **(a)** Subway: coins or an ad. Exists *because* one blocked mission stops the whole ladder — the
  wiki names "beat a friend's score" as the case that forces it.
- **(b)** No skip. Harmless today (flat board, nothing gates anything); **becomes a wall the moment
  item 1 or 2 lands**, and `run.warden1` (`MissionCatalog.swift:96`) is the mission most likely to
  wall a weak player.
- **(c)** A coin skip. **Ads are forbidden by decree 5**, so the coin price is the only lever — and
  note this is a genuinely good coin *sink*, which `s016_coins-economy.md:143-152` says the game
  badly needs. Price it against the ratio table there, not by feel.
- **(d)** **S**, if it ships with sets. **Blocking** if sets ship without it.

### 7. Make set-completion a moment, not a toast
- **(a)** Subway's set completion is a multiplier bump — a permanent number visibly changing. The
  reward *is* legible as a state change, not a receipt.
- **(b)** Claim fires `purchaseChime` + a success haptic + a `+N` coin fly-up over the card
  (`MissionsView.swift:187-190`, `:476-484`, `:548-576`). Competent for a single claim, but there is
  **no set-completion beat at all** because there are no sets. This is the same class of defect as
  M11 / D-049 (`s016_mandate.md:28`, `:37-39`) — a flat statement of fact where a reward should be.
- **(c)** One authored moment when the third card in a set lands: the multiplier number itself
  animating up, held, with sound. Reuse whatever D-049 built for the chest so the game has *one*
  reward vocabulary rather than two.
- **(d)** **S–M**, and it is dependent on item 1 (there must be a number to animate).

### 8. Make the first set nearly free, with the biggest reward attached
- **(a)** Subway set 1 = "Pick up 100 Coins" / "Score 500 points in one run" / "Complete 1 Word Hunt",
  and it pays the largest multiplier gain in the game (**+100%**). Apple: begin with basic elements,
  build objectives that "intuitively build on one another"
  ([Apple](https://developer.apple.com/app-store/onboarding-for-games/)). Endowed progress: a bar
  that starts non-zero completes more often.
- **(b)** A fresh board is 19 cards at 0/N. The summary strip correctly says `N OPEN · UP TO N COINS`
  rather than `ALL CLEAR` (`ProfileStore.swift:513-517`, `MissionsView.swift:96`) — that half is
  already right — but there is no *first* mission, no ramp, and the largest rewards
  (`ach.runs` tier 3 = 2,000 coins, `MissionCatalog.swift:135`) are the furthest away.
- **(c)** Author set 1 explicitly for minute one. Consider seeding its first card partially complete
  from the player's very first run (endowed progress) rather than showing three zeros.
- **(d)** **S.** Catalogue authoring plus one ordering rule.

### 9. Pay boxes and unlocks, not only coins
- **(a)** Word Hunt streak: Mini box → box → 1,050 coins → 1,500 coins → **Super box every day at
  5+**. Collections pay keys and permanent multipliers. Season Hunt pays characters, boards and
  gameplay upgrades. Subway's ladders pay **coins in the middle and boxes at the top**.
- **(b)** Every mission, every achievement tier, the daily login ladder, the chest and the challenge
  tiers pay coins and only coins (`ProfileStore.swift:585-586`, `:296`, `:339-348`, `:619`;
  `s016_subway-reference.md:330-337`).
- **(c)** Have set completion (or the top of the achievement ladders) pay a **Mystery Box** — which
  also serves M7/M9 by giving the box-opening choreography another delivery route that is *earned*
  rather than bought.
- **(d)** **S** on the meta side (`ProfileStore.openMysteryBox` exists, `ProfileStore.swift:135-144`)
  — but if the box is *queued* rather than opened immediately it needs a `Profile` field, so
  **iron rule 7** applies.

### 10. An in-run collectible that feeds a daily objective (the Word Hunt shape)
- **(a)** Letters spawn in-run; the magnet deliberately **cannot** attract them; Super Sneakers
  **can** jump-collect them; a 5-day streak pays a Super box daily; missing a day resets the streak.
- **(b)** Prism Rush's daily challenge is a seeded *run*, not a collectible
  (`Core/DailyChallenge.swift`, `ProfileStore.swift:605+`). Nothing in the spawn stream feeds a meta
  objective.
- **(c)** A per-day collectible in the spawn stream, banked to the meta layer.
- **(d)** **L, and the most expensive item here.** This is a spawn-path change: **the solvability bot
  must stay green (200 seeds × 6,000 m plus the 12,000 m soak) and `DailyChallenge.layoutVersion`
  must go 12 → 13** — the v13 pin is pre-armed at `0x9E49_3424_C18A_59C5`
  (`CLAUDE.md` iron rule 3), and `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens` pins the
  same seeds from the meta layer. **It shares that single pre-armed v13 pin with the in-run Mystery
  Box (`s016_subway-reference.md:385-397`) — if both ship they must ship in ONE `layoutVersion`
  bump, not two.** Derive goldens in Python from the SplitMix64 constants
  (`s016_goldens_derive.py` exists). Sequence this behind items 1–9.

### 11. Season/pass cadence — defer, but know the shape
- **(a)** 50–110 tiers, seasons of 8–12 weeks (30–90 days), premium track $10–20; the premium track
  in SYBO's own *Subway Surfers City* pass **adds bonus daily and seasonal missions** rather than
  only unlocking rewards. Clash Royale is the documented cautionary case — SensorTower showed a
  temporal correlation between pass introduction and a **drop in monthly revenue**, via
  cannibalisation of other purchases
  ([DoF battle passes](https://www.deconstructoroffun.com/blog/2022/6/4/battle-passes-analysis),
  [Grokipedia: Battle pass](https://grokipedia.com/page/Battle_pass)).
- **(b)** No seasons, no pass, no live-ops cadence.
- **(c)** Nothing this pass.
- **(d)** **L+.** A pass without a content pipeline behind it is a treadmill with nothing on it, and
  the Clash Royale case says a pass bolted onto a shallow spend depth can *lose* money — which is
  exactly Prism Rush's situation per `s016_coins-economy.md:143-152` (finite sink, everything free in
  13–27 days). **Fix the sink first.**

---

## 7. THE ONE-LINE VERSION OF EACH OF THE OWNER'S FOUR COMPLAINTS

| Complaint | Root cause, per the references | Item(s) above |
|---|---|---|
| **ugly** | 19 cards, 4 competing tints, rings that all read empty for the first 0.7 s | 2, and `s016_design-system.md` F1–F10 |
| **does nothing** | every mission is a passive read of a run the player was going to have anyway; 2 of 21 point at another surface | 4, 5 |
| **not easy to understand** | board-level, not card-level — the card is fine, there are just nineteen of them | 2, 3, 8 |
| **not rewarding at all** | **an economy defect.** Missions pay a currency that a one-tap chest pays more of (140 > 115) into a catalogue that is free in 13–27 days. Every reference game pays **permanent power** instead | **1**, 6, 9 |

The fourth is the one the brief warned would be mis-fixed as a prettier screen, and the reference set
is unanimous about the fix: **stop paying currency for missions.**

---

## 8. SOURCES

Access notes: `subwaysurf.fandom.com` returns **HTTP 402** to `WebFetch` and `sybo.helpshift.com`
returns **403** (same as `s016_subway-reference.md:486-488`); both Subway wikis were read through the
**browser pane**, which renders them fine. Browser navigation to *other* origins
(`snowman.miraheze.org`, `subway-surfer-city.fandom.com`, `disneycrossyroad.fandom.com`) was
**denied** in this non-interactive session, so claims sourced only from those pages are marked
corroborated-but-not-primary above. `dl.acm.org`, `researchgate.net`, `appunwrapper.com`,
`supercheats.com`, `templerun2.zendesk.com`, `appsupport.disney.com` and `playbite.com` all refused
`WebFetch` (403/502).

**Subway Surfers (read in browser pane, 2026-08-03):**
- Missions — https://subwaysurf.fandom.com/wiki/Missions
- Multiplier — https://subwaysurf.fandom.com/wiki/Multiplier
- Word Hunt — https://subwaysurf.fandom.com/wiki/Word_Hunt
- Season Hunt — https://subwaysurf.fandom.com/wiki/Season_Hunt
- Collections — https://subwaysurf.fandom.com/wiki/Collections
- Season Pass (Subway Surfers City) — https://subway-surfer-city.fandom.com/wiki/Season_Pass *(search index only)*
- Official help centre, Missions — https://sybo.helpshift.com/hc/en/5-subway-surfers/faq/143-missions/ *(403)*

**Other games:**
- Objectives (Temple Run 2) — https://templerun.fandom.com/wiki/Objectives_(Temple_Run_2)
- Temple Run 2 Objectives (official support) — https://templerun2.zendesk.com/hc/en-us/articles/1500009158462-Objectives *(403)*
- Alto's Odyssey press kit (180 goals / 60 levels) — http://altosodyssey.com/press/sheet.php?p=altos_odyssey
- Goals (Alto's Odyssey Wiki) — https://altosodyssey.fandom.com/wiki/Goals
- Alto's Odyssey walkthrough/goals — https://www.appunwrapper.com/2018/02/21/altos-odyssey-walkthrough-guide-tips-and-tricks/ *(403)*
- Alto's Odyssey (Wikipedia — premium, no ads, no IAP) — https://en.wikipedia.org/wiki/Alto%27s_Odyssey
- Daily quests (Candy Crush Jelly Wiki) — https://candycrushjelly.fandom.com/wiki/Daily_quests
- Quests (Candy Crush Soda Wiki) — https://candycrushsoda.fandom.com/wiki/Quests
- Pecking Order (Crossy Road Wiki) — https://crossyroad.fandom.com/wiki/Pecking_Order
- Daily Missions (Disney Crossy Road Wikia) — https://disneycrossyroad.fandom.com/wiki/Daily_Missions

**Design / research:**
- The Making Of A Mechanic: Daily Goals — https://www.deconstructoroffun.com/blog//2016/07/the-making-of-mechanic-daily-goals.html
- Battle Passes — Everything You Ought to Know — https://www.deconstructoroffun.com/blog/2022/6/4/battle-passes-analysis
- Battle pass (Grokipedia) — https://grokipedia.com/page/Battle_pass
- Designing battle passes in mobile games (GameAnalytics) — https://www.gameanalytics.com/blog/designing-battle-passes-in-mobile-games-the-whats-whys-and-hows
- Daily Quests or Daily Pests? (CHI PLAY 2022) — https://dl.acm.org/doi/10.1145/3549489 · https://research-portal.uu.nl/en/publications/daily-quests-or-daily-pests-the-benefits-and-pitfalls-of-engageme
- Daily quests aren't fun, they're tedious (PC Gamer) — https://www.pcgamer.com/daily-quests-arent-fun-theyre-tedious/
- Onboarding for Games (Apple Developer) — https://developer.apple.com/app-store/onboarding-for-games/
- Goal Gradient Effect — https://learningloop.io/plays/psychology/goal-gradient-effect
- Endowed progress effect — https://uxdesign.cc/endowed-progress-effect-give-your-users-a-head-start-97d52d8b0396
- Deceptive Patterns — Fake urgency — https://www.deceptive.design/types/fake-urgency
- Deceptive Patterns — Chapter 15: Urgency — https://www.deceptive.design/book/contents/chapter-15
- ACM fines Epic for dark patterns (countdown timers) — https://www.stibbe.com/publications-and-insights/game-over-for-dark-patterns-acm-fines-epic-for-unfairly-targeting
- Game UI Database — Missions and Quests (screenshot corpus, for the mockup gate) — https://www.gameuidatabase.com/index.php?scrn=81

**Repo sources (HEAD `ba9655d`):**
`CLAUDE.md`; `docs/agent/audits/scratch/s016_mandate.md`; `s016_coins-economy.md`;
`s016_subway-reference.md`; `s016_design-system.md`;
`PrismRush/Meta/MissionCatalog.swift`; `PrismRush/Meta/ProfileStore.swift`;
`PrismRush/Meta/Profile.swift`; `PrismRush/UI/MissionsView.swift`; `PrismRush/UI/MenuView.swift`;
`PrismRush/Core/Tuning.swift`.

---

## 9. NOT FOUND — do not let these be invented downstream

1. **The coin price of a Subway Surfers mission skip**, and whether it scales with set number. Query:
   `Subway Surfers missions list examples "set" skip missions cost coins`. Every source says a skip
   exists; none gives a figure. Official help centre 403s.
2. **Disney Crossy Road's daily-mission count and reward.** `appsupport.disney.com` 403s;
   `disneycrossyroad.fandom.com` could not be opened in the browser pane.
3. **The exact Subway Surfers mission-card UI at pixel level** — how progress is drawn (bar? counter?
   tick?). The wiki gallery captions imply a 3-state per-row read ("1 and 3 completed") but I could
   not view the images. **This is the single biggest gap for the mockup gate (M4)**; it needs a
   screenshot pass, not a text source.
4. **Whether Subway's mission progress is visible mid-run**, or only in the pause menu. The wiki says
   pausing "can also lead you to it", which is not the same claim.
5. **Any published number for how mission systems move D7/D30 retention.** Genre benchmarks exist
   (`s016_subway-reference.md:326-329`) but nothing isolates the mission system's contribution.
   Do not let a ticket claim "+X% retention".
6. **Alto's Odyssey per-level goal strings, primary-sourced.** The wording in §2 comes from search
   indexes of pages that refused direct fetch.
7. **Temple Run 2's ×67 maximum, primary-sourced.** Corroborated across two summaries; the wiki page
   itself was not readable in this session.
