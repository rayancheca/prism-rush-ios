# PRISM RUSH v1.3 — UI/UX REFRAME (DESIGN_uiux.md)

Owner brief: *"Too loaded with info and colors and visuals. Reframe the UI/UX; everything must be
clickable and lead somewhere; worlds tab interactive; nice previews for everything; pull from
well-known sources but be creative."*

Design thesis: **the character is the product; PLAY is the verb; everything else is one tap deep.**
We borrow Subway Surfers' play-first home and character spotlight, Crossy Road's collection joy,
Alto's Adventure's restraint and single-accent hierarchy, and Monument Valley's chrome-less
"the world IS the menu" cards — and re-cut all of it in Prism Rush's neon-procedural identity.

Iron-rule compliance is stated inline. Nothing in this document touches `Core/`, the spawner,
pattern order, or RNG consumption — so the solvability bot and `DailyChallenge.layoutVersion` are
unaffected by this spec. Every visual is 100% procedural (SwiftUI `Canvas`/`TimelineView`/shapes
or the existing RealityKit mesh pipeline). Zero binary assets. New `Profile` fields decode via
`decodeIfPresent ?? default` (rule 7). All views read `ProfileStore.shared` live, never snapshot
into a `let` at the top of `body` (rule G3).

---

## 0. THE ONE-SENTENCE RULES (apply to every screen)

1. **One accent for "tap me."** Cyan `0x00F5FF` is the only interactive accent in meta UI.
2. **Gold means money/claim. Only money/claim.**
3. **World palettes live only inside the game, world previews, and character swatches.** Meta
   chrome is neutral (white-alpha on near-black).
4. **Max one gradient per screen** (PLAY, or a CLAIM, or the wordmark — never two side by side).
5. **If it's on screen, it's tappable and it goes somewhere.** Display-only text is either
   deleted, merged into a tappable element, or demoted into the screen it belongs to.
6. **Preview before commit.** Anything selectable (skin, world) shows a live procedural preview
   before the user pays/equips/starts.

---

## 1. MENU REFRAME — "Hero, Verb, Rail, Nav"

**Pattern source:** Subway Surfers (character front-and-center, giant play affordance, one
promo rail) + Alto's Adventure (calm, sparse, single accent) + Monument Valley (no decorative
chrome). Creative twist: our hero stage is a *procedural* idle slime on a neon glow disc — the
character designer's `CharacterIdleStage(skinID:)` (assumed delivered) is the centerpiece, so
"what you picked" is finally visible the moment the app opens.

### 1.1 Zone layout (portrait iPhone, top → bottom)

```
┌──────────────────────────────────────────┐
│ A  STATUS STRIP                 (44 pt)  │  profile/level ring ←→ coin badge
│                                          │
│ B  HERO STAGE              (flex, ≥38%)  │  wordmark lockup (small)
│        [ idle character on glow disc ]   │  selected-skin idle preview
│        ◦ skin name pill ◦                │  world progress chip
│                                          │
│ C  PLAY                         (64 pt)  │  the ONLY gradient on screen
│    ── best chip (28 pt) ──               │
│                                          │
│ D  REWARDS RAIL                 (64 pt)  │  Daily Rush | Rewards | Missions
│                                          │
│ E  NAV ROW                      (56 pt)  │  Characters | Shop | Worlds
└──────────────────────────────────────────┘
padding: Theme.Space.l (24) horizontal, zones separated by Space.m (16)
```

### 1.2 Zone A — Status strip (44 pt)

- **Left:** Profile button becomes a **level ring avatar**: 40×40 circle, the player's level
  number (from the new XP system) centered at `caption` size, surrounded by a 2.5 pt circular
  XP-progress ring in cyan on white-12% track. Tap → ProfileView.
  - VO: "Profile. Level 7, 60 percent to level 8." Hint: "Opens your profile and stats."
- **Right:** CoinBadge unchanged in look, **now tappable → ShopView** (Crossy Road: tapping your
  coin total opens the prize/shop surface). Press uses `.neon` style.
  - VO: "1,240 coins." Hint: "Opens the shop."
- **Settings gear is removed from the menu.** It moves to ProfileView's top-right corner (§6.6).
  Alto's pattern: secondary chrome hides until you're in a secondary place. Net: 3 elements → 2.

### 1.3 Zone B — Hero stage (flexible, min 38% of height)

- **Wordmark lockup shrinks**: "PRISM RUSH" single line, 26 pt black rounded, tracking 6,
  `Theme.actionGradient` fill (this is the wordmark's gradient allowance; PLAY below uses the
  same gradient family so visually they read as one system, but the wordmark drops its 26 pt
  magenta shadow → a 10 pt one). The 70 pt two-line title and the "A THREE-WORLD HYPERSPEED
  RUNNER" kicker and the "Outrun the void" tagline are **deleted** — the character replaces
  them as the identity carrier.
- **CharacterIdleStage(skinID: profile.selectedSkin)** fills the zone: the procedural slime
  (rounded box + eyes + pupils + blink + antenna, exactly the in-run mesh recipe, rendered via
  the character designer's stage — RealityKit non-AR view or Canvas fallback) standing on an
  elliptical glow disc tinted by the skin's `bodyHex` (or a slow world-palette cycle for
  `followsWorld` skins). Subtle floor reflection at 18% opacity.
  - **Idle motion:** vertical bob ±3 pt, 2.4 s sine; blink every 3–7 s; antenna lag 0.15 s
    behind bob. Squash 1.04×/0.97× at bob extremes.
  - **Tap the character → CharacterSelectView.** The whole stage is one button.
  - Below the character: **skin name pill** — capsule, white-8% fill, hairline stroke, skin
    name at `caption` weight bold + a 6 pt swatch dot of `bodyHex`. Tappable (same action).
  - VO (stage as one element): "Your character: Ember. Equipped." Hint: "Opens characters."
- **World progress chip** (replaces the three dead world chips, §5 item 1): one capsule,
  `WORLD 04 · SOLAR SANDS · 1,800m`, micro caption type, the world's `accent2` used ONLY for
  the small "04" numeral (the one sanctioned spot of world color on the menu). **Tap → Worlds.**
  - VO: "World 4, Solar Sands, checkpoint at 1,800 meters." Hint: "Opens world select."

### 1.4 Zone C — PLAY + best chip

- **PLAY**: full width minus `Space.s`, 64 pt tall, `radius.l` (20), `Theme.actionGradient`
  fill, black 24 pt label, tracking 3. **The repeatForever pulse is deleted** (it fights the
  idle character for attention; Alto's never pulses). Replace with a static 24 pt cyan glow
  shadow at 0.35. Press feedback stays `.neon`.
- **Best chip** directly under PLAY: `BEST 5,280 ›` capsule, `caption` type, white-70%,
  chevron at 55%. **Tap → ProfileView (stats)** (§5 item 2). If `best == 0`: chip reads
  `FIRST RUN ›` and opens HowToPlay instead.
  - VO: "Best score 5,280." Hint: "Opens your stats."

### 1.5 Zone D — Rewards rail (ONE compact rail, 64 pt)

Replaces today's stacked DailyChallengeCard + 3-button RewardsBar (two rows, four glows) with a
single 3-cell rail. **At most one cell may be "lit" (gold) at a time**, chosen by priority:
unclaimed daily login > ready chest > claimable missions > unplayed Daily Rush. All other cells
render neutral with a small gold badge-dot if they hold something claimable. (Subway Surfers'
"one promo lit at a time" discipline; our twist is the deterministic priority ladder.)

| Cell | Content | Tap |
|---|---|---|
| **DAILY RUSH** | bolt glyph, `caption` label, sub-line: best score today or `HH:MM` to new track (countdown demoted to micro, ticks per minute not per second) | starts the seeded daily challenge directly (existing `startDailyChallenge()`); 7-day dots move to a small strip inside GameOver for challenge runs |
| **REWARDS** | gift glyph; merges daily-login claim + free chest. Sub-line: `CLAIM +80` (lit) / `CHEST 12:40` / `READY` | lit → claims/opens inline with coin-burst toast; otherwise opens a 280 pt mini-sheet listing Daily Login (day N streak row) + Chest (timer ring) with their own claim buttons |
| **MISSIONS** | target glyph + gold count badge if `unclaimed > 0` | → MissionsView |

Cell anatomy: 64 pt tall, equal widths, `radius.m` (16), white-6% fill, hairline stroke; lit
cell gets `goldGradient` fill + black text (gold = claim, rule 0.2).
- VO per cell, e.g. "Rewards. Daily bonus ready, 80 coins." Hint: "Claims your daily bonus."
- Reduce Motion: no glow pulse on the lit cell; it's just gold.

### 1.6 Zone E — Nav row

Keep the three hub buttons (Characters / Shop / Worlds) but **demote them visually**: 56 pt tall,
icon 17 pt + `micro` label, white-85% on white-6%, hairline stroke, **no shadows**. They are
redundant with the hero stage / coin badge / progress chip on purpose — discoverability for new
players, muscle memory for the rest. Badge-dots: cyan dot on Characters if a new skin became
affordable/unlocked since last visit (`lastSeenAffordableSkins` profile set, decodeIfPresent ??
[]); gold dot on Shop when the featured rotation changed today.

### 1.7 Removed / demoted from the menu (net element count 14 → 9)

| Element | Fate |
|---|---|
| 3 world chips | → one tappable world-progress chip (§1.3) |
| 70 pt two-line wordmark + kicker + tagline | → one-line 26 pt lockup |
| Settings gear | → ProfileView header |
| DailyChallengeCard (big) | → Daily Rush rail cell |
| RewardsBar (3 buttons) | → Rewards + Missions rail cells |
| BEST line (dead) | → tappable best chip under PLAY |
| PLAY pulse animation | → deleted |

### 1.8 Menu motion rules

| Motion | Default | Reduce Motion |
|---|---|---|
| Character idle bob/squash | on | **off** — static pose, blink only (blink is opacity-free lid scale; keep, it's tiny and characterful) |
| Glow disc shimmer | 8 s hue drift (followsWorld skins) | static |
| Lit rail cell | static gold (no pulse ever) | same |
| Sheet transitions | move(.bottom) | crossfade `.opacity` |
| Coin-burst claim toast | 12 procedural particles, 0.6 s | numeric "+80" fade only |

---

## 2. GLOBAL VISUAL SYSTEM — taming the rainbow

**Pattern source:** Alto's Adventure — one ambient palette, one functional accent, type does the
hierarchy. Creative twist: we keep neon *energy* by spending saturation only where it pays —
the game view, previews, and exactly one action per screen.

### 2.1 Role-based palette (extends `Theme` — new `Theme.Role` namespace)

```swift
// Theme.swift additions (spec — names are binding)
extension Theme {
    enum Role {
        static let bg          = color(0x05010E)      // app background (was per-screen radials)
        static let surface     = Color.white.opacity(0.06)   // cards, cells
        static let surfaceHi   = Color.white.opacity(0.10)   // raised/selected
        static let hairline    = Color.white.opacity(0.12)   // all strokes
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.70)
        static let textTertiary  = Color.white.opacity(0.50)
        static let interactive = color(0x00F5FF)      // THE tap accent (cyan)
        static let reward      = color(0xFFD23D)      // claim/coins/gold ONLY
        static let danger      = Color(red: 1, green: 0.37, blue: 0.37) // destructive/denied
        static let lock        = Color.white.opacity(0.35)   // locked states
    }
}
```

**Mapping rules:**
- `interactive` (cyan): selected borders, chevrons, toggles-on, link text, equipped ring, focus.
- `reward` (gold): CLAIM fills, coin amounts, badge counts, best-value tags. Never decoration.
- `danger`: deny shake border, quit/destructive, sign-out.
- World palettes (`Theme.worlds`): allowed ONLY in (a) GameView/HUD/EffectsOverlay, (b) world
  preview canvases, (c) character swatches/stage tint, (d) the single numeral in the menu's
  world chip. The menu's magenta radial background → replaced by `Role.bg` plus a **6%-opacity
  world-tinted radial** that tracks the furthest world (ambient, below perception threshold of
  "rainbow", still alive).
- Magenta `0xFF2BD6` exits the meta-UI chrome entirely; it survives in `actionGradient`,
  the wordmark, and in-game world 1.

### 2.2 Gradient law

Allowed: `actionGradient` (PLAY, primary buy CTA — max one per screen), `goldGradient` (lit
claim surfaces), wordmark. Banned: gradient strokes, gradient text outside the wordmark,
gradient card backgrounds, the three-color title gradient (delete `titleGradient`'s orange stop;
wordmark uses the two-stop `actionGradient`).

### 2.3 Typography scale (`Theme.Type`, all `.rounded`, Dynamic Type via @ScaledMetric)

| Token | Size/Weight | Use |
|---|---|---|
| `display` | 34 heavy | score on GameOver, PAUSED |
| `title` | 22 heavy | screen titles, card heroes |
| `heading` | 17 bold | row titles, world names |
| `body` | 13 medium | copy, descriptions |
| `caption` | 11 semibold, tracking 1.5 | labels, pills, buttons |
| `micro` | 9 semibold, tracking 2 | kickers, "WORLD 04" |

Every token wraps `@ScaledMetric(relativeTo:)` (display→.largeTitle … micro→.caption2).
Numbers always `monospacedDigit()`. Tracking collapses to 0 at accessibility sizes XL+.

### 2.4 Geometry tokens (`Theme.Space`, `Theme.Radius`)

- Space: `xs 4, s 8, m 16, l 24, xl 32` — replaces today's 7/9/10/11/12/14/18/20/22 zoo.
- Radius: `s 12 (pills/chips), m 16 (cells/rows), l 20 (cards/primary buttons)`, Capsule for
  capsules. One **`NeonCard`** ViewModifier = `Role.surface` fill + `Radius.m/l` + hairline
  stroke; every card/cell/row in the app adopts it (kills the per-screen drift the explorer
  flagged in RewardsBar vs scaffold paddings).
- Shadows: only on PLAY, the hero glow disc, and world-preview accents. Cards get none
  (depth comes from the two surface levels, Monument Valley-style flatness).

---

## 3. WORLDS TAB → ALIVE

**Pattern source:** Monument Valley's chapter select — every chapter is a tiny living vignette
of the place — crossed with Alto's biome restraint. Creative twist: our vignettes are *true
procedural slices of the actual renderer's recipe* (same palette structs, same decor archetypes)
drawn in a SwiftUI `Canvas`, so the preview is honest: what you tap is what you run.

### 3.1 Screen structure (`LevelSelectView` rebuild)

1. **Preview header** (full-width, 200 pt, `Radius.l`): a large `WorldPreviewCanvas` of the
   **furthest unlocked world** with overlaid: `micro` kicker `FURTHEST CHECKPOINT`, world name
   at `title`, `BEST HERE 2,140m` stat, and a 48 pt **`PLAY FROM HERE`** caption button
   (`Role.interactive` border, not gradient — PLAY gradient budget belongs to the menu).
   Tapping anywhere on the header = `startRun(fromWorld: furthest)`.
2. Instructional copy line: deleted (the cards explain themselves).
3. **Card grid**: adaptive min 160, `Space.m` gaps. Shows all unlocked worlds **plus the next
   locked one** (today locked worlds are invisible — a dead end; now the ladder is visible).

### 3.2 WorldCard anatomy (160×190, `Radius.l`)

```
┌────────────────────────┐
│  WorldPreviewCanvas    │ 96 pt — live procedural vignette (below)
│  (clipped, top radius) │
├────────────────────────┤
│ WORLD 02        (micro)│ white-50%
│ Crystal Caverns (head.)│ white
│ ⟓ BEST 1,240m   (capt.)│ white-70%, 0 → "UNTOUCHED"
│ ▸ 600m in       (capt.)│ accent2-tinted chip, "START" for world 1
└────────────────────────┘
```

- **Unlocked:** hairline stroke; the furthest card gets a 2 pt `accent2` stroke + 12 pt glow
  (only world-color stroke allowed in meta, because the preview already speaks that palette).
  Tap → `startRun(fromWorld:)` (existing behavior preserved).
- **Locked (next world):** preview rendered with `.saturation(0.15)` + 45% black scrim,
  `lock.fill` glyph 20 pt centered, requirement line replaces the best stat:
  `REACH 1,800m TO UNLOCK` (`caption`, `Role.lock`). Tap → ShakeEffect + haptic; VO announces
  the requirement. No purchase path — distance is the only key (fairness).
- **Best-in-world data:** new `Profile.bestDistanceByWorld: [Int: Double]`
  (`decodeIfPresent ?? [:]`, rule 7), written by `applyRunSummary` from per-world segment
  distances already known to the summary (meta-layer only; Core untouched).

### 3.3 WorldPreviewCanvas (the component, reused at 3 sizes)

Pure SwiftUI `TimelineView(.animation(minimumInterval: 1/30))` + `Canvas`. Inputs:
`palette: WorldPalette`, `worldIndex: Int`, `size: PreviewSize (.chip/.card/.hero)`.

Draw order (all derived from `palette`, zero assets):
1. `bg` fill + vertical luminance ramp (bg → bg×1.6) via two rects.
2. **Horizon glow**: ellipse of `accent` at 25%, blur 8.
3. **Decor silhouettes** at 2 parallax depths, archetype keyed by `worldIndex % 3`:
   Metropolis = rounded-rect tower clusters with 2×3 lit-window dots; Caverns = triangle
   crystal clusters (paired spikes, 8° tilt); Sands = overlapping quadratic-curve dunes +
   one ring-planet circle. Positions from a tiny `SplitMix64(seed: worldIndex)` consumed
   **locally in the UI layer** — deterministic per world, never touching run RNG (rule 2 safe:
   no Core involvement, layout of decor is cosmetic UI).
4. **3-lane perspective grid**: 5 converging verticals + horizontal rungs in `grid` color at
   35%, rung spacing animated by `phase = (t / 6).truncatingRemainder(1)` for a slow forward
   scroll. Lane center dashed in `accent2` 50%.
5. `.hero` size only: the player slime silhouette (rounded rect + eye dots) sitting in the
   center lane, static.
- **Reduce Motion:** `TimelineView(.explicit([.now]))` — a single static frame, same beauty,
  zero scroll. Battery note: previews pause when their sheet is not frontmost (`scenePhase` +
  sheet visibility gate).
- VO: canvas is `accessibilityHidden(true)`; the card's combined label carries meaning:
  "World 2, Crystal Caverns. Your best here: 1,240 meters. Checkpoint 600 meters in."
  Hint: "Starts a run from this checkpoint." / locked: "Locked. Reach 1,800 meters to unlock."

---

## 4. SHOP REFRAME — fuller without new SKUs

**Pattern source:** Subway Surfers' sectioned board (Featured up top, currency mid, gear below)
+ Crossy Road's "the collection IS the storefront" energy. Creative twist: fullness comes from
**coin-spend characters living inside the shop** as a section — five IAPs become a store with
~12 visible items and two currencies, no new products (rule: 5 IAPs only).

### 4.1 Sections (ScrollView, `Space.l` between sections, `micro` kickers)

1. **FEATURED** — one full-width 120 pt spotlight card, rotating daily: pick = first non-owned
   item from a UTC-day-seeded shuffle (`SplitMix64(seed: daysSinceEpoch)`, UI-layer only) over
   [aurora, doubleCoins, midas, toxic, mono]; all owned → medium coin pack. Anatomy: left = big
   preview (CharacterIdleStage `.chip` for skins / CoinGlyph stack / 2× monogram), right = title
   (`title`), blurb (`body`), price pill. The section's `actionGradient` budget lives on the
   price pill. `micro` corner tag: `TODAY'S FEATURE`. Gold badge-dot on menu Shop nav when
   rotation changes.
2. **COINS** — the 3 coin packs as a single row of three compact cards (was 3 full rows):
   CoinGlyph stack sized small/mid/large, amount (`heading`, gold), StoreKit price pill.
   `BEST VALUE` gold `micro` tag on the large pack (16,000/$9.99 leads $/coin). If
   `doubleCoins` owned, sub-line `EARNS 2× IN RUNS` on each pack.
3. **PERKS** — Double Coins full-width row: 2× monogram icon, title, blurb, price pill →
   when owned: `Role.interactive` check + `OWNED` caption, row stays visible (status, not ghost).
4. **CHARACTERS** — horizontal scroll of 96×128 mini skin cards (coin skins ember→midas +
   premium aurora): swatch/idle-chip preview, name, price = coin pill (gold glyph+amount) or
   StoreKit price (aurora). **Tap card → CharacterSelectView scrolled/focused to that skin**
   (preview-before-buy; the shop never charges coins without showing the stage). Trailing
   `ALL CHARACTERS ›` ghost card → CharacterSelectView. Owned skins show as equipped-check or
   `OWNED` — collection-progress flex, Crossy Road-style.

### 4.2 Store-unavailable fallback, integrated

Today the whole screen becomes a wifi-error void. New behavior: **only StoreKit-priced elements
degrade.** Sections 1–3 collapse into one compact `NeonCard` banner — wifi glyph, "Store is
offline — coin items still work", `RETRY` caption button (existing `loadProducts()`), while
section 4's coin-priced characters remain fully shoppable. Purchase-failure errors render as a
dismissible inline strip pinned above the section where the failure happened, never a modal.
- VO banner: "Store offline. Coin purchases still available. Button: Retry."

### 4.3 States (uniform across all shop cards)

| State | Treatment |
|---|---|
| Buyable (cash) | price pill, white text on `surfaceHi`, hairline |
| Buyable (coins, affordable) | gold coin glyph + amount pill |
| Coins, unaffordable | pill at 45% + tap = shake + `GET COINS` toast scrolling to COINS section |
| Pending | pill → spinner, row dims 60%, disabled |
| Owned | `checkmark.seal.fill` in `Role.interactive` + `OWNED` caption |
| Equipped (skins) | cyan 2 pt ring on preview + `EQUIPPED` |

---

## 5. CLICKABILITY AUDIT — every dead element's new job

| # | Element (explorer top-10) | New behavior |
|---|---|---|
| 1 | Menu world chips (decorative) | **Deleted**; replaced by ONE world-progress chip → opens Worlds (§1.3) |
| 2 | Menu `BEST` line | → best chip under PLAY, taps to ProfileView stats; `FIRST RUN ›` → HowToPlay when best==0 (§1.4) |
| 3 | GameOver coin breakdown line | → tap-to-expand disclosure: collapsed `+240 ⌄`, expanded itemized gems/distance/world rows; ×2 badge taps to Shop's Double Coins row when not owned (§6.7) |
| 4 | GameOver `Reached`/`Balance` rows | **Deleted.** Reached merges into the DISTANCE stat chip ("2,140m · World 3"); balance already lives in the coin badge, which becomes tappable → Shop |
| 5 | SkinCard dual-encoded state | Ring is the single state encoder (cyan=equipped, gold=premium, none=neutral, red=denied flash); badge text drops to one word; full state moves to VO value (§6.2) |
| 6 | Missions tier label + bar redundancy | Bar absorbs the label: tier ticks ON the progress bar, `micro` "TIER 3/5" right-aligned above it once, subtitle line deleted (§6.5) |
| 7 | Profile early-game stats grid | <5 runs → grid replaced by **Next Milestone card** ("Reach 500m — 3 of 3 missions live") tapping → Missions; grid earns its place at 5+ runs (§6.6) |
| 8 | Shop instructional copy | **Deleted**; section kickers carry the structure (§4.1) |
| 9 | Settings version footer | Becomes a tappable row → copies version+build to pasteboard with "Copied" toast (support-mail ready); VO: "Version 1.3, build 52. Double-tap to copy." |
| 10 | DailyChallenge per-second countdown | Demoted to per-minute `micro` text inside the Daily Rush rail cell; the cell itself is the tap target to play (§1.5) |

Additional formerly-dead surfaces gaining destinations: MetaScreenScaffold's coin balance →
Shop (everywhere); HUD stays intentionally non-interactive (the one sanctioned exception —
during play, the only "button" is the pause affordance).

---

## 6. SCREEN-BY-SCREEN DELTAS

### 6.1 Menu — full reframe per §1.

### 6.2 CharacterSelectView — "the stage and the shelf"
**Pattern:** Crossy Road's grid joy + Subway Surfers' preview-before-equip.
- **Top: CharacterIdleStage `.hero`** (240 pt) showing the *focused* skin (not necessarily
  equipped) idling on its glow disc — assumed component from the character designer, including
  per-skin idle accents (trail wisps, antenna tip color). Below the stage: skin name (`title`)
  + one-line flavor (`body`, new `Skin.flavor` strings in SkinCatalog) + **state button**:
  `EQUIP` (interactive border) / `EQUIPPED` (filled cyan, disabled) / `BUY · 500` (gold pill) /
  `UNLOCKS AT LEVEL 8` (lock) / `GET IN SHOP ›` (premium → ShopView focused on aurora).
- **Below: the shelf** — same adaptive grid, cards shrink to swatch+name+single-word badge.
  **Tap a card = focus it on the stage** (selection ≠ commitment); commit happens on the state
  button. Denied tap (unaffordable/locked) = existing ShakeEffect on the *stage button*.
- **Locked rows (XP system):** non-premium skins gain `unlockLevel` (catalog field; profile
  untouched): ember L2, void L4, toxic L6, mono L8, midas L12 (matches the progression
  designer's curve — coins AND level both gate, level shows first). Locked card: swatch
  silhouetted at 30% + lock glyph + `LVL 8` micro badge. Tap still focuses the stage (you can
  *see* what you're grinding for — desire-driven retention) with the locked state button.
- Grid order: equipped → owned → affordable → locked-by-coins → locked-by-level → premium.
- VO card: "Toxic. Locked, unlocks at level 6, costs 500 coins." Hint: "Shows preview."
  Stage button VO mirrors its label. Reduce Motion: stage static pose (§1.8).

### 6.3 ShopView — full reframe per §4.

### 6.4 LevelSelectView (Worlds) — full reframe per §3.

### 6.5 MissionsView
- Keep three sections; rows adopt `NeonCard` + the tier-tick progress bar (§5.6).
- **`CLAIM ALL` gold pill** appears in the scaffold title row when ≥2 claimables (one tap,
  staggered coin toasts; Reduce Motion: single summed toast).
- TODAY header's UTC countdown joins the kicker line as `micro` (`TODAY · RESETS 13:42`),
  ticking per minute.
- Each mission row gains a destination when actionable: rows whose goal is in-run ("near-miss
  20 obstacles") get a small `PLAY ›` ghost affordance on the right → starts a run. Claimed
  achievement rows compress to 32 pt single-line (history, not noise).

### 6.6 ProfileView
- **New header: Level card** — big level numeral (`display`), XP ring (reuses the menu ring at
  64 pt), `2,140 / 3,000 XP` (`caption`), next-unlock teaser chip ("LVL 8 · MONO" with swatch
  dot) → taps to CharacterSelect focused on that skin. This is the progression home base.
- **Settings gear** top-right of the scaffold (relocated from menu) → SettingsView.
- Stats grid: ≥5 runs only; tiles become tappable where a destination exists (BEST → Game
  Center leaderboard when authenticated; WORLDS → Worlds tab). <5 runs → Next Milestone card
  (§5.7). Account + leaderboard sections unchanged structurally, restyled to `NeonCard`.
- VO: level card combined: "Level 7. 2,140 of 3,000 experience. Next unlock at level 8: Mono."

### 6.7 GameOverView — three-band hierarchy (score → money → exits)
**Pattern:** Alto's restraint — one number you read, one number you earn, then the verbs.
- Band 1: SHATTERED (`title`, danger) → score (`display`, count-up; Reduce Motion: instant) →
  ONE context line: `★ NEW BEST ★` (gold) or `BEST 5,280 · 320 TO GO` (`caption`).
- Band 2: coin earn line `+240` (gold) with **tap-to-expand breakdown** (§5.3) + ×2 state.
- Band 3 stats: 4-tile grid → **2 chips**: `2,140m · World 3` and `×4 streak · 12 close calls`;
  a `FULL STATS ›` ghost link → ProfileView. Reached/Balance rows deleted (§5.4).
- New: **XP line** `+120 XP ▸ LVL 7` with a 4 pt progress sliver — the death screen sells the
  level system every run (one-per-run; rule 9 untouched, XP is meta not economy payout).
- Daily-challenge deaths only: the 7-day dot strip relocates here (from the old menu card).
- Buttons unchanged in function (CONTINUE/revive gates, RUN AGAIN cooldown, GET COINS lift —
  rules 9/10 untouched); CONTINUE uses goldGradient, RUN AGAIN uses the screen's single
  actionGradient, MENU is ghost.

### 6.8 HUDView — what hides during play
**Pattern:** Monument Valley/Alto's: the run is the UI.
- Keep: score (top-left, `display`-scaled) and multiplier pill (top-right).
- **Hide `BEST` sub-label** during normal play; it appears only as a one-shot **ghost-chase
  chip** when within 10% of best ("BEST 320 AHEAD", world-accent), then the existing NEW BEST
  flash on crossing. (Removes the static comparison nobody reads at 90 km/h.)
- Gem counter merges INTO the multiplier pill (gems drive streak anyway): `◆ 23 ×4`.
- Power-up timers: three text rows → up to three **20 pt icon rings** (circular depletion
  stroke, icon center) under the multiplier; ring color = `Role.interactive` for all (no
  rainbow), 4 s-left warning = ring blinks twice (Reduce Flashing: no blink, ring thins).
- All remain non-interactive (`allowsHitTesting(false)`); VO `.updatesFrequently` on score,
  popups in EffectsOverlay gain `UIAccessibility.post(notification:.announcement)` for
  SHIELD/NEW BEST class events only (not every +100 — chatter discipline).

### 6.9 Settings / HowToPlay / Pause (minor)
- Settings: rows adopt tokens; version row → copy-to-pasteboard (§5.9); reachable from Profile.
- HowToPlay: untouched structurally (it already follows the system); recolor to Role tokens.
- Pause: add a small live "session" line (`2,140m · ◆23`) so quitting is an informed choice;
  veil-tap-to-resume + buttons unchanged.

---

## 7. ACCESSIBILITY CONTRACT (new elements)

- **VoiceOver:** every new element specced above carries label/value/hint inline (§§1–6).
  Identifiers for UI tests: `heroStage`, `worldProgressChip`, `bestChip`, `railDaily`,
  `railRewards`, `railMissions`, `worldCard_N`, `worldCardLocked_N`, `shopFeatured`,
  `skinStageButton`, `claimAllButton`, `levelCard`, `xpLine`, `versionRow`.
- **Dynamic Type:** all type tokens are @ScaledMetric-backed (§2.3); rail cells and world cards
  grow vertically and reflow to 2-column → 1-column at accessibility sizes; tracking zeroes out
  at XL+; minimum tap target 44×44 everywhere (rail cells 64 pt, chips padded to 44 pt hit area
  via `.contentShape`).
- **Reduce Motion:** master table in §1.8 + per-component notes (§3.3 static preview frame,
  §6.2 static stage, §6.7 instant count-up, §6.5 summed toast). Existing `NeonButtonStyle`
  behavior retained.
- **Reduce Flashing (existing toggle):** power-ring blink off (§6.8); claim coin-burst dimmed.
- **Contrast:** textSecondary 70% on `Role.bg` ≥ 4.5:1; gold-on-black and black-on-gold pills
  both pass; locked `Role.lock` text always paired with an icon (never color-only state).

## 8. WHAT THIS SPEC DOES *NOT* TOUCH (iron-rule ledger)

- Core/, Spawner, Patterns, Tuning, run RNG: untouched → solvability bot stays green,
  `layoutVersion` unchanged (rules 1–4). UI-local SplitMix64 uses (world decor seed, featured
  rotation) consume no run RNG.
- Economy: payouts, revive costs, applyRunSummary single-shot, challenge/checkpoint gating —
  unchanged (rules 9–10). XP is additive meta written in the same applyRunSummary pass.
- Profile: only additive fields (`bestDistanceByWorld`, `lastSeenAffordableSkins`, XP/level
  fields owned by the progression designer), all `decodeIfPresent ?? default` (rule 7).
- Rendering of previews/stages: MeshDescriptor/Canvas/DSP only, zero binary assets (rule 6);
  all new views read `@Observable` stores live per G3; Swift 6 strict concurrency (rule 8).
- No ads, no SDKs, no new IAPs: shop fullness is layout + coin items + cross-links only.
