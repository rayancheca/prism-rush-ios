import Foundation

/// Fills the track ahead of the player with patterns, gating difficulty by distance and
/// shrinking the inter-pattern gap as the run heats up. Renderer-agnostic and deterministic.
struct Spawner {
    /// Absolute distance up to which patterns have been placed.
    var cursor: Double = 60

    /// The last two placed pattern indices (anti-repeat reroll); -1 = none yet. Lives in the
    /// spawner so they reset with it — deterministic for a given seed.
    var lastIdx: Int = -1
    var prevIdx: Int = -1

    /// Reused scratch buffer so `fill` allocates nothing per tick once warmed.
    private var scratch: [SpawnCmd] = []

    /// The previous pattern's spawns. The greed line may run back past the gap into the tail of the
    /// pattern before it (`riskLineReach`), and that tail is NOT always empty: pattern 5's last tall
    /// sits only 7 u from its end. Without this the line would hang gems inside that wall. Reset
    /// with the spawner, so it stays deterministic for a given seed.
    private var previous: [SpawnCmd] = []

    // MARK: - the two difficulty axes

    /// Act two's progress, 0 at `actTwoAt` rising to 1 at `actTwoFullAt`. This is the axis that
    /// keeps moving after speed, gap and the pattern catalogue have all saturated (PR-0400).
    /// Pure f(distance) — consumes ZERO RNG.
    static func intensity(forDistance dist: Double) -> Double {
        guard dist > Tuning.actTwoAt else { return 0 }
        return min(1, (dist - Tuning.actTwoAt) / (Tuning.actTwoFullAt - Tuning.actTwoAt))
    }

    /// Inter-pattern gap. Act one lerps 11 → 5 over `diffFullAt`; act two continues 5 → 4 over
    /// `actTwoFullAt`. Continuous at the seam (both read 5 at `actTwoAt`). Tested for monotonicity.
    static func gap(forDistance dist: Double) -> Double {
        let diff = min(1, dist / Tuning.diffFullAt)
        let actOne = lerp(Tuning.gapMax, Tuning.gapMin, diff)
        guard dist > Tuning.actTwoAt else { return actOne }
        return lerp(Tuning.gapMin, Tuning.gapFloorActTwo, intensity(forDistance: dist))
    }

    /// Highest selectable pattern index + 1 — the v1.3 five-tier prefix ladder (iron rule 4:
    /// every tier is a prefix of the catalogue; moving walls stay LAST).
    static func maxIndex(forDistance dist: Double) -> Int {
        let diff = min(1, dist / Tuning.diffFullAt)
        if dist < Tuning.earlyDistance { return 5 }        // 0–260 m: teach (patterns 0–4)
        if diff < Tuning.midEarlyDiff { return 9 }         // 260–576 m: + zigzag/mixed/pickup/double bar
        if diff < Tuning.midDiff { return 11 }             // 576–1440 m: + rings & overdrive runways
        if diff < Tuning.movingWallMinDiff { return 13 }   // 1440–1920 m: + gauntlet & split bars
        return Patterns.count                              // 1920 m+: full catalogue incl. moving walls
    }

    // Act two shifts the *mix*, never the catalogue. Every pattern stays reachable at every depth —
    // the breather beats (0, the plain gem line; 10, the obstacle-free overdrive runway) simply get
    // rarer as the demanding entries are drawn more often, so the reward beats never disappear and
    // no feature dies. Each wave APPENDS to the one before it, so availability stays monotone by
    // construction and iron rule 4's prefix gating is untouched — this selects *within* the prefix
    // the ladder has already unlocked, and act two only ever runs at the full catalogue (3,200 m is
    // well past the 1,920 m tier-5 gate).
    //
    // 5 = the zigzag (three talls, the catalogue's densest lane test) and 11 = the gauntlet
    // (talls → bar → triple low, the only pattern demanding all three verbs) carry the escalation;
    // 2/3/6/8/12 are the medium rows.
    //
    // Computed against the catalogue's lengths at the speed cap (and against the anti-repeat reroll,
    // which damps heavy weights by ~2% because a frequent pattern is more often one of the last
    // two), the three waves put obstacle density at +14% / +21% / +28% over act one's saturated
    // plateau of 5.99 per 100 m, and cut the share of track belonging to a zero-obstacle pattern
    // from 13.7% to 9.9% / 7.8% / 6.1%.
    private static let poolWave1: [Int] = Array(0..<Patterns.count) + [5, 11, 2, 6, 3, 8]
    private static let poolWave2: [Int] = poolWave1 + [5, 11, 2, 6, 12, 8]
    private static let poolWave3: [Int] = poolWave2 + [5, 11, 5, 11, 2, 3, 6, 8]

    /// The draw table at `dist`, or `nil` in act one — where the spawner draws uniformly from
    /// `0..<maxIndex` exactly as v1.6 did. Static tables, so selection allocates nothing.
    ///
    /// The waves are deliberately FRONT-LOADED (1/6, 1/2 of intensity, not 1/3 and 2/3): a good run
    /// is about two minutes ≈ 3,300 m, so an escalation whose first real step lands at 5,300 m is an
    /// escalation almost nobody meets. Boundaries here are 3,200 / 4,267 / 6,400 m, while the
    /// continuous axes (gap, wall phase) keep moving all the way to `actTwoFullAt`.
    static func pool(forDistance dist: Double) -> [Int]? {
        let i = intensity(forDistance: dist)
        guard i > 0 else { return nil }
        if i <= 1.0 / 6 { return poolWave1 }
        if i <= 1.0 / 2 { return poolWave2 }
        return poolWave3
    }

    // MARK: - fill

    /// Place patterns until the cursor reaches `horizon`. `emit` receives each spawn command.
    mutating func fill(to horizon: Double, dist: Double, rng: inout SplitMix64, emit: (SpawnCmd) -> Void) {
        if scratch.capacity < 64 { scratch.reserveCapacity(64) }
        while cursor < horizon {
            let maxIdx = Spawner.maxIndex(forDistance: dist)
            // Act one draws the index directly; act two draws a SLOT in a weighted table that
            // resolves to an index. Both consume exactly one `rng.int` — and in act one the table
            // is absent and the draw is byte-identical to v1.6, so the early game is untouched.
            let table = Spawner.pool(forDistance: dist)
            let slots = table?.count ?? maxIdx
            func resolve(_ slot: Int) -> Int { table.map { $0[slot] } ?? slot }
            var idx = resolve(rng.int(0, slots - 1))
            // Anti-repeat (v1.6): ONE bounded reroll when we'd repeat EITHER of the last two patterns
            // — keeps runs varied (owner: "don't get too repetitive") without a loop, so repeats stay
            // possible, just rarer. Same single-reroll shape as v1.3 (which only checked the last one);
            // the broader condition reshuffles the seeded stream → layoutVersion 6 → 7.
            if idx == lastIdx || idx == prevIdx { idx = resolve(rng.int(0, slots - 1)) }
            prevIdx = lastIdx; lastIdx = idx
            scratch.removeAll(keepingCapacity: true)
            let len = Patterns.run(idx, base: cursor, rng: &rng, out: &scratch)
            let gap = Spawner.gap(forDistance: dist)
            // Structured coin trail (v1.6, amended by D-006): a short gem breadcrumb leads through
            // the empty gap into THIS pattern's safe entry lane. It is the run's readable baseline
            // route — deliberate formations rather than scattered gems, which was the owner's actual
            // intent. It is no longer the *only* route: see the greed line below. Pure of the
            // pattern's spawns + fixed spacing → consumes ZERO RNG (the seeded stream +
            // PatternOrderTests are untouched; the added gems ride the layoutVersion bump).
            let lane = Spawner.safeEntryLane(scratch, base: cursor)
            var gd = cursor - gap + 1.0
            while gd < cursor - 0.5 {
                emit(.gem(d: gd, lane: lane, y: 0.8))
                gd += 1.7
            }
            // Risk-priced gems (v1.7, PR-0414 / D-006). Past `riskGemsFrom` the safe breadcrumb
            // stops being the only coin line: a second, richer cluster sits in a lane this pattern
            // CLOSES, ending one planned swerve short of the wall. Greed and survival stop being the
            // same input — there is finally a route to choose. Pure of the pattern's own spawns →
            // consumes ZERO RNG.
            if dist >= Tuning.riskGemsFrom {
                Spawner.emitGreedLine(scratch, behind: previous, safeLane: lane,
                                      from: cursor - gap + 1.0 - Tuning.riskLineReach, emit: emit)
            }
            for cmd in scratch { emit(cmd) }
            previous.removeAll(keepingCapacity: true)
            previous.append(contentsOf: scratch)
            cursor += len + gap
        }
    }

    // MARK: - lane analysis

    /// A lane that's laterally SAFE to enter `base` at (no tall / moving wall / split-bar cover in the
    /// entry zone — lows/bars are jumped or slid, so they don't block a lane sideways). Prefers
    /// the centre; falls back to centre if (rarely) all three read blocked. Pure → deterministic.
    ///
    /// The zone is 12 u, not v1.6's 8.5. Pattern 13 puts its first moving wall at `base + 9`, just
    /// outside the old window, so the "safe" breadcrumb was routed into the centre lane that wall
    /// crosses and the player had 9 u (0.27 s at the cap) to discover it. Nothing else in the
    /// catalogue has a lane-blocking obstacle between 8.5 and 12, so this fixes exactly that case.
    static func safeEntryLane(_ spawns: [SpawnCmd], base: Double) -> Int {
        var blocked = [false, false, false]
        let zone = base + 12
        for cmd in spawns {
            switch cmd {
            case let .tall(d, lane) where d <= zone:
                blocked[lane] = true
            case let .movingTall(d, phase) where d <= zone:
                for l in movingWallLanes(phase) { blocked[l] = true }
            case let .splitBar(d, openLane) where d <= zone:
                for l in 0..<3 where l != openLane { blocked[l] = true }
            default:
                break
            }
        }
        for lane in [1, 0, 2] where !blocked[lane] { return lane }
        return 1
    }

    /// Lanes a moving wall closes. It sits at sin(phase)·amplitude on its collision plane and sweeps
    /// across the ~1.9-unit kill depth around it, so the blocked band is widened by 0.7 — the same
    /// predicate `Autopilot` uses. At phase 0 this is exactly the centre lane (the v1.6 behaviour);
    /// act two's swung phases close an outer lane instead.
    static func movingWallLanes(_ phase: Double) -> [Int] {
        let ax = sin(phase) * Tuning.movingWallAmplitude
        return (0..<3).filter { abs(Tuning.laneX[$0] - ax) < Tuning.laneHitHalfWidth + 0.7 }
    }

    /// The lane a *greedy* player is offered: among the lanes this pattern eventually closes, the one
    /// that stays open LONGEST — so the cluster sits deep in the pattern and the exit is a single
    /// planned swerve rather than a scramble. `nil` when the pattern closes no lane at all (the
    /// breather beats, and everything cleared by jumping or sliding) — those keep one honest line.
    static func greedLane(_ spawns: [SpawnCmd], safeLane: Int) -> (lane: Int, closesAt: Double)? {
        var closesAt = [Double.infinity, .infinity, .infinity]
        for cmd in spawns {
            switch cmd {
            case let .tall(d, lane):
                closesAt[lane] = min(closesAt[lane], d)
            case let .movingTall(d, phase):
                for l in movingWallLanes(phase) { closesAt[l] = min(closesAt[l], d) }
            case let .splitBar(d, openLane):
                for l in 0..<3 where l != openLane { closesAt[l] = min(closesAt[l], d) }
            default:
                break
            }
        }
        var best: (lane: Int, closesAt: Double)?
        for l in 0..<3 where l != safeLane && closesAt[l].isFinite {
            if best == nil || closesAt[l] > best!.closesAt { best = (lane: l, closesAt: closesAt[l]) }
        }
        return best
    }

    /// Emit the greed line for `spawns`, if one is worth placing.
    ///
    /// The line is laid down BACKWARDS from `riskExitSeconds` of travel before its lane closes, so
    /// it always points at the wall it stops short of — the shape reads, at a glance, as "these run
    /// into that; leave in time". It may run back to `start` (`riskLineReach` before the gap the
    /// safe breadcrumb also starts in, so the two routes come into view together and visibly
    /// diverge), and it breaks around obstacles and around the pattern's own gems rather than
    /// rendering one inside another.
    static func emitGreedLine(_ spawns: [SpawnCmd], behind previous: [SpawnCmd], safeLane: Int,
                              from start: Double, emit: (SpawnCmd) -> Void) {
        guard let greed = greedLane(spawns, safeLane: safeLane) else { return }
        // Speed the player will actually be carrying when the lane shuts — pure f(d), zero RNG.
        let v = min(Tuning.speedCap, Tuning.speedStart + greed.closesAt * Tuning.speedRamp)
        let last = greed.closesAt - max(Tuning.riskExitMinLead, Tuning.riskExitSeconds * v)

        // The line reaches back into the PREVIOUS pattern's tail, and that tail is not always empty:
        // pattern 5's last tall sits only 7 u from its end. Raise the line's start above anything
        // back there — never lower `last`, because that is the exit window and it is not negotiable.
        // If the two squeeze the line below `riskGemsMin` it simply isn't placed.
        let floor = previous
            .filter { isObstacle($0) }
            .map { spawnDistance($0) + Tuning.riskGemClearance }
            .max() ?? -.infinity
        let from = Swift.max(start, floor)

        var ds: [Double] = []
        for i in 0..<Tuning.riskGemsMax {
            let d = last - Double(i) * Tuning.riskGemSpacing
            guard d >= from else { break }
            let occupied = (spawns + previous).contains { cmd in
                guard abs(spawnDistance(cmd) - d) < Tuning.riskGemClearance else { return false }
                if isObstacle(cmd) { return true }
                if case let .gem(_, lane, _) = cmd { return lane == greed.lane }
                return false
            }
            if !occupied { ds.append(d) }
        }
        guard ds.count >= Tuning.riskGemsMin else { return }
        for d in ds.reversed() { emit(.gem(d: d, lane: greed.lane, y: 0.8)) }
    }


    private static func isObstacle(_ cmd: SpawnCmd) -> Bool {
        switch cmd {
        case .low, .tall, .movingTall, .bar, .splitBar: return true
        default: return false
        }
    }

    private static func spawnDistance(_ cmd: SpawnCmd) -> Double {
        switch cmd {
        case let .low(d, _), let .tall(d, _), let .bar(d), let .gem(d, _, _),
             let .shield(d, _), let .magnet(d, _), let .doubler(d, _), let .chrono(d, _),
             let .superSneakers(d, _), let .ring(d, _, _), let .boostPad(d, _),
             let .splitBar(d, _), let .movingTall(d, _):
            return d
        }
    }
}
