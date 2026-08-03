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

    // Moving wall (pattern 13): deterministic phase + smaller amplitude + slower sweep so a human can
    // read it and a safe lane always exists.
    static let movingWallAmplitude: Double = 1.6
    static let movingWallFreq: Double = 0.22
    /// Tier five's gate — 900 m ≈ 47 s. See the unlock-ladder block further down for why the whole
    /// ladder moved.
    static let movingWallMinDiff: Double = 900.0 / diffFullAt
    static let bodyRadius: Double = 0.62, groundedCenterY: Double = 0.66
    static let lowKillTop: Double = 0.85
    static let barKillBottom: Double = 0.95, barKillTop: Double = 1.65

    // MARK: - the hanging bar (v2.2) — the catalogue's first MANDATORY slide
    //
    // Every bar in the game up to v2.1 could be JUMPED. `barHit` kills only between 0.95 and 1.65,
    // and a base jump puts the body's underside above 1.65 for 0.434 s of its 0.815 s arc — so a
    // player who never once swiped down could complete the entire pattern catalogue. Slide was the
    // game's only decorative verb.
    //
    // A hanging bar has NO top. That single property is what makes it unanswerable by jumping from
    // any state — the apex is 2.16 m and even Super Sneakers only reaches 3.65 m, both far above
    // 0.95 — and it is the same property, for the same reason, that `wardenCurtainKillBottom` had:
    // give it a ceiling of 1.65 and its airborne window becomes a strict superset of the ordinary
    // bar's, one jump answers both, and the verb ladder collapses back to a binary with the
    // solvability bot cheerfully certifying the degenerate strategy.
    //
    // Sliding clears it identically to an ordinary bar (`slideScaleY` 0.38 puts the body's top at
    // 0.446), so nothing new is taught: it is the bar the player already knows, with the escape
    // hatch removed.
    //
    // A hanging bar has no REACHABLE top — see `hangingBarKillTop` for why that is stated as a
    // ceiling above every attainable height rather than as no ceiling at all.
    static let hangingBarKillBottom: Double = barKillBottom

    /// Top of the kill band — and, exactly, the top of the drawn mesh.
    ///
    /// **UNREACHABLE, not unbounded, and the distinction is decree 2.** The property that makes this
    /// obstacle work is that no jump clears it; "no top at all" is one way to get that and it is the
    /// way `wardenCurtainKillBottom` used, but it forces the MESH to be drawn taller than anything
    /// the player could reach — 5.2 m of red wall — or else the render promises a gap the collision
    /// does not honour. That was finding F5 of the S-011 render audit, where a Super Sneakers jump
    /// put the body visibly clear of the drawn curtain and died anyway.
    ///
    /// A ceiling above every reachable height gives the same guarantee honestly and 28% shorter. The
    /// highest a body's UNDERSIDE ever gets is a Super Sneakers apex: `(10.6 × 1.3)² / 2g` = 3.648 m
    /// plus the 0.10 m foot inset = 3.748 m. 4.0 clears that by 0.25 m and is pinned by
    /// `WardenTests.testTheHangingBarCannotBeJumpedFromAnyState`, so raising the jump buff without
    /// raising this turns the suite red instead of quietly opening a hole in the one obstacle whose
    /// entire purpose is that there is no way over it.
    static let hangingBarKillTop: Double = 4.0
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

    // MARK: - The stumble (v2.0) — the game's first non-lethal contact
    //
    // Until now the game had no vocabulary for HARM: a contact either did nothing or ended the run.
    // The stumble is the missing middle. It is deliberately NOT a second life; it is one rescue,
    // available only from a mistake that was nearly right, and only while you are not already
    // recovering from the last one. That is the owner's "not two lives per say — more like 1.5".
    //
    // **The rule, stated once:** a contact is a stumble when the smallest move that would have made
    // it a clean pass is shallow, measured on the axis whose VERB answers that obstacle, at the
    // instant the overlap begins. Deep on every applicable axis → death. The chasm is exempt: there
    // is no shallow overlap in an eight-metre hole, and keeping one obstacle unconditionally fatal
    // is what stops the catalogue losing its only two-sided timing window.

    /// Lateral forgiveness. The kill line effectively moves 1.25 → 0.90; the CLOSE near-miss band
    /// ([1.25, 1.95)) is untouched, so no reward is eaten to pay for this.
    ///
    /// **Why 0.35 and not more.** It is exactly half the CLOSE band, so it is derived from a shipped
    /// constant rather than invented, and it is the deepest overlap that still reads as *half* a hit:
    /// a wall is 1.9 wide and the body 1.24, so contact becomes visible at dx 1.57 and at dx 0.90 the
    /// body is 0.67 into the wall — 54% buried. Below that you did not half-hit it, you ran through it.
    ///
    /// Honest measure of what this buys: `px` eases toward the target lane at `laneLerpRate`, so
    /// crossing the band takes `ln(1.30/0.95)/15 ≈ 21 ms` against 30–80 ms of human timing jitter.
    /// It converts roughly a quarter of "I swiped and it wasn't quite enough" deaths. It is a rescue
    /// from a near-miss, not a safety net — widening it is one edit if play says otherwise.
    static let stumbleGrazeDX: Double = 0.35

    /// Vertical forgiveness, applied at each edge of a `low` (feet) and both edges of a `bar`
    /// (slid almost low enough / jumped almost high enough). Widens the 660 ms low-clear window by
    /// ~23 ms per edge.
    static let stumbleGrazeDY: Double = 0.20

    /// The stagger. The player has no forward velocity — slowing the WORLD is what the chrono pickup
    /// does, i.e. a reward — so this cannot be sold as a difficulty penalty and must never be dressed
    /// like slow-mo (the renderer punches the FOV IN, where chrono pulls it out).
    ///
    /// It is worth ~13 points, which is not the punishment; the multiplier reset is. But it is not
    /// merely flavour either: because `stumbleRecover` is a TIME window and the dip cuts the speed,
    /// the stretch of deck you must survive while vulnerable shrinks from ~30 m to ~18 m. The
    /// slowdown and the danger window are coupled in the player's favour, which is the right shape.
    ///
    /// No new timer: `stepSpeedAndDistance` already lerps `speed` back toward a DISTANCE-derived
    /// target at `speedLerp`, so the dip self-heals over ~1.3 s and the difficulty ramp cannot desync.
    static let stumbleSpeedFactor: Double = 0.62

    /// I-frames immediately after a stumble. Sized off the worst-case paired-wall transit
    /// (`2 × obstacleZHalf / speedStart` = 112 ms): patterns 3/7/9 place twin talls at the same `d`,
    /// and without this the partner would convert the rescue into a death on the next tick.
    static let stumbleGrace: Double = 0.15

    /// How long a stumble leaves you vulnerable. `stumbleGrace` of that is invulnerable; for the rest
    /// **any** further contact is lethal — including one that would otherwise have been a stumble.
    /// This is the whole self-limiting mechanism: no counter, no HUD pip, no hoarding. One mistake is
    /// forgiven, two in a row are not.
    static let stumbleRecover: Double = 0.90

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
    // MARK: the unlock ladder (v2.1, S-011 — pulled forward by a factor of ~2.1)
    //
    // Difficulty gating thresholds for the pattern catalogue (six-tier prefix ladder, see Spawner).
    //
    // **Why these moved.** S-011 measured what a player actually meets, by re-implementing the
    // spawner and integrating the real speed ramp (`docs/agent/audits/scratch/s011_obstacles.md`).
    // Against the OLD ladder — 260 / 576 / 1,440 / 1,920 / 2,560 m:
    //
    //   - a player who dies at 1,500 m has met **10.9 of 15** patterns, and four of them
    //     (gauntlet, split bar, moving walls, chasm) were not unlikely — they were **unreachable**,
    //     because the tier gates at 1,440 m and the spawn horizon is 115 m ahead of it;
    //   - a player who dies at 800 m (a 42-second run) has met 9.0 of 15;
    //   - the five starter patterns are **49% of every encounter in a two-minute run**, each seen
    //     about nine times;
    //   - the LAST new thing the game ever introduces arrives at 2,560 m = **111.6 seconds**, after
    //     the speed axis (caps at 3,077 m), the gap axis and the ladder have all stopped moving.
    //
    // That is the arithmetic behind the owner's "the gameplay has been left stale": after ~30
    // seconds nothing new arrived for another 40, and the last new thing arrived at 1 min 52 s.
    //
    // The new ladder puts the WHOLE catalogue inside the first minute:
    //
    //   | tier | patterns | gate      | elapsed | what opens                       |
    //   |------|----------|-----------|---------|----------------------------------|
    //   | 1    | 0–4      | 0 m       | 0 s     | the warm-up: low, tall, bar      |
    //   | 2    | 0–8      | 150 m     | 8.6 s   | zigzag, mixed row, pickup, 2×bar |
    //   | 3    | 0–10     | 350 m     | 19.6 s  | prism ring, overdrive runway     |
    //   | 4    | 0–12     | 600 m     | 32.6 s  | gauntlet, split bar              |
    //   | 5    | 0–13     | 900 m     | 47.0 s  | moving walls                     |
    //   | 6    | 0–14     | 1,200 m   | 60.5 s  | THE CHASM                        |
    //
    // Tier one is the GILP "warm-up block" (a published 7–12 s safe zone before the game asks for
    // anything) and lands at 8.6 s. Nothing about the patterns themselves got harder — the player
    // simply stops running out of game before the game runs out of ideas.
    //
    // The gap axis is deliberately NOT pulled forward with it: `gap(forDistance:)` still lerps
    // 11 → 5 over `diffFullAt`, so at the chasm's new gate the inter-pattern gap is 9.75 u rather
    // than the old 6.20 u. New KINDS arrive early; crowding still arrives late. That split is the
    // whole safety argument — and it is why speed does the same favour: every one of these patterns
    // is met at a LOWER speed than before, which is strictly more reaction time.
    //
    // The one exception worth naming is the chasm, whose window does NOT widen at lower speed: it
    // is airborne-distance minus a fixed 8 m hole, so launch slop is `0.742 − 8/v` seconds — 0.398 s
    // at the new 1,200 m gate (23.2 m/s) against 0.478 s at the old 2,560 m gate. Still wider than
    // the bar's 0.408 s jump window, and its ballistic gem arc cues the launch. Pinned by
    // `DifficultyCurveTests`.
    static let earlyDistance: Double = 150
    static let midEarlyDiff: Double = 350.0 / diffFullAt    // 350 m — rings & overdrive
    static let midDiff: Double = 600.0 / diffFullAt         // 600 m — gauntlet & split bar

    // Collision / lifecycle (derived from the reference; named to avoid magic numbers).
    static let obstacleZHalf: Double = 0.95       // |z| < this → obstacle is at the player plane
    static let recycleObstacleZ: Double = 10      // obstacle behind camera → recycle
    static let recycleCollectibleZ: Double = 8    // gem / pickup behind camera → recycle
    static let pickupZHalf: Double = 1.1, pickupXHalf: Double = 1.1, pickupYHalf: Double = 1.3
    static let magnetGemXRate: Double = 7, magnetGemYRate: Double = 7   // y fast enough to reel in arc gems
    static let nearMissBonus: Int = 40, gemBaseScore: Int = 10

    // MARK: - THE BLAST (v2.2) — the game's first offensive verb
    //
    // Until now every input in the game was evasion: three verbs, all of them "get out of the way".
    // The owner's own idea closes that gap — *"maybe double tap sends a blast originating from the
    // player that knocks things down and clears a path"* — and it is also the answer to a second
    // problem, which is that the CHARGE meter appears 1.5 s into the first run anybody ever plays
    // and its referent (a Warden) does not exist for another 104 seconds. **Charge is now ammo.**
    // Gems fill it, a double tap spends it, and the meter means something from the first gem.
    //
    // **The input costs nothing, because the window it takes was already dead.** A tap is a jump and
    // stays a jump — tap 1 fires `jump()` on the same frame it always did. A second tap inside
    // `blastTapWindow` is the blast. That window is entirely inside the span where a second tap is
    // ALREADY swallowed: a buffered jump only survives to touchdown if it is tapped within
    // `jumpBuffer` (0.25 s) of landing, i.e. later than 0.565 s into an 0.815 s arc — so every tap in
    // [0, 0.565 s] after a launch is discarded today. Taking [0, 0.30 s] of that costs the player
    // nothing they could previously do. Pinned by `BlastTests.testTheDoubleTapWindowStealsNoLiveJump`.
    //
    // A blast with no charge falls through to today's `jump()`, so the verb can never eat an input.

    /// Seconds after a tap during which a second tap reads as a BLAST rather than a jump.
    /// 0.30 s is the iOS double-tap idiom and sits wholly inside the dead buffer span above.
    static let blastTapWindow: Double = 0.30

    /// Gems needed to fill the bank from empty. **240, down from v2.1's 520.** 520 was sized for a
    /// bank that was spent once per Warden; a bank that is spent three times a minute has to refill
    /// on a play-session timescale. At the solvability bot's measured collection rate (~637 gems by
    /// 2,400 m ≈ 6 gems/s perfect, call it 2–3/s for a human) 240 gems is ~80–120 s to fill from
    /// empty, i.e. roughly one blast every 27–40 s of good play.
    static let chargeFullGems: Double = 240
    static var chargePerGem: Double { 1.0 / chargeFullGems }

    /// What one blast costs. A third of the bank → three shots when full, and the meter reads as
    /// three pips rather than a percentage nobody can act on.
    static let blastCost: Double = 1.0 / 3.0

    /// How far ahead of the player the shockwave reaches, in metres of track. 46 m is ~1.4 s of
    /// track at the speed cap and comfortably inside both the ~65 m readable lead (the backdrop
    /// plane) and the 115 m spawn horizon, so a blast can never destroy something the player has
    /// not been given a chance to see.
    static let blastRange: Double = 46

    /// How fast the front travels, in metres per second, in the WORLD frame. Fast enough to read as
    /// a shot rather than a wave (the full 46 m in 0.31 s), slow enough that the shatters arrive as
    /// a sequence and the player sees the path open.
    static let blastFrontSpeed: Double = 150

    /// Score per obstacle destroyed, before the multiplier. Deliberately well under `nearMissBonus`
    /// (40): dodging is the skilful answer and must always pay better than spending ammo. Blasting
    /// pays NO coins and NO streak — it is safety bought with a resource, not a flourish.
    static let blastScorePerObstacle: Int = 15

    // MARK: - the coin faucet (v2.1, S-011 — see docs/agent/audits/AUDIT_011_ECONOMY.md)
    //
    // The owner: *"why am i getting so many coins. why would anyone spend 20$ on 40 coins if they
    // can just get it in on run… coins tie into everything so you cant just change one function."*
    //
    // Measured before this change (shipped Autopilot, real GameCore, 40 seeds, mult = 1):
    //
    //   | run      | gems | dist | worlds | style | bounty | total | coins/min |
    //   | 800 m    |  217 |   22 |      5 |    16 |      0 |   259 |       369 |
    //   | 1,500 m  |  511 |   42 |      5 |    27 |      0 |   586 |       478 |
    //   | 3,300 m  |  979 |   94 |     20 |    43 |    150 | 1,286 |       564 |
    //
    // Two things are wrong with that table and they are the same thing. Gems were currency at
    // **1:1**, so they were 76–87% of every payout — the game paid you for PICKING THINGS UP. And
    // `styleCoins`, the only term that measures whether you played WELL, was hard-capped at 80
    // coins a run, about 6%. The consequences compounded: nothing in the game costs more than
    // 23 minutes, the whole 83,500-coin catalogue is 2 h 22 m, and `$0.99 → 1,200 coins` is worth
    // less than one good run.
    //
    // The owner's calls (S-011): a mid-tier character should cost **30–45 minutes**, cut the FAUCET
    // rather than raise prices so the on-screen numbers stay small, and **skill should pay much
    // more**.
    //
    // The keystone is that a gem stops being a coin. Gems keep all three of their in-run jobs —
    // they draw the route, they fuel the blast charge, and they feed the score — and are worth a
    // FRACTION of a coin at payout. That is deliberately a payout change and not a spawn change:
    // gem placement is untouched, so `layoutVersion` stays at 11 and the solvability proof, the
    // `PatternOrderTests` call counts and the daily goldens are all unaffected.
    //
    // MEASURED AFTER (same harness, 24 seeds, mult = 1). These constants were tuned against this
    // table across two passes, not chosen and hoped for:
    //
    //   | run       | secs  | gems | dist | worlds | style | bounty | total | coins/min | style share |
    //   | 800 m     |  42.1 |   10 |    4 |      3 |    24 |      0 |    41 |      58.4 |         59% |
    //   | 1,500 m   |  73.8 |   21 |    8 |      3 |    47 |      0 |    79 |      64.2 |         59% |
    //   | 3,300 m   | 137.2 |   42 |   19 |     12 |    84 |     22 |   179 |      78.3 |         47% |
    //   | 12,000 m  | 411.1 |  148 |   70 |     45 |   339 |     88 |   691 |     100.9 |         49% |
    //   | 103,000 m | 3,270 | 1218 |  605 |    384 | 2,907 |    924 | 6,038 |     110.8 |         48% |
    //
    // Income is cut **6.3× / 7.4× / 7.2×** at 800 / 1,500 / 3,300 m, and STYLE — 3% of a payout
    // before — is now the largest single term at every distance. Consequences, against the owner's
    // stated targets: a mid-tier character (~2,000 coins) is **31–34 minutes**; the whole 83,500-coin
    // catalogue is **~21 hours**; and the 54-minute run that produced his screenshot pays 6,038
    // instead of 24,523. `$0.99 → 1,200 coins` is now ~21 minutes of play rather than less than one
    // run, which is what makes the IAP a shortcut instead of a rounding error.
    //
    // Note the rate still RISES with distance (58 → 111 coins/min). That is deliberate and it is the
    // reward for surviving; what it no longer does is compound, because the two terms that scale with
    // endurance alone (gems, distance) are now a third of the payout instead of nine tenths.

    /// Gems collected are divided by this to get coins. Was an implicit 1.
    static let coinsPerGemDivisor: Int = 20
    /// Metres travelled per coin. Was 35 — that made distance the second-largest term and let a
    /// 54-minute run mint a whole catalogue on endurance alone.
    static let coinsPerMetreDivisor: Double = 170
    /// Flat bonus per world crossed in a run (a checkpoint start pays only for worlds actually run).
    static let coinsPerWorld: Int = 3
    /// Coins per CLOSE / SLICK. **Uncapped as of v2.1** — the `min(…, 40)` cap was what made skill
    /// a rounding error. This is now the term that separates a good run from a long one, and it is
    /// the only term a player can raise without running further.
    static let styleCoinRate: Int = 2
    /// Coins per flow surge (every `flowPerSurge`-th near-miss with no hit between). Streaks paid
    /// score and nothing else before; paying them in currency is what makes a clean risky line
    /// worth more than the same number of scattered near-misses.
    static let flowSurgeCoins: Int = 5

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
    /// A Warden throws one hazard at a time and never launches a second before the first has
    /// arrived, so 2 is slack rather than a budget. It exists because `apply` gates every kind and
    /// an ungated one would be the only unbounded pool in the game.
    static let capHangingBar = 2

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
    /// How far a moving wall's phase is swung off centre. **Applied at every distance from v2.1**
    /// (S-011); it used to be zero until 3,200 m and ramp in only across act two.
    ///
    /// The owner, on pattern 13: *"the moving walls are stupid as you can always survive them by
    /// just sticking to one side."* He was right, and the measurement is worse than the complaint.
    /// At phase 0 each wall parks dead centre on its collision plane and sweeps only x ∈ [−0.332,
    /// +0.332] across the whole 1.9 u lethal window, so an outer lane cleared the kill half-width
    /// (1.25) by **0.618 u — 49% of margin, on both walls, every time**. Parking in lane 0 or lane 2
    /// and giving NO INPUT AT ALL survived the pattern, and kept surviving it until the act-two ramp
    /// finally closed an outer lane at **d = 6,841 m = 4 minutes 2 seconds**. Pattern 13 is the
    /// EXCLUSIVE unlock of its tier, so the only new thing the game introduced in that whole stretch
    /// was the one pattern you could beat by doing nothing.
    ///
    /// At the full swing each wall closes the centre and ONE outer lane (sin(0.75)·1.6 = 1.09 at the
    /// plane; the remaining outer lane keeps ≥ 3.0 u of clearance, so a safe answer always exists and
    /// two-of-three is never exceeded). Wall 0 swings positive and leaves lane 0; wall 1 swings
    /// negative and leaves lane 2 — so the pattern is now a genuine weave across 13 u, and the
    /// breadcrumbs it already emitted (lane 0 before wall 0, lane 2 before wall 1) were always
    /// drawing the correct route for a swing that had not been switched on yet.
    ///
    /// Act two loses this as an escalation axis and keeps its real one, the draw-table mix. A wall
    /// that closes a lane is the correct BASELINE, not an endgame reward.
    static let wallPhaseSwing: Double = 0.75

    // MARK: v1.7 — risk-priced gems (PR-0414 / D-006)

    /// Gems stay entirely safe until here — the tier that opens the gauntlet and the split bar, by
    /// which point every verb has been taught. D-006's revisit clause asks for risk to be gated
    /// behind a distance threshold rather than shipping a punishing early game.
    ///
    /// **Now DERIVED from the ladder rather than restated** (S-011). It was the literal `1_440`,
    /// which was `midDiff × diffFullAt` at the time and silently stopped being so the moment the
    /// ladder moved. Binding it to the tier keeps the documented intent true by construction instead
    /// of by coincidence: 600 m ≈ 33 s. That is also the first distance at which the greed line is
    /// worth having — the old 1,440 m sat past where most runs ended, so the one mechanic that makes
    /// coins a *choice* was invisible to the players who most needed a reason to take a risk.
    static var riskGemsFrom: Double { midDiff * diffFullAt }
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
    ///
    /// **v2.1 (S-011): 0.8 → 0.375, i.e. 2,560 m → 1,200 m.** Property 1 above was aspirational, not
    /// true. Measured across 600 seeds: at the old gate the earliest possible encounter was 2,675 m
    /// (gate + the 115 m spawn horizon) and the MEDIAN first encounter was 2,971 m / 124.8 s — so a
    /// run ending at 2,500 m met a chasm in **0.0%** of cases, and even the repo's own benchmark
    /// "good run" of 3,300 m met one in 77%. The owner asked for "a hole in the ground as well, not
    /// just a big and small wall" while the hole had been shipped for two versions: he had simply
    /// never been able to reach it. At 1,200 m the median first encounter is ~1,340 m / 66 s.
    static let chasmDiff: Double = 1_200.0 / diffFullAt   // × diffFullAt → 1,200 m

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

    /// The fraction of a jump during which the feet are clear of the deck — i.e. `jumpY(t) ≥
    /// chasmClearance`, solved rather than quoted. `y(t) = jumpV0·t − ½·gravity·t²`, so the roots are
    /// `(jumpV0 ∓ √(jumpV0² − 2·gravity·clearance)) / gravity` = **0.02936 s and 0.78603 s**.
    static var chasmAirborneEnter: Double {
        (jumpV0 - (jumpV0 * jumpV0 - 2 * gravity * chasmClearance).squareRoot()) / gravity
    }
    static var chasmAirborneExit: Double {
        (jumpV0 + (jumpV0 * jumpV0 - 2 * gravity * chasmClearance).squareRoot()) / gravity
    }

    /// Distance before the chasm's LEADING rim at which the Autopilot commits its jump.
    ///
    /// **Derived from the physics as of v2.1 (S-011), not clamped to a magic floor.** Launching `L`
    /// before the rim at speed `v` clears the hole exactly when
    ///
    ///     chasmAirborneEnter·v  ≤  L  ≤  chasmAirborneExit·v − 2·chasmHalfLength
    ///
    /// The old rule was `clamp(0.28·v, 7, 11)`. The `7` floor is what broke: at v = 17.5 m/s the
    /// valid interval is only [0.51, 5.76], so the clamp forced the launch **outside the window
    /// entirely** and the bot landed 1.3 u short of the far rim, every time, deterministically.
    /// It survived for two versions because the chasm gated at 2,560 m where v ≥ 30.3 — and 17.5 m/s
    /// is reachable there only under a chrono (×0.65), which no seed in the 200-seed soak had
    /// happened to hold over a chasm. Pulling the tier-six gate to 1,200 m made that coincidence
    /// common and seed 17604131991531453882 found it immediately.
    ///
    /// The replacement is the apex rule: launch so the jump's APEX lands on the chasm's CENTRE,
    /// which is the exact rule `Patterns` case 14 uses to PLACE the hole, so prover and author now
    /// agree by construction rather than by two sets of numbers that happened to match. It is also
    /// the midpoint of the valid interval — maximum margin on both sides at every speed — and it is
    /// still clamped, but to the true bounds instead of to constants.
    static func chasmBotLead(speed v: Double) -> Double {
        let apex = v * (jumpV0 / gravity) - chasmHalfLength
        let lo = chasmAirborneEnter * v
        let hi = chasmAirborneExit * v - 2 * chasmHalfLength
        return Swift.min(Swift.max(apex, lo), Swift.max(lo, hi))
    }

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
    ///
    ///   `wardenArmWindow` + (`wardenMaxSeconds` + `wardenDieTime` + `wardenLeaveTime`) × `boostSpeedMax`
    ///   = 60 + (17.5 + 1.0 + 0.9) × 36 = 758.4 m, against 770.
    ///
    /// **The `dying`/`leaving` terms matter and the v1.9 comment omitted them** (S-009): the cap at
    /// `WardenEncounter.step` deliberately exempts those two phases, so the craft's exit runs PAST
    /// `wardenMaxSeconds`. At the old cap of 16 s the honest worst case was 704.4 m — 44 m outside
    /// its own arena. It never bit because `deployOverdrive` needs banked Speed Ups to hold 36 m/s,
    /// but it was reachable, so the cap was lowered rather than the comment corrected.
    ///
    /// Using `boostSpeedMax` rather than `speedCap` is deliberate — pads are suppressed inside the
    /// arena, but a player can enter one already boosting, and banked Speed Ups chain every 3 s.
    /// Measured worst case across 24 seeded bot runs is 438 m, so the bound is conservative. Pinned by
    /// `WardenTests.testAnEncounterCanNeverOutrunItsArena` and `…testEveryEncounterFinishesInsideItsArena`.
    ///
    /// This is the feature's biggest tuning lever and the first thing to revisit after playtesting:
    /// 660 m of deliberately clear deck every 2,400 m is ~27% of the track past the first encounter.
    /// Shrinking it means cutting `wardenMaxSeconds`, which is what the bound above is made of —
    /// and `wardenMaxSeconds` must stay long enough to fit `wardenAnswersToKill` throws.
    ///
    /// **660 → 770 (v2.3), and this is what spent the layoutVersion bump to 12.** `Warden.suppresses`
    /// gates on `isArena(d)`, so the arena's length decides which spawn commands reach the deck:
    /// 110 m more clear deck every 2,400 m is a LAYOUT change even though the seeded spawn STREAM is
    /// byte-identical (`Spawner.fill` still draws the same patterns and consumes the same rng — only
    /// which of its output survives `apply` moves). Same mechanism as the v10 bump.
    ///
    /// It had to move: the bound above is made of `wardenMaxSeconds`, and the whole answer to *"its
    /// too short and boring"* is a longer, denser fight. 770 leaves 11.6 m of headroom over the
    /// 758.4 m worst case and stays 30 m clear of `worldLength` (800), which is the hard limit —
    /// past it one arena would straddle two worlds and `Warden.arenaWorld` would be ambiguous.
    static let wardenArenaLength: Double = 770

    // Encounter timings. The whole set is bounded by construction: a fixed answer count, a fixed
    // throw interval, and a fixed number of seconds — a Warden can never become a war of attrition.
    static let wardenArriveTime: Double = 0.9    // craft drops into view; nothing is on the deck yet
    /// How long the craft's muzzle flash takes to decay after a throw. Short: it is the beat that
    /// ties the thing now on the track to the thing that put it there, not an effect in its own right.
    static let wardenThrowFlashTime: Double = 0.35
    static let wardenDieTime: Double = 1.0
    static let wardenLeaveTime: Double = 0.9

    // MARK: rank — the same Warden gets harder the deeper you meet it (S-009)

    /// A Warden's difficulty rank: `min(wardenRankCap, world / wardenEveryWorlds)`, so worlds 3/6/9
    /// are ranks 1/2/3 and everything past world 9 fights the rank-3 case.
    ///
    /// v1.9 shipped `world` used for nothing but the RNG derivation — every Warden in the game was
    /// literally the same fight, which is half of why the owner's verdict was "takes no effort".
    /// It flattens at 3 rather than climbing forever because the rest of the game's escalation
    /// saturates there too (`actTwoFullAt` 9,600 m) and an endless ladder eventually stops being
    /// beatable, which would breach the owner's "not impossible" bar.
    static let wardenRankCap = 3
    static func wardenRank(world: Int) -> Int { min(wardenRankCap, max(1, world / wardenEveryWorlds)) }

    /// Indexed by `wardenRank - 1`. The wind-up shortens and the recovery tightens with rank, so a
    /// late Warden is read under real time pressure while the first one is still teachable.
    ///
    /// **0.70 s is a floor, not a starting point.** Below roughly that the fight gets harder for a
    /// human and not at all for the bot — perfect-information dodging is unaffected by wind-up
    /// length — so the difficulty would stop being testable. `LaggedAutopilotTests` is the two-sided
    /// gate that keeps this honest: a human-latency bot must survive, a sluggish one must not.
    /// Seconds between throws, by rank. The floor is set by TRAVEL time, not by taste: a hazard
    /// thrown from `wardenThrowLeadNear` (26 m) at the speed cap reaches the player in 0.79 s, and
    /// the interval must exceed that or two hazards demanding opposite verbs would be on the deck
    /// at once — the decree-6 failure the old three-shape system existed to avoid.
    ///
    /// **v2.3 shortens all three, and the closing speed below is what pays for it.** The interval's
    /// floor is travel time — two hazards demanding opposite verbs must never share the deck — and
    /// a hazard that closes under its own power clears the gap far sooner than one the player merely
    /// runs into. At rank 3 a throw from 52 m now lands in 0.97 s where the v2.2 equivalent took
    /// 1.56 s, so the same invariant holds at 1.10 s between throws that used to need 1.65 s.
    ///
    /// Owner, S-013: *"he only attacked me twice … its too short and boring"*. It was arithmetically
    /// true — rank 1 needed four answers and threw one every 1.95 s, so a competent player saw the
    /// fight end in four throws. Rank 1 now needs five answers and throws every 1.55 s.
    static let wardenThrowIntervalByRank: [Double] = [1.55, 1.30, 1.10]
    /// Answers needed on the OPEN CORE, by rank. Two more strip the armour first
    /// (`wardenShieldHits`), so the totals are **5 / 6 / 7** (v2.2: 4 / 5 / 6).
    ///
    /// The ladder widened rather than merely shifting: rank 1 gained one answer and rank 3 gained
    /// one on top of that, so the gap between the Warden that teaches you and the Warden that tests
    /// you is now two extra answers rather than the old flat two. Owner, S-013: *"he should be
    /// easier at first and tougher on harder levels"*.
    static let wardenCoreHitsByRank: [Int]     = [3, 4, 5]

    /// **How fast a thrown hazard travels TOWARD the player**, m/s on top of the track scroll, by
    /// rank (v2.3). Zero for everything the spawner places — only a Warden throws.
    ///
    /// This is the owner's headline note: *"its not sending walls down the lane like i asked … the
    /// walls he send come quicker like the trains from subway surfers"*. Until now a "throw" placed
    /// a wall at a fixed distance and the player ran into it at the same speed they ran into
    /// ordinary track, so nothing was ever launched at anybody and the boss's attack was
    /// indistinguishable from scenery.
    ///
    /// **The window is the difficulty knob; the lead and this number jointly set the drama.** A
    /// hazard is on screen for `lead / (runSpeed + this)` seconds, so the pair can be moved together
    /// to make something rush hard without making it unfair — which is the whole trick that lets a
    /// 52 m launch be TIGHTER than v2.2's 34 m one. Measured windows:
    ///
    ///   rank 1 (run 29.5, close 25 → 54.5 m/s):  0.95 s at full health → 0.73 s at the brink
    ///   rank 2 (run 33,   close 28 → 61 m/s):    0.85 s              → 0.66 s
    ///   rank 3 (run 33,   close 32 → 65 m/s):    0.80 s              → 0.62 s
    ///
    /// against v2.2's flat 1.15 → 0.75 s. Every one of them is tighter, and the hazard approaches at
    /// 1.85–1.97× the speed of the deck under it, which is what makes it read as thrown.
    ///
    /// **The first pass used [9, 16, 24] and `LaggedAutopilotTests` refuted it immediately**: a bot
    /// reacting a full 0.75 s late killed 48 of 48 Wardens, because a 52 m lead against +9 m/s is a
    /// 1.35 s window — far MORE generous than the thing it replaced. Moving the leads out without
    /// moving these up would have shipped a boss that looked faster and played easier.
    ///
    /// Bounded below by the fairness gate: a 0.40 s human reaction plus the ~0.30 s a lane change
    /// settles in. If that gate goes red the fix is a LONGER lead, never a smaller hitbox.
    static let wardenCloseSpeedByRank: [Double] = [25, 28, 32]
    static func wardenCloseSpeed(rank: Int) -> Double { wardenCloseSpeedByRank[rank - 1] }

    /// Extra closing speed on an aimed shot, over the wall thrown beside it (v2.3).
    ///
    /// A shot fires from the same lead as everything else, so this is the ONLY thing that makes it
    /// faster — which keeps the difference honest and in one number. At rank 3 a shot closes at
    /// 32 + 6 = 38 m/s on top of a 33 m/s run, giving a `40 / 71` = **0.56 s** window at the brink:
    /// the tightest read in the game, and deliberately so, because it belongs to the one hazard the
    /// blast can always answer instead of dodging.
    ///
    /// Bounded below by the same fairness gate as everything else — `LaggedAutopilotTests` requires
    /// an untouched run at a 0.40 s reaction.
    static let wardenShotCloseBonus: Double = 6
    /// Answers that strip the armour before the core is open. Flat across ranks: the armour is the
    /// tutorial half of every fight and must not get longer as the fight gets harder.
    static let wardenShieldHits: Int = 2

    /// **How many landed hazards a player survives inside ONE encounter before the next one kills
    /// them** — `nil` meaning "never lethal" (v2.4, D-039). This is D-037: *"yeah he should be able
    /// to kill you at some point."*
    ///
    /// **Rank 1 is `nil`, and that is the decree, not a softening of it.** D-037 is explicit that
    /// the teaching rank stays survivable and that *"any implementation that can kill a player
    /// during their first encounter has misread this decree"*. S-013 recommended 3/2/1 on the
    /// reasoning that rank 1's five-entry script *"only has room for so many misses"* — which is
    /// wrong, and playing it is what proved it: **a stationary player takes ~10 landed hazards in a
    /// single rank-1 encounter** (`docs/agent/audits/scratch/s014_play_report.md`, measured off a
    /// 26 s real-speed capture with zero inputs). The script repeats; it is the 17.5 s clock and the
    /// 1.55 s interval that set the throw count, not the script's length. A budget of 3 at rank 1
    /// would therefore kill a first-time player about six seconds into the first Warden they ever
    /// meet — the exact outcome the decree forbids.
    ///
    /// So lethality is the top of the ladder: **rank 1 never, rank 2 on the 4th landed hazard, rank
    /// 3 on the 3rd.** An idle player still dies at ranks 2 and 3 (they take ~12), which is the
    /// point; a player answering throws takes none, which is why `LaggedAutopilotTests`' 0.40 s gate
    /// stays green — and why that gate's `died == 0` assertion, trivially true since v2.2, has teeth
    /// again.
    ///
    /// Counting is per ENCOUNTER, so it resets at every arena and never accumulates across a run.
    static let wardenStrikesSurvivedByRank: [Int?] = [nil, 3, 2]
    static func wardenStrikesSurvived(rank: Int) -> Int? {
        wardenStrikesSurvivedByRank[rank - 1]
    }

    static func wardenThrowInterval(rank: Int) -> Double { wardenThrowIntervalByRank[rank - 1] }
    static func wardenCoreHits(rank: Int) -> Int { wardenCoreHitsByRank[rank - 1] }
    /// Total answers to kill one, armour and core together — what the encounter's time budget must
    /// actually fit.
    static func wardenAnswersToKill(rank: Int) -> Int { wardenShieldHits + wardenCoreHits(rank: rank) }

    // MARK: the throw — how far out a hazard is launched (v2.2)
    //
    // **Travel time IS the telegraph.** v1.9–v2.1 fired an instant shape on the player's own plane
    // after an abstract 0.70–0.80 s wind-up drawn as a red band; the S-011 render audit measured a
    // full-width opaque red band on screen for 92–95% of the exposed phase, with a 100 ms dark gap
    // between shapes and a curtain that erased 100% of the track beyond 5.3 m. The wind-up was long
    // enough (583–742 ms of usable input, and a 0.40 s-latency bot survives it) — what was drawn in
    // it was unreadable.
    //
    // A thrown hazard replaces both halves. It is a real obstacle in the vocabulary the player has
    // been reading for 2,400 m, and the time to read it is the time it takes to arrive:
    // 46 m / 29.5 m/s = **1.56 s** at the first Warden, against 0.80 s of red band. Nothing new
    // moves: the hazard is static in world space and the world scrolls it in, exactly like every
    // other obstacle, so `z = distance − d` still describes it and no velocity field is needed.
    //
    // The lead CLOSES as the Warden takes damage — 46 m at full health to 26 m at the brink. Three
    // things fall out of one lerp: the fight gets harder as it goes, the craft grows as it closes so
    // the climax is the moment it has the most presence, and the boss's health becomes SPATIAL —
    // you can see you are winning without reading a bar.
    //
    // **34/22 and not 46/26, and the difference was measured rather than guessed (S-012).** The
    // first build used 46 m, reasoning that more reading time must be better. It is not: at the
    // first Warden's 29.5 m/s that is 1.56 s, and `LaggedAutopilotTests` immediately went red in the
    // direction that matters — a bot reacting a full 0.75 s late took ZERO hits and killed 48 of 48
    // Wardens. A fight nobody can lose is the exact verdict this rebuild exists to answer.
    //
    // 34 m is 1.15 s at the first encounter closing to 0.75 s at the brink, which brackets v2.1's
    // 0.70–0.80 s wind-up at the hard end while opening ~50% more generous than it ever was. The
    // S-011 verifier had already refuted "the telegraph is too short" — measured usable windows were
    // 583–742 ms and a 0.40 s-latency bot survived them — so length was never the problem, and
    // buying more of it costs the fight its teeth. What changed is WHAT is drawn in the window: a
    // wall you have been reading for 2,400 m instead of a red band you have never seen.
    //
    // **v2.3 moves them OUT again — 52/40 — and this time it does not buy reading time.**
    //
    // The S-012 lesson above still stands and is the reason this is not a repeat of the mistake it
    // describes: a longer WINDOW makes the fight unloseable. But the window is `lead / (runSpeed +
    // closeSpeed)`, and `wardenCloseSpeedByRank` has just added a second term to the denominator.
    // Holding 34 m against a rank-3 close of +24 m/s would have cut the window to 0.60 s — below
    // the 0.40 s human floor plus the 0.19 s a lane change takes, i.e. genuinely unfair. Moving to
    // 52/40 restores it to 0.91 s → 0.70 s, which is TIGHTER than v2.2's 1.15 → 0.75 s at rank 3
    // and looser at rank 1, which is exactly the ladder the owner asked for.
    //
    // What the extra distance actually buys is the LOOK. A hazard that appears 52 m out and arrives
    // in under a second has to visibly rush, and that rush is the whole of *"like the trains from
    // subway surfers"*. At a fixed 34 m with no closing speed there was nothing to see: the wall sat
    // there and the deck slid under it.
    static let wardenThrowLeadFar: Double = 52
    static let wardenThrowLeadNear: Double = 40

    /// What a landed hazard takes out of the blast bank. One round: the same unit the player spends,
    /// so "it cost me a blast" is a thing they can count rather than a percentage they cannot.
    static var wardenHitChargeLoss: Double { blastCost }

    /// Hard ceiling on a whole encounter, from arrival to the craft clearing the sky.
    ///
    /// The phase timings alone do NOT bound it. A held shield absorbs a caught beam, and an absorbed
    /// beam is spent without landing a core hit — so a player who keeps picking up shields (pickups
    /// are deliberately left in the arena) can trade indefinitely and drag the fight past the end of
    /// its own arena, where obstacles resume and beams and walls arrive together. That is the one
    /// combination the arena exists to prevent, so the encounter is capped outright: at the cap it
    /// breaks off exactly as it would on a held shield. Pinned by
    /// `WardenTests.testAnEncounterCanNeverOutrunItsArena`.
    ///
    /// **17.5 (v2.3), and 18.1 is a wall rather than a preference.** The cap exempts `.dying` and
    /// `.leaving`, so the true distance cost is `(cap + wardenDieTime + wardenLeaveTime) ×
    /// boostSpeedMax` = 698.4 m, and `wardenArmWindow` adds 60 on top. An arena must fit inside ONE
    /// world (`worldLength` 800) or `Warden.arenaWorld` would report two worlds for one stretch of
    /// deck, so the ceiling on this constant is `(800 − 60) / 36 − 1.9` = **18.1 s**. Anything past
    /// that is not a tuning decision, it is a different world layout.
    ///
    /// That ceiling is why *"its too short and boring"* is answered with DENSITY rather than
    /// duration: 14.5 → 17.5 is only +21%, but the throw interval falling 1.95 → 1.55 (rank 1) and
    /// 1.65 → 1.10 (rank 3) roughly doubles the number of hazards that fit inside it. Rank 3 now has
    /// room for ~15 throws against the 7 answers it takes to kill, so missing several is survivable
    /// and the fight has a middle instead of ending on the fourth read.
    static let wardenMaxSeconds: Double = 17.5

    /// Throws over which the lead closes from `wardenThrowLeadFar` to `wardenThrowLeadNear` on the
    /// CLOCK, for a player who is landing no answers at all (v2.3). See `WardenEncounter.throwLead`.
    ///
    /// Eight, which is slightly more than the longest script (7 at rank 3) and comfortably inside
    /// the ~11–15 throws a fight has room for — so a player who misses everything still meets the
    /// tightest windows before the clock runs out, but only in the back half of the fight.
    static let wardenLeadClockThrows: Double = 8

    /// How far out the HUD starts warning that a Warden is ahead (v2.3).
    ///
    /// 240 m is ~8 s at the first arena's 29.5 m/s — long enough to be a build-up rather than a
    /// jump-scare, short enough that it is not background furniture for half a world. The countdown
    /// is the point: *"i have no clue when its coming"* is answered by a number that visibly runs
    /// down, not by a word that appears.
    static let wardenWarnDistance: Double = 240

    /// How many Wardens a player must have MET before the per-throw verb coaching stops.
    ///
    /// Three, and it counts encounters rather than runs: *"if its my first time playing instead of
    /// being the designer i would be super confused"*. Three encounters is one per rank, so the
    /// coaching survives long enough to introduce the aimed shot (which does not exist at rank 1)
    /// and then gets out of the way. It is a lifetime count on the profile, so a player who meets
    /// their first Warden in run 9 still gets taught.
    static let wardenCoachEncounters: Int = 3

    /// A Warden only arms in the first stretch of its arena. Without this, a checkpoint run that
    /// began 80 m from the arena's end would summon a Warden with no room to fight it.
    static let wardenArmWindow: Double = 60

    // The gun. Fire rate is the player's charge bank, spent as it burns — a timer they earned before
    // the fight started, never a win button (it cannot kill; only dodging can).
    //
    // Damage is `wardenBaseDPS + charge × wardenChargeDPS` while charge drains at
    // `wardenChargeDrain`/s, so the integral to break `wardenShieldHP` inside `wardenShieldWindow`
    // solves to a threshold at charge ≈ 0.744:
    //   charge 1.00 → shield falls at 4.71 s ✓   charge 0.85 → 5.75 s ✓
    //   charge 0.75 → 6.94 s ✓ (only just)       charge ≤ 0.70 → never
    // A player who banked nothing fires at `wardenBaseDPS` and mathematically cannot break it,
    // which is the point. Pinned by `WardenTests.testTheChargeThresholdIsWhereTheArithmeticSaysItIs`.
    //
    // **HP 80 / window 7.0, down from 100 / 9.0 (S-009).** The shield phase is the one stretch of a
    // Warden with nothing to *do* in it, and at full charge it ran 6.25 s. Cutting both terms
    // together takes that to 4.71 s while leaving the threshold in the same place it always was —
    // the point of the gate is that ignoring gems loses you the fight, not that watching a bar is
    // the fight.


    /// Charge granted per world skipped by a checkpoint / purchased start.
    ///
    /// A checkpoint run begins with an empty bank, i.e. with no ammo, which made a bought start at a
    /// Warden world the one place in the game where you arrived at a fight unarmed. This grants what
    /// a player would plausibly have banked reaching that distance. At `chargeFullGems` 240 and the
    /// bot's measured ~212 gems per world, a world is worth ~0.88 of a bank; 0.34 is deliberately
    /// well under that (a bought start is a shortcut, not a stockpile) while still handing over one
    /// full blast per world skipped.
    static let wardenCheckpointChargePerWorld: Double = 0.34

    // MARK: - the throw table (v2.2) — the fix for "the fight is a red thing covering the screen"
    //
    // v1.9–v2.1 fired three ABSTRACT shapes on the player's own plane — a lance (per-lane columns),
    // a floor (a slab on the deck) and a curtain (a wall from the sky). The verb design was right:
    // three disjoint answers, so no fixed motor pattern survives a fight. What was wrong was that
    // all three were drawn as red bands nobody had ever seen before, appearing on the strike plane
    // rather than arriving down the track. The S-011 render audit measured the consequence: a
    // full-width opaque red band on screen for 92–95% of the exposed phase, a 100 ms dark gap
    // between shapes, a curtain that erased 100% of the track beyond 5.3 m, and a floor 379 of
    // whose final 440 px appeared in a single frame.
    //
    // The owner's instruction was to stop firing beams and **rebuild the track instead** — "launches
    // walls down a lane, drops bars to slide under, blasts holes in the deck". So the three shapes
    // become three REAL obstacles, one for one, keeping the disjoint-answer property exactly:
    //
    //   LANCE   → two `tall` walls with one lane open.  answer: change lane
    //   FLOOR   → a `chasm` blown in the deck.          answer: jump  (and now with a two-sided window)
    //   CURTAIN → a `hangingBar`.                       answer: slide (and ONLY slide)
    //
    // Every one of them is vocabulary the player has been reading for 2,400 m, drawn by the meshes
    // that already exist, killed by the collision rules they already know. Nothing new has to be
    // taught, nothing new has to be drawn, and the wind-up is not a band — it is the object getting
    // closer.

    /// The four things a Warden throws. One per `WardenBand`, so the verb design is preserved by
    /// construction and the compiler enforces the mapping.
    static func wardenThrowKind(_ band: WardenBand) -> EntityKind {
        switch band {
        case .lance:   return .tall         // a PAIR of them — see `GameCore.throwHazard`
        case .floor:   return .chasm
        case .curtain: return .hangingBar
        case .shot:    return .bolt         // v2.3 — aimed at the lane you are standing in
        }
    }

    // Where the craft hangs. Far enough forward to read as a thing in the sky ahead rather than an
    // obstacle arriving, low enough to sit inside the camera's frustum above the vanishing point.
    //
    // Checked against the actual rig (`RealityRenderer`: eye at (0, 5.1, 9.6), looking at
    // (0, 1.3, −5), 62° FOV — a view axis 14.6° below horizontal, 31° half-angle). At hover the
    // craft sits 14.7° off that axis: in frame, upper third. At the top of its arrival it is 25.9°
    // off — still inside. `wardenLeaveRise` deliberately takes it PAST the edge, because leaving the
    // frame is what "climbs away" should look like. Well in front of the ~65 u backdrop plane.
    // **Re-staged in S-009.** Measured on the simulator, the craft was 288 × 91 px — 0.46% of the
    // frame — with its centre at y 827 against a horizon at y 833. It sat SIX PIXELS above the
    // vanishing point, in the lowest-contrast band of the image, while its own curtain attack filled
    // 56% of the screen and an ordinary wall was four times its size. The owner's verdict was
    // "its just a basic triangle… nothing to tell you what it is or what it does."
    //
    // Closer and lower fixes both problems at once: it leaves the vanishing-point band and grows to
    // roughly 2% of frame. It cannot come much nearer than this without crowding the strike plane
    // at z −9, where the shapes the player must actually read are drawn (decree 6).
    static let wardenStandOff: Double = 19     // units ahead of the player (rendered at z = −this)
    /// **7.4, up from 4.2 (S-012).** Measured on the simulator: at 4.2 the craft hovers INSIDE the
    /// vertical span of its own thrown hanging bar (0.95 → `hangingBarKillTop` 4.0), so the boss
    /// spent every curtain throw hidden behind its own attack — the exact opposite of the rebuild's
    /// purpose, which is that the attacker and the attack are visibly one event. Above the bar's
    /// top and above the camera's eye line (5.1), it sits clear of everything it throws.
    static let wardenHoverY: Double = 7.4
    static let wardenArriveRise: Double = 7.0  // starts this much higher and descends in
    static let wardenLeaveRise: Double = 14.0  // climbs away by this much on the way out

    /// How much FURTHER out the craft sits at the moment of arrival, closing to `wardenStandOff` as
    /// it drops in. Depth was a hard constant for the whole of v1.9 — the code comment claiming the
    /// craft "closes in as it arrives" was simply false, and only its height ever animated. An
    /// approach is the cheapest possible "something is coming".
    static let wardenArriveDepth: Double = 22
    /// And how much further out it retreats while leaving, so departure reads as distance rather
    /// than as a fade.
    static let wardenLeaveDepth: Double = 26

    /// The craft leans toward the lane the player is in, by this many units of x at full deflection.
    /// Small on purpose: it must read as attention, not as a dodge the player has to track.
    static let wardenLeanX: Double = 1.6
    /// How far the craft rocks backward as it THROWS. Rides `throwFlash`.
    ///
    /// This is the behaviour v2.2 shipped; until S-015 it was doing that job under the name
    /// `wardenHitRecoil`, whose doc comment described the *opposite* event. The two are now separate
    /// constants on separate fields, so neither can quietly become the other again.
    static let wardenThrowKick: Double = 2.2
    /// How far it recoils backward when the player ANSWERS a hazard — the visible consequence of a
    /// dodge, and the fight's only "you are winning" signal. Rides `hitFlash`.
    ///
    /// **This constant existed since v2.2 and did nothing it claimed to** (S-015): it was multiplied
    /// by the muzzle flash, so the craft kicked back when it attacked and sat perfectly still when it
    /// was hurt. Larger than `wardenThrowKick` on purpose — taking damage must read louder than
    /// dealing it, or a dodge still looks like nothing happened.
    static let wardenHitRecoil: Double = 3.4
    /// How long the flinch takes to decay. Longer than `wardenThrowFlashTime` (0.35) because a hit
    /// has to survive being read at the same moment the player is still landing their own input.
    static let wardenHitFlashTime: Double = 0.45
    /// How far a KILLED craft sinks as it detonates. A kill must not look like a withdrawal: the
    /// one that gave up climbs away (`wardenLeaveRise`), the one you beat comes down.
    static let wardenDeathSink: Double = 3.4

    /// Payout for a kill. Coins are deliberately the SMALLEST reward tier (10_WARDENS.md §4) — this
    /// feature exists to fix the coin sink, not to feed it — but a fight with no payout is not a
    /// fight worth playtesting, so phase 1 ships the bounty and the run-scoped kill count. The
    /// world-exclusive character and the Countermeasure sink are later phases.
    /// v2.1 (S-011): 150 → 40. Unchanged, this single flat award would have been ~70% of a whole
    /// good run under the new faucet — a boss bounty worth more than the run it happened inside.
    static let wardenCoinBounty = 22
    static let wardenScoreBonus = 1_200
}
