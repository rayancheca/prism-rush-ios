# Session 013 — the Warden, made a fight

**Date:** 2026-07-31 · **Base:** `3b98616`

**261 SPM tests green** (was 254). Xcode build OK. `DailyChallenge.layoutVersion` **11 → 12** — the
pre-armed pin is spent; v13 is now pre-armed.

---

## What the session was asked for

The owner played the S-012 Warden and rejected it, in one message. Verbatim:

> *"okay the warden sucks. i have no clue when its coming or what i have to do. if its my first time
> playing instead of being the designer i would be super confused. he only attacked me twice and the
> wall it created that i had to crouch under was blocking the view of everything also i hate the red
> colour. also its not sending walls down the lane like i asked. so it needs to be a challenge. think
> about the warden more. he should be easier at first and tougher on harder levels. so when hes
> tougher he shoots you as well and the walls he send come quicker like the trains from subway
> surfers. but its too short and boring."*

Nine complaints. Every one of them is answered below, and three of them turned out to trace to a
single code fact each — which is why the session opened by reading rather than designing.

| # | complaint | root cause found in code | fix |
|---|---|---|---|
| A | "no clue when its coming" | nothing announced a Warden but the Warden, already armed | `Warden.metresToNextArena` + HUD countdown from 240 m |
| B | "no clue what i have to do" | no teaching existed at all | per-throw verb coaching, first 3 encounters MET |
| C | "he only attacked me twice" | rank 1 needed 4 answers at 1.95 s apart; launch guard also over-reserved | 5 answers at 1.55 s; guard divisor fixed |
| D | "blocking the view of everything" | the bar was a solid `7.6 × 3.05` slab = 23.2 u² of opaque frontal area | portcullis; 23.2 → 11.6 u² |
| E | "i hate the red colour" | `0xFF3355` as a flat saturated fill on every Warden surface | dark body + violet `0xC77BFF` edge |
| F | **"not sending walls down the lane"** | **`applyThrown` pinned every hazard to a fixed `d`; nothing was ever launched at anybody** | `CoreEntity.closeSpeed`, 25/28/32 m/s by rank |
| G | "easier at first, tougher later" | the ladder was 2 numbers and a flat clock | 5 axes incl. the script itself |
| H | "when hes tougher he shoots you" | never built; S-007's original pitch was *"ships that shoot at you"* | `EntityKind.bolt`, rank ≥ 2 |
| I | "too short and boring" | 14.5 s flat, ~4 throws | 17.5 s, ~2× the hazards |

Decisions **D-032 … D-036**.

---

## The one that mattered most

**F was not a tuning miss, it was a missing mechanic.** Every obstacle in this game — including a
Warden's — was pinned to a fixed `d`, and the player ran into it at the same speed they run into
ordinary track. There was no velocity field anywhere in `Core/`. So "the Warden throws a wall" and
"the spawner places a wall" produced *identical* motion, and the only thing distinguishing the boss's
attack was that it was tinted red. He was right, and he had been right in S-012 too.

`closeSpeed` is 0 for everything the spawner places, so ordinary track, the 200-seed solvability
proof and every daily golden are untouched by the field's existence. Only `applyThrown` sets it.

The leads moved OUT (34/22 → 52/40) and this is **not** extra reading time — the window is
`lead / (run + close)`, so it went from a flat 1.15 → 0.75 s to **0.95 → 0.62 s** across the ranks.
Further away, arrives sooner, visibly rushes.

---

## What measurement refuted

- **Closing speeds of 9/16/24 made the boss EASIER.** `LaggedAutopilotTests` went red immediately: a
  bot reacting a full 0.75 s late killed **48 of 48** Wardens, because 52 m against +9 m/s is a
  1.35 s window — more generous than the thing it replaced. Moving leads out without moving closing
  speed up ships a boss that looks faster and plays easier. Corrected to 25/28/32.
- **The fairness gate had never tested rank 3.** `survives()` ran to 6,000 m and asserted
  `encounters == 24 * 2` — worlds 3 and 6 only. Every claim the file made about "the fight is fair /
  the fight is hard" was a claim about ranks 1 and 2 wearing a general name, and rank 3 is where the
  aimed shots live. Now 7,400 m and `24 * 3`.
- **A 1-in-200 solvability failure was a real bug of mine, not a trajectory shift.**
  `Autopilot.closingRatio` compared a chrono-scaled `effectiveSpeed` against an *unscaled*
  `closeSpeed`, so under slow-mo the factors stopped cancelling: the bot read a closing chasm as
  nearer than it was, launched early into the catalogue's only two-sided window, and air-slammed
  into the hole. Found by instrumenting the exact tick rather than by reasoning — the failure dump
  pointed at d=6000 (where the run *ended*) while the stumble was at d=2510.
- **The coaching's first location was wrong and only the screen showed it.** As a popup it rendered
  at frame row 0.52, straight across the hazard it was describing — the same reason `.wardenCoreHit`
  has had no popup since v2.2. Moved into `HUDView.wardenPanel`.

## What a hostile reader found in code written the same hour

A verification pass over the freshly-written implementation found three defects (D-036):

1. **A shield was being spent on something that cannot kill you** — and worse, it deleted the throw
   without paying a Warden answer, so holding a shield made the fight strictly *longer*, and opened
   0.4 s of invulnerability in which the next hazard collected a free answer.
2. **The fight never escalated for a player who was losing it.** A landed hazard never registers an
   answer, so a damage-only `throwLead` lerp pinned the lead at its most forgiving value for exactly
   the player having the most trouble.
3. **A build break the SPM suite structurally cannot see.** `.shot` left `switch band` in
   `GameView.swift` non-exhaustive, and `GameView.swift` is not in `Package.swift`. 261 tests were
   green over a target that did not compile.

---

## Verified on the simulator, not merely tested

Recorded and read frame by frame (`PR_WARDEN=1|2|3`, autoplay):

- the portcullis with the **track grid and gems visible through it**
- a lance in flight: two violet walls, one lane open, deck readable around them
- `CORE EXPOSED` and every hazard in violet — **no red anywhere in the fight**
- all four coaching lines firing in the HUD's bottom strip: `SWIPE TO MOVE`,
  `SWIPE UP TO JUMP`, `SWIPE DOWN TO SLIDE`, `INCOMING — MOVE!`

The first capture attempt ran a **stale binary** from `~/Library/Developer/Xcode/DerivedData` and
showed the old red slab and a pre-S-012 HUD. `Tools/build.sh` writes to `.dd/Build/Products/` —
install from there, and uninstall first, because `simctl install` keeps the profile and the coaching
gate reads a profile counter.

---

## Numbers

| gate | before | after |
|---|---|---|
| SPM tests | 254 | **261** |
| sluggish (0.75 s) bot: Wardens killed | 31 / 48 | **17 / 72** |
| sluggish bot: hazards landed | 68 | **357** |
| human-floor (0.40 s) bot: hazards landed | 0 | **0** (unchanged — still fair) |
| solvability bot, 200 seeds | 0 contacts | **0 contacts** |
| hanging-bar frontal area | 23.2 u² | **11.6 u²** |
| reaction window, rank 1 → rank 3 | 1.15 → 0.75 s (flat) | **0.95 → 0.62 s (laddered)** |
