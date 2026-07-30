import XCTest
@testable import PrismRush

/// THE STUMBLE (v2.0) — the game's first non-lethal contact.
///
/// `CollisionTests` pins the geometry; this pins the CONSEQUENCES, which is where the design
/// actually lives. Three claims are load-bearing and each has a test here:
///
///   1. A shallow contact costs the multiplier and the tempo, and nothing else.
///   2. It is not a second life. A second contact inside the recovery window ends the run.
///   3. The wall you crashed into must not turn round and pay you a near-miss bonus.
///
/// The fourth claim — that the 200-seed solvability proof is still a proof — lives in
/// `SolvabilityBotTests`, because a green bot that never met the hazard proves nothing.
@MainActor
final class StumbleTests: XCTestCase {

    /// Start a clean run with the spawner parked, ready for `debugSpawn` scenarios.
    private func cleanCore(seed: UInt64 = 7) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed)
        core.debugClearTrack()
        return core
    }

    private func tickUntil(_ core: GameCore, max maxTicks: Int = 2_000, _ cond: () -> Bool) -> Bool {
        var n = 0
        while !cond() && n < maxTicks { core.tick(Tuning.tickDt); n += 1 }
        return cond()
    }

    /// Where `px` will be after the next tick. `stepPlayer` runs before `stepObstacles`, so THIS is
    /// the value a contact resolves against — not the one readable now. Deriving it from the shipped
    /// constants rather than hardcoding an offset keeps these fixtures honest if the ease is retuned.
    private func pxNextTick(_ core: GameCore) -> Double {
        let target = Tuning.laneX[core.laneIndex]
        return core.px + (target - core.px) * min(1, Tuning.tickDt * Tuning.laneLerpRate)
    }

    /// Stage a contact with a wall in `wallLane` at a chosen lateral depth.
    ///
    /// A half-hit is a mid-swipe event, so the player is driven ACROSS the wall's lane and the wall
    /// is dropped in at the exact tick the ease puts them at the wanted `dx`. Returns false rather
    /// than asserting, so a caller can say why the scenario mattered.
    @discardableResult
    private func stageContact(_ core: GameCore, wallLane: Int, driftTo: Int,
                              dx wanted: ClosedRange<Double>, max maxTicks: Int = 600) -> Bool {
        core.changeLane(driftTo - core.laneIndex)
        var n = 0
        while !wanted.contains(abs(pxNextTick(core) - Tuning.laneX[wallLane])), n < maxTicks {
            core.tick(Tuning.tickDt); n += 1
        }
        guard wanted.contains(abs(pxNextTick(core) - Tuning.laneX[wallLane])) else { return false }
        // Half a metre ahead: one tick of travel (~0.14 m at launch speed) leaves it well inside
        // `obstacleZHalf`, so the contact resolves on exactly the tick we just aimed at.
        core.debugSpawn(.tall(d: core.distance + 0.5, lane: wallLane))
        core.tick(Tuning.tickDt)
        return true
    }

    /// The lateral band a stumble lives in, read off the constants that define it.
    private var grazeBand: ClosedRange<Double> {
        (Tuning.laneHitHalfWidth - Tuning.stumbleGrazeDX)...(Tuning.laneHitHalfWidth - 0.01)
    }
    /// …and a depth that is unambiguously a crash.
    private var crashBand: ClosedRange<Double> {
        0...(Tuning.laneHitHalfWidth - Tuning.stumbleGrazeDX - 0.05)
    }

    // MARK: - 1. what a stumble costs

    func testAHalfHitStaggersAndResetsTheMultiplier() async {
        let core = cleanCore()

        // Bank a multiplier first — otherwise "it reset" is indistinguishable from "it never rose".
        for i in 0..<6 { core.debugSpawn(.gem(d: core.distance + 4 + Double(i) * 3, lane: 1, y: 0.8)) }
        XCTAssertTrue(tickUntil(core) { core.mult > 1 }, "the scenario needs a live multiplier")
        let multBefore = core.mult
        let speedBefore = core.speed

        var stumbles: [Bool] = []   // fromWarden flags, in order
        core.onFX = { if case let .stumbled(_, w) = $0 { stumbles.append(w) } }

        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 2, dx: grazeBand),
                      "fixture: the player must cross lane 1 at graze depth")

        XCTAssertEqual(core.mode, .play, "a half-hit must not end the run")
        XCTAssertEqual(stumbles, [false], "exactly one stumble, and not attributed to a Warden")
        XCTAssertEqual(core.stumbles, 1)
        XCTAssertGreaterThan(multBefore, 1)
        XCTAssertEqual(core.mult, 1, "the multiplier reset IS the punishment")
        XCTAssertEqual(core.streak, 0)
        XCTAssertLessThan(core.speed, speedBefore * 0.7, "and it staggers")
        XCTAssertGreaterThan(core.stumbleT, 0, "…leaving the player vulnerable")
    }

    /// The other side of the same boundary: go in deep and it is still a crash.
    func testARealCrashIsStillFatal() async {
        let core = cleanCore()
        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 2, dx: crashBand))
        XCTAssertEqual(core.mode, .over, "half the body inside a wall is not a half-hit")
        XCTAssertEqual(core.stumbles, 0)
    }

    // MARK: - 2. it is 1.5 lives, not 2

    func testASecondContactInsideTheRecoveryWindowKills() async {
        let core = cleanCore()
        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 2, dx: grazeBand))
        XCTAssertEqual(core.mode, .play)
        XCTAssertGreaterThan(core.stumbleT, 0)

        // Sit out the i-frames, then take an IDENTICAL contact from the other side — geometrically
        // a graze, and fatal anyway because the recovery window is still open.
        XCTAssertTrue(tickUntil(core) { core.invulnT <= 0 })
        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 0, dx: grazeBand))
        XCTAssertGreaterThan(core.stumbleT, 0.3,
                             "the second contact must land well inside the window under test")
        XCTAssertEqual(core.mode, .over, "two mistakes in a row is a death, not two lives")
        XCTAssertEqual(core.stumbles, 1, "the fatal one is a death, not a second stumble")
    }

    /// …and once you have recovered, the rescue is available again. Otherwise it is one per run,
    /// which is a different mechanic with a HUD requirement this build does not have.
    func testTheRescueReturnsOnceYouHaveRecovered() async {
        let core = cleanCore()
        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 2, dx: grazeBand))
        XCTAssertEqual(core.mode, .play)

        XCTAssertTrue(tickUntil(core) { core.stumbleT <= 0 }, "recovery must expire on its own")
        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 0, dx: grazeBand))
        XCTAssertEqual(core.mode, .play, "a fully recovered player gets the same forgiveness again")
        XCTAssertEqual(core.stumbles, 2)
    }

    // MARK: - 3. the wall must not pay you for hitting it

    /// The near-miss scorer samples `dx` at the EXIT plane, where it has grown while the player kept
    /// escaping. Leave the wall alive after a stumble and it awards CLOSE — +40 × mult, style coins
    /// and a flow pip — for the wall that just staggered you.
    func testAStumbleRemovesTheWallSoItCannotPayANearMiss() async {
        let core = cleanCore()
        var nearMisses = 0
        core.onFX = { if case .nearMiss = $0 { nearMisses += 1 } }

        XCTAssertTrue(stageContact(core, wallLane: 1, driftTo: 2, dx: grazeBand))

        XCTAssertEqual(core.stumbles, 1)
        XCTAssertEqual(core.activeObstacles.count, 0, "the wall you hit must leave the field")
        let bonusAfter = core.bonus
        XCTAssertTrue(tickUntil(core) { core.distance > 40 })
        XCTAssertEqual(nearMisses, 0, "a wall that staggered you must never also reward you")
        XCTAssertEqual(core.bonus, bonusAfter, "and must pay no score at all")
    }

    // MARK: - 4. the Warden: stumble first, then kill

    /// The owner's ruling, verbatim: *"stumble first then kill"*. Standing still guarantees the
    /// lance closes the player's lane, so every strike lands and the two outcomes arrive in order.
    func testAWardenStumblesYouOnceThenKillsYou() async {
        let core = GameCore(seed: 11)
        core.startRun(seed: 11, startDistance: 3 * Tuning.worldLength)
        core.debugFillWardenCharge()

        var stumbles = 0, died = false
        core.onFX = {
            if case let .stumbled(_, fromWarden) = $0 { XCTAssertTrue(fromWarden); stumbles += 1 }
            if case .died = $0 { died = true }
        }

        // Never touch the controls: every strike is unanswered by construction.
        XCTAssertTrue(tickUntil(core, max: 120 * 40) { core.mode == .over })

        XCTAssertTrue(died)
        XCTAssertEqual(stumbles, 1,
            "the first landed beam must stagger and the second must kill — \(stumbles) staggers "
            + "means the escalation is not per-encounter")
    }

    /// The forgiveness is per-ENCOUNTER, not per-run: surviving world 3's Warden must not spend the
    /// rescue that world 6's will offer.
    func testAPaidContinueDoesNotResumeOneShotFromDeath() async {
        let core = GameCore(seed: 11)
        core.startRun(seed: 11, startDistance: 3 * Tuning.worldLength)
        core.debugFillWardenCharge()
        XCTAssertTrue(tickUntil(core, max: 120 * 40) { core.wardenCaughtOnce })
        XCTAssertEqual(core.stumbles, 1)
        XCTAssertTrue(tickUntil(core, max: 120 * 40) { core.mode == .over })

        core.revive()
        XCTAssertFalse(core.wardenCaughtOnce,
                       "a continue must not resume already one shot from death")
        XCTAssertEqual(core.stumbleT, 0, "…nor inside the fatal recovery window")
        XCTAssertEqual(core.stumbles, 1, "the run STAT survives — it is not a spent resource")
    }

    // MARK: - 5. determinism

    /// The stumble draws no RNG and emits no `SpawnCmd`, so the PATTERNS it meets — which ones, in
    /// which order, in which lanes — must be identical to a clean run's. That is the property
    /// `layoutVersion` exists to protect, and it holds exactly.
    ///
    /// **What does NOT hold, and did not before this feature either.** `GameCore.spawn` calls
    /// `spawner.fill(to:dist:)` with the player's LIVE distance, and `Spawner.gapFor(dist)` derives
    /// the inter-pattern gap from it — so the gap is a function of where the player was standing
    /// when a pattern was emitted, not of the cursor. Any speed change therefore nudges every
    /// subsequent `d` by a sub-millimetre amount. Measured here: **0.0002 m at 184 m**, one part in
    /// a million, three orders of magnitude below `obstacleZHalf` and below the 0.14 m a single tick
    /// covers. It cannot change an answer, a lane or a verb.
    ///
    /// The stumble is not special in this: the test proves the SAME drift from a chrono pickup and
    /// from the overdrive boost, both of which have shipped for versions. This corrects the S-009b
    /// probe, which recorded the spawner as fully cursor-driven; it is cursor-driven for pattern
    /// CONTENT and player-distance-driven for the GAP. See PR-0052 — the daily challenge has never
    /// been able to promise an identical experience, only an identical layout.
    func testStumblingPerturbsTheTrackNoMoreThanAShippedPowerUpDoes() async {
        struct Placement: Equatable { var kind: String; var lane: Int }
        func fingerprint(_ mutate: (GameCore) -> Void) -> ([Placement], [Double]) {
            let core = GameCore(seed: 4242)
            core.startRun(seed: 4242)
            _ = tickUntil(core, max: 40_000) { core.distance > 30 }
            mutate(core)
            _ = tickUntil(core, max: 40_000) { core.distance > 1_500 }
            let sorted = core.activeObstacles.sorted { $0.d < $1.d }
            return (sorted.map { Placement(kind: "\($0.kind)", lane: $0.lane) }, sorted.map(\.d))
        }

        let (baseP, baseD) = fingerprint { _ in }
        let (stumbleP, stumbleD) = fingerprint {
            XCTAssertTrue(self.stageContact($0, wallLane: 1, driftTo: 2, dx: self.grazeBand))
            XCTAssertEqual($0.stumbles, 1, "the fixture must actually stumble")
        }
        let (chronoP, chronoD) = fingerprint { $0.activateSlowMo() }
        let (boostP, boostD) = fingerprint { $0.activateHeadStart() }

        XCTAssertFalse(baseP.isEmpty, "the fixture must actually place obstacles")
        for (name, p) in [("stumble", stumbleP), ("chrono", chronoP), ("boost", boostP)] {
            XCTAssertEqual(p, baseP, "\(name) changed WHICH patterns reach the deck — that is a "
                                   + "layoutVersion bump and this feature must not need one")
        }
        // The gap drift, bounded and compared against the shipped baseline.
        func drift(_ a: [Double]) -> Double { zip(a, baseD).map { abs($0 - $1) }.max() ?? 0 }
        let shipped = max(drift(chronoD), drift(boostD))
        XCTAssertLessThan(drift(stumbleD), 0.01, "gap drift must stay far below a tick of travel")
        XCTAssertLessThanOrEqual(drift(stumbleD), max(shipped, 1e-9) * 10,
            "a stumble must perturb the track no more than chrono/boost already do "
            + "(stumble \(drift(stumbleD)) m vs shipped \(shipped) m)")
    }
}
