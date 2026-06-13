# Prism Rush v1.5 Phase 2 — 12 Distinct Worlds: Final Implementation Blueprint

> Reconciles the 12-world art/systems design against the adversarial feasibility critique. Every claim below has been mapped to the real codebase. The two CRITICAL findings (C1 white-bg renderer break, C2 `evolvedPalette` divisor) are resolved up front; the HIGH findings (side-decor scope, mesh-factory specs, animation honesty) are folded into the build order and pattern templates. The implementer edits shared files sequentially and verifies each increment with a Mac build + the solvability bot + an on-sim screenshot.

---

## 0. Reconciliation summary — what the critique changed

| Critique finding | Severity | Resolution adopted in this blueprint |
|---|---|---|
| **C1** World 12 white bg breaks obstacles/ground/gems/FX (none read the world palette) | CRITICAL | **World 12 ships on a deep-violet bg, radiant-white motif only.** No light-bg renderer path. Playfield stays dark-on-glow like every other world. Zero `RealityRenderer` changes. |
| **C2** `evolvedPalette` cycle divisor stays `/3` → worlds 0–11 get corrupted suffixes/hues | CRITICAL | Change the **family divisor AND the cycle divisor together**: `% 3 → % 12` and `cycle = o/3 → o/12`. Pin with a cycle-0 identity test. |
| **H1** Side decor is 9 real set-pieces, not one table cell; `Slot` hardcodes 5 meshes | HIGH | **Generalize `Slot` to one swappable `ModelEntity` + a 12-entry recipe table** before adding worlds 4–12. Re-estimated as 9 distinct decor builds. |
| **H2** `tentacleStrip` is a tapered **ribbon**, not a rotated ridge; `gridCard` needs baked spacing | HIGH | Re-specced both factories precisely below. `gridCard` perspective = baked non-uniform row spacing. |
| **H3** Baked-wave meshes can't phase-scroll per frame; "flow" is really "slide" | HIGH | All "flow" promises downgraded to **parallax slide** (matches shipped aurora). Stated honestly per world. |
| **M1** `famRoots`/`famTints` need exactly 12 entries, switches need 12 explicit cases, no `default` | MEDIUM | Enforced in the family template + infra section. |
| **M2/M3/M4** Music `WorldBed` table, modulus RNG-safety, preview `% 12` | MEDIUM | Confirmed sound; folded in. |

**The single biggest scope correction:** the design's "change surface" table treats side decor as one row. It is **9 distinct set-pieces**, each comparable to an existing family's decor. The `Slot` generalization (H1) is therefore a *prerequisite* infra task, landed before any bespoke world.

---

## 1. FINAL 12-world table

Hex is `Theme.rgb(0xRRGGBB)`. "Reuse" = existing `buildMetropolis/Caverns/Sands` family, no new code beyond palette refine. "New N" = bespoke `buildX/restyleX/animateX`. All bgs stay dark enough for dark-on-glow obstacles (decree 6) — **World 12 deliberately uses a deep-violet bg, not white** (C1 resolution).

| # | Name | Mood (one line) | bg | grid | accent | accent2 | Sky family | Motif (one line) |
|---|---|---|---|---|---|---|---|---|
| 1 | **Pulse City** | Neon synthwave skyline at midnight — home turf | `0x06021C` | `0xFF2BD6` | `0x18F0FF` | `0xFF49DE` | **Reuse Metropolis** (fam 0) | Blinking-window towers, searchlight beams |
| 2 | **Geode Deep** | Hushed crystal cavern lit by violet shards | `0x02131A` | `0x00FFC8` | `0xB26BFF` | `0x35FFD8` | **Reuse Caverns** (fam 1) | Stalactites + floating octahedron shards, aurora bands |
| 3 | **Solar Sands** | Dusk desert under a swollen sun, ringed planets | `0x1C0A02` | `0xFFB13D` | `0xFF5E3A` | `0xFFD23D` | **Reuse Sands** (fam 2) | Dunes, obelisks, ringed planet |
| 4 | **Orbital Drift** | Weightless silence above a blue planet — a tethered astronaut drifts | `0x01030E` | `0x2E5BFF` | `0x6FE8FF` | `0xE9F4FF` | **New 3** | Planet limb + drifting astronaut (sphere head, box suit) + satellites + stars |
| 5 | **Tidal Glow** | Bioluminescent trench — jellyfish pulse in warm aqua dark | `0x010F12` | `0x0AE0D2` | `0x33FFE0` | `0xB17BFF` | **New 4** | Jellyfish (flattened sphere bell + torus rim + tentacle strips) + light shafts + plankton |
| 6 | **Ashfall** | Volcanic night — lava crawls, embers rise, a cone smolders | `0x140402` | `0xFF7A1A` | `0xFF3D1A` | `0xFFC23D` | **New 5** | Pyramid volcano + lava-pool disc + ember motes + ash ridges |
| 7 | **Borealis** | Frozen tundra under rippling aurora curtains | `0x040A14` | `0x4FFFB0` | `0x6FD8FF` | `0xC8A8FF` | **New 6** | Aurora ribbons + ground ice shards + snow plain + snowfall (closest Caverns derivative) |
| 8 | **Datastream** | Inside the machine — a Tron grid recedes to a glowing point | `0x000308` | `0x00E5FF` | `0x18FFE0` | `0xFFFFFF` | **New 7** | `gridCard` horizon grid + vanishing-point glow + vertical beam pylons + ordered motes |
| 9 | **Bloomfall** | Cherry-blossom grove at night — petals fall through pink light | `0x0E0414` | `0xFF8FC8` | `0xFFB3D9` | `0xFFE08A` | **New 8** | Trunk boxes + oblate-sphere canopies + petal motes + disc moon |
| 10 | **Eventide** | The edge of a black hole — accretion disc warps around a void | `0x040108` | `0x9B3DFF` | `0xFF6FD8` | `0xFFC04D` | **New 9** | Disc hole + two flattened tori (accretion) + polar beams + nebula motes (zero new factory) |
| 11 | **Tempest** | Violent lightning storm — bolts split the dark, rain streaks | `0x06061A` | `0x6A5BFF` | `0xBFA8FF` | `0xFFFFFF` | **New 10** | Cloud ridges + `isEnabled`-flashed beam-chain bolts + stretched rain motes |
| 12 | **Singularity** | The white endgame — radiant core, rainbow rings, pure light | `0x140A2E` | `0xFF4DA6` | `0x4DC8FF` | `0xFFD24D` | **New 11** | Bright disc core + concentric rainbow tori + radial beams (on **deep-violet bg**, not white) |

> **World 12 bg note (C1 resolution):** original design called `bg: 0xF2F0FF` (near-white). That breaks the hardcoded near-black ground plane (`RealityRenderer.buildScene` line 676), bright-accent obstacle materials (lines 333–343), gold gems (lines 152–153), and white/bright trail+shatter FX (lines 27, 428–445) — none of which read the world palette. **Resolution: `bg = 0x140A2E` (deep violet-black).** The "white endgame" reads through the radiant white **core disc + rainbow rings + background wash**, which are bright on a dark field exactly like every other world's glow. The playfield stays calm and dark-on-glow (decree 6 holds). No renderer code path is added. If a true light-bg finale is ever funded, it is a separate renderer task (per-world ground color, light-world obstacle ink, gem retint, FX retint) — explicitly out of Phase 2 scope.

---

## 2. INFRASTRUCTURE changes (do these FIRST — Phase 2a)

These five edits break the 3-world loop immediately. After 2a, worlds 4–12 already exist as **recolored reuse families** (palette + name correct, motif temporarily borrowed) — nothing looks broken, and every bespoke world (2b onward) is a pure additive swap.

### 2a.1 — `Theme.swift`: expand `worlds` 3 → 12, fix BOTH divisors

**File:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/UI/Theme.swift`

Replace the 3-entry `Theme.worlds` array with 12 entries (names + hex from §1, using the existing `rgb(0x…)` helper). Then fix `evolvedPalette`:

```swift
// BEFORE (line ~47–48):
let base = worlds[o % 3]
let cycle = o / 3

// AFTER — both divisors move to worlds.count together (C2):
let base = worlds[o % worlds.count]   // worlds.count == 12
let cycle = o / worlds.count          // 0 for worlds 0–11 → strict identity, no roman suffix
```

- **Why both:** if only `% 3 → % 12` changes but `cycle` stays `o/3`, world 3 ("Orbital Drift") gets `cycle = 1` → hue rotation + "II" suffix on first sight. Worlds 0–11 must be `cycle 0` = byte-identity to their authored palettes.
- `evolutionRampCycles`, the HSB shift math, and `roman()` are **unchanged** — infinite-run evolution now kicks in at world 12 (`cycle 1`), which is correct: "Pulse City II" etc. appear only past the authored set.
- Use `worlds.count` literally (not `12`) everywhere so a future 13th world is a one-line array append.

**New test** (add to a Theme/palette test target, Linux-testable since `Theme` is pure):

```swift
func testWorlds0to11AreCycleZeroIdentity() {
    for o in 0..<Theme.worlds.count {
        let evolved = Theme.evolvedPalette(ordinal: o)
        XCTAssertEqual(evolved.name, Theme.worlds[o].name,         // no roman suffix
                       "world \(o) must keep its authored name (cycle 0)")
        XCTAssertEqual(evolved.bg, Theme.worlds[o].bg,             // byte-identity
                       "world \(o) bg must equal authored palette (cycle 0)")
    }
}
```

### 2a.2 — `GameCore.stepWorld`: modulus `% 3 → % worldFamilyCount`

**File:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Core/GameCore.swift` (around line 225–236)

```swift
// BEFORE:
let wi = ((wn % 3) + 3) % 3

// AFTER:
let wi = ((wn % Theme.worlds.count) + Theme.worlds.count) % Theme.worlds.count
```

(If `Core/` must not import the UI `Theme`, mirror the count as a `Tuning.worldFamilyCount = 12` constant and assert `Tuning.worldFamilyCount == Theme.worlds.count` in a test. Given the existing seam, prefer the `Tuning` constant to keep `Core/` Foundation-only.)

**RNG-safety verdict (cite the architecture map, confirmed by the critique M3):** `stepWorld` is **pure arithmetic on `distance`** — zero `rng.unit()`/`rng.int()` calls. `Spawner.fill` never reads the world index (`maxIndex`/`gap` are pure `f(dist)`). Changing the modulus consumes **no RNG**, produces **byte-identical** obstacle layouts across all 200 seeds, and the only behavioral change is which palette family each 800 m segment maps to (a cosmetic `FXEvent.worldChanged` + snapshot field effect).
**→ `DailyChallenge.layoutVersion` does NOT need to bump. The solvability bot is unaffected.** (Verify anyway by running the bot post-change — see build order.)

### 2a.3 — `WorldSky` / `WorldDecor`: family selection `% 3` → `worlds.count`-aware

**File:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Render/Reality/WorldDecor.swift`

The goal: **worlds 1–3 keep Metropolis/Caverns/Sands; worlds 4–12 each get a new family root.** Replace the `fam = world % 3` family index with a **direct ordinal-keyed mapping into a 12-slot family array**.

**Step A — size the family arrays to exactly 12 (M1):**
```swift
// WorldSky:
famRoots = [metroRoot, cavernRoot, sandsRoot,
            orbitalRoot, tidalRoot, ashfallRoot, borealisRoot,
            datastreamRoot, bloomfallRoot, eventideRoot, tempestRoot, singularityRoot]
// must satisfy famRoots.count == Theme.worlds.count == 12
famTints = Array(repeating: [], count: Theme.worlds.count)   // was [[],[],[]]
```

**Step B — family selector keyed off absolute ordinal, folded to family count:**
```swift
let fam = ((world % famRoots.count) + famRoots.count) % famRoots.count
```
This keeps worlds 0/1/2 → metro/cavern/sands and gives 3…11 their own roots, and folds 12+ back to fam 0 (Pulse City) for infinite runs — matching the palette cycle.

**Step C — `update` and `restyle` switches: 12 explicit cases, NO `default` fallthrough (M1):**
```swift
switch fam {
case 0:  animateMetropolis(...)
case 1:  animateCaverns(...)
case 2:  animateSands(...)
case 3:  animateOrbital(...)
// ... cases 4–10 ...
case 11: animateSingularity(...)
default: break   // unreachable; never silently maps world 11 → Sands
}
```
Same shape for `restyle`. A silent `default` mapping the wrong world to Sands is an invisible decree-2 violation ("previews never lie" extends to the live sky).

**Step D — `WorldDecor.style`:** change `let w = world % 3` to the `worlds.count`-aware fold, and replace the `(w, alt)` switch (currently branches only for `w == 0/1/2`) with the **generalized recipe-table lookup** from H1 (see §2a.4).

> **Phase 2a stub strategy (so the loop breaks before any motif exists):** in 2a, point `famRoots[3…11]` at *recolored copies of an existing family root* (e.g. all initially alias the Sands or Caverns root) and let `restyle` tint them with the new palettes. The screen now shows 12 named, distinctly-colored worlds with borrowed silhouettes — nothing crashes, nothing looks broken. Each bespoke world (2b+) then replaces one alias with a real `buildX` root. This is the "breaks the loop immediately, even if 4–12 temporarily reuse a recolored family" requirement.

### 2a.4 — `WorldDecor.Slot` generalization (H1 — prerequisite for worlds 4–12)

`Slot` currently hardcodes 5 mesh members (`tower`, `crystal`, `pyramid`, `altA`, `altB`) and `style()` switches `(w, alt)` only for `w ≤ 2`. Adding 9 more hardcoded members will blow the 800-line file limit and won't scale.

**Refactor:** make each `Slot` hold **one swappable `ModelEntity` + a per-world mesh/scale/material recipe**, driven by a 12-entry table:

```swift
struct DecorRecipe {
    let makeMesh: () -> MeshResource     // built once per world on first use, then cached
    let scale: SIMD3<Float>
    let tintRole: TintRole               // .accent / .accent2 / .grid — resolved via evolvedPalette
}
// One entry per family ordinal 0–11. style(world:) folds world→fam, looks up recipe,
// swaps the slot entity's model + materials only when the family actually changes
// (guard on a stored lastFam to avoid per-frame mesh churn — Iron-rule per-frame alloc ban).
```

- Cache built meshes per family (build-once); the per-frame `update` only writes transforms + `isEnabled`.
- This keeps `WorldDecor.swift` under 800 lines and makes worlds 4–12 each a **single table row + one `makeMesh` closure**, not 9 new struct fields.
- Decor meshes reuse the same primitive set as the sky motifs (see §3 per-world decor).

### 2a.5 — `LevelSelectView` / `WorldPreviewCanvas`

**File (preview):** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/UI/WorldPreviewCanvas.swift`
- `ProfileStore.worldDisplayCount` is **already 12** — no change.
- Change the motif selector `switch worldIndex % 3` → `worldIndex % 12` and add **9 new `draw*` functions** (recipes in §3). In Phase 2a, route the new indices to the existing `drawTowers/Crystals/Dunes` (recolored) so cards render; replace one per bespoke world to honor **decree 2 (previews never lie)** — each 2D recipe must match its 3D motif's silhouette + colors.
- All name strings already flow from `palette.name` via `evolvedPalette` (8 visual + 5 accessibility sites in `LevelSelectView.swift`) — **zero edits needed there**; they pick up the 12 new names automatically.

**File (level select):** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/UI/LevelSelectView.swift` — **no changes** (all ordinal/`world+1` and `palette.name` driven).

### 2a.6 — `Synth.step(beat:world:)`: 12-entry `WorldBed` table (M2)

**File:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Audio/Synth.swift` (lines ~252–304)

Replace the 3-entry parallel arrays (`rootShift`, `scales`) + the `% 3` fold with a **single 12-entry `WorldBed` table keyed off the absolute ordinal**:

```swift
struct WorldBed {
    let rootMidi: Int      // tonic
    let scale: [Int]       // 4 intervals used by bass/arp
    let hasSparkleArp: Bool
    let hatVolBoost: Float
    let layerCount: Int    // fold the old cycle layering in per-world (decouple from world/3)
    let noKick: Bool       // W4 Orbital = no driving beat
}
private static let beds: [WorldBed] = [ /* 12 entries, one per §1 world's Music line */ ]

static func step(beat: Int, world: Int) -> [Float] {
    let bed = beds[max(0, min(world, beds.count - 1))]   // clamp; 12+ reuse W11 character or fold % count
    ...
}
```

Per-world characters (from the design's Music lines): W1 A2 minor-7th driving / W2 B2 open sparkle / W3 G2 sus4 airy / W4 D2 lydian-maj7 **no kick** / W5 E2 pentatonic-soft 6/8 / W6 C2 tritone heavy / W7 A2 **major-7th** glassy / W8 E2 minor **double-tempo** square-arp / W9 F#2 major-pentatonic koto / W10 C2 flat-2 dissonant drone / W11 A2 harmonic-minor tremolo / W12 C3 **major-9th** lush resolve.

`Synth.step` is pure, RNG-free (`noise()` uses fixed seed), Foundation-only, Linux-tested. **Pin tests** (`Tests/CoreTests/SynthTests.swift`):
```swift
func testAllWorldsHaveDistinctCharacter() {
    var bars: [[Float]] = []
    for w in 0..<Theme.worlds.count { bars.append((0..<8).flatMap { Synth.step(beat: $0, world: w) }) }
    for i in 0..<bars.count { for j in (i+1)..<bars.count {
        XCTAssertNotEqual(bars[i], bars[j], "worlds \(i)/\(j) sonically identical") } }
}
```
Keep `noise()`'s explicit seed constant — **never `Date()`/`Int.random`** in the music path.

---

## 3. NEW SKY FAMILY pattern (copy per bespoke world)

Every bespoke world (4–12) is the **same six-touchpoint additive change**. The engineer copies this template, fills the per-world meshes, and changes nothing in the playfield/sim.

### 3.0 The six touchpoints (checklist per world)

1. **`Theme.worlds[N]`** — palette + name (already landed in 2a).
2. **`WorldSky`**: add `Entity` root to `famRoots[N]`, a `[]` already in `famTints[N]` (sized in 2a), write `buildXRoot` and call it in `init`.
3. **`WorldSky.update` switch** `case N: animateX(...)`.
4. **`WorldSky.restyle` switch** `case N: restyleX(...)`.
5. **`WorldDecor`** recipe-table row N (the side-decor set-piece).
6. **`WorldPreviewCanvas`** `drawX(...)` for index N.
7. **`Synth.beds[N]`** — already landed in 2a; tune per world.

### 3.1 `buildX` template (build-once geometry)

```swift
private func buildX() {
    var rng = SplitMix64(seed: UInt64(/* family ordinal */ 0xCAFE &+ N))  // LOCAL seed, never run RNG
    let pal = Theme.evolvedPalette(ordinal: N)
    let root = Entity(); xRoot = root; root.isEnabled = false
    famRoots[N]'s root added under self.root once.

    // SET PIECES: build each from the verified primitives, parent under root.
    // Pool the repeated motes/particles with a CAP constant (e.g. let starCap = 40).
    // Register every entity whose tint must restyle:
    register(entity, fam: N, TintRecipe(base: pal.accent, role: .accent))
}
```
- **Build once.** Geometry never rebuilt per frame.
- **Pool caps** are explicit constants (mirror the existing `lines 199–201` cap pattern). Motes/stars/embers/rain/petals all capped.
- **Local `SplitMix64`** seeded from the family ordinal — deterministic cosmetic placement, **never the run RNG** (Iron rule 2).
- `register(_:fam:_:)` records each entity into `famTints[N]` so `restyleX` can recolor on palette crossfade.

### 3.2 `restyleX` template
Walk `famTints[N]`, set each entity's `UnlitMaterial(color:)` from the crossfaded `evolvedPalette`. Mirror `restyleCaverns`/`restyleSands`. No geometry change.

### 3.3 `animateX` template (transform + `isEnabled` ONLY)
```swift
private func animateX(elapsed: Double, reduceMotion: Bool) {
    if reduceMotion { /* set a single static pose, return */ }
    // per-frame: position/scale/orientation writes + isEnabled toggles. ZERO allocation.
}
```
- **RM-gated**: Reduce Motion → one static frame.
- **Honest motion (H3):** baked-wave meshes (`ribbon`, `ridge`) can only **parallax-slide**, not phase-flow. Lava "flow", grid "flow toward camera", aurora ripple = **slow lateral/vertical slide + amplitude/scale breathing** — exactly what shipped `animateCaverns` does. Do not promise per-frame phase scroll (would require banned per-frame mesh rebuild).

### 3.4 Per-world set-piece mesh recipes (from the verified primitive catalog)

Primitives: `disc`, `skyline`, `ridge`, `beam`, `ribbon`, `torus`, `pyramid`, `octahedron(rx:ry:rz:)`, `chevronStrip` + RealityKit `.generateSphere/.generateBox/.generateCone/.generatePlane`. **Only two new factories total.**

- **W4 Orbital (New 3) — zero new factory.** Planet limb: `.generateSphere` (large, low) + `disc` atmosphere-rim child. Astronaut entity tree (mirrors blimp body+fin assembly): helmet `.generateSphere(r≈0.5)` + visor `disc` child (dark, tilted); torso/backpack/4 limbs = scaled `.generateBox`; tether = `ribbon(width:3, thickness:0.04, amplitude:0.15, waves:1.2)` rotated off-frame. Satellites: `.generateBox` core + `disc` solar wings + blinking `disc` nav-light (`isEnabled` toggle). Stars: capped `disc` mote pool. **Decor:** solar-array masts (`.generateBox` + `disc`/`generatePlane` panels).
- **W5 Tidal (New 4) — NEW factory `tentacleStrip`.** Jellyfish: bell `.generateSphere` scaled `(1,0.6,1)` + rim `torus(major:1.0,minor:0.06)` + core `disc` + 4–6× `tentacleStrip` hung down. Light shafts: `beam(length:8,…)`. Plankton: `disc` motes. Seabed: `ridge`. **Decor:** kelp = thin low-amplitude `tentacleStrip` + coral `octahedron(rx:small,ry:tall,rz:small)`.
- **W6 Ashfall (New 5) — zero new factory.** Volcano: `pyramid(halfBase:3,height:4)` + base `disc` lava-pool (scale-pulse breathing). Lava: `ribbon` laid flat (parallax-slide, not flow — H3). Embers: capped `disc` motes (fast rise, flicker). Ash: `ridge`. Far peaks: sharp `ridge`. **Decor:** basalt `.generateBox` obelisks + cracked-seam `disc` strip + `pyramid` rubble.
- **W7 Borealis (New 6) — zero new factory** (closest Caverns derivative). Aurora: 3–4× `ribbon(width:12,amplitude:1.2,waves:1.5,phase varied)` (slide + breathe). Ice shards: `octahedron(rx:0.3,ry:1.4,rz:0.3)` at ground. Snow plain: low `ridge`. Snowfall: `disc` motes (downward). **Decor:** ice monoliths = tall `octahedron` + internal `disc` glow (recolored Caverns silhouette).
- **W8 Datastream (New 7) — NEW factory `gridCard`.** Horizon grid: one `gridCard` (perspective via **baked non-uniform row spacing** — H2). Vanishing glow: large dim `disc`. Pylons: `beam(length:6, halfWidthNear/Far:0.04)` (`isEnabled` flicker, **local-seeded cadence**). Motes: orderly `disc` columns (no sway). Corners: reuse `chevronStrip`. **Decor:** `.generateBox` posts + small `gridCard` panel + `chevronStrip`.
- **W9 Bloomfall (New 8) — zero new factory.** Trees: trunk `.generateBox` + branches `beam(length:2, taper)` + canopy `.generateSphere` scaled `(1,0.7,1)` (sway). Petals: `disc` motes (downward, wide sway, off-axis tilt). Lanterns: bright `disc` (scale flicker). Hills: `ridge`. Moon: single large `disc`. **Decor:** stone lantern `.generateBox` + flame `disc` + `beam` branch + canopy spheres.
- **W10 Eventide (New 9) — zero new factory.** Hole: large near-black `disc`. Accretion: 2× `torus(major:3.0,minor:0.5,majorSeg:32)` scaled `(1,1,0.18)`, different tints, slow spin. Horizon ring: `torus` at 1.05× (scale pulse). Nebula: large dim `disc` pool. Jets: 2× `beam` 180° apart. Stars: `disc` motes. **Decor:** tumbling `octahedron` asteroids + rim `disc` glints.
- **W11 Tempest (New 10) — zero new factory.** Clouds: sharp `ridge` (top) + wider rear `ridge`. Bolts: 2–3 groups, each a chain of 3–4 `beam(length:2, taper)` at alternating angles, **all `isEnabled`-flash together in a 2-frame strobe on a LOCAL-seeded cadence** (never run RNG, never `Date()` — critique LOW + Iron rule 2) + synced `disc` ground-flash. Rain: `disc` motes scaled `(0.2,1.5,1)` streaks (fast downward). Haze: large dim `disc` (`isEnabled` pulse). **Decor:** `.generateBox` masts + `octahedron` tip + flash-synced `disc` glint.
- **W12 Singularity (New 11) — zero new factory, deep-violet bg.** Core: bright `disc` (max). Rings: 5–6× `torus(major increasing, minor:0.08)` flattened in Z, spectrum tints (expand-and-recycle via scale, RM-gated). Rays: 8× `beam(length:5, taper)` at equal Y intervals (slow group rotation). Flare: `disc` pool along an offset axis (static). Wash: largest dim `disc` farthest. **Decor:** prismatic `octahedron` arch shards (per-shard spectrum tint) + small `torus` halos.

### 3.5 Two new `ProceduralMesh` factories (the ONLY mesh additions)

**File:** `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Render/Reality/ProceduralMesh.swift`

**`tentacleStrip(length:width:amplitude:segments:)` — modeled on `ribbon`, NOT `ridge` (H2):**
A **two-rail tapering strip** in the XY plane, verts running down −Y. For each sample `i` in `0…segments`: center x-offset = `amplitude * sin(t)` (wave baked at build), half-width = `width * (1 - i/segments)` (tapers to a point at the tip). Emit left/right rail verts per row; `(segments−1)×2` triangles. CCW-from-+Z. ~25 lines, same emit loop as `ribbon`. (`ridge` fills to a y=0 baseline — wrong shape for a free-hanging tentacle; do **not** use it as the template.)

**`gridCard(width:height:cols:rows:lineThickness:)` — modeled on `skyline`'s batching (H2):**
One flat XY card encoding `cols` vertical + `rows` horizontal thin quads in a single mesh (one draw call). **Perspective is baked via non-uniform row spacing** — rows packed closer toward the top (vanishing) edge so the static card reads as a receding grid; columns may also fan toward the center. `(cols+rows)×2` triangles. ~30 lines, mirrors `skyline`'s building-batch loop. (Evenly-spaced quads = parallel lines, not converging — the non-uniform spacing is the factory's actual job.)

Both new meshes: `MeshDescriptor` + `UnlitMaterial`, built once, no normals, with sphere fallback.

---

## 4. BUILD ORDER (phased, each increment verified)

> **Hard rule:** do NOT land 12 palettes + the `% 12` switch and "fill motifs later" naively — but the 2a stub strategy (recolored-alias families) makes that safe: the loop breaks with no broken-looking worlds, and each bespoke world is an isolated swap. **Foundations first, then prove with World 4, then iterate one world per increment.**

### Phase 2a — Infrastructure + 12 palettes/names (one or two commits)
**Land:** §2a.1 (`Theme.worlds` 12 + both divisors + cycle-0 identity test) → §2a.2 (`stepWorld` modulus) → §2a.4 (`Slot` generalization) → §2a.3 (family arrays sized to 12, switches to 12 cases, `famRoots[3…11]` aliased to recolored existing roots) → §2a.5 (preview `% 12`, new indices routed to recolored existing `draw*`) → §2a.6 (`WorldBed` table + uniqueness test).
**Verify:**
- `swift test -c release` — 89+ tests incl. new `testWorlds0to11AreCycleZeroIdentity`, `testAllWorldsHaveDistinctCharacter`. **The solvability bot (200×6,000 m + 12,000 m soak) must stay green** — confirms the modulus change is RNG-neutral (no `layoutVersion` bump).
- `./Tools/ci.sh` (Mac build + full suite, 95 tests).
- On-sim screenshot of the World Select screen showing **12 distinctly-colored, correctly-named cards** (borrowed silhouettes OK at this stage). Confirms decree 1/2 plumbing and no broken states.

### Phase 2b — World 4 "Orbital Drift" (the proving slice — owner headline)
Chosen first because it is the **least-risky bespoke world**: built entirely from existing built-ins + `ribbon` (**zero new factory**), dark bg (no readability risk), and it exercises the **full six-touchpoint family plumbing end-to-end** — `buildOrbital/restyleOrbital/animateOrbital`, `famRoots[3]` real root, `update`/`restyle` `case 3`, `WorldDecor` recipe row 3, `Theme.worlds[3]` (already), `beds[3]`, `drawOrbital` preview. The astronaut is the highest-value showpiece, so the slice doubles as the owner demo.
**Verify:**
- `./Tools/ci.sh` green (Mac build + tests).
- **Solvability bot green** (any sky/decor change still must not touch the sim — confirm zero core diff).
- On-sim: drive distance to ≥2400 m (or use a debug warp) so world 3 is live; screenshot the running game (astronaut + planet limb visible) **and** the World Select "Orbital Drift" card (preview parity with the 3D motif — decree 2). Verify obstacles readable in a single frame (decree 6).

**If World 4 ships clean, the pattern for 5–12 is proven.**

### Phase 2c… — Remaining worlds, ONE per increment
Recommended order (cheapest/safest → newest-factory → finale):
1. **W7 Borealis** — recolored Caverns aurora; cheapest second world, validates the retint registry under a new family.
2. **W10 Eventide** — zero new factory, proves torus-stacking.
3. **W6 Ashfall**, **W9 Bloomfall** — zero-new-factory composition worlds.
4. **W5 Tidal** (lands `tentacleStrip`) and **W8 Datastream** (lands `gridCard`) — the two factory-introducing worlds; add the factory + its mesh unit test in the same commit.
5. **W11 Tempest** — `isEnabled` flash bolts; verify cadence is **local-seeded** (grep the diff for `Date()`/`.random` in the render path — must be absent).
6. **W12 Singularity — LAST**, on the **deep-violet bg** (C1 resolved); verify the radiant-white core/rings read as the finale while obstacles stay dark-on-glow.

**Per-world verification (every increment):**
1. `./Tools/ci.sh` — Mac build + full test suite green.
2. `swift test -c release` — **solvability bot green** (proves no sim/RNG regression; a sky/decor change must produce zero `Core/` diff — if `layoutVersion` ever needs bumping you broke Iron rule 3).
3. On-sim screenshot: the running game at that world's distance **and** its World Select card — confirm preview↔in-game parity (decree 2), single-frame obstacle readability (decree 6), and no broken states (decree 3).
4. Never run `simctl launch`/screenshots on the dev sim while `xcodebuild test` runs on it (concurrent installs crash the test host).

---

## 5. RISKS / INVARIANTS checklist (every increment must pass)

**Iron rule 2 — all randomness through seeded RNG:**
- [ ] Cosmetic placement uses a **LOCAL `SplitMix64`** seeded from the family ordinal — never the run RNG, never `Date()`, never `.random`.
- [ ] Tempest bolt flash cadence + Datastream pylon flicker are local-seeded (grep diff: zero `Date()`/`.random` in `Render/`).

**Iron rule 3 — solvability + layoutVersion:**
- [ ] The world-index modulus change is **RNG-neutral** (confirmed: `stepWorld` pure arithmetic, spawner world-blind). **No `DailyChallenge.layoutVersion` bump.**
- [ ] Solvability bot (200 seeds × 6,000 m + 12,000 m soak) **green after every increment**.
- [ ] Any commit touching only `Render/`/`UI/`/`Audio/` produces **zero `Core/` diff** — if not, stop and re-examine (you may have leaked world index into the spawn path).

**Iron rule 4 — pattern order load-bearing:** untouched (no spawner/pattern changes in Phase 2).

**Decree 6 — clarity / single-frame readability:**
- [ ] Every world's bg stays dark enough for dark-on-glow obstacles. **World 12 uses `0x140A2E` deep-violet, NOT white** (C1) — no light-bg renderer path.
- [ ] Obstacle/lane/gem/ground/FX assumptions unchanged (all read existing dark-bg palette path).
- [ ] One gradient family per screen; UI stays calm; every input readable in a single frame.

**Decree 1/2 — identity + previews never lie:**
- [ ] Character identity constant across all worlds (no `followsWorld`).
- [ ] Each `drawX` preview matches its 3D motif's silhouette + colors before that world ships (no recolored-stub left in a shipped world).

**Pool caps / no per-frame alloc:**
- [ ] Every mote/star/ember/rain/petal pool has an explicit CAP constant.
- [ ] Geometry built once at `init`; per-frame `update` = transform + `isEnabled` writes only, **zero allocation**.
- [ ] No per-frame mesh rebuild (so "flow" is parallax-slide + breathe — H3, matches shipped aurora).

**Family-array safety (M1):**
- [ ] `famRoots.count == famTints.count == Theme.worlds.count == 12` exactly.
- [ ] `update`/`restyle` switches have 12 explicit cases, **no silent `default`** mapping a world to the wrong family.

**Determinism / Linux-testability:**
- [ ] `Synth.step` stays pure, RNG-free (fixed `noise()` seed), Foundation-only — `WorldBed` table + uniqueness/identity tests run on Linux CI.
- [ ] `evolvedPalette` cycle-0 identity test pins worlds 0–11 to authored palettes (C2 regression guard).

**Zero binary assets (Iron rule 6):**
- [ ] All meshes via `MeshDescriptor` + `UnlitMaterial`; only two new factories (`tentacleStrip`, `gridCard`); no textures/asset catalogs/sound files added.

**Files touched (verified):** `PrismRush/UI/Theme.swift` · `PrismRush/Core/GameCore.swift` (+ optional `Tuning.swift` constant) · `PrismRush/Render/Reality/WorldDecor.swift` · `PrismRush/Render/Reality/ProceduralMesh.swift` · `PrismRush/UI/WorldPreviewCanvas.swift` · `PrismRush/Audio/Synth.swift` · `Tests/CoreTests/SynthTests.swift` + new Theme palette test. **`RealityRenderer.swift` is NOT touched** (C1 resolved by deep-violet bg, not a renderer path).