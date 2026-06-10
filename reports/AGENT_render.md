# AGENT_render — Render/VFX pass handoff

Files touched (all within ownership): `PrismRush/Render/Reality/RealityRenderer.swift`,
`EntityPools.swift`, `ParticleSystem.swift`, `ProceduralMesh.swift`, `WorldDecor.swift`.
`RendererPort.swift` is **unchanged** — no protocol additions were needed.

## Fixes (reviewer-verified issues)

### P0 — WorldDecor never resets
- `WorldDecor.reset(distance:)` re-seeds every slot `s.d = distance + Float(pairIndex) * gap - span/2`
  and flags `needsRestyle` (styling is deferred to the next `update`, which knows the current world).
- `RealityRenderer.resetEntities()` now calls `decor.reset(distance: 0)`. It deliberately passes 0:
  `resetEntities()` is invoked by GameView with no arguments (I don't own that file), and for
  checkpoint starts (distance = world × 800) the new recycle loop self-heals on the first
  `update` frame — see next bullet — so decor is correct immediately for any start distance.
- The single-step recycle is now `while z > 14 { s.d += span }` followed by **one** restyle, so a
  large forward distance jump converges in one frame instead of ~26 frames of stream chaos.

### P0 — Residual per-frame material churn
- `sync` computes a palette key: `(worldFrom % 3) &* 4096 &+ (worldTo % 3) &* 256 &+ Int(worldBlend * 64)`
  (fields can't collide: blend ≤ 64 < 256, to ≤ 768 < 4096). Only when the key changes (i.e. during a
  crossfade, in 1/64-blend steps) does it construct a `Palette` and rebuild/reassign materials for:
  backdrop, the 36 grid rungs (**one** shared `UnlitMaterial`), the 4 lane lines (one shared
  material), character body+antenna (shared), antenna tip, and `matAccent`/`matAccent2` (the D1
  obstacle materials are folded into the same key path; the old per-frame `UIColor.isEqual` keys
  are gone). Steady state (`worldBlend == 1`, ~95% of frames) allocates nothing and constructs no
  `Palette`/UIColors.
- `applySkin` invalidates the key (`paletteKey = -1`) so a skin change recolors next frame.
- The old `setColor(_:_:)` helper (one fresh material per call) is deleted.

### P1 — Frame-rate-dependent particle emission
- Trail (180/s ≈ old 3/frame@60Hz), slide dust (360/s ≈ old 6/frame@60Hz) and speed lines all use
  time-based accumulators (`debt += rate * lastDt; emit Int(debt); debt -= emitted`). `lastDt` is
  captured in `advanceVisuals`, which GameView calls immediately before `sync` every frame, so dt
  is always current. Identical density at 60 and 120 Hz; debts are zeroed in `resetEntities()`.
- `ParticleSystem.burst` no longer allocates an `UnlitMaterial` per call: materials are cached per
  `UIColor` (`matCache`, hard-capped at 64 entries → bounded even across crossfade tint steps).
  `burst` also early-returns for `count <= 0`.

### P1 — `EntityState.fading`
- In the `.gem` arm of the pools place closure: fading gems lerp scale toward 0.55
  (`scale += (0.55 - scale) * 0.35`) and swap to a cached hotter material (`matGemHot`, warm
  white-gold). Non-fading gems with non-1 scale (recycled pooled entities) snap back to scale 1 and
  the cached gold material — no per-frame churn in the common path.

### P2 — Reduce Motion
- `reduceMotion` is now a `var`, seeded at init and updated live via
  `UIAccessibility.reduceMotionStatusDidChangeNotification` (block observer on `.main`, body in
  `MainActor.assumeIsolated`, matching the GameView update-loop pattern). It gates: screen shake
  (position + roll), the FOV speed-punch (the `+9°` speed term is zeroed), the transient FOV kicks,
  the slide camera roll, and speed lines. The observer token is retained for the renderer's
  lifetime (the renderer is app-lifetime; no deinit removal needed).

### P2 — Bar y
- The renderer now reads `s.y` for every kind, with one guard:
  `(s.kind == .bar && s.y == 0) ? 1.3 : Float(s.y)`. Reason: at the time of writing,
  `GameCore.swift:442` still emits `y = 0` for `.bar`, so unconditionally trusting `s.y` would sink
  bars into the track if the render change lands first. Once the core makes `EntityState.y`
  authoritative (1.3 for static bars), the fallback is inert and may be deleted. Pistons (which
  oscillate y) are unaffected by the guard since they use a different kind.

### P3
- `EntityPools.sync` reuses a `vanished` scratch buffer (ivar, `removeAll(keepingCapacity:)`).
- WorldDecor bob wraps elapsed with `truncatingRemainder(dividingBy: 2π)` before the `Float`
  conversion — continuous (sin period) and bounded.

## Polish

1. **Speed lines** — above speed 26 (play mode, not Reduce Motion): rate ramps
   `min(70, (speed-26)*6)`/s via accumulator; each line spawns at x ±4.5 (±0.5 jitter), y 2–5,
   z −8, `velZ = speed * 1.5`, `stretchZ: 2.8`. `burst` gained optional `velZ` (added to random z
   velocity) and `stretchZ` (> 1 renders the particle as a thin streak scaled
   `(0.05, 0.05, stretchZ)`, length fading with life). Defaults keep every existing call site valid.
2. **Gem-streak escalation** — `tier = min(3, streak / 8)`; count `12 + 4*tier`; color ladder
   gold → cyan → magenta → white.
3. **Slide skid** — pool of 4 flattened dark boxes (0.9 × 0.01 × 2.4) built in `buildScene`; on
   `.slid(x)` one is dropped at `(x, 0.005, 0.3)`, scrolls back with `lastSpeed`, fades via scale
   over 0.9 s (`stepSkids` in `advanceVisuals`). Cleared in `resetEntities()`.
4. **World-crossfade flourish** — `fire(.worldChanged)` emits `ParticleSystem.ring(...)`: 24
   particles on a circle (y 4.5, z −42, r 9) in the incoming world's accent, rushing at the player
   (`velZ 26`), plus an FOV kick. Lane lines are pushed toward white by `(1 − blend) * 0.85`
   (`Palette.lane`), folded into the palette-key recolor path — alloc-free in steady state.
5. **Camera** — smoothed z-roll to −0.04 while sliding, composed onto the look-at orientation
   (same composition pattern as the shake roll); transient `fovKick = 3°` on pickup and world
   change, decaying at 12°/s (≈0.25 s, same decay pattern as shake in `advanceVisuals`). Both
   Reduce Motion-gated.
6. **Decor variety** — one alternate silhouette per world, 35% chance at restyle, sharing the three
   existing static meshes (no new meshes): Metropolis spire = two stacked thin boxes (towerMesh),
   Caverns stalagmite cluster = 2 grounded cones (crystalMesh, `floating = false`, no bob),
   Sands obelisk = tall thin pyramid (pyramidMesh, scale (0.22, h/4, 0.22)). Each slot carries two
   reusable `altA`/`altB` ModelEntities whose `ModelComponent` is swapped at restyle (rare).
7. **`twinOctahedron`** added to `ProceduralMesh` (gem vertex set duplicated at ±offset on x,
   rebased indices, one `MeshDescriptor`); `doublerMesh` is built at renderer init
   (`twinOctahedron(0.26, offset: 0.34)`) ready for the `.doubler` arm.

## NOT yet wired (core hasn't landed it — re-checked Models.swift at finish time)

`Core/Models.swift` still has **no** `.doubler` / `.piston` `EntityKind` cases, no doubler `FXEvent`,
and no `GameSnapshot.timeScale`. To keep the Xcode build compiling I left clearly-marked
`// INTEGRATION` commented arms instead of dead cases. When the core lands, the integrator flips:

1. **`makeEntity`** (RealityRenderer, bottom): uncomment
   `case .doubler: ModelEntity(mesh: doublerMesh, materials: [UnlitMaterial(color: uiHex(0x00FF88))])`
   and `case .piston: boxEntity(7.6, 0.7, 0.7, .magenta)`. The switch is exhaustive, so the compiler
   will point straight at it.
2. **Pools place closure** (in `sync`): uncomment the `.doubler` arm (spins like the magnet, via
   `s.spin`) and `.piston` arm (recolors with `matAccent2`; its y already flows from `s.y`).
3. **`fire`**: uncomment the doubler-pickup case (36-count gold + emerald `0x00FF88` split burst +
   `kickFOV()`); rename the case pattern to whatever the core calls it
   (placeholder: `.doublerCollected(x, y)`).
4. **Frenzy** (`timeScale`): two marked spots in `sync` — add `+8°`/`−6°` to the FOV expression for
   timeScale >1/<1 (gate with `!reduceMotion`), and multiply the 180/s trail rate by
   `Float(snapshot.timeScale)`.

## What I need from snapshot/FXEvent (summary)

- `EntityState.y` authoritative for `.bar` (1.3) — fallback in place until then.
- `EntityKind.doubler` / `.piston` — render side ready behind comments.
- A doubler-pickup `FXEvent` case — burst ready behind comments.
- `GameSnapshot.timeScale` — FOV/trail hooks marked.

## Honesty / not verifiable on Linux

- RealityKit/UIKit code **cannot compile or run here**; the Render files are excluded from the
  SwiftPM target, so `swift test` does not type-check them. I hand-verified API usage against the
  existing patterns in this codebase (e.g. `ModelComponent(mesh:materials:)`, `camera.look`,
  `MainActor.assumeIsolated`, `@Sendable` notification block capturing the implicitly-Sendable
  `@MainActor` class), and all six Render files pass a parse-only check
  (`swiftc -parse`, exit 0 — syntax only, no type-checking). A Mac build is required to confirm: the notification-observer closure
  under Swift 6 `complete`, the visual tuning numbers (ring z −42, speed-line rate, skid fade,
  spire/stalagmite proportions), and that the (0.05, 0.05, 2.8) streak scale reads well at distance.
- `swift test -c release` (pure-Swift suite) run after all edits: **43 tests, 0 failures** (the
  suite has grown beyond the original 38 — other agents are adding tests concurrently; all green).
- Other agents had uncommitted edits to Core/Audio/Tests in the worktree while I worked; I touched
  none of those files and ran no git commands.
