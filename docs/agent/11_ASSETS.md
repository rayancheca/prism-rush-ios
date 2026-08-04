# Assets — the budget, the licence floor, and the order things land in

**Status:** **POLICY, NOTHING BUILT.** D-046 (2026-08-03) revoked "zero binary assets"; this file is
what replaced it. No binary asset has shipped yet — `PrismRush/Assets.xcassets` still holds exactly
`AppIcon.appiconset` (948 KB) and `PrismRush/Resources/` does not exist. Full owner mandate,
verbatim and decomposed: `docs/agent/audits/scratch/s016_mandate.md` (session scratch, gitignored —
the load-bearing parts are reproduced here on purpose).

> **This file exists because an iron rule cited a gitignored path.** `CLAUDE.md`'s amended iron
> rule 6 pointed at `docs/agent/audits/scratch/s016_assets.md`, which `.gitignore:33` excludes. Cite
> this file instead. If you are adding an asset and something below is in your way, change it
> deliberately and record why — do not route around it.

---

## 1. What the owner actually said

> *"why are you not importing real assests. delete that code only decree"* — and later in the same
> message — *"use things online idc what."*

Two things arrived with it and are not separable from it:

> *"the app becomes slow at points. this can never happen. manage ram and memory somehow."*

> *"ciopy subway surfers"*

So the replacement for the ban is **a budget** (§3) and **a licence floor** (§4). Neither is a
narrowing of the instruction for its own sake: an app that stutters fails the same message that
asked for the art, and an app that ships another studio's art does not ship at all.

**"Copy Subway Surfers" means copy its design language** — readability at speed, pickup
choreography, the mystery-box loop, the pacing of its reveals — **with our own assets in that
idiom.** Never its art, characters, names, logo, board, hoverboard, or typeface.

---

## 2. What the game renders today (the baseline every budget is measured against)

| fact | evidence |
|---|---|
| `UnlitMaterial` is the only material type | `grep -rn "UnlitMaterial" PrismRush \| wc -l` → **127**; `SimpleMaterial\|PhysicallyBasedMaterial\|CustomMaterial` → **0** |
| No texture is ever constructed | `grep -rn "TextureResource" PrismRush/` → **0** |
| No model is ever loaded | `grep -rn "Entity.load\|Entity(named\|\.usdz" PrismRush/` → **0** |
| No mesh carries UVs or normals | `ProceduralMesh.swift:4-6`; `grep -rn "textureCoordinates" PrismRush/` → **0** |
| The scene has no lights | `grep -rn "DirectionalLight\|PointLight\|ImageBasedLight" PrismRush/` → **0** |
| No test asserts anything about assets | `grep -rniE "asset\|Bundle\.\|xcassets\|texture\|usdz" Tests/ UITests/` → **0** |
| The UI already ships system art | 53 `Image(systemName:)` sites |

**The two consequences that decide the whole pipeline:**

1. **Any imported PBR model renders flat or black.** There are no lights.
   `PhysicallyBasedMaterial` is not a drop-in. Adding a `DirectionalLight` would change the look of
   every existing surface at once and add a real-time lighting pass over ~500 entities.
2. **Form is currently faked by value banding** — `ProceduralMesh.bandedSphere` (`:412-443`), and
   `WardenRig.swift:187-189`: *"`UnlitMaterial` has no normals, so a single-colour body has no form
   at all — it is a silhouette."*

**Therefore the pipeline is: `UnlitMaterial` + a BAKED albedo/AO texture.** It reproduces the form
the banding is hand-faking, at zero runtime lighting cost, and it keeps every existing per-world
recolour working — because `UnlitMaterial.color` is a **tint × texture** pair:

```swift
var m = UnlitMaterial()
m.color = .init(tint: c, texture: .init(atlas))   // tint MULTIPLIES the texture
```

Every palette recolour in the codebase (`RealityRenderer.swift:281-290`,
`ArenaShell.restyleIfNeeded`, `WorldDecor.retint`) keeps working by writing the tint and leaving the
texture alone. We do not have to choose between real art and twelve worlds.

---

## 3. The budget

### 3.1 Device floor

`project.yml:5` sets `deploymentTarget iOS: "18.0"`; `:14` sets `TARGETED_DEVICE_FAMILY: "1"`.
iOS 18 runs on A12+, so the floor device is an **iPhone XR, 3 GB unified memory**. Community-measured
(not Apple-published) jetsam limits on a 3 GB iPhone land around 1.3–1.4 GB foreground.

**Target: ≤ 250 MB total app footprint steady state on the floor device, of which ≤ 62 MB is asset
residency.** The headroom is not timidity: the memory compressor produces intermittent multi-frame
stalls long before an actual jetsam, and the owner's complaint is about *stalls*, not crashes.

### 3.2 Format math — memorise these four rows

| format | bits/px | 512² +mips | 1024² +mips | 2048² +mips |
|---|---|---|---|---|
| RGBA8 (uncompressed) | 32 | 1.33 MB | 5.33 MB | 21.3 MB |
| ASTC 4×4 | 8 | 0.33 MB | 1.33 MB | 5.33 MB |
| **ASTC 6×6** | 3.56 | 0.15 MB | **0.59 MB** | 2.37 MB |
| ASTC 8×8 | 2 | 0.08 MB | 0.33 MB | **1.33 MB** |

(Mip chain ×1.333.)

**Default: ASTC 6×6 for anything the player looks at; 8×8 for backgrounds; 4×4 only for the player
character and full-screen UI art.** Set per-imageset in the catalog inspector.

> **THE USDZ TEXTURE TRAP — write this on the wall.** A `.usdz` is an uncompressed zip of USDC plus
> PNG/JPEG textures. Those textures **do not go through the asset catalog**, are **not** ASTC
> compressed, and decode to full RGBA8 at load. One 2048² PNG inside a USDZ = **16 MB of GPU memory**
> where the same image as an ASTC 6×6 catalog entry is **2.4 MB** — a 6.7× penalty, paid silently.
> **Rule: ship USDZ with materials but NO embedded textures; bind catalog `TextureResource`s in code
> after load.**

### 3.3 Where assets live

| destination | for | compression |
|---|---|---|
| `PrismRush/Assets.xcassets` | every 2-D texture, RealityKit's and SwiftUI's alike | **ASTC**, per imageset, plus App Store thinning |
| `PrismRush/Resources/Models/*.usdz` | geometry, and skeletal/blend-shape animation | none — see the trap |
| `PrismRush/Resources/Audio/*.m4a` | music beds and sampled SFX | AAC, streamed |

`project.yml:24-25` already globs `- path: PrismRush`, and xcodegen classifies by extension into the
right build phase. **`PrismRush/Resources/` needs zero `project.yml` edits.** Proof it already works
this way: `Assets.xcassets` and `Support/PrivacyInfo.xcprivacy` both ship with no explicit
declaration. Two defensive edits are still worth making: add
`ASSETCATALOG_COMPILER_OPTIMIZATION: space` under `targets.PrismRush.settings.base`, and retire the
now-wrong catalog comment at `project.yml:40-41`.

**`Package.swift` (Linux CI):** the SPM target declares `path: "PrismRush"` with an explicit
`sources:` list (`:14-24`), so non-listed files are excluded from compilation. CI is green today with
`Assets.xcassets`, `UI/` and `Render/` all inside that path, which is strong evidence the explicit
form suppresses SPM's unhandled-files warning. **Verify with one `swift build` after the first
`Resources/` file lands; add `exclude: ["Resources", "Assets.xcassets"]` only if SPM warns.**

### 3.4 The residency budget, per category

**IN-RUN RESIDENT — never released while the app lives:**

| category | assets | format | resident |
|---|---|---|---|
| Player skin — **equipped only** | 1 packed albedo+AO | 1024² ASTC 4×4 +mips | 1.33 MB |
| Pickups + gems + coins | one atlas | 1024² ASTC 6×6 +mips | 0.59 MB |
| Obstacles | one atlas | 1024² ASTC 6×6 +mips | 0.59 MB |
| Deck | track surface + rung/lane emissive | 2 × 512² ASTC 6×6 +mips | 0.30 MB |
| **World sky + decor — ALL TWELVE, one atlas** | every skyline/ridge/card/silhouette | 2048² ASTC 8×8 +mips | 1.33 MB |
| Warden + arena | hull, spars, kerb, pylon, gate | 1024² ASTC 6×6 +mips | 0.59 MB |
| Particles / VFX | one 4×4 alpha sprite sheet | 512² ASTC 4×4 +mips | 0.33 MB |
| Meshes — all USDZ, textureless | ~30 models, ≤ 5 k tris each | — | ≤ 4 MB |
| Sampled SFX as PCM | ≤ 24 × 0.4 s mono Float32 @ 44.1 kHz | — | ≤ 2 MB |
| | | **subtotal** | **≈ 9.1 MB** |
| | | **ceiling** | **48 MB** |

**ON-DEMAND — loaded when a sheet opens, released when it closes, never resident during a run:**

| category | budget | note |
|---|---|---|
| Character-select / shop art | 8 MB, **and probably 0** | `CharacterSwatch.swift` draws all 24 skins as 2-D SwiftUI `Canvas` today. That is already correct and already satisfies decree 2. Do not replace it with 24 textures. |
| Mystery-box open sequence | 6 MB | model + open animation + burst sheet. Purge on dismiss. |
| **Music bed** | **STREAM, NEVER DECODE** | ⚠️ a 60 s stereo loop decoded to Float32 PCM is `60 × 44100 × 4 × 2` = **21 MB**. Play compressed `.m4a` via `AVAudioFile` scheduling. `SynthEngine.swift:24` caches SFX as `AVAudioPCMBuffer` — right for 0.4 s one-shots, catastrophic for a bed. |

**REPO / INSTALL:**

| | budget |
|---|---|
| Committed binary assets | **≤ 60 MB** |
| Install-size delta | ≤ 80 MB |
| Git LFS | **do not adopt** — complicates CI checkout, burns a 1 GB free quota; 60 MB of ordinary blobs is fine |
| Source art (4K masters, `.blend`, layered files) | **outside the repo.** Git keeps every version forever. Commit shipping-resolution exports only; add `Art/` to `.gitignore`. |

### 3.5 Polygon and draw-call budget

Memory is the budget everyone states. **Draw calls are the one that will bite.**

| | budget | today |
|---|---|---|
| Player character | ≤ 3,000 tris | 1,728 (`bandedSphere` 6 bands) + rig |
| Any single pickup | ≤ 400 tris | ring gate **560 — over**; magnet 360 (320 after the horseshoe); shield 152 |
| Any single obstacle | ≤ 500 tris | boxes, RK-internal |
| Warden (whole rig) | ≤ 8,000 tris | ≈ 2,100 |
| Whole frame | ≤ 60,000 tris | **UNVERIFIED** — dominated by 560 `.generateSphere` particles (`ParticleSystem.swift:33,35,40`) |
| Whole frame | ≤ 150 draw calls | likely 300–600 busy |

**Every asset added is charged against these, and the charge is paid before it is spent.**

> **Measure `generateSphere` before spending anything.** `ParticleSystem.swift:35` builds ONE
> `.generateSphere(radius: 0.085)` and instances it 560 times (`:33,39-44`). If RealityKit's default
> sphere is a 24×24 lat-long grid (~1,100 tris) the particle field alone is ~616,000 triangles at
> peak. **Nobody in this repo has ever printed that number.** Recipe, Mac, one-line, no build-config
> change:
> ```swift
> let m = MeshResource.generateSphere(radius: 0.085)
> let t = m.contents.models.flatMap(\.parts).reduce(0) { $0 + (($1.triangleIndices?.count ?? 0) / 3) }
> let v = m.contents.models.flatMap(\.parts).reduce(0) { $0 + $1.positions.count }
> print("sphere: \(v) v / \(t) t")
> ```

---

## 4. The licence floor — not the owner's to waive

Two things survive *"use things online idc what"*:

1. **We must have the right to ship what we ship.** App Store review rejects infringing content, and
   a trademark complaint against a live app is worse than a rejection.
2. **"Copy Subway Surfers" is a design brief, never an art source.** See §1.

**Permitted, in descending order of confidence:**

| source | licence | confidence |
|---|---|---|
| **Poly Haven** | CC0, no attribution | ✅ highest — ideal for surface textures |
| **AI-generated** | check each generator's ToS for commercial use; purely-AI output is uncopyrightable in the US, which means we cannot claim exclusivity — irrelevant for shipping | ✅ high, **once the ToS check is recorded** |
| **CC0 libraries** (ambientCG, Kenney, OpenGameArt CC0-filtered) | CC0 | ✅ high |
| **SIL OFL fonts** | OFL — **the licence file must ship in the bundle** | ✅ high, with the paperwork |
| **Freesound** | mixed — **filter to CC0 only** | ⚠️ per-file check |
| **Sketchfab** | **mixed per model** — many CC-BY, many non-commercial | ⚠️ per-model check, and record it |

**Forbidden, no exceptions:** anything ripped from a shipping game; any model or texture whose name,
filename or metadata references another game's IP; anything "found on the internet" with no traceable
licence; Sketchfab NC models.

### 4.1 The provenance ledger — required, not optional

**`docs/ASSET_LICENCES.md`, one row per shipped asset, updated in the same commit as the asset:**

| column | content |
|---|---|
| `path` | repo-relative path of the shipped file |
| `source` | URL, or the generator name for AI output |
| `licence` | CC0 / OFL / "AI-generated, <model>, <ToS checked YYYY-MM-DD>" |
| `date` | date added |
| `prompt` | for AI output: the exact prompt |
| `budget` | which §3.4 row it is charged against, and its measured size |

This is what makes a takedown or a review query answerable in one minute instead of one week, and it
is the artifact that proves the floor was respected. **An asset without a ledger row is not shipped.**

---

## 5. Migration order — every step ships on its own

> Owner, verbatim: *"im not saying replace everything im saying revise."*

**Stays exactly as it is** — a commitment, not a default: the chasm well
(`RealityRenderer.swift:1402-1424`), the hanging-bar portcullis (`:1492-1525`), the deck rungs and
lane lines (`:1086-1097`), Prism's static banded sphere (`:1194-1195`, D-011), `EntityPools`, the
whole `Synth.swift` DSP layer, and the 2-D `CharacterSwatch` previews.

| # | step | assets | risk | why here |
|---|---|---|---|---|
| 1 | **Magnet becomes magnet-shaped** — `ProceduralMesh.horseshoe` replaces `torus(0.30, 0.12)` at `RealityRenderer.swift:213` | none | nil | closes the mandate's cheapest item with no pipeline, no budget, no licence. Also a **net −40 triangles**. |
| 2 | **Particle billboards** — one 512² alpha sheet; `ParticleSystem.mesh` (`:35`) becomes a 2-triangle quad with `opacityThreshold` | 0.33 MB | low | ⚠️ **must precede every other asset.** Simultaneously the first real texture and the single biggest perf reclamation available. It *buys* the frame budget the rest of the plan spends. Put the before/after triangle count in the PR. |
| 3 | **`AssetLibrary` + the four-phase preload** (§6), wired to `GameModel.install` and gating `startRun`, carrying exactly step 2's sheet | — | low | proves the pipeline end to end with one asset in flight |
| 4 | **Deck + backdrop textures** — all targets are `.generatePlane`/`.generateBox`, already UV'd | 0.30 MB | low | biggest perceived-quality jump per byte: it is the surface the player stares at for the whole run |
| 5 | **Obstacle atlas** — `boxEntity` (`:1527`) gains a texture, tint stays the per-world palette | 0.59 MB | low | zero mesh work, zero gameplay change |
| 6 | **`ProceduralMesh.build` learns UVs** (`:445-450`), then the **sky/decor atlas** — one 2048² for all twelve | 1.33 MB | medium | the "it stops looking procedural" moment; medium only because it touches the shared mesh builder |
| 7 | **Player: equipped-skin textured model** | 1.33 MB | medium | ⚠️ decrees 1 and 2 both bind. `CharacterProportions` (`ProceduralMesh.swift:459-474`) is **extended, never bypassed**; `CharacterSwatch` updated in the SAME commit. One skin at a time; Prism last (D-011 pins it). |
| 8 | **Mystery box** — model + open animation + in-run catchable entity | 6 MB on-demand | **high** | the only step that adds an `EntityKind`, so it touches `Core/` → **iron rule 3 applies: the 200-seed bot green AND `DailyChallenge.layoutVersion` 12 → 13 (pin pre-armed at `0x9E49_3424_C18A_59C5`), goldens repinned in BOTH `DailyChallengeTests` and `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`.** |
| 9 | Warden + arena textures | 0.59 MB | low | the rig's measured proportions untouched |
| 10 | Pickup atlas + coin | 0.59 MB | low | |

**Running total after step 10: ≈ 11 MB resident + 6 MB on-demand against a 48 MB ceiling** —
deliberately 4× under, because the number that kills a game is never the one you planned.

### 5.1 What must NOT be replaced by an artist model

| thing | why the mesh is load-bearing |
|---|---|
| Obstacles | **the mesh IS the read of the hitbox.** See `hangingBarEntity`'s 23.2 → 11.6 u² frontal-area reasoning (`RealityRenderer.swift:1467-1491`) and the chasm's `deckHalfWidth` derivation (`:230-239`). Swapping in an artist model desyncs picture from rule. **Texture them, keep the geometry.** |
| Chasm | its geometry *is* the read, and it is deliberately world-blind (`:1385-1401`). Nothing to gain, a documented failure mode to re-earn. |
| Gem | the octahedron is the game's identity mark and it is 8 triangles |
| Warden / arena | every proportion derives from measured on-screen percentages (`WardenRig.swift:92-112`) |

---

## 6. Load timing — the preload phase

**Where scene construction happens today:** `GameView` declares `@State private var model = GameModel()`
(`GameView.swift:1228`); `@State` initialisers run **before** `body`, so `GameModel()` →
`RealityRenderer()` → `buildScene()` (`RealityRenderer.swift:252`) runs **synchronously on the main
actor before the first frame**, building roughly a thousand entities. `SplashView` is a sibling in the
same `ZStack` at `zIndex(10)` — it covers the booting scene visually but does not delay it.
`GameModel.install(_:)` (`GameView.swift:159`) is the first thing that runs with the RealityView
content in hand. **That is the hook.**

| phase | when | thread | what |
|---|---|---|---|
| **0 — geometry** | `RealityRenderer.init` | MainActor, sync | unchanged |
| **1 — decode** | `Task.detached` from `install(_:)` | **off** MainActor | `AssetLibrary.warm()` — every in-run-resident `TextureResource` / `Entity(named:)`, held in an `actor` with strong refs so nothing is re-decoded |
| **2 — bind + warm draw** | on phase-1 completion, hopped to MainActor | MainActor, one frame | assign textures into already-built entities; **then park a 1-px quad behind the camera carrying every distinct material for exactly one frame, and remove it** |
| **3 — gate** | `startRun` | MainActor | `guard assets.isWarm` |

**Phase 2's warm draw is not optional and is the part most plans forget.** Having a `TextureResource`
in memory is not the same as having a Metal pipeline state compiled for the material referencing it.
The first draw of a never-drawn material stalls the render thread while Metal compiles and uploads. A
sub-frame stall at metre 1,400 is precisely *"the app becomes slow at points."* `EntityPools.prewarm`
(`EntityPools.swift:58-66`) already encodes this instinct for entities — extend it to materials.

**Absolute rule: zero asset construction while `mode == .play`.** No `TextureResource(...)`, no
`Entity(named:)`, no `MeshResource.generate` inside `sync(_:)` (`RealityRenderer.swift:281`),
`advanceVisuals(_:)` (`:888`) or `fire(_:)` (`:670`). Anything arriving mid-run arrives as a
pre-decoded resource already in `AssetLibrary`, and the only mid-run operation is a material swap.

**World crossfades.** Worlds are 800 m (`Tuning.swift:8`) and crossfade over a blend window, so a
naive "load world N+1 at the boundary" design loads mid-run — the exact thing forbidden above.
**One 2048² ASTC 8×8 atlas for all twelve worlds: 1.33 MB resident, permanently.** No mid-run loading
exists at all and the whole failure class is deleted. Sky and decor art is background, low-frequency
and heavily tinted per world (`WorldDecor.retint`) — it does not need per-world resolution.

---

## 7. What survives the revocation

Iron rule 6's number is kept as a tombstone (the other eight are cited by number across
`docs/agent/`). Two things survive it and are not the owner's to waive:

1. **The licence floor (§4).**
2. **The memory budget (§3)** — the same owner message that asked for assets said the app must never
   be slow, and importing assets is the fastest way to make that worse.

`PrismRush/Assets.xcassets` is no longer a carve-out; it is the catalogue.
**`AppIcon.appiconset` stays a byte-copy of `Tools/gen_icon.swift`'s output** (the tool syncs it,
`gen_icon.swift:297-306`) — never hand-edit it. That half of INV-110
(`07_ARCHITECTURE.md:2843-2851`) survives; its "never add anything else to `Assets.xcassets`" clause
does not.
