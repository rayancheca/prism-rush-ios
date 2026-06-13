I now have everything verified: hex format (`rgb(0xRRGGBB)`), the three existing palettes, all primitive signatures. I have the complete picture to deliver the full 12-world design.

---

# Prism Rush — 12 Distinct Worlds: Final Art + Systems Spec

This is the implementation-ready catalog. Every palette is `Theme.rgb(0xRRGGBB)`. Every motif is composed from the verified primitive set: `disc`, `skyline`, `ridge`, `beam`, `ribbon`, `torus`, `pyramid`, `octahedron(rx:ry:rz:)`, `chevronStrip`, plus RealityKit built-ins `.generateSphere`, `.generateBox`, `.generateCone`, `.generatePlane`. Animation is transform/`isEnabled` only, geometry built once at `init`, cosmetic RNG is a LOCAL `SplitMix64` seeded from the world index (never the run RNG).

## The deliberate arc (read top to bottom)

The 12 form one descent from **human civilization → nature's depths → cosmic scale → annihilation/rebirth**. The `bg` value brightness walks a curve: dim-saturated city (1–3) → near-black naturals (4–7) → synthetic black (8) → soft night (9) → void black (10–11) → pure white blowout (12). Accent hue rotates roughly around the wheel: magenta/cyan → teal/violet → amber → ice-blue/white → aqua → orange/red → ice-green → cyan/white-on-black → pink/lilac → magenta/gold → violet/white → full rainbow. No two neighbors share a dominant accent hue, and obstacle readability is preserved because every `bg` stays dark enough (or, for #12, the obstacles invert to dark-on-white — see its note).

**New mesh factories required across all 12: exactly two** — `tentacleStrip` (Tidal Glow) and `gridCard` (Datastream). Everything else is pure composition. Sketches included.

---

## World 1 — Pulse City
*Mood: a neon synthwave skyline at the edge of midnight — the runner's home turf.*

**Family: REUSE existing `Metropolis` (`buildMetropolis` / `restyleMetropolis` / `animateMetropolis`).** No new sky family. This is `fam 0`.

- **PALETTE** (refined from current "Neon Metropolis" — slightly deeper bg, hotter cyan so the arc opens cool):
  - `bg: 0x06021C` · `grid: 0xFF2BD6` · `accent: 0x18F0FF` · `accent2: 0xFF49DE`
- **Side decor (WorldDecor, REUSE):** the existing `.generateBox` towers with lit-window `disc` columns. Keep as-is.
- **Music:** family 0 today — A2 root (45), `[0,3,7,10]` minor-7th, bluesy/dark, four-on-the-floor kick. **Distinct from neighbors:** lowest, driving, sparkle-arp OFF.
- **Preview recipe:** `drawTowers` (current `worldIndex % 3 == 0` branch) — blinking-window skyline gradient from `bg`, magenta grid, cyan horizon glow.

---

## World 2 — Geode Deep
*Mood: a hushed crystal cavern lit from within by violet shards.*

**Family: REUSE existing `Caverns` (`buildCaverns` / `restyleCaverns` / `animateCaverns`).** `fam 1`.

- **PALETTE** (current "Crystal Caverns", nudged so it reads as the cool floor of the arc):
  - `bg: 0x02131A` · `grid: 0x00FFC8` · `accent: 0xB26BFF` · `accent2: 0x35FFD8`
- **Side decor (REUSE):** existing `.generateCone` stalactites/stalagmites + `octahedron` cluster shards. Keep.
- **Music:** family 1 today — B2 root (47), `[0,3,7,12]`, open/minor, sparkle-arp ON. **Distinct:** airier and higher than Pulse City, with the shimmer voice.
- **Preview recipe:** `drawCrystals` (current `% 3 == 1`) — stalactite/stalagmite cave, cyan grid, violet glow.

---

## World 3 — Solar Sands  *(owner landmark — keep)*
*Mood: a dusk desert under a swollen sun and ringed planets.*

**Family: REUSE existing `Sands` (`buildSands` / `restyleSands` / `animateSands`).** `fam 2`.

- **PALETTE** (current "Solar Sands", verified):
  - `bg: 0x1C0A02` · `grid: 0xFFB13D` · `accent: 0xFF5E3A` · `accent2: 0xFFD23D`
- **Side decor (REUSE):** existing `pyramid` obelisks + ringed `.generateSphere` planet (torus ring scaled flat). Keep.
- **Music:** family 2 today — G2 root (43), `[0,5,7,12]` sus4, suspended/airy. **Distinct:** warmest, most spacious, the "exhale" before space.
- **Preview recipe:** `drawDunes` (current `% 3 == 2`) — ringed-planet desert, amber grid, orange horizon.

> **From here (4–12) every family is bespoke.** Each needs: a new `buildX` called in `WorldSky.init`, a new `Entity` root in `famRoots`, a `[]` slot in `famTints`, a `case` in the `update` switch + `restyle` switch, a `case` in `WorldDecor.style`, and a 4th+ entry in `Theme.worlds`. The exploration map confirms `evolvedPalette`'s `% 3` becomes `% 12` and the preview `% 3` becomes `% 12`.

---

## World 4 — Orbital Drift
*Mood: weightless silence above a blue planet — an astronaut drifts past, tethered, while satellites blink.* (The owner's headline beat.)

- **PALETTE** (the arc's first true void — near-black with cold cyan-white):
  - `bg: 0x01030E` · `grid: 0x2E5BFF` · `accent: 0x6FE8FF` · `accent2: 0xE9F4FF`

- **BACKGROUND MOTIF — new `buildOrbital`:**
  1. **The planet limb** — `.generateSphere(radius: large)` positioned low so only its upper curve is in frame, `accent`-blue Unlit; a thin `disc` halo child at 1.04× scale, dim `accent2`, for an atmosphere rim. *Anim (RM-gated): rotate ~0.01 rad/s about Y so surface bands drift.*
  2. **The astronaut** — entity tree (the showpiece, mirrors the blimp body+fin assembly pattern):
     - Helmet: `.generateSphere(r≈0.5)`, `accent2` near-white. Visor: child `disc` (flat, scaled 0.35, tilted, dark `bg`-tinted) for a reflective faceplate.
     - Torso: `.generateBox(0.6×0.8×0.4, cornerRadius 0.12)`, white.
     - Backpack: `.generateBox(0.4×0.5×0.25)` behind torso.
     - 4 limbs: scaled `.generateBox` children posed mid-drift (arms out, one knee bent).
     - Tether: `ribbon(width: 3, thickness: 0.04, amplitude: 0.15, waves: 1.2, phase: 0)` rotated to trail off-frame toward the planet — a gently curving cable. *Anim: slow bob on Y (±0.1) + 0.05 rad/s tumble about Z. The whole astronaut group parallax-drifts left across the frame on a long loop, then `isEnabled`-recycles to the right edge.*
  3. **Satellites** — 2× small entity clusters: `.generateBox` core + two flat `disc` solar-panel wings (scaled 1.2×0.4). *Anim: blink a tiny `disc` nav-light via `isEnabled` toggle on a 1.3 s phase; slow parallax.*
  4. **Star field** — `disc` mote pool (existing pattern), tiny scale, `accent2` white, near-static slow twinkle via per-mote scale sine.

- **SIDE DECOR (WorldDecor):** slim **solar-array panels** — `.generateBox` masts with flat `disc`/`generatePlane` panel cards tinted `grid`-blue, edge-lit `accent2`. Replaces the tower silhouettes for `fam 3`.
- **Music:** drifting weightlessness. Root D2 (50), `[0,5,7,11]` (lydian-ish maj7), pad-forward, NO kick (or a soft 1/4 pulse), long reverb-feel sustains. **Distinct:** first world with no driving beat — the air goes thin after the warm desert.
- **Preview recipe:** `drawOrbital` — radial dark-blue gradient, a partial planet arc bottom-left (filled circle clipped at frame edge), a tiny white astronaut silhouette (sphere head + box body) drifting upper-right, scattered star dots.

---

## World 5 — Tidal Glow
*Mood: a bioluminescent ocean trench — jellyfish pulse and tentacles sway in warm aqua dark.*

- **PALETTE** (descent into water — deep teal-black, luminous aqua, the arc's softest glow):
  - `bg: 0x010F12` · `grid: 0x0AE0D2` · `accent: 0x33FFE0` · `accent2: 0xB17BFF`

- **BACKGROUND MOTIF — new `buildTidal`:**
  1. **Jellyfish (3, parallax depths)** — entity tree:
     - Bell: `.generateSphere` scaled `SIMD3(1, 0.6, 1)` (flattened dome), `accent` aqua, semi-bright.
     - Rim lip: `torus(major: 1.0, minor: 0.06)` scaled to bell diameter, `accent2` lilac — the glowing bell edge.
     - Glow core: `disc` at bell center, bright `accent2`.
     - Tentacles: 4–6× **`tentacleStrip`** (NEW factory, below), hung downward, high amplitude, tapering. *Anim: bell "breathes" — scale Y 0.6↔0.72 on a 2.2 s sine; tentacles phase-offset sway; whole jelly bobs up/down + slow vertical rise-and-recycle.*
  2. **Light-shaft god-rays** — 2–3× `beam(length: 8, halfWidthNear: 0.05, halfWidthFar: 0.9)` from top of frame, very dim `accent`, near-vertical. *Anim: slow opacity-free lateral sway via ±3° Z-rotation.*
  3. **Plankton motes** — `disc` mote pool, tiny, `accent2`, slow upward drift + wide horizontal sway.
  4. **Seabed silhouette** — `ridge(width:, heights:)` with low rolling coral mounds at the bottom, dark `grid`-teal.

- **NEW FACTORY — `tentacleStrip(length:width:amplitude:segments:)`:** a vertical tapering wavy strip in the XY plane (a `ridge`-cousin turned 90° with a width envelope). Two columns of vertices down −Y; left/right X offset = `width * (1 - i/segments)` (tapers to a point) plus `amplitude * sin(t)` lateral wave baked at build; `(segments−1)×2` tris. ~25 lines, same shape as `ridge`/`ribbon`. Also reusable for seaweed.
- **SIDE DECOR:** **kelp/coral fronds** — tall thin `tentacleStrip` instances (low amplitude) rooted at lane edges, plus `octahedron(rx: small, ry: tall, rz: small)` glowing coral shards. Sways on the same RM-gated phase.
- **Music:** liquid and slow. Root E2 (40 → use 40), `[0,2,5,7]` pentatonic-soft, gentle swung 6/8 feel, watery delayed plucks, sub-bass swell. **Distinct:** rounder and warmer than Orbital's cold pads; pentatonic vs lydian.
- **Preview recipe:** `drawTidal` — vertical teal-black gradient, 1–2 glowing dome jellyfish (flattened ellipse + bright core + 4 wavy hanging strokes), faint vertical light shafts, scattered aqua plankton dots.

---

## World 6 — Ashfall
*Mood: a volcanic night — lava rivers crawl, embers rise, a cone smolders on the horizon.*

- **PALETTE** (heat after water — charcoal-black bg, molten orange/red; sharply distinct from aqua):
  - `bg: 0x140402` · `grid: 0xFF7A1A` · `accent: 0xFF3D1A` · `accent2: 0xFFC23D`

- **BACKGROUND MOTIF — new `buildAshfall`:**
  1. **Volcano cone** — `pyramid(halfBase: 3, height: 4)` at the horizon (or `.generateCone` for a rounder peak), dark `bg`; a `disc` lava-glow pool parented at its base, large, bright `accent`. *Anim: glow `disc` pulses scale 1.0↔1.08 on a slow 3 s sine (the caldera breathing).*
  2. **Lava rivers** — 2× `ribbon(width: 7, thickness: 0.18, amplitude: 0.25, waves: 5, phase: …)` laid flat near the base, bright `accent`→`accent2` blend. *Anim: scroll phase via tiny per-frame X-offset so the molten channel appears to flow (transform-only).*
  3. **Ember field** — `disc` mote pool, tiny, `accent2` gold, FAST upward rise + flicker (per-mote scale sine), wide sway — the signature falling-up embers.
  4. **Ash-smoke bank** — `ridge(width:, heights:)` second layer, dark grey-`bg`, low and wide, drifting slowly.
  5. **Far peak silhouettes** — `ridge` with sharp tall jagged heights, near-black.

- **SIDE DECOR:** **basalt obelisks** — `.generateBox` (tall, thin, dark) with a glowing `accent` cracked-seam `disc` strip up one face, plus low `pyramid` rubble. Embers drift past them.
- **Music:** ominous and percussive. Root C2 (36), `[0,3,6,7]` (with the tritone for menace), heavy tom/floor-kick pattern, low brass-saw drone. **Distinct:** the only world with a tritone and the heaviest low end — a hard pivot from Tidal's softness.
- **Preview recipe:** `drawAshfall` — dark gradient with orange floor glow, a black volcano triangle with a bright pool at its foot, a couple of glowing wavy lava lines, scattered rising gold ember dots.

---

## World 7 — Borealis
*Mood: a silent frozen tundra under rippling aurora curtains.*

- **PALETTE** (cooling from fire — slate-blue night, ice-green/teal aurora; complements Ashfall):
  - `bg: 0x040A14` · `grid: 0x4FFFB0` · `accent: 0x6FD8FF` · `accent2: 0xC8A8FF`

- **BACKGROUND MOTIF — new `buildBorealis` (closest derivative of Caverns' aurora ribbons):**
  1. **Aurora curtains** — 3–4× `ribbon(width: 12, thickness: 0.5, amplitude: 1.2, waves: 1.5, phase: varied)` stacked at the top, `grid` green → `accent2` violet, additive-feel bright. *Anim: slow phase scroll + gentle vertical drift; each band a different phase so they ripple independently.*
  2. **Ice shards** — `octahedron(rx: 0.3, ry: 1.4, rz: 0.3)` scattered along the horizon (Caverns' cluster pattern, repositioned to ground level, not ceiling-hung), pale `accent` blue, glinting. *Anim: subtle scale-twinkle on a `disc` glint child.*
  3. **Snow plain** — `ridge(width:, heights:)` very low gently-rolling heights, dim `accent2`-white — flat tundra.
  4. **Snowfall** — `disc` mote pool, tiny white, slow DOWNWARD drift (negative rise), minimal sway.
  5. **Far mountains** — second `ridge`, medium sharp profile, near-black blue.

- **SIDE DECOR:** **ice monoliths** — tall `octahedron(rx, ry tall, rz)` frozen pillars at lane edges, pale blue, with a faint internal `disc` glow; low snow `ridge` drifts. Reuses Caverns' crystal silhouette, recolored to ice.
- **Music:** crystalline and weightless. Root A2 (45) but `[0,4,7,11]` MAJOR-7th (bright, the arc's first major key), glassy bell pads, soft 1/4 chime, airy choir-saw. **Distinct:** the brightest, most "open sky" world — major key vs Ashfall's tritone dread.
- **Preview recipe:** `drawBorealis` — deep blue gradient, 2–3 stacked rippling green-violet aurora ribbons up top, a low white horizon ridge, a few pale upright ice shards, drifting snow dots.

---

## World 8 — Datastream
*Mood: inside the machine — a Tron grid receding to a glowing vanishing point.*

- **PALETTE** (synthetic black after natural worlds — pure black, electric cyan/white):
  - `bg: 0x000308` · `grid: 0x00E5FF` · `accent: 0x18FFE0` · `accent2: 0xFFFFFF`

- **BACKGROUND MOTIF — new `buildDatastream`:**
  1. **Horizon grid plane** — ONE **`gridCard`** (NEW factory, below) standing at the far horizon: a flat card of `grid`-cyan lines converging toward a center vanishing point (perspective faked by line spacing). *Anim: scroll the card's V-offset toward the camera in a loop so the grid appears to flow forward.*
  2. **Vanishing-point glow** — large dim `disc`, `accent` teal, dead center at the horizon — the data-core sun.
  3. **Vertical data-pylons** — 3–4× `beam(length: 6, halfWidthNear: 0.04, halfWidthFar: 0.04)` (hairline vertical bars) flanking the grid, `accent2` white. *Anim: `isEnabled` flicker on a fast staggered phase — packets lighting up.*
  4. **Floating data motes** — `disc` pool, tiny, `accent` cyan, rising in straight columns (no sway) — orderly, machine-like.
  5. **Corner chevrons** — `chevronStrip` (reuse the boost-pad mesh) standing at frame edges, `grid` cyan — UI-circuit accents.

- **NEW FACTORY — `gridCard(width:height:cols:rows:lineThickness:)`:** a flat XY card encoding `cols` vertical + `rows` horizontal thin quads in ONE mesh (like `skyline` batches buildings). Each line = 2 tris of width `lineThickness`; total `(cols+rows)×2` tris, one draw call. ~30 lines, mirrors `skyline`'s batching loop. Avoids O(cols+rows) entities — the one factory that genuinely earns its place.
- **SIDE DECOR:** **circuit pylons** — thin `.generateBox` posts with `gridCard` (small) micro-grid panels and `chevronStrip` accents, cyan-lit. Strict, rectilinear — contrasts the organic worlds.
- **Music:** glitchy and rigid. Root E2 (40), `[0,3,7,10]` minor but at DOUBLE tempo, arpeggiated 16th-note sequence, gated stutter hat, square-wave lead. **Distinct:** fastest BPM-feel and the only square/arp-driven world — pure synthetic energy.
- **Preview recipe:** `drawDatastream` — black bg, a cyan perspective grid converging to a bright center point (reuse the existing grid-draw layer, brightened), a few vertical white packet-lines, orderly rising cyan dots.

---

## World 9 — Bloomfall
*Mood: a cherry-blossom grove at night — petals fall through soft pink light.*

- **PALETTE** (breath of warmth after the cold machine — deep plum night, blossom pink/gold):
  - `bg: 0x0E0414` · `grid: 0xFF8FC8` · `accent: 0xFFB3D9` · `accent2: 0xFFE08A`

- **BACKGROUND MOTIF — new `buildBloomfall`:**
  1. **Blossom trees (2–3, parallax)** — entity tree:
     - Trunk: thin `.generateBox` (or scaled `pyramid` apex-down), dark `bg`.
     - Branches: 3–4× `beam(length: 2, halfWidthNear: 0.06, halfWidthFar: 0.02)` (tapering strokes) rotated out from the trunk at varied angles.
     - Canopy: 2–3× `.generateSphere` scaled oblate `(1, 0.7, 1)`, `accent` pink, soft. *Anim: canopy spheres sway ±2° on a slow 4 s sine — wind in the blossoms.*
  2. **Petal fall** — `disc` mote pool, tiny, `accent`/`accent2` pink-gold, slow DOWNWARD drift with WIDE lazy sway + per-mote spin (off-axis tilt) — the signature drifting petals.
  3. **Lantern glints** — 3–4× small bright `disc`, `accent2` gold, hung among branches. *Anim: gentle `isEnabled`-free scale flicker (warm flame).*
  4. **Rolling hills** — `ridge(width:, heights:)` soft low undulation, dark plum; second far `ridge` lower.
  5. **Moon** — single large `disc`, dim `accent2`, high in frame, static.

- **SIDE DECOR:** **stone lanterns + blossom branches** — `.generateBox` lantern bodies with a warm `disc` flame, plus `beam` branch strokes dotted with `accent`-pink canopy spheres at lane edges; petals drift past.
- **Music:** gentle and pentatonic-Eastern. Root F#2 (42), `[0,2,4,7,9]` major pentatonic, soft koto-pluck arp, brushed soft beat, warm pad. **Distinct:** the only pentatonic-major, most melodic and tender world — emotional valley before the cosmic finale.
- **Preview recipe:** `drawBloomfall` — plum gradient, a dim gold moon, 1–2 dark trunks with pink oblate canopies, a soft low hill ridge, scattered slow pink-gold petal dots.

---

## World 10 — Eventide
*Mood: the edge of a black hole — a luminous accretion disc warps around a void, nebula gas glowing.*

- **PALETTE** (true cosmic void — black with magenta/gold accretion fire):
  - `bg: 0x040108` · `grid: 0x9B3DFF` · `accent: 0xFF6FD8` · `accent2: 0xFFC04D`

- **BACKGROUND MOTIF — new `buildEventide` (achievable with zero new factories):**
  1. **Black hole** — `disc`, large, near-black `bg`, far center.
  2. **Accretion disc** — `torus(major: 3.0, minor: 0.5, majorSeg: 32)` scaled `SIMD3(1, 1, 0.18)` (flattened to a ring), wrapping the hole, `accent` magenta→`accent2` gold gradient feel via two stacked tori at different tints. *Anim: spin slowly about its own axis (Z-rotation ~0.08 rad/s) — matter falling in.*
  3. **Event-horizon glow ring** — second `torus` at 1.05× major, thin minor, bright `accent2`. *Anim: subtle scale pulse.*
  4. **Nebula gas** — `disc` pool, LARGE scale (2–4 units), dim `grid` violet near `bg`, slow sway — diffuse cloud pockets behind the hole.
  5. **Polar jets** — 2× `beam(length: 6, halfWidthNear: 0.0, halfWidthFar: 0.6)` from the hole center, 180° apart on Y, bright `accent2` — energy jets. *Anim: faint length-pulse.*
  6. **Star field** — `disc` motes, tiny, behind everything.

- **SIDE DECOR:** **drifting asteroids / gravitational debris** — `octahedron` chunks (irregular `rx≠ry≠rz`) tumbling slowly at lane edges, dark with `accent`-magenta rim `disc` glints, faintly pulled toward frame center.
- **Music:** vast and unsettling. Root C2 (36), `[0,1,5,8]` (with the flat-2 for cosmic dread), deep drone bass, slow swelling pads, sparse high pings. **Distinct:** the most dissonant, lowest, slowest world — gravity made audible.
- **Preview recipe:** `drawEventide` — black bg, a black center disc ringed by a flattened glowing magenta-gold ellipse (two arcs), two faint vertical jets, dim violet gas blobs, sparse stars.

---

## World 11 — Tempest
*Mood: a violent lightning storm — bolts split the dark, rain streaks down.*

- **PALETTE** (the storm before the light — bruised indigo-black, electric violet/white):
  - `bg: 0x06061A` · `grid: 0x6A5BFF` · `accent: 0xBFA8FF` · `accent2: 0xFFFFFF`

- **BACKGROUND MOTIF — new `buildTempest`:**
  1. **Storm-cloud front** — `ridge(width: 14, heights:)` with sharp irregular tall peaks at the top of frame (inverted feel), dark `bg`-indigo; a second wider/lower `ridge` cloud bank behind. *Anim: slow lateral drift.*
  2. **Lightning bolts** — 2–3× bolt groups, each a vertical chain of 3–4 `beam(length: 2, halfWidthNear: 0.05, halfWidthFar: 0.02)` segments at slight alternating angles (entity children off a group node, approximating a jagged path), `accent2` white. *Anim: ALL segments `isEnabled`-toggle together in a brief 2-frame flash on a randomized (local-seeded) cadence — the defining strobe.* Plus a `disc` ground-flash bloom at each bolt's foot, flashed in sync.
  3. **Rain** — `disc` mote pool, tiny, stretched (scaled `SIMD3(0.2, 1.5, 1)` into streaks), `grid`-violet, FAST downward, near-zero sway.
  4. **Distant flash haze** — large dim `disc` behind clouds, `isEnabled`-pulsed occasionally to back-light the front.

- **SIDE DECOR:** **storm-blasted spires / lightning rods** — tall thin `.generateBox` masts with a sharp `octahedron` tip and a `disc` glint that flashes in sync with the bolts; rain streaks past.
- **Music:** tense and building. Root A2 (45), `[0,3,5,8]` (harmonic-minor color), tremolo string-saw, rolling tom build, a sub-boom synced loosely to flash cadence. **Distinct:** rhythmically agitated and rising — maximum tension right before release.
- **Preview recipe:** `drawTempest` — indigo gradient, a dark jagged cloud ridge up top, 1–2 white zigzag bolts (chained angled strokes) with a bright ground-flash, vertical violet rain streaks.

---

## World 12 — Singularity
*Mood: the white endgame — a radiant core, rainbow rings, pure light. The reward for going this far.*

- **PALETTE** (the inversion — the ONLY light-bg world; a blowout of white with full-spectrum accents):
  - `bg: 0xF2F0FF` · `grid: 0xFF4DA6` · `accent: 0x4DC8FF` · `accent2: 0xFFD24D`

  > **Readability note (decree 6 + obstacle contrast):** this world inverts. With a near-white `bg`, obstacles must read DARK against it. The `Palette` struct already crossfades obstacle/lane colors per world via `evolvedPalette`; for #12 the lane lines and obstacle tints resolve to deep ink (`grid`/`lane` here used as saturated darks against white), so a single frame stays perfectly readable — the rainbow is in the SKY motif and rings, not the playfield, keeping the playfield calm. This is the deliberate climax: every prior world was dark-on-glow; the finale is glow-on-light.

- **BACKGROUND MOTIF — new `buildSingularity` (zero new factories):**
  1. **Core** — `disc`, scale ~1, pure white `bg`-bright (max), dead center — the singularity.
  2. **Rainbow rings** — 5–6× `torus(major: increasing, minor: 0.08)` flattened flat in Z, concentric from the core, each a different spectrum tint (`grid` pink, `accent` blue, `accent2` gold, + cyan/violet/green interpolations). *Anim: rings expand outward (scale up) and `isEnabled`-recycle inward — endless emanation; RM-gated to a slow steady pulse.*
  3. **Radial light rays** — 8× `beam(length: 5, halfWidthNear: 0.0, halfWidthFar: 0.25)` from the core at equal Y-rotation intervals (like clock hands), faint white. *Anim: slow whole-group rotation ~0.04 rad/s.*
  4. **Lens-flare motes** — `disc` pool along a horizontal axis offset from core, descending sizes — the classic flare artifact, static.
  5. **Background wash** — largest `disc`, very dim warm-white, farthest Z, behind all.

- **SIDE DECOR:** **prismatic crystal arches** — `octahedron` shards at lane edges each tinted a different spectrum color (the rainbow split), bright; small `torus` halos around them. The world's name pays off in the decor: the player's prism, refracted into all colors at last.
- **Music:** triumphant and resolving. Root C3 (48), `[0,4,7,11,14]` major-9th (lush, fully consonant — resolves the whole arc's tension), full bright pad + arp + the deepest layer stack, shimmering high bells. **Distinct:** the highest, brightest, most consonant world — the only major-9th, the emotional payoff.
- **Preview recipe:** `drawSingularity` — radial WHITE gradient (inverted: bright center → soft lilac edge), a brilliant center dot ringed by 4–5 concentric rainbow circles, faint radial rays, a dark player silhouette (it reads against the white) — the one card that glows light, signaling "the end."

---

## Implementation summary (the change surface, verified against the architecture map)

| Surface | Change |
|---|---|
| `Theme.worlds` | Expand 3 → **12** entries (palettes above). `evolvedPalette` line 47: `worlds[o % 3]` → `worlds[o % 12]`. Cycle-evolution math stays for infinite runs past world 12; `roman()` suffix now only appears on cycle ≥1 (worlds 12+), which is correct. |
| `WorldSky` | Add 9 roots to `famRoots` (now 12), 9 `[]` to `famTints`, 9 `buildX` called in `init`, 9 `case`s in the `update` and `restyle` switches. `world % 3` → `world % 12` for `famRoots[fam]`. |
| `WorldDecor.style` | `world % 3` → `world % 12`; add `case 3…11` silhouette branches + new `Slot` mesh types per side-decor spec. |
| `WorldPreviewCanvas` | `worldIndex % 3` → `worldIndex % 12`; add 9 `draw*` functions (recipes above). |
| `Synth.step(beat:world:)` | Replace 3-entry `rootShift`/`scales` parallel arrays with a **12-entry `WorldBed` table** (roots/scales/voices per the Music lines above); drop the `% 3` fold (use absolute ordinal directly). Keep `cycle = world/3` layering or fold into `WorldBed`. Pin with the uniqueness `XCTAssertNotEqual` test + per-world bass-root regression. |
| **New mesh factories** | **`tidalStrip`/`tentacleStrip`** (World 5) and **`gridCard`** (World 8). Both ~25–30 lines, modeled on `ridge`/`skyline`. All other 10 worlds use existing primitives only. |

**Iron-rule compliance:** the world-index modulus change is RNG-neutral (confirmed: `stepWorld` is pure arithmetic, spawner is world-blind) — **no `DailyChallenge.layoutVersion` bump, solvability bot unaffected**. All cosmetic placement uses a local `SplitMix64` seeded from the world index. All meshes are `MeshDescriptor` + `UnlitMaterial`, built once, animated transform-only, RM-gated. Decree 6 (calm, one gradient family per screen, readable obstacles) holds for all 12, with World 12's inversion explicitly handled so obstacles stay dark-on-white.

**Relevant files:** palettes/naming `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/UI/Theme.swift`; sky families `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Render/Reality/WorldDecor.swift`; primitives + 2 new factories `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Render/Reality/ProceduralMesh.swift`; previews `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/UI/WorldPreviewCanvas.swift`; music table `/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/PrismRush/Audio/Synth.swift`.