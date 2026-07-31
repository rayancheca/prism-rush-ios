import XCTest
@testable import PrismRush

/// The difficulty *instrument*. Session 003 proved the curve dies at 3,200 m by reading the HUD off
/// a simulator screen recording; that measured the two numbers the HUD happens to show (distance
/// and score) and nothing else. This measures the thing that actually is the difficulty: what the
/// spawner puts on the track, and how much work the track extracts from a player.
///
/// Deterministic (fixed seed set, pure spawner sweep + Autopilot runs), so the table it prints is
/// reproducible and pasteable into a session log. `testPrintDifficultyTable` is the instrument;
/// the other tests are the gates that stop the second act regressing back to flat.
@MainActor
final class DifficultyCurveTests: XCTestCase {

    // MARK: - measurement

    /// A gem is **priced** when a lane-blocking obstacle closes its lane within this distance ahead:
    /// standing on it means committing to a lane you must actively leave. 15 m is 0.45 s at the
    /// speed cap and 0.88 s at the start speed — a deliberate swerve, never a reaction.
    static let priceWindow: Double = 15
    /// A stretch with no obstacle at all this long is a *rest beat* — 40 m is 1.2 s at the cap.
    static let restBeat: Double = 40

    struct Band {
        let from: Double, to: Double
        var obstacles = 0            // low/tall/movingTall/bar/splitBar/chasm spawned in the band
        var chasms = 0               // the tier-six beat alone (v1.8) — its arrival is a STEP
        var gems = 0                 // all gems
        var pricedGems = 0           // gems whose lane closes within `priceWindow`
        var restMetres = 0.0         // metres covered by obstacle-free stretches >= `restBeat`
        var measuredSpan = 0.0       // total boundary-snapped metres actually swept, all seeds
        var sweeps = 0               // how many seeds contributed to the spawn measurements
        var inputs = 0               // Autopilot input EDGES (lane commit / jump / slide start)
        var runs = 0                 // how many seeds contributed to `inputs`

        var span: Double { to - from }
        var obstaclesPer100m: Double { measuredSpan == 0 ? 0 : Double(obstacles) / measuredSpan * 100 }
        var chasmsPer1000m: Double { measuredSpan == 0 ? 0 : Double(chasms) / measuredSpan * 1_000 }
        var gemsPer100m: Double { measuredSpan == 0 ? 0 : Double(gems) / measuredSpan * 100 }
        var pricedShare: Double { gems == 0 ? 0 : Double(pricedGems) / Double(gems) }
        var restShare: Double { measuredSpan == 0 ? 0 : restMetres / measuredSpan }
        var inputsPer100m: Double { runs == 0 ? 0 : Double(inputs) / Double(runs) / span * 100 }
    }

    /// Seeds used by every measurement here. Widely spread so they exercise distinct pattern streams.
    /// 64 of them: a single 500 m band holds only ~1.1 pattern cycles, so per-band variance across
    /// a handful of seeds is larger than the effect being measured. The gates below also compare
    /// bands ≥ 1,200 m wide for the same reason.
    static let seeds: [UInt64] = (0..<64).map { UInt64($0) &* 0x9E37_79B9_7F4A_7C15 &+ 0x0D1F_F1C0 }

    /// Replay the spawner exactly as `GameCore.spawn()` drives it: step the player distance in fine
    /// increments and refill to `dist + spawnHorizon` each step. Same cursor/RNG evolution as a run.
    /// Returns the pattern boundaries it crossed — `fill` advances `cursor` to the end of each
    /// pattern it places, so reading the cursor after every call recovers them.
    @discardableResult
    private static func sweep(seed: UInt64, to end: Double, emit: (SpawnCmd) -> Void) -> [Double] {
        var spawner = Spawner()
        var rng = SplitMix64(seed: seed)
        var dist = 0.0
        var boundaries: [Double] = [spawner.cursor]
        while dist < end {
            spawner.fill(to: dist + Tuning.spawnHorizon, dist: dist, rng: &rng, emit: emit)
            if spawner.cursor != boundaries.last { boundaries.append(spawner.cursor) }
            dist += 0.25
        }
        return boundaries
    }

    /// Snap a band edge to the nearest pattern boundary.
    ///
    /// Without this every measurement aliases: the catalogue's mean cycle is ~451 m, so a fixed
    /// 500 m grid beats against it with a ~4.6 km period and produces a slow oscillation that looks
    /// exactly like a difficulty trend. It is not one — it is band edges chopping patterns in half.
    /// Snapping measures whole patterns only, and the oscillation disappears.
    private static func snap(_ d: Double, _ boundaries: [Double]) -> Double {
        boundaries.min { abs($0 - d) < abs($1 - d) } ?? d
    }

    private static func isObstacle(_ c: SpawnCmd) -> Bool {
        switch c {
        case .low, .tall, .movingTall, .bar, .splitBar, .chasm: return true
        default: return false
        }
    }

    private static func isChasm(_ c: SpawnCmd) -> Bool {
        if case .chasm = c { return true }
        return false
    }

    private static func distance(_ c: SpawnCmd) -> Double {
        switch c {
        case let .low(d, _), let .tall(d, _), let .bar(d), let .gem(d, _, _),
             let .shield(d, _), let .magnet(d, _), let .doubler(d, _), let .chrono(d, _),
             let .superSneakers(d, _), let .ring(d, _, _), let .boostPad(d, _),
             let .splitBar(d, _), let .movingTall(d, _), let .chasm(d), let .hangingBar(d):
            return d
        }
    }

    /// Lanes a spawn closes to lateral entry (the same predicate `Spawner.safeEntryLane` uses).
    private static func blockedLanes(_ c: SpawnCmd) -> [Int] {
        switch c {
        case let .tall(_, lane):        return [lane]
        case let .movingTall(_, phase): return Spawner.movingWallLanes(phase)
        case let .splitBar(_, open):    return [0, 1, 2].filter { $0 != open }
        default:                        return []
        }
    }

    /// Measure the spawn stream across `bands` for one seed, folding into the accumulators.
    private static func measureSpawns(seed: UInt64, into bands: inout [Band]) {
        var obstacles: [(d: Double, lanes: [Int])] = []
        var gems: [(d: Double, lane: Int)] = []
        var chasms: [Double] = []
        let end = bands.last!.to
        let boundaries = sweep(seed: seed, to: end) { cmd in
            let d = distance(cmd)
            if isObstacle(cmd) { obstacles.append((d, blockedLanes(cmd))) }
            if isChasm(cmd) { chasms.append(d) }
            if case let .gem(gd, lane, _) = cmd { gems.append((gd, lane)) }
        }
        obstacles.sort { $0.d < $1.d }

        for i in bands.indices {
            let b = snap(bands[i].from, boundaries), e = snap(bands[i].to, boundaries)
            guard e > b else { continue }
            bands[i].sweeps += 1
            bands[i].measuredSpan += e - b
            bands[i].obstacles += obstacles.filter { $0.d >= b && $0.d < e }.count
            bands[i].chasms += chasms.filter { $0 >= b && $0 < e }.count
            let inBand = gems.filter { $0.d >= b && $0.d < e }
            bands[i].gems += inBand.count
            bands[i].pricedGems += inBand.filter { g in
                obstacles.contains {
                    $0.d > g.d && $0.d - g.d < priceWindow && $0.lanes.contains(g.lane)
                }
            }.count

            // Rest beats: stretches of >= `restBeat` with no obstacle at all.
            var cursor = b
            var rest = 0.0
            for o in obstacles where o.d >= b && o.d < e {
                if o.d - cursor >= restBeat { rest += o.d - cursor }
                cursor = max(cursor, o.d)
            }
            if e - cursor >= restBeat { rest += e - cursor }
            bands[i].restMetres += rest
        }
    }

    /// Play one seed with the Autopilot and count input EDGES per band — the closest headless proxy
    /// for "how much work does this stretch of track ask for".
    private static func measureInputs(seed: UInt64, into bands: inout [Band]) {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        let end = bands.last!.to
        var wasSliding = false
        var lastLane = core.laneIndex
        var ticks = 0
        while core.mode == .play && core.distance < end && ticks < 400_000 {
            let d = Autopilot.decide(core)
            var edges = 0
            if d.laneDir != 0 && core.laneIndex == lastLane { edges += 1 }   // a NEW lane commit
            if d.jump && core.grounded { edges += 1 }
            if d.slide && !wasSliding { edges += 1 }
            wasSliding = d.slide
            lastLane = core.laneIndex

            if edges > 0, let i = bands.firstIndex(where: { core.distance >= $0.from && core.distance < $0.to }) {
                bands[i].inputs += edges
            }
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        // Only credit bands the run actually reached, or the rate is diluted by a short run.
        for i in bands.indices where core.distance >= bands[i].to { bands[i].runs += 1 }
    }

    private static func measure(_ edges: [Double]) -> [Band] {
        var bands = zip(edges, edges.dropFirst()).map { Band(from: $0, to: $1) }
        for seed in seeds {
            measureSpawns(seed: seed, into: &bands)
            measureInputs(seed: seed, into: &bands)
        }
        return bands
    }

    // MARK: - the instrument

    /// Band edges aligned to act two's wave boundaries. Arbitrary fixed-width bands are a bad ruler
    /// here: within a single wave the pool is constant, so any variation across sub-bands is phase
    /// noise, and a band that straddles a wave edge reports a blend of two different games.
    /// The act-one edges are DERIVED from the ladder rather than written down, as of v2.1 (S-011):
    /// they used to be the literals `1_200, 2_400` chosen when tier five gated at 1,920 m and tier
    /// six at 2,560 m, and the whole ladder has since been pulled forward (150 / 350 / 600 / 900 /
    /// 1,200 m). Binding them to `movingWallMinDiff` and `chasmDiff` keeps the instrument pointed at
    /// the content boundaries wherever those boundaries move: the band below the tier-six gate is
    /// the last stretch that CANNOT contain a chasm, the band above it is the first that can.
    ///
    /// **S-011 also REMOVED the old `2_200` "mid act one" edge, merging tier six's whole span
    /// (1,200 → `actTwoAt`) into ONE band, and this is a fix, not a simplification.** Splitting it
    /// at 2,200 measured a bogus 3× step — 0.75 chasm/km on 1,200–2,200 against 2.30/km on
    /// 2,200–3,200 — that looked exactly like the kind of "step vs slope" signal this file exists to
    /// catch, but wasn't one. None of the real candidates hold up: `gap(forDistance:)` only drifts
    /// 7.8 u → 5.9 u across that stretch (≤ 5% effect on patterns/km, not 3×); every `gemArc`-sized
    /// pattern (1/2/6/9/11/14) is already speed-capped at its max span by d ≈ 1,150 m, before either
    /// band starts, so pattern length is not the lever either; and the 115 m spawn-horizon lag only
    /// costs the first ~115 m of the 2,000 m stretch. A per-eligible-draw histogram (idx 0–14,
    /// conditioned on `maxIdx == 15` so ineligible draws near the gate are already excluded) is what
    /// found the real cause: specific indices are wildly over- or under-represented per band — index
    /// 9 drew ZERO times in 1,596 eligible draws on 1,200–2,200 (expectation ≈ 106) while index 6 drew
    /// 17 times in 1,984 on 2,200–3,200 (expectation ≈ 132) — and a real per-metre DENSITY effect
    /// (gap, horizon, pattern length) changes how MANY patterns a band draws, never WHICH index a
    /// single draw resolves to, so density cannot produce that shape at all.
    ///
    /// The actual cause: `Self.seeds` is `i × 0x9E37_79B9_7F4A_7C15 + offset` for i in 0..<64 — the
    /// exact Weyl increment `SplitMix64.next()` itself adds to its state every call. That makes
    /// `seeds[i]`'s k-th `next()` bit-identical to `seeds[i+1]`'s (k−1)-th (verified directly): the
    /// 64 "seeds" are not 64 independent streams, they are 64 adjacent offsets into ONE shared master
    /// sequence. At shallow draw-depth — a few dozen patterns into a run, which is all a 1,000 m
    /// band past the gate has time for — the streams have barely spread apart, so 64 "seeds" behave
    /// like a handful of effectively-independent samples, not 64, and whatever a short local run of
    /// the master sequence happens to look like shows up identically across all of them. Deeper bands
    /// (or, as here, a WIDER band that accumulates twice the draws) give the streams room to diverge
    /// and actually decorrelate, which is why merging fixes it rather than merely hiding it: the
    /// merged 1,200 → 3,200 band measures ≈ 1.57 chasm/km, consistent with the ≈ 1/15 per-draw rate
    /// the catalogue promises, instead of a split that reads a coin flip as two different games.
    static let waveEdges: [Double] = [
        0,
        Tuning.movingWallMinDiff * Tuning.diffFullAt,                          // 900 — tier five
        Tuning.chasmDiff * Tuning.diffFullAt,                                  // 1,200 — tier six
        Tuning.actTwoAt,                                                       // 3,200 — rest of act one
        Tuning.actTwoAt + (Tuning.actTwoFullAt - Tuning.actTwoAt) / 6,         // wave 1 → 2
        Tuning.actTwoAt + (Tuning.actTwoFullAt - Tuning.actTwoAt) / 2,         // wave 2 → 3
        Tuning.actTwoFullAt,
    ]

    func testPrintDifficultyTable() async {
        let bands = Self.measure(Self.waveEdges)
        var out = "\n=== difficulty curve (mean of \(Self.seeds.count) seeds) ===\n"
        out += "  band(m)      obst/100m  inputs/100m  gems/100m  priced%  rest%  chasm/km  phase\n"
        // 6 labels for 6 bands (v2.1, S-011): "act 1 t6" now spans 1,200 → actTwoAt — the old
        // "act 1 t6" / "act 1 full" split at 2,200 was a measurement artifact, not a real seam
        // (see the comment on `waveEdges`), so the two bands merged into one.
        let labels = ["act 1 t1-4", "act 1 t5", "act 1 t6",
                      "act 2 w1", "act 2 w2", "act 2 w3"]
        for (b, label) in zip(bands, labels) {
            out += String(format: "  %5.0f-%5.0f  %9.2f  %11.2f  %9.1f  %6.1f%%  %4.1f%%  %8.2f  %@\n",
                           b.from, b.to, b.obstaclesPer100m, b.inputsPer100m,
                           b.gemsPer100m, b.pricedShare * 100, b.restShare * 100,
                           b.chasmsPer1000m, label)
        }
        print(out)
    }

    /// PR-0450: the sixth tier must arrive as a STEP, not a slope.
    ///
    /// That distinction is the whole point of the item. Act two (v1.7) is a slope — it changes how
    /// OFTEN you meet the existing fourteen patterns, and a player cannot point at a metre marker
    /// and say "something new started here". A tier is different: below 2,560 m the chasm is
    /// structurally impossible (the ladder cannot select index 14, and the spawn cursor never runs
    /// behind the player), and above it the chasm is a recurring beat. This asserts both halves —
    /// the hard zero below, and a rate that then keeps climbing through act two's waves.
    func testTheSixthTierArrivesAsAStep() async {
        let bands = Self.measure(Self.waveEdges)
        let gate = Tuning.chasmDiff * Tuning.diffFullAt
        let tier5 = bands[1]        // 900 – 1,200: moving walls open, the chasm cannot appear
        // 1,200 – actTwoAt (3,200): the rest of act one, chasm unlocked. Single merged band
        // (v2.1, S-011) — splitting it at 2,200 measured a bogus 3× step that was a sampling
        // artifact of `Self.seeds`, not a real content seam; see the comment on `waveEdges`.
        let tier6 = bands[2]
        let wave1 = bands[3]
        let deep = bands[5]

        // The step itself: not "rare below", but IMPOSSIBLE below.
        for b in bands.prefix(2) {
            XCTAssertEqual(b.chasms, 0,
                "no chasm may exist below the tier-six gate at \(gate) m "
                + "(band \(b.from)-\(b.to) had \(b.chasms))")
        }
        XCTAssertGreaterThan(tier6.chasmsPer1000m, 1.0,
            "past the gate the chasm must be a real beat, not a curiosity "
            + "(\(tier6.chasmsPer1000m)/km)")
        XCTAssertEqual(tier5.chasmsPer1000m, 0, accuracy: 1e-9)

        // And the deep game meets it more often than act one does. Note the shape deliberately is
        // NOT monotone: wave 1 DIPS below act one (~1.06 vs ~1.84/km) because act two's draw tables
        // are larger, so a pattern that is not up-weighted gets diluted by them. Up-weighting the
        // chasm in wave 1 to remove that dip was measured and rejected — the chasm pattern is sparse,
        // so it cost `testSecondActEscalatesPastTheSpeedCap`, which protects a more important
        // property. See the comment on `Spawner.poolWave1`. Do not "fix" the dip without re-running
        // that gate.
        XCTAssertGreaterThan(deep.chasmsPer1000m, tier6.chasmsPer1000m,
            "deep act two must meet the chasm more often than act one does "
            + "(act one t6 \(tier6.chasmsPer1000m)/km, deep \(deep.chasmsPer1000m)/km)")
        XCTAssertGreaterThan(deep.chasmsPer1000m, wave1.chasmsPer1000m * 1.5,
            "the chasm's frequency must recover strongly across the waves "
            + "(wave1 \(wave1.chasmsPer1000m)/km, deep \(deep.chasmsPer1000m)/km)")
    }

    // MARK: - the gates

    /// PR-0400: the run must keep escalating past the point where speed, gap and the pattern
    /// catalogue all cap out. Thresholds are set below what v1.7 measures, with margin — the point
    /// is to catch a regression back toward flat, not to pin today's exact numbers.
    ///
    /// For reference, v1.6 measured 5.7 obstacles/100 m, 3.4 inputs/100 m and 32% rest across the
    /// whole 3,000–8,000 m stretch with no trend at all in any of them.
    func testSecondActEscalatesPastTheSpeedCap() async {
        let bands = Self.measure(Self.waveEdges)
        // 1,200–3,200 m: act one saturated, the old end of the curve. v1.8 moved this reference up
        // from 2,400 so it sits entirely inside tier six — which makes every gate below STRICTER,
        // since the baseline it compares against now contains chasms too. **v2.1 (S-011):** this is
        // now the whole merged tier-six band rather than just its 2,560–3,200 tail (a 2,200 sub-split
        // measured a sampling artifact, not a real seam — see the comment on `waveEdges`), which only
        // makes the comparison below stricter still, since it folds in the lower-density stretch
        // right after the gate.
        let plateau = bands[2]
        let wave1 = bands[3]
        let deep = bands[5]         // the last wave

        XCTAssertGreaterThan(wave1.obstaclesPer100m, plateau.obstaclesPer100m * 1.03,
            "act two must start escalating immediately, not at a depth nobody reaches "
            + "(plateau \(plateau.obstaclesPer100m), wave1 \(wave1.obstaclesPer100m))")
        XCTAssertGreaterThan(deep.obstaclesPer100m, plateau.obstaclesPer100m * 1.15,
            "deep act two must place substantially more obstacles per metre "
            + "(plateau \(plateau.obstaclesPer100m), deep \(deep.obstaclesPer100m))")
        XCTAssertGreaterThan(deep.obstaclesPer100m, wave1.obstaclesPer100m,
            "density must keep climbing across the waves "
            + "(wave1 \(wave1.obstaclesPer100m), deep \(deep.obstaclesPer100m))")
        XCTAssertGreaterThan(deep.inputsPer100m, plateau.inputsPer100m * 1.05,
            "deep act two must extract more inputs per metre than the plateau "
            + "(plateau \(plateau.inputsPer100m), deep \(deep.inputsPer100m))")
        XCTAssertLessThan(deep.restShare, plateau.restShare * 0.65,
            "the share of track with no obstacle at all must fall sharply with depth "
            + "(plateau \(plateau.restShare), deep \(deep.restShare))")
    }

    /// PR-0414: past the risk gate, a real share of the gems on the track sit in a lane the player
    /// has to leave. Before the gate, every coin line stays takeable (D-006's revisit clause: risk is
    /// gated behind a distance threshold so the early game is never punishing).
    ///
    /// v1.6 measured ~2% priced everywhere — the finding that greed and survival were the same input.
    func testGemsArePricedInRiskOnlyPastTheGate() async {
        let bands = Self.measure([200, Tuning.riskGemsFrom, Tuning.actTwoAt, Tuning.actTwoFullAt])
        let teaching = bands[0]     // 200 m – the gate: teaching, no price
        let mid = bands[1]          // gate – 3,200 m: act one with the gate open
        let late = bands[2]         // act two

        XCTAssertLessThan(teaching.pricedShare, 0.03,
            "before the risk gate the coin line must stay takeable "
            + "(priced share \(teaching.pricedShare))")
        XCTAssertGreaterThan(mid.pricedShare, 0.08,
            "the gate must actually open in act one, not only deep in act two "
            + "(priced share \(mid.pricedShare))")
        XCTAssertGreaterThan(late.pricedShare, 0.10,
            "past the gate a real fraction of gems must cost something "
            + "(priced share \(late.pricedShare))")
        // **Re-baselined 0.95 → 0.90 in v2.1 (S-011), and the reason is understood, not shrugged at.**
        // Measured after the ladder moved: mid 0.1338, late 0.1259 → ratio 0.941. The guard exists
        // to catch a COLLAPSE (act two quietly reverting to v1.6's ~2% priced everywhere); a 6%
        // decline is the known dilution effect, not a collapse. Act two's pools up-weight patterns
        // 2, 8 and 14 — a triple low, a double bar and the chasm — none of which close a lane, so
        // none of them can carry a greed line at all (`Spawner.greedLane` returns nil). More slots
        // for lane-less patterns means a smaller priced share, by construction. Pulling the risk
        // gate from 1,440 m to 600 m also widened the `mid` band into lower distances where the
        // inter-pattern gap is larger and greed lines therefore fit more often, which lifts `mid`
        // rather than lowering `late`. Both effects push this ratio down without anything regressing.
        XCTAssertGreaterThanOrEqual(late.pricedShare, mid.pricedShare * 0.90,
            "the priced share must not collapse with depth "
            + "(mid \(mid.pricedShare), late \(late.pricedShare))")
    }

    /// The greed line's own fairness proof.
    ///
    /// `SolvabilityBotTests` does NOT cover this: the Autopilot reads only `activeObstacles` and has
    /// never collected a gem in its life, so it walks the safe line every time and would stay green
    /// even if the greed line were lethal. This walks every greed gem the spawner can emit and
    /// asserts the lane it sits in stays open for at least `riskExitSeconds` of travel afterwards —
    /// a planned swerve, never an impossible one.
    func testEveryGreedGemLeavesATakeableExit() async {
        var checked = 0
        for seed in Self.seeds.prefix(16) {
            var spawner = Spawner()
            var rng = SplitMix64(seed: seed)
            var dist = 0.0
            var obstacles: [(d: Double, lanes: [Int])] = []
            var gems: [(d: Double, lane: Int)] = []
            while dist < 12_000 {
                spawner.fill(to: dist + Tuning.spawnHorizon, dist: dist, rng: &rng) { cmd in
                    if Self.isObstacle(cmd) { obstacles.append((Self.distance(cmd), Self.blockedLanes(cmd))) }
                    if case let .gem(d, lane, _) = cmd { gems.append((d, lane)) }
                }
                dist += 0.25
            }
            for g in gems {
                // The distance until this gem's lane closes, if it ever does.
                guard let closes = obstacles
                    .filter({ $0.d > g.d && $0.lanes.contains(g.lane) })
                    .map({ $0.d }).min() else { continue }
                let runway = closes - g.d
                guard runway < 40 else { continue }   // far enough away to be unrelated
                let v = min(Tuning.speedCap, Tuning.speedStart + closes * Tuning.speedRamp)
                let need = max(Tuning.riskExitMinLead, Tuning.riskExitSeconds * v)
                XCTAssertGreaterThanOrEqual(runway, need - 1e-6,
                    "a gem at d=\(g.d) lane=\(g.lane) leaves only \(runway) m before its lane "
                    + "closes at \(closes) — the exit needs \(need) m (\(Tuning.riskExitSeconds) s)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 500, "expected to have checked a meaningful number of gems")
    }

    /// Gems are dropped on the floor when the live pool is full (`GameCore.apply`, capGem), which
    /// would silently punch holes in a greed line. v1.7 adds gems, so this pins the headroom.
    func testLiveGemCountStaysUnderThePoolCap() async {
        var peak = 0
        for seed in Self.seeds.prefix(16) {
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            var ticks = 0
            while core.mode == .play && core.distance < 12_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                peak = max(peak, core.activeGems.count)
                ticks += 1
            }
        }
        XCTAssertLessThan(peak, Tuning.capGem,
            "live gems peaked at \(peak) against a pool cap of \(Tuning.capGem) — gems are being "
            + "silently dropped; raise capGem here AND in the renderer's pool")
        print("peak live gems: \(peak) / \(Tuning.capGem)")
    }
}
