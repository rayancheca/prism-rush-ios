# DESIGN — v1.3 Character System ("Characters become the game's identity")

Status: READY FOR IMPLEMENTATION · Designer: character-system · Date: 2026-06-10
Inputs: explorer skin-pipeline report (verified against source), CLAUDE.md iron rules, v1.2 @ 95/95 green.

Iron-rule compliance up front:
- **No Core/ changes.** Everything here lives in `Meta/`, `UI/`, `Render/Reality/`. No RNG consumption
  changes, no spawner/pattern changes → **no `DailyChallenge.layoutVersion` bump, bot untouched.**
- **Zero binary assets** — every character is colors + existing mesh generators
  (`generateSphere/generateBox/ProceduralMesh.octahedron`) + SwiftUI Canvas.
- Render-side animation may use `Double.random`/`elapsed` (established pattern: `blinkT`,
  particle jitter). Core determinism is unaffected.
- New `Profile` fields are `decodeIfPresent ?? default` (§5).
- All UI reads follow G3 (§5.3).

---

## 1. FIX-VISIBILITY — your character is unmistakably YOURS in-run

### 1.1 Root causes being fixed (from explorer report, verified)
1. Trail/dust/landing/death FX are hardcoded to `tintAccent`/`tintAccent2` (world palette) —
   `RealityRenderer.swift:186` (slide dust), `:244` (trail), `:276` (landed), `:299` (died).
2. All 7 skins share identical rig geometry — only a body-color swap on a blob that fills ~5–7% of
   screen height. Color alone cannot carry identity at that size.
3. The default skin follows the world accent, so the out-of-box impression is "the world owns my color".

### 1.2 Decision on `followsWorld`

> ### ⚠️ SUPERSEDED BY DECREE 1 (owner decree; dated 2026-06-11, shipped v1.4.2 `7349a19`)
>
> CLAUDE.md §Owner decrees, decree 1: *"A character NEVER changes identity with the world —
> including the default. The player's pick (colors, shape, trail) is constant across all worlds.
> No `followsWorld` behavior on any skin."* Origin: v1.2 + v1.4.1 owner feedback — *"what's the
> point of characters if they change colors every level?"* The chameleon decision below is
> **REVOKED**, and the V13_SPEC carries a matching DECREE-1 REVOCATION addendum.
>
> What shipped instead: Prism owns authored hexes (body `0x00F5FF`, antenna `0xFF2BD6`) plus
> `isPrismatic` — a **fixed, time-based 8 s shimmer** (`SkinCatalog.prismaticColor(at:)`,
> cyan→magenta→amber, identical in every world; previews and the rig sample the same clock).
> `trailHex == nil` is repurposed to mean "ride the shimmer hue" — never the world accent.
> `Skin.followsWorld` is deleted; `SkinCatalogTests` pins zero world-following skins.
> New flavor line: *"The first runner. Every world remembers it."*

~~**Keep `followsWorld` for exactly one character — "Prism" (id `default`) — and make it the
personality, not a fallback.** Prism's flavor line is *"Born of every world, loyal to none."* — the
chameleon IS its identity. Every other character (15/16) has a fixed body color that **never** reads
from the palette. Prism's trail stays world-accent (current behavior); every other character gets a
fixed `trailHex`. Rationale: killing `followsWorld` outright would silently change the look every
existing player has, and the rainbow-chameleon is genuinely the best "free default" in the roster —
it makes fixed-color characters feel like an upgrade ("I stopped being everyone").~~

### 1.3 Skin-tinted FX (the character claims the screen)
The trail is on screen ~100% of a run; this is the single highest-leverage identity change.
All four hooks read one new renderer field `skinTrailColor: UIColor?` ~~(nil = follow world)~~
**[REVOKED v1.4.2 (decree 1): `skinTrailColor` is non-optional — every FX bursts the skin's own
color; Prism's is the live shimmer hue. The world-accent fallbacks in the table below are
deleted]**:

| Hook | File:line (current) | Change |
|---|---|---|
| Speed trail | `RealityRenderer.swift:244` | `color: skinTrailColor ?? tintAccent` |
| Slide dust | `RealityRenderer.swift:186` | `color: skinTrailColor ?? tintAccent` |
| Landing burst | `RealityRenderer.swift:276` (`.landed`) | `color: skinTrailColor ?? tintAccent` |
| Death shatter | `RealityRenderer.swift:299` (`.died`) | FIRST burst (120 particles): `skinTrailColor ?? tintAccent2`; second white burst unchanged |

**Unchanged on purpose (readability is gameplay):** gem streak ladder (gold→cyan→magenta→white is
global scoring language), pickup bursts (shield white / doubler gold-emerald / chrono ice are item
semantics), speed lines (white), world-change ring (incoming world accent), obstacles, decor.
The world stays readable; only *the player's own wake* is theirs.

### 1.4 Signature silhouette (geometry, not just color)
Per-skin rig parameters (§5.1) — body shape (sphere / rounded cube / crystal octahedron), overall
scale 0.85–1.10, eye radius, pupil style, antenna height/tip scale. `RealityRenderer.applySkin`
gains a rig rebuild (§1.6). **Scale is visual-only and capped to ±12–15%** — Core collision knows
nothing about skins; the cap keeps the visual from misrepresenting the hitbox. Eyes stay at the same
world-space face anchor so squash/stretch and blink code is untouched.

### 1.5 Idle personality in-run: antenna sway
In `advanceVisuals` (after the blink block, `RealityRenderer.swift:321`):

```swift
// Antenna sway — per-skin idle personality; visual-only, gated by Reduce Motion.
if !reduceMotion, skinSway > 0 {
    let a = Float(sin(elapsed * skinSwaySpeed)) * skinSway
    antenna.orientation = simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1))
    antennaTip.position = SIMD3<Float>(sin(a) * 0.24, 1.66 - (1 - cos(a)) * 0.24, 0)
}
```
(`skinSway` = `skin.idle.sway`, `skinSwaySpeed` = `skin.idle.bobSpeed * 2`.) Zero allocations,
two transform writes per frame.

### 1.6 Renderer plumbing (fixes "equip does nothing" end-to-end)
- `applySkin(bodyHex:antennaHex:followsWorld:)` → **`applySkin(_ skin: Skin)`**
  *(the legacy 3-arg shim lingered un-called until v1.4.2 `7349a19` deleted it — its parameter
  name is the decree-1-banned behavior)*
  (`RealityRenderer.swift:342`, call sites `GameView.swift:348`). `Skin` is a `Sendable` value type
  in the app target — passing it whole avoids a 10-parameter signature. Core never sees it.
- `applySkin` stores the skin params, sets `paletteKey = -1` (existing force-rebuild), **and calls
  `rebuildCharacter()`**: removes `playerBody/eyes/antenna/antennaTip` from `playerRig`, clears the
  `eyes` array, and re-runs `buildCharacter()` parameterized by the skin:
  - `.sphere` → `generateSphere(radius: 0.62)` (today's mesh)
  - `.cube` → `generateBox(width: 1.06, height: 1.06, depth: 1.06, cornerRadius: 0.18)`, position y 0.66
  - `.crystal` → `ProceduralMesh.octahedron(0.78)`, position y 0.72
  - eyes: `generateSphere(radius: skin.eyeRadius)`, eye material `uiHex(skin.eyeTintHex)`; pupil per
    `pupilStyle` (§5.1: `.dot` r 0.06 · `.wide` r 0.085 · `.slit` r 0.07 scaled (0.45, 1.5, 1) ·
    `.glint` r 0.06 + tiny white child sphere r 0.025 at (0.025, 0.025, 0.03))
  - antenna: `generateCylinder(height: 0.42 * antennaHeightScale, radius: 0.025)`, y position
    `1.21 + 0.21 * antennaHeightScale`; tip `generateSphere(radius: 0.095 * antennaTipScale)` at
    `y = 1.21 + 0.42 * antennaHeightScale + 0.045`
    **[AMENDED v1.4.2 `c173f37` (decree 2, AUDIT D2-1): stem AND tip are painted `antennaHex` on
    BOTH sides of the seam — preview and rig. The rig had been painting the stem in body color,
    erasing Mono/Thorn/Pebble/Golem's sold antenna cue. Same wave: in-run blink re-arms from the
    skin's `idle.blinkMin/Max` (not a global 2.2–4.2 s), sway uses the preview's exact
    `bobSpeed·2π·0.8` formula, and a shared `CharacterProportions` contract pins preview/rig
    shape parity (preview cube at the rig's true 85 % span; crystal gets a real 3D elongation
    via `ProceduralMesh.octahedron(rx:ry:rz:)`).]**
  - store `skinScale = skin.scale` and fold into the per-frame pose line
    (`RealityRenderer.swift:173`): `playerRig.scale = SIMD3<Float>(sx, sy, sx) * skinScale`
  Rebuild cost: ~7 small entities, only on equip/launch — negligible.
- Already true and kept: the `SceneEvents.Update` subscription runs in menu mode too
  (`GameView.swift:131–158`), so `paletteKey = -1` re-tints on the very next frame after equip.
  The reason equips "felt like nothing" in menus is the sheet covering the 3D view — solved by the
  idle previews (§4), not by renderer changes.

---

## 2. ROSTER — 16 characters *(24 as of v1.4)*, 100% procedural

> **[AMENDED v1.4 `9b77316`: the roster is now 24 — the v1.4 eight (Circuit L8, Tide 2,000,
> Facet ach.gems t2, Nebula L18, Thorn 3,500, Golem 5,000, Monarch 7,500, Vigil 14 challenge
> days) take the parking-lot rungs. The 16 below are frozen by tests; row 1 (Prism) is amended
> per the §1.2 decree-1 revocation.]**

The existing 7 keep their ids, body/antenna hexes, coin costs, and Aurora stays the IAP exclusive.
They gain `trailHex` + idle params + rarity (additive — owners notice their character got *better*).

Conventions: shape `S`=sphere `C`=cube `X`=crystal · pupil `dot/wide/slit/glint` ·
idle = `bobSpeed Hz / bobAmp / blinkMin–blinkMax s / sway rad` · eyes white (`0xFFFFFF`) unless noted.

### Base tier — the existing 7 (looks preserved)

| # | id | Name | Flavor | Body | Antenna | Trail | Shape/Scale | Eyes/Pupil | Antenna H/Tip | Idle | Rarity | Unlock |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `default` | Prism | The first runner. Every world remembers it. *[was "Born of every world, loyal to none." — chameleon lore retired]* | `0x00F5FF` + isPrismatic *[was 0 (world) — REVOKED v1.4.2, decree 1]* | `0xFF2BD6` *[was 0 (world)]* | nil = shimmer hue *[was nil (world)]* | S / 1.00 | 0.13 dot | 1.0/1.0 | 1.6/0.05/2.2–4.2/0.12 | Common | Free |
| 2 | `ember` | Ember | Runs hot. Cools never. | `0xFF5E3A` | `0xFFD23D` | `0xFF7A3D` | S / 1.00 | 0.13 dot | 1.0/1.0 | 1.9/0.06/2.0–3.6/0.15 | Common | 200 coins |
| 3 | `void` | Void | It stares back. | `0xB26BFF` | `0x00FFC8` | `0xB26BFF` | S / 1.00 | 0.14 wide | 1.0/1.0 | 1.2/0.04/3.0–5.0/0.08 | Rare | 350 coins |
| 4 | `toxic` | Toxic | Do not lick. | `0x39FF14` | `0xFF2BD6` | `0x39FF14` | S / 1.00 | 0.13 slit | 1.0/1.0 | 1.7/0.05/2.6–4.6/0.18 | Rare | 500 coins |
| 5 | `mono` | Mono | Allergic to color. | `0xF4F8FF` | `0x0A0A14` | `0xE8EEFF` | S / 1.00 | 0.12 dot | 1.0/1.0 | 1.1/0.03/2.8–4.8/0.05 | Rare | 750 coins |
| 6 | `midas` | Midas | Everything it touches turns to score. | `0xFFD23D` | `0xFFFFFF` | `0xFFD23D` | S / 1.00 | 0.13 glint | 1.0/1.3 | 1.4/0.04/2.4–4.2/0.10 | Epic | 1,500 coins |
| 7 | `aurora` | Aurora | The sky wears it. | `0x00FFC8` | `0xFF2BD6` | `0xFF2BD6` | S / 1.00 | 0.13 glint | 1.1/1.2 | 1.8/0.07/2.2–4.0/0.22 | Legendary | **IAP (Shop)** |

(Aurora's magenta trail against its teal body is the deliberate "money look" — the one two-tone wake.)

### New 9

| # | id | Name | Flavor | Body | Antenna | Trail | Shape/Scale | Eyes/Pupil | Antenna H/Tip | Idle | Rarity | Unlock |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 8 | `bolt` | Bolt | First off the line. Every line. | `0x00B3FF` | `0xFFFFFF` | `0x00B3FF` | S / 0.95 | 0.13 dot | 1.0/1.0 | 2.6/0.07/1.2–2.4/0.20 | Common | 300 coins |
| 9 | `pebble` | Pebble | Small. Round-ish. Unbothered. | `0x8E9BAE` | `0xFFB13D` | `0xAFC2D9` | **C** / 0.85 | 0.11 wide | 0.6/0.9 | 0.8/0.03/3.5–6.0/0.05 | Common | **Level 3** |
| 10 | `blossom` | Blossom | Runs on petals and spite. | `0xFF8AD4` | `0xB4FF5C` | `0xFFB3E2` | S / 1.00 | 0.14 dot | 1.3/1.4 | 1.5/0.06/2.4–4.0/0.30 | Rare | **Level 6** |
| 11 | `fang` | Fang | Bites first. Blinks never. | `0xFF3B30` | `0x14141E` | `0xFF6B4A` | S / 1.00 | 0.13 slit | 1.0/1.0 | 1.4/0.04/5.0–8.0/0.10 | Rare | 900 coins |
| 12 | `drift` | Drift | Found asleep in the Sands. Still asleep. | `0xE08A3C` | `0x00FFC8` | `0xFFB36B` | S / 1.05 | 0.15 wide | 0.8/1.1 | 0.9/0.06/4.5–7.0/0.08 | Rare | **Achievement: `ach.dist` tier 1** (10,000 m lifetime) |
| 13 | `shard` | Shard | A splinter of the first prism. | `0x7DF9FF` | `0xFFFFFF` | `0x7DF9FF` | **X** / 1.00 | 0.12 glint | 1.1/0.8 | 1.3/0.04/3.0–5.0/0.10 | Epic | **Level 12** |
| 14 | `wisp` | Wisp | Half here. All speed. | `0xDFF6FF` | `0x9BF0FF` | `0xCFF8FF` | S / 0.90 | 0.12 dot | 1.4/0.7 | 2.2/0.09/3.8–6.0/0.25 | Epic | **Achievement: `ach.close` tier 1** (100 CLOSE calls) |
| 15 | `tempo` | Tempo | Never misses a beat. Or a day. | `0xC6FF4D` | `0xFF2BD6` | `0xC6FF4D` | S / 1.00 | 0.13 dot | 1.2/1.2 | 2.0/0.05/3.0–3.0/0.35 | Epic | **Play the Daily Challenge on 7 days** |
| 16 | `eclipse` | Eclipse | The dark between worlds. | `0x1A1A2E` | `0xFF2BD6` | `0x6B5BFF` | S / 1.08 | 0.14 slit, **eye tint `0xFFD23D`** | 1.0/1.2 | 1.0/0.03/4.0–6.0/0.06 | Legendary | **Level 25** |

Design notes:
- **Tempo is the metronome**: `blinkMin == blinkMax == 3.0` (blinks exactly on the beat), bob locked
  at 2.0 Hz, the biggest antenna sway in the roster — the antenna *is* the metronome. Its unlock
  (7 challenge days) matches the personality.
- **Eclipse** is the only dark body; its gold eyes (only non-white sclera), indigo trail, magenta
  tip, and 1.08 scale carry it against dark backdrops — verify on Caverns in QA, lighten body to
  `0x232337` if it sinks.
- Color-collision audit done against world accents: no fixed body within ΔH ≈ 20° of all three
  world accents simultaneously; near-accent bodies (toxic/lime, midas/gold) pop via trail + shape +
  antenna instead. Pebble is the only desaturated body (gray is its joke).
- Coin sinks now ladder 200/300/350/500/750/900/1,500 — Bolt (300) is the day-one "first buy",
  Fang (900) the mid-game flex; works with the new earn rates the economy designer is adding.
- Rarity census: Common 4 · Rare 6 · Epic 4 · Legendary 2.

---

## 3. UNLOCKS

### 3.1 Unlock model (one enum, evaluated in one place)

```swift
// SkinCatalog.swift
extension Skin {
    enum Unlock: Equatable, Sendable {
        case free
        case coins(Int)
        case level(Int)                       // XP system (levels 1...30, other designer's spec)
        case achievement(id: String, tier: Int) // profile.achievementTier[id] ?? 0 >= tier
        case challengeDays(Int)               // profile.challengeDaysPlayed.count >= n
        case iap                              // premium — routes to Shop (aurora only)
    }
}
```

```swift
// NEW: PrismRush/Meta/SkinUnlocks.swift — pure, testable, no UI imports.
enum SkinUnlocks {
    /// Non-purchase requirement met? (coins/iap return false — those go through buy flows.)
    static func earned(_ skin: Skin, profile: Profile, level: Int) -> Bool {
        switch skin.unlock {
        case .free:                          return true
        case .level(let n):                  return level >= n
        case .achievement(let id, let tier): return (profile.achievementTier[id] ?? 0) >= tier
        case .challengeDays(let n):          return profile.challengeDaysPlayed.count >= n
        case .coins, .iap:                   return false
        }
    }

    /// Requirement line for locked cards (UPPERCASE, the UI styles it).
    static func requirementText(_ skin: Skin) -> String {
        switch skin.unlock {
        case .free:                       return ""
        case .coins(let c):               return "\(c)"            // UI renders CoinBadge instead
        case .level(let n):               return "REACH LEVEL \(n)"
        case .achievement(let id, _):
            switch id {                   // copy pinned per id — never derive from Mission titles
            case "ach.dist":  return "RUN 10,000 M LIFETIME"
            case "ach.close": return "THREAD 100 CLOSE CALLS"
            default:          return "COMPLETE ACHIEVEMENT"
            }
        case .challengeDays(let n):       return "PLAY \(n) DAILY CHALLENGES"
        case .iap:                        return "★ PREMIUM · SHOP"
        }
    }
}
```

### 3.2 Auto-grant — earned characters appear, with fanfare

```swift
// ProfileStore.swift
/// Insert every newly-earned skin into ownedSkins; returns the new ones (for the unlock toast).
/// ownedSkins insertion IS the dedupe — a skin is "new" exactly once, and the existing
/// cloud-merge `formUnion(ownedSkins)` syncs grants across devices for free.
@discardableResult
func refreshSkinUnlocks(level: Int) -> [Skin] {
    let new = SkinCatalog.all.filter {
        !profile.ownedSkins.contains($0.id) && SkinUnlocks.earned($0, profile: profile, level: level)
    }
    guard !new.isEmpty else { return [] }
    mutate { p in for s in new { p.ownedSkins.insert(s.id) } }
    return new
}
```

Call sites (all in `GameView`, which owns popups + audio):
- `install()` — launch catch-up (old saves that already meet requirements get everything at once),
- end of `recordRunResults()` (after `applyRunSummary` — covers achievements + level-ups),
- after `recordChallengeRun(...)` (covers Tempo),
- after any mission claim from MissionsView (claim can advance `achievementTier`).

Each returned skin fires the existing popup system: **"NEW CHARACTER — SHARD"** in the skin's body
color + `synth.play(.purchaseChime)` + a `NEW` badge in CharacterSelect until first viewed (§5.2
`seenSkins`). Coins/IAP keep today's `buyOrEquipSkin` / Shop flows untouched.

### 3.3 XP dependency (coordination contract)
The XP designer owns `profile.xp` → `level` (1…30). This spec consumes a single integration point:
`ProfileStore.shared.playerLevel: Int`. **Fallback if XP lands later:** `playerLevel` returns 1 →
level-locked skins simply stay locked; nothing crashes, no field of ours depends on XP.
Recommended level→character beats for the XP curve: L3 Pebble, L6 Blossom, L12 Shard, L25 Eclipse
(a character at the start, middle, and near-end of the ladder keeps levels meaningful).

### 3.4 Locked-card presentation + "every tap leads somewhere"
Locked characters render as **silhouettes** (§4.2): all shapes filled `#202036`, eyes drawn closed
(two short dark arcs), no glow, `lock.fill` glyph bottom-trailing, requirement line under the name.
**[AMENDED v1.4 `985859b`: the dark silhouette became the full-color tease at 0.45 opacity.
AMENDED v1.4.2 `37ea7f2` (D6-5): the SHOP renders locked skins with the SAME locked tease as the
select grid it routes to — rail cards and both featured-card previews pass ownership through; no
more owned-bright storefront vs locked-dim select one tap later.]**
Tap behavior per unlock type (owner rule — nothing on screen is dead):

| Unlock | Tap on locked card |
|---|---|
| coins | Buy attempt — existing shake + red flash on insufficient funds |
| iap | `model.open(.shop)` (existing) |
| level | Requirement toast popup: "REACH LEVEL 12 — keep running!" |
| achievement | `model.open(.missions)` — lands on the ladder that unlocks it |
| challengeDays | `model.closeSheet()` — menu, where DailyChallengeCard sits, with toast "Play today's challenge" |

---

## 4. IDLE PREVIEW — you SEE who you are

Approach per explorer recommendation: **SwiftUI `TimelineView(.animation) + Canvas`** (no
per-card RealityViews — 16 RealityKit instances in a grid is a memory/stutter trap).

### 4.1 `AnimatedCharacterSwatch` (NEW file `PrismRush/UI/CharacterSwatch.swift`)
Moves `CharacterSwatch` out of `MetaScreenScaffold.swift` (scaffold keeps scaffold) and upgrades it:

```swift
struct AnimatedCharacterSwatch: View {
    let skin: Skin
    var size: CGFloat = 62
    var silhouette = false          // locked state — shapes only, eyes closed, no glow
    var animated = true             // hero/buddy: true; grid cards: true; reduceMotion: forced off

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion && !silhouette {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in   // 30 Hz is plenty for 2D
                canvas(t: tl.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(t: 0)
        }
    }
}
```

Canvas draw rules (all derived from the same `Skin` recipe the renderer uses — one source of truth):
- **Bob**: `yOff = sin(t * skin.idle.bobSpeed * 2π) * skin.idle.bobAmp * size` applied to body+eyes+antenna.
- **Blink**: deterministic schedule, no state — `period = (blinkMin + blinkMax) / 2`,
  `phase = t.truncatingRemainder(dividingBy: period)`; eyes' Y-scale 0.1 while `phase < 0.12`.
  Per-skin period means Tempo visibly blinks on its 3 s beat next to Fang's long stare.
- **Sway**: antenna stem + tip rotate `sin(t * bobSpeed * 2π * 0.8) * idle.sway` around the stem base.
- **Shape**: `.sphere` → `Circle`; `.cube` → `RoundedRectangle(cornerRadius: size * 0.22)`;
  `.crystal` → diamond `Path` (square rotated 45°, slightly elongated vertically).
- **Pupils**: `.dot` circle `0.09·size` · `.wide` `0.13·size` · `.slit` ellipse `0.05×0.14·size` ·
  `.glint` `0.09·size` + white `0.035·size` dot offset (+0.02, −0.02). Eye fill = `eyeTintHex`.
- **Body fill**: ~~`followsWorld` keeps today's `AngularGradient` rainbow; else~~ **[AMENDED
  v1.4.2 (decree 1): a rainbow/shimmer is allowed ONLY as a fixed, time-based effect identical
  in-game — never palette-driven. The preview's `isPrismatic` fill is a flat sample of the same
  shared `SkinCatalog.prismaticColor(at:)` 8 s clock the rig paints with, so menu and run agree
  at any instant. All other skins:]** flat `bodyHex` with the
  existing glow shadow in `bodyHex` (glow dropped entirely in silhouette mode).
- **Scale**: drawing scaled by `skin.scale` so Pebble reads small next to Eclipse in the same grid.
- Frame stays `size × size·1.5` (antenna headroom + bob never clips).
Perf: 16 Canvas instances at 30 Hz is trivial (flat 2D fills); `LazyVGrid` already culls off-screen
cards; Reduce Motion renders a single static frame.

### 4.2 CharacterSelect v2 layout (`CharacterSelectView.swift`)
```
┌──────────────────────────────────────────────┐
│ ‹  Characters                      🪙 8,000  │  MetaScreenScaffold (unchanged)
│ ┌──────────────────────────────────────────┐ │
│ │  [hero swatch]   SHARD          ◆ EPIC   │ │  Hero card, height 148pt, rrect 24,
│ │   size 96,       "A splinter of the      │ │  .ultraThinMaterial. Always shows the
│ │   animated       first prism."           │ │  SELECTED character. Name 24 heavy
│ │                  ● EQUIPPED              │ │  rounded; flavor 13 white .7 italic;
│ └──────────────────────────────────────────┘ │  rarity chip + status line.
│  COMMON ────────────────────────────────────  │  Section header: 11 heavy, tracking 2,
│  [Prism] [Ember] [Bolt] [Pebble]              │  rarity-tinted (see chip colors below)
│  RARE ──────────────────────────────────────  │
│  [Void] [Toxic] [Mono] [Blossom] [Fang] [Drift]│  Grid: adaptive min 104, spacing 12 —
│  EPIC ──────────────────────────────────────  │  3-up on every iPhone. Card: swatch 56
│  [Midas] [Shard] [Wisp] [Tempo]               │  (animated), name 14 bold, status 10.
│  LEGENDARY ─────────────────────────────────  │  Locked = silhouette + requirement line.
│  [Aurora] [Eclipse]                           │  Owned-unseen = NEW badge (gold dot).
└──────────────────────────────────────────────┘
```
- Rarity chip colors: Common `#9BA6B5` · Rare `#00B3FF` · Epic `#B26BFF` · Legendary `#FFD23D`.
  Card stroke = rarity color at 0.35 opacity (equipped ring stays cyan `#00F5FF`, denied stays red).
- Tap an owned card → equip (existing `buyOrEquipSkin`); hero card crossfades to it
  (`.animation(.spring(duration. 0.35, bounce: 0.3), value: selectedSkin)` — keep reduceMotion gate).
- `.onAppear` → mark all currently-owned skins seen (`seenSkins.formUnion(ownedSkins)`), clearing NEW badges.
- Accessibility: keep `skin_<id>` ids; locked value becomes `"locked — REACH LEVEL 12"` etc.

### 4.3 Menu buddy — always see who you are (`MenuView.swift`)
A tappable chip directly **above the PLAY button** (after `rewards`, before the `Spacer`):

```
┌────────────────────────────────────────────┐   height 60, rrect 16, .ultraThinMaterial,
│ [swatch 44, animated]  RUNNING AS       ›  │   stroke white 0.14 (matches hub buttons).
│                        SHARD               │   "RUNNING AS" 9 heavy tracking 2 white .55;
└────────────────────────────────────────────┘   name 15 heavy white. Chevron 12 white .4.
```
- Whole chip = `Button(action: onCharacters)`, `.buttonStyle(.neon)`,
  `accessibilityIdentifier("buddyChip")`, label "Running as Shard. Opens characters."
- MenuView gains two parameters: `let selectedSkin: Skin` (resolved by the caller in `body` so
  observation tracks it — §5.3) and reuses existing `onCharacters`.
- This chip + the §1 trail work close the loop: pick → see it on the menu → see your wake in-run.

---

## 5. DATA MODEL

### 5.1 `Skin` v2 (`SkinCatalog.swift`) — new fields all defaulted, existing entries stay terse

```swift
struct Skin: Identifiable, Sendable {
    enum BodyShape: Sendable { case sphere, cube, crystal }
    enum PupilStyle: Sendable { case dot, wide, slit, glint }
    enum Rarity: Int, Sendable, Comparable { case common = 0, rare, epic, legendary
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue } }
    struct Idle: Sendable {                    // shared by Canvas preview + renderer sway
        var bobSpeed: Double = 1.6             // Hz
        var bobAmp: Double = 0.05              // fraction of swatch size
        var blinkMin: Double = 2.2, blinkMax: Double = 4.2
        var sway: Double = 0.12                // antenna sway amplitude, radians
    }

    let id: String
    let name: String
    let flavor: String                         // one-line personality (hero card + buddy a11y)
    let bodyHex: UInt32                        // 0 = follows world (Prism only)
                                               //   ^ REVOKED v1.4.2 (decree 1): sentinel deleted;
                                               //     Prism authored 0x00F5FF + isPrismatic flag
    let antennaHex: UInt32
    var trailHex: UInt32? = nil                // nil = follow world accent (Prism only)
                                               //   ^ REPURPOSED v1.4.2: nil = ride the prismatic
                                               //     shimmer hue — NEVER the world accent
    var bodyShape: BodyShape = .sphere
    var scale: Float = 1                       // rig scale, visual only, clamp 0.85...1.12
    var eyeRadius: Float = 0.13
    var eyeTintHex: UInt32 = 0xFFFFFF
    var pupilStyle: PupilStyle = .dot
    var antennaHeightScale: Float = 1
    var antennaTipScale: Float = 1
    var idle: Idle = Idle()
    let rarity: Rarity
    let unlock: Unlock                         // §3.1

    var followsWorld: Bool { bodyHex == 0 }    // DELETED v1.4.2 (decree 1) — replaced by
                                               //   `var isPrismatic = false` (exactly one: default)
    // Back-compat for existing call sites (CharacterSelect, Shop, GameView):
    var premium: Bool { unlock == .iap }
    var cost: Int { if case .coins(let c) = unlock { return c }; return 0 }
}
```
Catalog: 16 entries **[24 as of v1.4]** from §2, **ordered by rarity then unlock difficulty** (the grid renders catalog
order inside each rarity section). `skin(_:)` fallback to `all[0]` unchanged. **Not Codable, never
persisted** — only ids are stored, so catalog evolution can't corrupt saves.

### 5.2 `Profile` changes (`Profile.swift`) — ONE new field

```swift
var seenSkins: Set<String> = ["default"]   // NEW-badge dedupe for auto-granted characters
```
- Add `seenSkins` to `CodingKeys`; in `init(from:)`:
  `seenSkins = try c.decodeIfPresent(Set<String>.self, forKey: .seenSkins) ?? d.seenSkins` (rule 7).
- Migration behavior: old saves decode to `["default"]` → previously-owned skins show NEW once,
  cleared on first Characters visit. Acceptable one-time sparkle.
- `mergeFromCloud`: `merged.seenSkins.formUnion(remote.seenSkins)` (monotonic, same as ownedSkins).
- `ownedSkins` / `selectedSkin` / `achievementTier` / `challengeDaysPlayed` already exist — the
  unlock system adds **no other persistent state**. (`profile.xp` belongs to the XP designer's spec.)
- ⚠️ `challengeDaysPlayed` is capped at a 60-day window (ProfileStore.swift:336) — fine for
  `challengeDays(7)`; never spec a challenge-days unlock above ~50.

### 5.3 G3-safe UI read patterns (this exact anti-pattern shipped three v1.0 bugs)
- **Never** `@State`/stored-property/init-capture a shared `@Observable` or its `profile`.
- **Never** `let profile = ProfileStore.shared.profile` at the top of `body`.
  ⚠️ `CharacterSelectView.swift:12` does exactly this today — **rewrite it in this pass**: each
  subview reads `ProfileStore.shared.profile.<field>` (and `IAPManager`/level via
  `ProfileStore.shared.playerLevel`) directly at the point of use inside `body`, so Observation
  registers every dependency.
- `MenuView` stays dumb: `GameView` resolves
  `SkinCatalog.skin(ProfileStore.shared.profile.selectedSkin)` inline in its `body` where MenuView
  is constructed (a per-render local in an actively-evaluating body is the established pattern for
  *passing* values down; the ban is on snapshotting *shared state* a view reads for itself).
- Card-level reads (`owned/equipped/affordable/seen`) are computed per card from
  `ProfileStore.shared.profile` inside the card's `body`, not hoisted.

### 5.4 `GameView` wiring deltas
- `applyCurrentSkin()` → resolves `Skin`, guards `owns(selected)` (cloud-merge safety: unowned
  selection falls back to `default`), calls `renderer.applySkin(skin)`.
- `buyOrEquipSkin` unchanged (compat properties keep it compiling).
- `recordRunResults()` tail + challenge/mission claim paths: `refreshSkinUnlocks(level:)` → popup per
  new skin (§3.2). Launch catch-up in `install()` after the demo-profile block.
- Demo profile (`PR_DEMOPROFILE`, GameView.swift:100): add `"bolt"` to the `formUnion` so screenshots
  show a NEW-badge + a colored trail without buying.

---

## 6. FILE IMPACT

**Modified**
| File | Change |
|---|---|
| `PrismRush/Meta/SkinCatalog.swift` | Skin v2 struct (§5.1) + 16-entry catalog (§2) **[24 as of v1.4; Prism amended per §1.2 revocation]** |
| `PrismRush/Meta/Profile.swift` | `seenSkins` + CodingKeys + decodeIfPresent (§5.2) |
| `PrismRush/Meta/ProfileStore.swift` | `refreshSkinUnlocks(level:)`, `seenSkins` cloud merge, `markSkinsSeen()` (§3.2/§5.2) |
| `PrismRush/UI/CharacterSelectView.swift` | Hero card, rarity sections, silhouettes + requirement lines, locked-tap routing, NEW badges, G3 rewrite (§3.4/§4.2/§5.3) |
| `PrismRush/UI/MetaScreenScaffold.swift` | Remove `CharacterSwatch` (moves to new file); scaffold untouched |
| `PrismRush/UI/MenuView.swift` | Buddy chip above PLAY + `selectedSkin` param (§4.3) |
| `PrismRush/UI/GameView.swift` | `applySkin(skin)` call, unlock refresh + toasts, demo profile, MenuView wiring (§5.4) |
| `PrismRush/Render/Reality/RealityRenderer.swift` | `applySkin(_ Skin)`, `rebuildCharacter()`, `skinScale`, trail/dust/landed/died tint hooks, antenna sway (§1) |

**New**
| File | Contents |
|---|---|
| `PrismRush/Meta/SkinUnlocks.swift` | `earned(_:profile:level:)` + `requirementText(_:)` (§3.1) — pure, Linux-testable |
| `PrismRush/UI/CharacterSwatch.swift` | `AnimatedCharacterSwatch` Canvas/TimelineView + silhouette mode (§4.1) |
| `PrismRushTests/SkinCatalogTests.swift` | See §7 |

**Untouched (by design):** `Core/` (everything), `ParticleSystem.swift` (burst API already takes a
color), `ShopView` (aurora flow as-is), `DailyChallenge` / spawner / patterns → **no layoutVersion
bump**, solvability bot unaffected.

## 7. TESTS (new, keeps 95 green + adds)
1. Catalog integrity: 16 skins **[24 as of v1.4]**, unique ids/names; the 7 legacy ids keep exact
   body/antenna hexes, costs, and aurora `premium == true`; every skin `0.85...1.12` scale; every
   locked unlock has non-empty `requirementText`; ~~exactly one `followsWorld`~~ **[AMENDED
   v1.4.2 (decree 1): ZERO followsWorld — the computed is deleted, no skin has `bodyHex == 0`;
   exactly one `isPrismatic` (`default`), whose nil trail is the shimmer source]**, exactly one
   `.iap`.
2. `SkinUnlocks.earned`: level boundary (11 no / 12 yes for shard), achievement tier
   (`achievementTier["ach.close"] = 0/1`), challengeDays (6 no / 7 yes), coins/iap always false.
3. `refreshSkinUnlocks`: grants once, returns newly granted only, second call returns `[]`
   (use `ProfileStore(testing:)`).
4. Profile decode: legacy JSON without `seenSkins` → `["default"]`; round-trip keeps it (extends
   existing decode-resilience tests).
5. Compat: `skin.cost`/`skin.premium` match the old table for the 7 legacy skins.

## 8. QA CHECKLIST (device pass)
- Equip Bolt → menu buddy shows Bolt instantly; start run → blue trail, blue slide dust, blue death shatter.
- ~~Prism equipped → trail still follows world accent through a world crossfade (regression guard).~~
  **[INVERTED v1.4.2 (decree 1 — the old item regression-guarded the violation): Prism equipped →
  body colors and trail do NOT change across a world crossfade. The shimmer keeps its own fixed
  8 s cycle, never the world accent, in all 12 worlds.]**
- Eclipse on Caverns: body readable (else lighten to `0x232337`).
- Reduce Motion: swatches static, no antenna sway in-run, equip ring animation off (existing gate).
- Pebble vs Eclipse side-by-side in grid: size difference visible; cube vs crystal silhouettes read at 56pt.
