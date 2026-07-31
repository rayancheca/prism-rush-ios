import Foundation

/// A single thing a pattern asks the spawner to place, at an absolute world distance `d`.
enum SpawnCmd: Sendable, Equatable {
    case low(d: Double, lane: Int)
    case tall(d: Double, lane: Int)
    case movingTall(d: Double, phase: Double)
    case bar(d: Double)
    case splitBar(d: Double, openLane: Int)
    case gem(d: Double, lane: Int, y: Double)
    case shield(d: Double, lane: Int)
    case magnet(d: Double, lane: Int)
    case doubler(d: Double, lane: Int)
    case chrono(d: Double, lane: Int)
    case superSneakers(d: Double, lane: Int)
    case ring(d: Double, lane: Int, y: Double)
    case boostPad(d: Double, lane: Int)
    case chasm(d: Double)          // full-width gap, `d` is its CENTRE
}

/// The 15-pattern catalogue: 0–8 ported from the shipped prototype, 9 the prism-ring arc and 10 the
/// overdrive runway (both new in v1.3 — the reward beats unlock before the pain tiers), 11 the
/// gauntlet, 12 the split bar (chrono reward), 13 the moving walls, 14 THE CHASM (v1.8, PR-0450 —
/// the sole tier-six unlock and the only pattern carrying a new verb since v1.3).
///
/// **Order is load-bearing** (iron rule 4): the spawner gates by PREFIX index, so each tier must be
/// a prefix of this array and a pattern's index is its unlock rank. v1.8 amends the rule's old
/// shorthand — "moving walls stay LAST" — because tier six now sits behind them: moving walls are
/// the last entry of tier FIVE (index 13, still exclusive to it, still pinned by
/// `PatternOrderTests`), and the chasm is the last entry of the catalogue. The rule's actual
/// purpose — every tier is a prefix, nothing is unlocked out of rank — is unchanged.
///
/// Every pattern is provably solvable (see `SolvabilityBotTests`). Each function appends its spawns
/// to `out` and returns its length (used by the spawner to advance the cursor).
enum Patterns {
    static let count = 15

    // MARK: helpers (gemLine verbatim from the prototype; gemArc rewritten ballistic in v1.3)

    /// Predicted ramp speed when the player reaches absolute distance `d`. Pure — zero RNG — so
    /// speed-aware placement never perturbs the seeded spawn stream (iron rule 2).
    private static func crossingSpeed(at d: Double) -> Double {
        min(Tuning.speedCap, Tuning.speedStart + d * Tuning.speedRamp)
    }

    private static func gemLine(_ d: Double, _ lane: Int, _ n: Int, _ out: inout [SpawnCmd]) {
        for i in 0..<n { out.append(.gem(d: d + Double(i) * 1.7, lane: lane, y: 0.8)) }
    }

    /// Ballistic gem arc (v1.3): gem 0 is the jump telegraph — the player jumps when it is
    /// underfoot, at every speed. Every later gem sits at exactly the height the player's center
    /// will have when crossing it at the predicted speed, so a single well-timed jump collects all
    /// seven (`ArcCollectionTests`). Returns the arc's span so callers size their lengths from it.
    @discardableResult
    private static func gemArc(_ d: Double, _ lane: Int, _ out: inout [SpawnCmd]) -> Double {
        let v    = crossingSpeed(at: d)                                       // crossing speed
        let tAir = 2 * Tuning.jumpV0 / Tuning.gravity                         // total airtime
        let span = min(Tuning.gemArcAirFrac * v * tAir, Tuning.gemArcMaxSpan) // 10.40 … 14
        let hMax = Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity)       // 2.16077
        for i in 0..<7 {
            let frac = Double(i) / 6                       // 0…1 across the span
            let tau  = frac * span / (v * tAir)            // airtime fraction at gem i
            let y    = Tuning.gemArcBaseY + 4 * hMax * tau * (1 - tau)
            out.append(.gem(d: d + frac * span, lane: lane, y: y))
        }
        return span
    }

    /// Test hook: emit the ballistic arc exactly as the patterns do, returning its span
    /// (`ArcCollectionTests` drives scripted jumps through it at known distances).
    @discardableResult
    static func debugGemArc(_ d: Double, lane: Int, out: inout [SpawnCmd]) -> Double {
        gemArc(d, lane, &out)
    }

    private static func otherLanes(_ l: Int) -> [Int] { [0, 1, 2].filter { $0 != l } }

    /// Phase for moving wall `index` of pattern 13 at base distance `b`.
    ///
    /// **v2.1 (S-011): the swing is now full at EVERY distance.** It used to be
    /// `Spawner.intensity(forDistance: b)`-scaled, which is zero below 3,200 m and does not close an
    /// outer lane until 6,841 m — so for the first four minutes of every run both walls parked dead
    /// centre and both outer lanes were permanently safe. See `Tuning.wallPhaseSwing` for the
    /// measurement and the owner's verdict on it.
    ///
    /// Opposite sides, so the pair reads as a weave: wall 0 swings positive (closing the centre and
    /// lane 2, and its breadcrumb is already in lane 0); wall 1 swings negative (closing the centre
    /// and lane 0, breadcrumb in lane 2). sin(0.75)·1.6 = 1.09 at the collision plane, so the one
    /// open lane keeps ≥ 3.0 u of clearance and two-of-three is never exceeded.
    ///
    /// It is still a function of `index` alone and still consumes ZERO RNG, so pattern 13's pinned
    /// call count of 0 (`PatternOrderTests`) is unchanged and the seeded obstacle stream is
    /// untouched — but the emitted phase VALUE changes, so this rides the layoutVersion bump.
    ///
    /// The `b` parameter is retained deliberately: it is the seam any future distance-varying swing
    /// would reattach at, and removing it would churn three call sites and two tests to save nothing.
    static func wallPhase(at b: Double, index: Int) -> Double {
        _ = b
        return (index == 0 ? 1 : -1) * Tuning.wallPhaseSwing
    }

    // MARK: dispatch

    /// Run pattern `idx` (0-based) at `base`, returning its length. Per-pattern RNG call counts
    /// are pinned in `PatternOrderTests` — consuming one extra call silently reshuffles every
    /// seeded run (that is a `DailyChallenge.layoutVersion` bump, not an edit).
    static func run(_ idx: Int, base b: Double, rng: inout SplitMix64, out: inout [SpawnCmd]) -> Double {
        switch idx {
        case 0:  // gem line, random lane
            gemLine(b, rng.int(0, 2), 6, &out); return 14

        case 1:  // one low + gem arc over it (the arc jump IS the survival jump)
            let l = rng.int(0, 2)
            out.append(.low(d: b + 6, lane: l))
            let span = gemArc(b + 2.2, l, &out)
            return max(16, span + 6)

        case 2:  // triple low across all lanes, arc over center → forces jump
            out.append(.low(d: b + 6, lane: 0)); out.append(.low(d: b + 6, lane: 1)); out.append(.low(d: b + 6, lane: 2))
            let span = gemArc(b + 2.2, 1, &out)
            return max(18, span + 8)

        case 3:  // twin talls, gems in the free lane → forces weave
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 7, lane: o[0])); out.append(.tall(d: b + 7, lane: o[1]))
            gemLine(b + 1, free, 5, &out); return 18

        case 4:  // bar + low gem line after → forces slide
            out.append(.bar(d: b + 7)); gemLine(b + 10, rng.int(0, 2), 5, &out); return 20

        case 5:  // tall zigzag x3, alternating lanes, weaving gem trails
            let l1 = rng.int(0, 2)
            let l2 = rng.pick(otherLanes(l1))
            let l3 = rng.pick(otherLanes(l2))
            out.append(.tall(d: b + 5, lane: l1)); out.append(.tall(d: b + 14, lane: l2)); out.append(.tall(d: b + 23, lane: l3))
            gemLine(b + 8, l2 == 0 ? 1 : l2 - 1, 3, &out)
            gemLine(b + 17, l3 == 0 ? 1 : l3 - 1, 3, &out); return 30

        case 6:  // tall + low + low mixed row, arc over the free low
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.low(d: b + 6, lane: o[1])); out.append(.low(d: b + 6, lane: free))
            let span = gemArc(b + 2, free, &out)
            return max(18, span + 8)

        case 7:  // twin talls, then a pickup in the free lane (shield/magnet common, doubler rarer,
                 // Super Sneakers the rare treat). The SAME single `rng.unit()` selects all four —
                 // re-banding consumes ZERO extra RNG (PatternOrderTests count stays [.. ,7:2, ..]),
                 // so the obstacle geometry is byte-identical; only the pickup KIND shifts. Still a
                 // layoutVersion bump (placement changed) — see DailyChallenge (v1.5: 2 → 3).
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.tall(d: b + 6, lane: o[1]))
            let roll = rng.unit()
            if roll < 0.35 { out.append(.shield(d: b + 13, lane: free)) }
            else if roll < 0.70 { out.append(.magnet(d: b + 13, lane: free)) }
            else if roll < 0.88 { out.append(.doubler(d: b + 13, lane: free)) }
            else { out.append(.superSneakers(d: b + 13, lane: free)) }
            gemLine(b + 1, free, 6, &out)   // coin trail through the free lane to the pickup (zero RNG)
            return 18

        case 8:  // double bar 9 apart — a CONTINUOUS centre coin trail traces the slide path through
                 // both bars, so the formation reads as one committed route rather than gems either
                 // side of an obstacle. Bars are full-width slides: they close no LANE, so this
                 // pattern prices nothing and offers no greed line (D-006 — structure was always the
                 // intent; safety is only guaranteed where the geometry guarantees it). Zero RNG.
            out.append(.bar(d: b + 6)); out.append(.bar(d: b + 15))
            gemLine(b + 1, 1, 3, &out)      // run-up into the first bar
            gemLine(b + 10, 1, 2, &out)     // between the bars
            gemLine(b + 18, 1, 4, &out)     // out the far side
            return 24

        case 9:  // PRISM RING (v1.3): 3-gem run-up telegraph, a low keeping the jump honest, and a
                 // ring hung at the apex of a jump triggered on the last gem. v(d) is pure; the
                 // ring is non-lethal and lives in activePickups — the bot is unaffected.
            let l = rng.int(0, 2)
            gemLine(b, l, 3, &out)                          // run-up: b, b+1.7, b+3.4
            out.append(.low(d: b + 7, lane: l))
            let tApex = Tuning.jumpV0 / Tuning.gravity
            let v = crossingSpeed(at: b + 3.4)
            out.append(.ring(d: b + 3.4 + v * tApex, lane: l, y: Tuning.ringY))
            return max(18, 9.4 + v * tApex)

        case 10: // OVERDRIVE RUNWAY (v1.3): a boost pad into a gem river with ZERO obstacles.
                 // Worst-case boost travel (trigger by b+5.1, then 1.0 s × 36) is over by b+41.1
                 // < 48, and the next pattern's earliest obstacle sits past the gap — the boost can
                 // never coexist with an obstacle (invariant pinned in SolvabilityBotTests).
            let r = rng.int(0, 2)
            out.append(.boostPad(d: b + 4, lane: r))
            gemLine(b + 8, r, 10, &out)                     // main river  b+8 … b+23.3
            gemLine(b + 12, r == 2 ? 1 : r + 1, 8, &out)    // offset stream — weave temptation
            gemLine(b + 28, 1, 6, &out)                     // center finisher b+28 … b+36.5
            return 48

        case 11: // gauntlet: twin talls → bar → triple low. v1.6 fairness (owner): the bar(slide)→
                 // triple-low(jump) gap was 9u — only ~0.16s of blind reaction at the speed cap, the
                 // catalogue's one human-unfair adjacency. Widened to 27u (≥0.8s at the cap) by pushing
                 // the triple low + its arc telegraph later; the bar stays put and the arc's gem 0 stays
                 // 4u ahead of the low (the cued jump telegraph). A free-lane coin trail marks the safe
                 // lane through the talls; past `riskGemsFrom` the spawner also hangs a greed line in
                 // one of the CLOSED lanes, so this is the pattern where the two routes diverge most
                 // (D-006 — coins are structure, not a safety guarantee). All ZERO-RNG (only the lane draw) — the
                 // obstacle RNG is byte-identical; the moved/added entities ride DailyChallenge v5→6.
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.tall(d: b + 6, lane: o[1]))
            out.append(.bar(d: b + 15))
            out.append(.low(d: b + 42, lane: 0)); out.append(.low(d: b + 42, lane: 1)); out.append(.low(d: b + 42, lane: 2))
            gemLine(b + 1, free, 7, &out)                   // coin trail: stay in the free lane past the talls
            let span = gemArc(b + 38, free, &out)           // arc jump clears the triple low (telegraph 4u ahead)
            gemLine(b + 38 + span + 2, free, 4, &out)
            return 42 + span + 12

        case 12: // split bar over two lanes — steer to the open gap OR slide under. Gem line marks
                 // the gap; a chrono slow-mo sometimes waits just beyond it as the reward.
            let open = rng.int(0, 2)
            out.append(.splitBar(d: b + 7, openLane: open))
            gemLine(b + 10, open, 4, &out)
            if rng.chance(0.35) { out.append(.chrono(d: b + 17, lane: open)) }
            return 22

        case 13: // MOVING WALLS ×2 — a weave, as of v2.1. Each wall is swung to its own side (see
                 // `wallPhase`), so wall 0 leaves only lane 0 open and wall 1 leaves only lane 2:
                 // enter left, cross right, 13 u apart. The breadcrumbs below were already drawing
                 // exactly that route while the swing was switched off, which is how the pattern
                 // managed to look designed while being survivable with no input at all for the
                 // first four minutes of a run.
                 //
                 // 13 u is ~0.59 s at the tier's unlock speed and the lane lerp clears wall 1's band
                 // in 0.061 s, so the crossing is a planned move, not a scramble. The wall still
                 // oscillates visually on approach (that sweep IS the telegraph); amplitude 1.6
                 // guarantees a clear lane at every phase.
            out.append(.movingTall(d: b + 9, phase: wallPhase(at: b, index: 0))); gemLine(b + 1, 0, 3, &out)
            out.append(.movingTall(d: b + 22, phase: wallPhase(at: b, index: 1))); gemLine(b + 14, 2, 3, &out); return 32

        case 14: // THE CHASM (v1.8, PR-0450) — the sole tier-six unlock, and the first genuinely new
                 // KIND of moment since v1.3. The deck itself stops: an 8 u full-width gap that can
                 // only be crossed by being airborne along its whole span.
                 //
                 // Why this is not another low. Every jump in the catalogue is a ONE-SIDED window —
                 // clear a plane, and jumping early is free. The chasm is the first two-sided one:
                 // go too early and you land IN it. Nothing in the game punished going too soon.
                 //
                 // It is taught the way the catalogue already teaches: pattern 1's contract is "the
                 // arc jump IS the survival jump", so the run-up line pulls the player into a lane on
                 // the same 1.7 spacing, gem 0 of the ballistic arc lands as the launch cue, and the
                 // gap is centred on the APEX of exactly that jump. Centring on the apex is what
                 // makes the window symmetric: the launch may be ~±0.25 s early or late at any speed
                 // (±7.5 u at the tier's unlock speed, ±8.5 u at the cap), which is the same order as
                 // `jumpBuffer`. Three of the arc's gems hang over the void — the reward is collected
                 // mid-flight, so the greedy line and the survival line are the same line here, by
                 // design: this pattern prices TIMING, not routing.
                 //
                 // Speed-aware via the pure `crossingSpeed`, so placement consumes ZERO RNG beyond
                 // the single lane draw (`PatternOrderTests` pins 1 call).
            let l = rng.int(0, 2)
            gemLine(b, l, 3, &out)                                  // run-up: b, b+1.7, b+3.4
            let d0 = b + 5.1                                        // arc gem 0 — one more 1.7 step
            let v = crossingSpeed(at: d0)
            gemArc(d0, l, &out)
            let centre = d0 + v * (Tuning.jumpV0 / Tuning.gravity)  // apex of the cued jump
            out.append(.chasm(d: centre))
            // Land clear of the far rim, then leave the usual trailing room before the next gap.
            return max(34, centre + Tuning.chasmHalfLength + 12 - b)

        default:
            return 14
        }
    }
}
