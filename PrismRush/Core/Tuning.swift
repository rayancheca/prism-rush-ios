import Foundation

/// All gameplay constants, ported verbatim from the shipped Three.js prototype.
/// These are ground truth — do not "improve" them without re-tuning against the reference.
/// `Core/` imports Foundation only; never a renderer.
enum Tuning {
    static let laneX: [Double] = [-2.2, 0, 2.2]
    static let worldLength: Double = 800
    /// Number of distinct world families before the palette/sky set evolves and repeats (v1.5: 12).
    /// `Core/` can't import the UI `Theme`, so this mirrors `Theme.worlds.count`; a test pins them
    /// equal. Purely cosmetic — `stepWorld` folds the absolute ordinal to this for the family index,
    /// consuming no RNG, so changing it never touches the spawn stream (no `layoutVersion` bump).
    static let worldFamilyCount = 12
    static let worldBlendRate: Double = 0.6   // crossfade speed → ~1.7 s cinematic world transition
    static let speedStart: Double = 17, speedRamp: Double = 0.0052, speedCap: Double = 33
    static let menuSpeed: Double = 7
    static let jumpV0: Double = 10.6, gravity: Double = 26
    static let laneLerpRate: Double = 15   // lane settle ~0.30 s — snappier dodges, strictly easier
    static let slideDuration: Double = 0.55, slideScaleY: Double = 0.38, slamVy: Double = -14
    static let jumpBuffer: Double = 0.25   // widened for human reaction + iOS touch latency

    // Moving wall (pattern 10): deterministic phase + smaller amplitude + slower sweep so a human can
    // read it and a safe lane always exists; only spawns once the player has acclimated (diff >= 0.6).
    static let movingWallAmplitude: Double = 1.6
    static let movingWallFreq: Double = 0.22
    static let movingWallMinDiff: Double = 0.6
    static let bodyRadius: Double = 0.62, groundedCenterY: Double = 0.66
    static let lowKillTop: Double = 0.85
    static let barKillBottom: Double = 0.95, barKillTop: Double = 1.65
    static let laneHitHalfWidth: Double = 1.25
    static let gemPickup = (dz: 1.0, dx: 1.0, dy: 1.15)
    static let magnetDuration: Double = 6, magnetRange: Double = 16
    static let doublerDuration: Double = 10   // gems pay double CURRENCY (skill stats unaffected)
    // Chrono slow-mo: distance integrates at speed × factor while the player ticks at real dt,
    // stretching every dodge window ~1.5× — strictly easier. The raw `speed` ramp is untouched.
    static let chronoDuration: Double = 5, chronoFactor: Double = 0.65
    // Super Sneakers: a collected winged-boot pickup launches jumps at × this velocity for the
    // duration (height ∝ v², so ×1.25 ≈ ×1.56 apex). Only the player's launch velocity changes —
    // ballistic gem-arc/ring PLACEMENT stays on the base constants (it never reads this), so the
    // buff only ever over-clears, never under-places. The bot never collects pickups, so the buff
    // is never active in the solvability soak (its air-slam arc model stays on the base jump).
    static let superSneakersDuration: Double = 8, superSneakersJumpMult: Double = 1.3
    // While Super Sneakers is active, a jump whose feet clear this height VAULTS a tall wall instead
    // of dying (the tall mesh spans y 0…3.2; 2.9 gives a forgiving near-apex window). Height-aware
    // ONLY when the buff is active — the solvability bot never has the buff, so its runs are
    // unchanged and stay byte-identical (no layoutVersion bump; collision-only, no spawn RNG).
    static let tallVaultClearance: Double = 2.9
    // Post-absorb grace: patterns place twin talls at the same `d`, so a mid-lane-change shield hit
    // must not let the second wall kill on the same tick (or the next — it's still in the kill band).
    static let invulnDuration: Double = 0.4
    static let streakPerMult: Int = 5, multCap: Int = 5   // v1.3: ×5 at 20 gems — minute one escalates visibly
    static let spawnHorizon: Double = 115
    // Guaranteed power-up cadence (v1.6): on top of the pattern pickups, drop one power-up every
    // `powerUpCadence` m cycling through ALL kinds, so the player reliably meets each one. Placed in
    // a FREE lane near the mark (no obstacle overlap), deterministically (no RNG → the seeded spawn
    // stream + PatternOrderTests are untouched; the added entities DO change the daily track, so it
    // rides the layoutVersion 3→4 bump).
    static let powerUpCadence: Double = 350, powerUpFirstAt: Double = 150, cadenceClearance: Double = 5
    static let gapMax: Double = 11, gapMin: Double = 5, diffFullAt: Double = 3200
    static let tickDt: Double = 1.0 / 120.0

    // Near-miss windows (tall passed in this |dx| band → CLOSE bonus). The outer edge must stay
    // below the lane pitch (2.2) or simply standing one lane away auto-awards CLOSE.
    static let nearMissInner: Double = 1.25, nearMissOuter: Double = 1.95
    // Difficulty gating thresholds for the pattern catalogue (5-tier prefix ladder, see Spawner).
    static let earlyDistance: Double = 260
    static let midEarlyDiff: Double = 0.18   // v1.3: 576 m — rings & overdrive unlock before the pain
    static let midDiff: Double = 0.45

    // Collision / lifecycle (derived from the reference; named to avoid magic numbers).
    static let obstacleZHalf: Double = 0.95       // |z| < this → obstacle is at the player plane
    static let recycleObstacleZ: Double = 10      // obstacle behind camera → recycle
    static let recycleCollectibleZ: Double = 8    // gem / pickup behind camera → recycle
    static let pickupZHalf: Double = 1.1, pickupXHalf: Double = 1.1, pickupYHalf: Double = 1.3
    static let magnetGemXRate: Double = 7, magnetGemYRate: Double = 7   // y fast enough to reel in arc gems
    static let nearMissBonus: Int = 40, gemBaseScore: Int = 10

    // Spawn / speed lerp factors.
    static let speedLerp: Double = 1.5, overDecel: Double = 22
    static let bankRate: Double = 0.32, bankLerp: Double = 10, slideLerp: Double = 20
    static let landSquashY: Double = 0.68, airStretchY: Double = 1.18, airHoldY: Double = 1.12

    // Pool caps — bound the live entity count. (`capGem` is Core-only: the RealityKit renderer pools
    // gems on demand and never reads this, so raising it costs nothing but a few more unlit
    // octahedra.) v1.7: 72 → 112. Measured peak concurrent demand inside the 115 m spawn horizon is
    // 94, so 72 was silently dropping up to 22 gems per frame at `GameCore.apply` — a defect that
    // predates v1.7 (v1.6 also pegged the cap) and that would have punched holes in the new greed
    // line. Pinned by `DifficultyCurveTests.testLiveGemCountStaysUnderThePoolCap`.
    static let capLow = 18, capTall = 14, capBar = 6, capGem = 112, capShield = 4, capMagnet = 4
    static let capDoubler = 2, capChrono = 2, capSplitBar = 6, capSuperSneakers = 2
    /// One chasm per pattern and only pattern 14 places one; at the tightest act-two gap two
    /// consecutive chasm patterns still span > `spawnHorizon`, so 3 is slack, not a budget.
    static let capChasm = 3

    // MARK: v1.3 mechanics

    // Ballistic gem arc: gems sit ON the predicted jump path. Pure f(d) — zero RNG (rule 2).
    static let gemArcBaseY: Double = 0.8      // gem 0 height — the grounded jump telegraph
    static let gemArcAirFrac: Double = 0.75   // arc covers the first 75% of the airtime (up, over, ¾ down)
    static let gemArcMaxSpan: Double = 14     // span cap keeps pattern lengths bounded at high speed

    // Prism rings (aim verb): thread the torus mid-jump; PERFECT = bullseye at the apex.
    static let ringY: Double = 2.90           // apex center height: h_max (2.16) + in-air center (0.74)
    static let ringPassDX: Double = 0.9
    static let ringPassDY: Double = 0.9
    static let ringPerfectDY: Double = 0.12
    static let ringZHalf: Double = 0.9
    static let ringScore: Int = 150
    static let ringCoins: Int = 5             // pays into gemCount (currency) — never streak (rule 9)
    static let ringPerfectCoins: Int = 12
    static let capRing = 4

    // Overdrive pads: +30% speed (capped) for one second, contained in an obstacle-free runway —
    // worst-case boost travel (trigger ≤ pad+1.1, then 1.0 s × 36) ends well inside the pattern.
    static let boostDuration: Double = 1.0
    static let speedUpDeployDuration: Double = 3.0   // manual "Speed Up" deploy — a 3 s overdrive burst
    static let boostFactor: Double = 1.3
    static let boostSpeedMax: Double = 36
    static let boostScoreBonus: Int = 60
    // Pre-run "Head Start" consumable: launch with this many seconds of Overdrive boost (a momentum
    // head start, not a score grant). Longer than a pad boost; leaderboard-safe (no usedCheckpoint).
    static let headStartBoostDuration: Double = 4.5   // a longer, clearly-felt launch (v1.6)
    static let boostGemBonus: Int = 1         // each gem pays this many extra coins while boosting
    static let capBoostPad = 2

    // Flow surge: every flowPerSurge-th CLOSE/SLICK without a hit detonates a score bonus and a
    // gem fountain sprayed into the player's lane. Deterministic from state — consumes ZERO RNG.
    static let flowPerSurge: Int = 3
    static let flowSurgeScore: Int = 80
    static let fountainGems: Int = 10
    static let fountainLead: Double = 26
    static let fountainSpacing: Double = 1.7

    // MARK: v1.7 — the second act (PR-0400)

    // Act one saturates and then stops: `speedCap` is reached at 3,077 m, `maxIndex` opens the last
    // pattern at 1,920 m, and the gap floors at `diffFullAt`. Before v1.7 a 4,000 m run and a
    // 40,000 m run were the same run (measured on device, session 003). Act two is a SECOND
    // escalation axis over the same speed: the pattern mix sheds its breather beats, the gap keeps
    // closing on a shallow curve, and the moving walls stop parking in the centre.
    //
    // Speed deliberately does NOT rise. The readable lead is hard-capped at ~65 m by the backdrop
    // plane (RealityRenderer.swift:756) — 1.97 s at the cap — and pushing it back was tried and
    // reverted in v1.6. Faster would be unreactable, which is a worse game, not a harder one.
    static let actTwoAt: Double = diffFullAt          // 3,200 m — exactly where act one stops moving
    static let actTwoFullAt: Double = 9_600           // world 12, where the palette cycle evolves
    /// Act two's gap floor: act one lerps 11 → 5 by `diffFullAt`, act two continues 5 → 4.
    /// Deliberately shallow. The catalogue's tightest cross-pattern adjacency is pattern 8's
    /// trailing clearance (9 u) + gap + pattern 5's leading obstacle (5 u); at gap 4 that is still
    /// 18 u ≈ 0.55 s at the cap — looser than adjacencies act one already ships *inside* a pattern
    /// (pattern 5's talls are 9 u apart). Density comes from the mix, not from crowding the seams.
    static let gapFloorActTwo: Double = 4
    /// Moving walls (pattern 13) spawn at phase 0 in act one, which parks them dead centre on their
    /// collision plane and leaves BOTH outer lanes permanently safe — verified the easiest late
    /// pattern in the catalogue despite being the exclusive tier-5 unlock. In act two the phase
    /// swings out to ±this (scaled by intensity) so the safe lane has to be read, not memorised.
    /// Bounded: sin(0.75)·1.6 = 1.09, so one outer lane always keeps ≥ 3.0 u of clearance.
    static let wallPhaseSwingActTwo: Double = 0.75

    // MARK: v1.7 — risk-priced gems (PR-0414 / D-006)

    /// Gems stay entirely safe until here — `midDiff × diffFullAt`, the tier that opens the gauntlet
    /// and the split bar, by which point every verb has been taught. D-006's revisit clause asks for
    /// risk to be gated behind a distance threshold rather than shipping a punishing early game.
    static let riskGemsFrom: Double = 1_440
    /// The greed line stops this many SECONDS of travel short of the lane it occupies closing.
    /// Constant in time, so the exit is the same commitment at 17 m/s and at the cap (a planned
    /// swerve, never a reaction — clearing a lane takes ~0.06 s of lane lerp).
    static let riskExitSeconds: Double = 0.30
    static let riskExitMinLead: Double = 7
    /// Bounds on the greed line so it stays a legible detour, not a second economy. At most 6 gems
    /// against the safe breadcrumb's 2–3: roughly a 2× price for the risk.
    static let riskGemsMin = 3, riskGemsMax = 6
    static let riskGemSpacing: Double = 1.7
    /// How far the greed line may run BACK past the start of the inter-pattern gap, into the empty
    /// tail of the pattern before it. Most patterns close a lane within ~7 u of their start, and the
    /// gap is only 4–5 u, so without this the line has nowhere to live and almost never appears.
    /// 8.5 u is `(riskGemsMax − 1) × riskGemSpacing` — the exact length of a full line — and stays
    /// inside the catalogue's smallest trailing clearance (9 u, pattern 8), so it can never reach
    /// back into the previous pattern's obstacles.
    static let riskLineReach: Double = 8.5
    /// A greed gem this close to an obstacle is dropped — the line simply breaks around a low you
    /// have to jump, rather than rendering a gem inside it.
    static let riskGemClearance: Double = 1.5

    // MARK: v1.8 — the chasm, tier six (PR-0450)

    /// The catalogue's sixth and last tier, at `diff 0.8`. Two properties make this the right gate:
    ///
    /// 1. It is INSIDE a good run. A good run is about two minutes ≈ 3,300 m (§3 of the design
    ///    bible), so a tier that opens at 2,560 m is one players actually meet — the whole point of
    ///    PR-0450 was that the last new thing arrived at 1,920 m and nothing followed it.
    /// 2. It is at or before `actTwoAt` (3,200 m). Act two draws from `Spawner.pool`, which is a
    ///    slot table that BYPASSES `maxIndex` entirely — so a tier gate later than act two's start
    ///    would let the table spawn a pattern its own ladder had not unlocked yet.
    ///    `DifficultyTests.testEveryWaveKeepsTheFullCatalogueReachable` probes d = 3,300 and pins
    ///    exactly this.
    ///
    /// Below this distance `maxIndex` returns 14, which is what `Patterns.count` used to be — so
    /// every tier boundary under 2,560 m draws byte-identically to v1.7 (pinned by
    /// `PatternOrderTests.testSixthTierLeavesTheEarlierLadderByteIdentical`).
    static let chasmDiff: Double = 0.8                 // × diffFullAt → 2,560 m

    /// Half the chasm's length along the track: the gap is `2 × 4 = 8` u of missing deck.
    ///
    /// Bounded above by `recycleObstacleZ` (10): the record is culled when its CENTRE passes z = +10,
    /// so any half-length under 10 guarantees the trailing edge is already behind the player.
    /// Bounded below by legibility — much shorter and it is a wide bar, not a hole.
    static let chasmHalfLength: Double = 4.0

    /// Feet must be at least this far off the deck to be over the gap rather than in it.
    ///
    /// With `jumpV0` 10.6 and `gravity` 26, `y(t) = 10.6t − 13t²` exceeds 0.30 for
    /// t ∈ [0.0294, 0.7860] — a 0.7567 s airborne window out of 0.8154 s of total airtime (93%).
    /// The chasm is therefore forgiving in the air and absolute on the ground, which is the read
    /// we want: "be airborne", not "be airborne at exactly the apex".
    static let chasmClearance: Double = 0.30

    /// Seconds of travel before the chasm's LEADING edge at which the Autopilot commits its jump.
    ///
    /// The launch point must satisfy `0.0294·v ≤ lead ≤ 0.7860·v − 2·chasmHalfLength`. At the tier's
    /// unlock speed (30.3 m/s) that is [0.89, 15.8]; at the cap (33) [0.97, 17.9]; under a pad boost
    /// (36) [1.06, 20.3]. `0.28·v` lands at 8.5 / 9.2 / 10.1 — near the middle of all three, with
    /// > 7 u of margin on either side. Clamped so the arithmetic cannot walk out of range if the
    /// speed constants are ever retuned.
    static let chasmBotLeadSeconds: Double = 0.28
    static let chasmBotLeadMin: Double = 7, chasmBotLeadMax: Double = 11

    // MARK: v1.9 — THE WARDENS (PR-0457, design in docs/agent/10_WARDENS.md)

    /// A Warden guards every third world, so encounters land 2,400 m apart (worlds 3, 6, 9, …).
    /// Owner call, S-007: often enough to be a structure, rare enough to stay an event.
    static let wardenEveryWorlds = 3

    /// The arena: the stretch of deck at the head of a Warden's world where obstacles and boost pads
    /// are suppressed so the encounter's telegraphs are the only thing to read (decree 6). Gems are
    /// deliberately NOT suppressed — they are the ammunition, so the shield phase is spent
    /// collecting rather than waiting.
    ///
    /// Must outlast the longest possible encounter in DISTANCE, since the encounter is timed and the
    /// arena is not. Sized from the crudest bound that is still provable, so no run can defeat it:
    /// `wardenArmWindow` (60) + `wardenMaxSeconds` (16) × `boostSpeedMax` (36) = 636 m, against 660.
    /// Using `boostSpeedMax` rather than `speedCap` is deliberate — pads are suppressed inside the
    /// arena, but a player can enter one already boosting. Measured worst case across 24 seeded bot
    /// runs is 438 m, so the bound is conservative by design. Pinned by
    /// `WardenTests.testAnEncounterCanNeverOutrunItsArena` and `…testEveryEncounterFinishesInsideItsArena`.
    ///
    /// This is the feature's biggest tuning lever and the first thing to revisit after playtesting:
    /// 660 m of deliberately clear deck every 2,400 m is ~27% of the track past the first encounter.
    /// Shrinking it means shortening `wardenShieldWindow`, which moves the charge threshold below.
    static let wardenArenaLength: Double = 660

    // Encounter timings. The whole set is bounded by construction: three fixed core hits, a fixed
    // shield window, and a fixed number of seconds — a Warden can never become a war of attrition.
    static let wardenArriveTime: Double = 0.9    // craft drops into view; nothing is lethal yet
    static let wardenShieldWindow: Double = 9.0  // break the shield inside this or it breaks off
    static let wardenTelegraphTime: Double = 0.85 // wind-up before a beam fires — the read
    static let wardenStrikeShowTime: Double = 0.30 // the fired beam stays lit this long
    static let wardenAttackRecover: Double = 0.55  // gap after a strike before the next telegraph
    static let wardenDieTime: Double = 1.0
    static let wardenLeaveTime: Double = 0.9

    /// Hard ceiling on a whole encounter, from arrival to the craft clearing the sky.
    ///
    /// The phase timings alone do NOT bound it. A held shield absorbs a caught beam, and an absorbed
    /// beam is spent without landing a core hit — so a player who keeps picking up shields (pickups
    /// are deliberately left in the arena) can trade indefinitely and drag the fight past the end of
    /// its own arena, where obstacles resume and beams and walls arrive together. That is the one
    /// combination the arena exists to prevent, so the encounter is capped outright: at the cap it
    /// breaks off exactly as it would on a held shield. Pinned by
    /// `WardenTests.testAnEncounterCanNeverOutrunItsArena`.
    static let wardenMaxSeconds: Double = 16.0

    /// A Warden only arms in the first stretch of its arena. Without this, a checkpoint run that
    /// began 80 m from the arena's end would summon a Warden with no room to fight it.
    static let wardenArmWindow: Double = 60

    /// Clean dodges needed to kill. Fixed and small: the fight is the fun part, not the grind.
    static let wardenCoreHits = 3

    // The gun. Fire rate is the player's charge bank, spent as it burns — a timer they earned before
    // the fight started, never a win button (it cannot kill; only dodging can).
    //
    // Damage is `wardenBaseDPS + charge × wardenChargeDPS` while charge drains at
    // `wardenChargeDrain`/s, so the integral to break `wardenShieldHP` inside `wardenShieldWindow`
    // solves to a threshold at charge ≈ 0.80:
    //   charge 1.00 → shield falls at 6.25 s ✓   charge 0.85 → 8.02 s ✓
    //   charge 0.80 → 9.13 s ✗ (just past the window)   charge ≤ 0.75 → never
    // A player who banked nothing fires at `wardenBaseDPS` and mathematically cannot break it,
    // which is the point. Pinned by `WardenTests.testTheChargeThresholdIsWhereTheArithmeticSaysItIs`.
    static let wardenShieldHP: Double = 100
    static let wardenBaseDPS: Double = 4
    static let wardenChargeDPS: Double = 16
    static let wardenChargeDrain: Double = 0.08

    /// Gems needed to fill the bank from empty. Measured, not guessed: the solvability bot banks
    /// ~637 gems by the first encounter at 2,400 m (24 seeds, min 586, max 686), so 520 fills a
    /// well-run first act with margin and the 0.80 threshold lands at ~416 gems — reachable by
    /// collecting, missable by ignoring. Charge is SPENT, so every later Warden must be re-armed.
    static let wardenChargeFullGems: Double = 520
    static var wardenChargePerGem: Double { 1.0 / wardenChargeFullGems }

    /// How often a beam closes a SECOND lane as well as the player's own.
    ///
    /// Every beam always locks the lane the player is standing in, so standing still is always
    /// fatal and the gun can never win a fight on its own — that invariant is the design's, and an
    /// earlier build that merely *usually* stalked broke it: a player who never moved won outright
    /// whenever three consecutive beams happened to pick an empty lane, because "wasn't in the beam"
    /// was being scored as a dodge. It isn't one.
    ///
    /// This much of the time a second lane closes too, leaving exactly one safe lane — so answering
    /// every telegraph with a blind sidestep is punished about half the time, and the wind-up has to
    /// actually be READ. At most two of three lanes ever close, so a safe answer always exists and
    /// every attack resolves in exactly one cycle: the fight stays bounded at `wardenCoreHits`
    /// exchanges and can never outrun its arena.
    static let wardenDoubleBeamChance: Double = 0.4

    /// Half-width of the beam column. Same value as `laneHitHalfWidth`, deliberately: a beam is as
    /// wide as a wall, so the lane you are safe in is the lane you would be safe in for anything
    /// else, and mid-transit between two lanes is exposed to both — exactly as it already is.
    static let wardenBeamHalfWidth: Double = laneHitHalfWidth

    // Where the craft hangs. Far enough forward to read as a thing in the sky ahead rather than an
    // obstacle arriving, low enough to sit inside the camera's frustum above the vanishing point.
    //
    // Checked against the actual rig (`RealityRenderer`: eye at (0, 5.1, 9.6), looking at
    // (0, 1.3, −5), 62° FOV — a view axis 14.6° below horizontal, 31° half-angle). At hover the
    // craft sits 14.7° off that axis: in frame, upper third. At the top of its arrival it is 25.9°
    // off — still inside. `wardenLeaveRise` deliberately takes it PAST the edge, because leaving the
    // frame is what "climbs away" should look like. Well in front of the ~65 u backdrop plane.
    static let wardenStandOff: Double = 26     // units ahead of the player (rendered at z = −this)
    static let wardenHoverY: Double = 5.2
    static let wardenArriveRise: Double = 7.0  // starts this much higher and descends in
    static let wardenLeaveRise: Double = 14.0  // climbs away by this much on the way out

    /// Payout for a kill. Coins are deliberately the SMALLEST reward tier (10_WARDENS.md §4) — this
    /// feature exists to fix the coin sink, not to feed it — but a fight with no payout is not a
    /// fight worth playtesting, so phase 1 ships the bounty and the run-scoped kill count. The
    /// world-exclusive character and the Countermeasure sink are later phases.
    static let wardenCoinBounty = 150
    static let wardenScoreBonus = 1_200
}
