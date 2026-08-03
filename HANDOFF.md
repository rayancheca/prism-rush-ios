# HANDOFF → Session 016

## Paste this to start the next session

```
You are session 016 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

READ THE OWNER'S MANDATE FIRST: docs/agent/audits/scratch/s015_mandate.md. It is verbatim and it
governs. He wants MANY passes on the Warden, explicitly authorises copying other games, and closes
with "we still have a lot of passes for all aspects of the game."

YOUR ONE JOB THIS SESSION IS R1 + R2 — THE DEAD AIR AND THE PLACEMENT. They are the same bug and
they are the owner's loudest complaint. S-015 already cleared the cheap wins so this one has room.
Do not spread yourself across the backlog instead.

  The arena is 770 m of an 800 m world, starts at offset 0.0 m, and the fight uses ~297 m of it.
  `Warden.suppresses` keys on `isArena(d)` — a pure distance function that cannot know whether the
  encounter is still alive — so after the kill the deck stays empty for 473.3 m = 14.75 s. The
  owner said "a good 15 seconds". It is exactly that, and it was also measured on the simulator:
  withdrawal at 2,851 m, first obstacle at ~3,121 m.

  The arithmetic, three candidate seams, the blast radius and the rejected alternatives are in
  docs/agent/audits/scratch/s015_r1_deadair.md and s015_r2_placement.md. READ BOTH BEFORE TOUCHING
  ANYTHING; do not re-derive them. Both were adversarially verified (.../s015_verify_*.md).

  THE HARD WALL, and it is real: a worst-case fight is 698 m long and a world is 800 m, so there is
  nowhere to put the arena except the start unless you either cut `wardenMaxSeconds` (which S-013
  just RAISED, to answer "its too short and boring") or let the arena cross a world boundary with
  the palette HELD for the duration. S-015's recommendation is the latter — the Warden becomes the
  bridge between worlds: you fight it at the end of world N and burst into N+1 as it dies. That is
  a judgement call, not a settled decision. Make it deliberately and write it up as a D-number.

  This is a LAYOUT change. `DailyChallenge.layoutVersion` 12 → 13; v13 is pre-armed and unspent at
  0x9E49_3424_C18A_59C5. Goldens are pinned in TWO places (DailyChallengeTests AND
  MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens) and must be derived in Python from the
  SplitMix64 constants, never read off the Swift they pin. SolvabilityBotTests (200 seeds x 6,000 m
  plus the 12,000 m soak) is a REAL risk surface here, not a formality: 473 m per Warden world that
  was guaranteed-clear will start carrying act-two-density obstacles. DifficultyCurveTests bands
  will need re-baselining. And the renderer will start LYING unless you thread an `arenaLive` flag
  through the snapshot — ArenaShell and the deck tint both derive "am I in an arena" from distance
  alone, so they would keep painting boss-arena treatment over ordinary track (breaks decree 2).

AFTER THAT the roadmap is already written. docs/agent/audits/scratch/s015_r5a_fightdesign.md is a
697-line inventory of the Warden plus THIRTEEN ranked changes W1-W13, each with its code seam, the
game it is borrowed from, its risk and its RNG exposure. W1 and W2 shipped in S-015 (D-042, D-043).
W3 — a victory outro, which converts the first ~120 m of the dead air into aftermath with NO layout
risk — pairs naturally with R1. Do not re-derive that list.

Decisions are in docs/agent/04_DECISIONS.md as D-023..D-045. Do not re-ask what is answered there.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and now hold ~1.2 GB from fifteen sessions. Git does NOT move them between worktrees.
No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

  THEN reclaim space: rm -f docs/agent/scratch/s015/*.mp4  (they are ~700 MB and the contact
  sheets next to them are what actually carry the evidence).

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Fifteen for fifteen. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. S-015 wrote `Theme.Role.warning`, which does not exist, and 266 SPM tests were perfectly
green over it — the iOS build caught it in one line.

PUSH TO GITHUB. The owner asked for this explicitly in S-015 and it is now standing.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 015 did

Two commits, `1ad384c` (`PR-0463`) and `2513c30` (`PR-0464`). **266 SPM tests green**, iOS build
green, `layoutVersion` untouched at **12** (**v13 still pre-armed and unspent**). Decisions
**D-042..D-045**. Recovery tag `pre-s015`. Session log: `docs/agent/sessions/SESSION_015.md`.

The session opened as "play the Warden and report back" and was redirected mid-flight by the owner
into a broad mandate. It also **pushed 17 local-only commits reaching back to S-010** — the repo had
never been pushed since then.

## Landed and verified on the simulator

| | What | Decision |
|---|---|---|
| **W1** | The Warden **reacts to being hit**. `wardenHitRecoil` was documented as the damage recoil and was wired to the *muzzle flash* — the only recoil in the game fired when the Warden ATTACKED, and answering a hazard moved nothing at all. Split into `wardenThrowKick` (rides `throwFlash`, behaviour unchanged) and `wardenHitRecoil` (rides a new `hitFlash`, set on every answered hazard including armour chips). The rig banks the hull on **roll** — the last unused axis, so "hurt" cannot be misread as the nose-down "about to throw". | D-042 |
| **W2** | The fight is **legible**. `WARDEN · III` (five things differ by rank and the player could name none), a draining clock (`secondsRemaining` had been computed every frame since v2.3 and read by nothing), and D-039's strike budget as dots — **absent at rank 1**, where the absence IS the teaching signal. | D-043 |
| **R3** | The **chasm covers the floor**. Every part was 7.6 wide "matching the bar mesh" — the width an OBSTACLE needs, not a HOLE. Deck rungs are 9, so 0.7 u of lit rung survived on each shoulder for the whole 8 m. Both now derive from one `deckHalfWidth`. Gameplay untouched: `Collisions.chasmHit` takes no `x`. | D-044 |
| **R4** | The **backdrops stand on ground**. Not a depth bug — no sort group or depth flag exists anywhere in the renderer. The only floor was a 16-wide ribbon while the frustum sees to \|x\| ≈ 23, and all twelve skies are authored against an infinite floor at y = 0. Fixed with an invisible 70-wide occluder apron. A/B'd on Solar Sands at 1,600 m. | D-045 |

Also corrected: **`CLAUDE.md` iron rule 3 claimed "layoutVersion 11, a v12 pin is pre-armed"** — v12
had been spent two sessions earlier. It now says 12, with v13 pre-armed.

## Root-caused, NOT fixed — session 016's job

- **R1 · 14.75 s of dead air.** Exactly the owner's "a good 15 seconds".
- **R2 · the Warden opens its world instead of ending it.** Offset **0.0 m**, by construction
  (`Warden.arenaWorld`: *"Arenas sit at the START of every wardenEveryWorlds-th world"*). This is
  real play, not a debug artefact — `PR_WARDEN` reproduces it faithfully.

## Measured, not yet acted on

- **The boss does not own the frame, now with numbers.** At rank 3 the world-9 horizon ring is
  **13.63 % of the frame at L\* 76.1**; the entire Warden craft is **1.82 %**. Craft rim vs that ring
  is **1.61 : 1** contrast — below even the 3:1 non-text floor. The wallpaper beats the boss 7.5× on
  area and wins on luminance. The single lever is `EventideSky.swift:122`,
  `horizonC = lift(pal.accent, 0.30)`. Full workings: `s015_r5b_presentation.md`.
- **The chasm still cannot be seen into.** An unbroken 16-wide ground plane at y −0.02 sits above the
  well and the chasm's own opaque lid at y +0.045 covers the mouth, so the walls and floor render for
  nobody. The lid at `0x07060E` is also chromatically identical to the deck at `white 0.02`, so the
  hole reads as *"the grid is missing"* and never as a dark hole. **S-015 fixed the width only.**

# Things you would otherwise rediscover the hard way

- **I never got a chasm on screen — six attempts, and that gap is honest.** `PR_CHASM` places it at
  `distance + spawnHorizon` (115 m), and `debugSpawn` → `apply` → `Warden.suppresses` **deletes it
  inside an arena**, so `PR_WORLD=3/6/9` cannot work. Seed 7 is deterministic, so the bot dies at
  the same metre every time — I missed by 5–9 m in worlds 1, 2 and 4 repeatedly. Raise the horizon
  temporarily, or drive it by hand. R3's fix is proven by arithmetic, not by a picture.
- **`Tools/build.sh` writes to `.dd/Build/Products/`, NOT `~/Library/Developer/Xcode/DerivedData`.**
  Both exist and the latter is stale. Confirm a build is current by grepping the dylib for a string
  only your change introduced; file mtimes in this checkout are misleading.
- **SourceKit here resolves against macOS.** `No such module 'UIKit'` and `Cannot find 'Theme' in
  scope` are noise. Believe `./Tools/build.sh`.
- **`simctl install` KEEPS the profile.** This sim's `wardensMet` is 7, which is why lethality is
  live on it (needs > `wardenCoachEncounters` = 3). Uninstall and you are silently testing the
  *teaching* Warden. Read a field with:
  `python3 -c "import plistlib,json;print(json.loads(plistlib.load(open(P,'rb'))['pr.profile.v1'])['wardensMet'])"`
- **Contact sheets are the instrument that works.**
  `ffmpeg -ss T -i v.mp4 -vf "fps=N,scale=W:-1,tile=RxC" -frames:v 1 out.png`, OUTPUT seeking only.
  Then OPEN the sheet — a captured PNG nobody read is not evidence. A `crop=` before `tile=` is how
  you inspect the craft; my first attempt cropped the wrong band and showed empty sky.
- **Screenshot bursts beat video when you are NOT recording** — `simctl io screenshot` in a tight
  python loop. During a recording, screenshots stall the app into slow motion.
- **This `ffmpeg` has no `drawtext` filter.** Use `pad` to separate A/B panels.
- **`while core.warden != nil` does not terminate after a Warden kill** (`stepWarden` bails on
  `.over`). Add `&& core.mode == .play`. Inherited from S-014, still true.

# Rayan action items

1. **Play the new Warden.** Two things to judge: the **flinch** (it banks when you answer a hazard)
   and the **HUD** (rank, clock, life dots). Both are new and unseen by you.
2. **THE WARDEN'S EARS — five sessions old and only you can unblock it.** A landed hazard plays
   `.shieldBreak`, the same buffer as a wall clip, a shield breaking, armour breaking and a blast
   shattering walls. One buffer, five meanings, three opposite in valence. There is one 1.82 s music
   loop for the whole session, so a boss sounds exactly like open track. A costed design is in
   `docs/agent/audits/scratch/s014_audio.md`. **Nobody in this program can hear a sound.** Either
   listen and direct, or say "ship your best guess and I'll judge it" — both fine; silence is not.
3. **World 9's sky is the reason the boss looks small** (numbers above). Dim it during a fight,
   shrink the horizon ring permanently, or both? It is a look you chose, so it is your call.
4. Carried, still never confirmed by a human: **the stumble** (six sessions), the slide SFX (S-006),
   the hub redesign (PR-0452).
5. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2x coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — boss-fight music is a *different axis* from the per-world-bed decree and would not
  violate it. Needs a yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible?
- **Buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71 % of the coin catalogue makes runs count for LESS. Intended?
