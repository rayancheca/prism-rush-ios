# Prism Rush v1.5 — "Depth & Clarity" overhaul plan

Owner-driven redesign (2026-06-12). Captures the agreed decisions and the phased plan so any fresh
session can resume. Owner decrees in `CLAUDE.md` and iron rules still bind everything below.

## Locked decisions (from the owner, this session)

1. **Worlds** — Replace the 3-world `% 3` loop with **12 distinct themed worlds**, each its own
   palette + background motif, then *evolve* (hue-rotate / intensify) on subsequent cycles rather
   than repeat identically. Distinct names, not "name + bigger number." Per-world themed music is a
   later sub-phase.
2. **Character rarity** — Keep characters as **cosmetic identity** (decree 1: never changes with the
   world) **plus** an **honest passive perk** on higher tiers (e.g. legendary head-start / larger
   magnet radius — modest, never pay-to-win, decree 5), **plus** a separate **equippable power-up
   loadout** the player chooses (identity stays constant; loadout is "what I bring").
3. **In-run HUD** — **Distance in meters is the big primary number.** Score + coins are clear
   secondary readouts; add a ×N multiplier badge, coin-fly-to-counter juice, and a **live XP/level
   bar that fills during the run**. Results screen reconciles coins + XP with animation.
4. **Build order** — (1) Home/menu UX + navigation + animated splash + music → (2) Worlds + names +
   variety → (3) Gameplay difficulty + scoring clarity → (4) Power-ups + tutorial.

## Proposed 12-world sequence (theme + motif; names final-pending owner tweak)

| # | Name | Theme / background motif |
|---|------|--------------------------|
| 1 | Pulse City | synthwave skyline (was Neon Metropolis) |
| 2 | Geode Deep | underground crystal (was Crystal Caverns) |
| 3 | Solar Sands | desert dunes (name kept — owner landmark) |
| 4 | Orbital Drift | outer space, astronaut drifting in background, satellites |
| 5 | Tidal Glow | bioluminescent deep ocean, jellyfish |
| 6 | Ashfall | volcanic, lava cracks, embers |
| 7 | Borealis | frozen tundra under northern lights |
| 8 | Datastream | Tron-like digital grid |
| 9 | Bloomfall | cherry-blossom night city |
| 10 | Eventide | cosmic nebula / black hole |
| 11 | Tempest | electric storm, lightning |
| 12 | Singularity | white/rainbow endgame |

## Phase 1 — Home/menu UX + navigation + splash + music (IN PROGRESS)

Research basis (Subway Surfers / Alto's / Temple Run): one hub screen, dominant PLAY, character as
hero, **coins top-left, gear top-right**, distinct standout icon buttons — never uniform gray cards.

- [ ] **Character clip fix** — `CharacterHeroStage` `.clipped()` crops tall antennas + bob. Remove
      the top crop so characters are never cut off (clip only the floor reflection's spill). Same
      issue is the owner's "loading screen square."
- [ ] **Settings surfaced** — gear in the home top-right (`model.open(.settings)`); no longer 3 taps
      deep behind Profile.
- [ ] **Top-bar conflict fix** — the floating mute/pause cluster in `GameView` renders in `.menu`
      and overlaps the coin badge. Hide it in `.menu` mode (mute lives in Settings on the hub).
- [ ] **Nav cards stand out** — color-coded, larger, role-tinted icon buttons with real hierarchy
      instead of uniform `Theme.Role.surface` light-gray chips.
- [ ] **Animated splash** — full-screen, character bobbing freely (uncropped), logo, "tap to start"
      shimmer; fades into the menu.
- [ ] **Menu/splash music** — ambient bed plays on the splash + menu (today nothing plays outside a
      run). Calm, inviting; carries until a run starts.

## Phase 2 — Worlds (next)

- 12 `WorldPalette` entries in `Theme.worlds`; `stepWorld` modulus → `worlds.count`; per-world decor
  motif in `WorldSky`/renderer; evolved naming kept for cycles >0. **Visual/decor only where
  possible — no spawn-RNG consumption, no `DailyChallenge.layoutVersion` bump unless the spawn path
  changes** (iron rule 3).

## Phase 3 — Gameplay + scoring

- HUD: meters primary, score/coins/×N secondary, coin-fly juice, live XP bar; results reconcile.
- Difficulty: fix the speed ramp so checkpoint worlds don't start at the speed cap; add an
  **animation-state conflict rule** to the spawner/validation (no slide-obstacle immediately before
  a jump-obstacle within reaction+anim distance unless an open lane exists); more pattern variety.
  Keep the solvability bot green; bump `layoutVersion` on any spawn-path change.

## Phase 4 — Power-ups + tutorial

- New power-ups (super sneakers / boost / mystery box; pre-run head-start + score-booster
  consumables); one **manually-triggered saved power-up** (HUD becomes tappable; careful with the
  seeded RNG — iron rule 2). **Active-shield HUD indicator.** A **power-ups screen** reachable from
  the hub, and an **inline first-run tutorial** (replayable from settings).
