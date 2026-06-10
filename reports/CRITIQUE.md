# Prism Rush — Master Critique & Build Plan

> **ROUND 1 DONE (commit):** A1 (back-to-menu) · A2+G4 (sign-in: `let`-not-`@State`, applesignin
> entitlement, error surfacing) · A3/D5 (live equip) · A4 (dramatic slide) · A5+B1 (deterministic,
> gated, slower moving walls — World 2 now has none) · B2 (no checkpoint speed cliff) · B3 (jump
> buffer 0.14→0.25) · B5 (instant slide) · E1 (audible slide) · G3 (observation anti-pattern) ·
> **G1 (XCUITest interaction suite — 3 tests proving A1/A3/nav)**. 30 unit + 3 UI tests green.
> Remaining: B4 pause, C/D/E juice & perf, F monetization (daily/chests/streaks/revive-for-coins).


> Synthesized from an 8-layer hater-critic review + adversarial pass (10 agents). Ordered
> **gameplay-first, then monetization**. Severities: **P0** ship-blocker · **P1** must-fix · **P2** polish.
> Decisions locked: **monetization = revive-with-coins (no ad SDK, zero new deps)**; **visuals = hybrid
> (procedural core + a few targeted assets where they most help)**.

## A. P0 BUGS (user-reported blockers)
- **A1** — No escape from game-over (only RUN AGAIN). Add `BACK TO MENU` (+ `returnToMenu()`); allow meta
  sheets to open from `.over`. `GameOverView.swift`, `GameView.swift`.
- **A2** — Sign in with Apple silently no-ops. Root: `@State var account = AccountService.shared` snapshot
  (G3) **and** missing `applesignin` entitlement (G4). Use `let`, add `lastError`/`signingIn`, surface
  errors, ignore `.canceled`. `ProfileView.swift`, `AccountService.swift`.
- **A3** — Equip gives no visual confirmation. Root: stale `let profile = ...` snapshot (G3). Read live in
  the `ForEach`, `.id(selectedSkin)` the grid, haptic on equip, `applyCurrentSkin()` on close. `CharacterSelectView.swift`, `GameView.swift`.
- **A4** — Slide imperceptible. Min: `sx*=1.55`, lean `-0.85`, dust regardless of grounded, slide flash. Full = C1.
- **A5** — Moving walls human-unfair. Random phase (`Patterns.swift:90`) is bot-solvable but not human. Min:
  deterministic phase + amplitude `2.2→1.5`. Full = B1.

## B. Gameplay & fairness
- **B1** — Moving-wall redesign: deterministic phase, freq `0.32→0.22`, gate later (diff≥0.6), lane telegraph, density cap.
- **B2** — Checkpoint speed cliff: start at `speedStart` (ramp up) or ramp-from-prev-boundary; GET-READY countdown; first obstacle ≥15u.
- **B3** — Jump buffer `0.14→0.25–0.30` (re-run solvability). Coyote time on slide.
- **B4** — Add `.paused` GameMode + pause button + scenePhase auto-pause + PAUSED overlay (RESUME/QUIT).
- **B5** — Air-slam: snap `sy` to slide scale instantly (avoid mid-transition bar deaths).
- **B6** — Restart delay `0.5→1.5`, disabled state + "Ready in X…".
- **B7** — How-to-play tutorial.
- **B8** — Wire the inert Worlds button (`onLevels` not passed in `GameView`).

## C. Feel, animation, screen effects (hybrid assets OK)
- **C1** — Dramatic multi-layer slide (lean/width/deeper squash/snappier lerp/8-12 particles grounded+air/skid decal/camera tilt/SLIDE popup/SFX/haptic).
- **C2** — Beef particles (death 120, gem 12, pickup 36; longer life; min scale 0.05→0.15).
- **C3** — Stronger shake (pos 0.3→0.6, + rotational, death 1.0→1.5).
- **C4** — Tier flash hierarchy (pickup 0.25, gem 0.2, death 0.6; color-coded).
- **C5** — Jump-apex hold, world-unlock fanfare, brighter lane stripes + HUD lane dots, popup polish, rig idle motion.

## D. Render & performance
- **D1** — Stop allocating `UnlitMaterial` per entity per frame (~6k allocs/s). Cache 2 materials/frame.
- **D2** — Pooled entities get stale colors on reuse mid-crossfade. Set materials in sync, not make.
- **D3** — Particle cursor overwrites live particles; skip occupied slots / free list.
- **D4** — Decor recycle desyncs from blend; rig has no LOD.
- **D5** — Apply skin live (not only run-start); validate `selectedSkin`. (render side of A3)

## E. Audio
- **E1** — Slide SFX louder/deeper (vol 0.13→0.20, cutoff 900→600, + low thud). Pairs with A4/C1.
- **E2** — Music duck under SFX; death decel sweep.
- **E3** — Missing SFX: lane change, shield≠magnet, purchase, sheet transitions, mute fade.
- **E4** — Music fade-in 1.2→0.5s; clearer gem-streak pitch (1.045→1.08).
- **E5** — Harden: guard `AVAudioFormat(...)!`, log swallowed engine errors.

## F. Monetization & meta (revive = coins, no ads)
- **F1** — Daily reward + timed free chests (~30 min) with countdown.
- **F2** — Login-streak rewards (tiered, resets on lapse).
- **F3** — Revive/continue **for coins** (no ad SDK). On death restore + keep world/speed.
- **F4** — Higher earn (`distance/50→/35` + world mult + events); run-scoped boost consumables; rebalance packs/skin costs.
- **F5** — Convert permanent Double Coins to a renewable time-limited booster pass (protect revenue); optional skin stat badges.
- **F6** — IAP transaction error handling/logging.

## G. Code quality & testing
- **G1** — **XCUITest interaction suite** (the gap that shipped A1–A5): GameOverFlow, CharacterSelect, Profile sign-in, Slide feedback, Navigation/Worlds.
- **G2** — Human-reaction-window solvability variant; NaN/finite guards; checkpoint-speed & jump-buffer tests.
- **G3** — Fix `@Observable`/`@State` anti-pattern repo-wide: reference singletons directly in `body`, never `@State` a shared ref, never snapshot `store.profile` at body top.
- **G4** — Entitlements: add iCloud KVS + Sign in with Apple to `.entitlements` + `project.yml`.
- **G5** — Remove dead power-up upgrade system (`powerUpLevels`).
- **G6** — Hardening/accessibility: guard swipes to `.play`, VoiceOver labels, extend reduce-motion, cancel PLAY pulse onDisappear, GC error handling.

## H. Build order (gameplay-first)
1. A1 → 2. G3 → 3. A2 → 4. A3/D5 → 5. A5→B1 → 6. B2 → 7. B3,B5,B6 → 8. A4→C1+E1 → 9. B4 →
10. D1,D2,D3 → 11. C2,C3,C4,C5 → 12. E2,E3,E4,E5 → 13. G4 → 14. G1,G2 → 15. G5,G6,B7,B8,F6 →
16. F1,F2,F3 → 17. F4,F5
