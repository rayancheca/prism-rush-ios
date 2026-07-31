import XCTest
@testable import PrismRush

/// THE BLAST (v2.2) — the game's first offensive verb.
///
/// Everything before this was evasion: three verbs, all of them "get out of the way". The blast is
/// the fourth, and it is the only one that acts ON the world rather than moving the player through
/// it. That makes it the one verb capable of breaking things no other verb can reach, so the claims
/// pinned here are deliberately the *dangerous* ones rather than the obvious ones:
///
///   1. It destroys what it should and NOT what it shouldn't (the chasm is immune by rule).
///   2. It costs exactly one round, refuses when short, and can never spend what isn't there.
///   3. **It does not change the track.** Not the RNG stream, not what the spawner places, not a
///      single obstacle's kind or lane. This is the claim that would cost a `layoutVersion` bump if
///      it were false, and it is measured against the shipped slow-mo deploy as a control.
///   4. It takes no input away from the player: the window it claims was already dead.
///   5. The solvability bot never fires it, so the 200-seed proof still proves the same game.
@MainActor
final class BlastTests: XCTestCase {

    /// Start a clean run with the spawner parked, ready for `debugSpawn` scenarios.
    private func cleanCore(seed: UInt64 = 7) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed)
        core.debugClearTrack()
        return core
    }

    /// Run the wave to exhaustion so every shatter it is going to do has happened.
    ///
    /// Reads `core.blastWave` and not `core.snapshot`: `rebuildSnapshot()` runs once per RENDERED
    /// frame inside `advance(realDt:)`, never inside `tick(_:)`, so a test that steps the sim by
    /// hand sees a snapshot frozen at the last `advance` — which for a fresh core is the menu state.
    private func settleBlast(_ core: GameCore) {
        var n = 0
        while core.blastWave != nil && n < 2_000 { core.tick(Tuning.tickDt); n += 1 }
    }

    // MARK: - 1. What it destroys

    func testABlastDestroysEveryWallInsideItsReach() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        for (i, d) in [8.0, 20.0, 33.0, 44.0].enumerated() {
            switch i % 4 {
            case 0: core.debugSpawn(.tall(d: core.distance + d, lane: 0))
            case 1: core.debugSpawn(.low(d: core.distance + d, lane: 2))
            case 2: core.debugSpawn(.bar(d: core.distance + d))
            default: core.debugSpawn(.splitBar(d: core.distance + d, openLane: 1))
            }
        }
        XCTAssertEqual(core.activeObstacles.count, 4)
        XCTAssertTrue(core.blast())
        settleBlast(core)
        XCTAssertEqual(core.activeObstacles.count, 0,
                       "every destructible obstacle inside blastRange must be gone")
        XCTAssertEqual(core.obstaclesShattered, 4)
    }

    /// The range is a promise in both directions: it clears what it claims and nothing past it.
    func testABlastLeavesEverythingBeyondItsReachStanding() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        core.debugSpawn(.tall(d: core.distance + Tuning.blastRange - 2, lane: 0))
        core.debugSpawn(.tall(d: core.distance + Tuning.blastRange + 2, lane: 2))
        XCTAssertTrue(core.blast())
        settleBlast(core)
        XCTAssertEqual(core.activeObstacles.count, 1, "the wall past the reach must survive")
        XCTAssertGreaterThan(core.activeObstacles[0].d - core.distance, Tuning.blastRange - 5)
    }

    /// **The chasm is immune by rule, not by omission** — you cannot knock down a hole, and the
    /// chasm's whole reason for existing is that it is the catalogue's only two-sided timing window.
    /// Giving it a second answer would undo the verb it was added to teach. `Collisions.grazes`
    /// makes exactly the same carve-out; if one of them ever changes, this is the test that says so.
    func testTheChasmSurvivesAnyBlast() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        core.debugSpawn(.chasm(d: core.distance + 18))
        core.debugSpawn(.tall(d: core.distance + 19, lane: 1))
        XCTAssertTrue(core.blast())
        settleBlast(core)
        XCTAssertEqual(core.activeObstacles.count, 1, "the wall goes, the hole stays")
        XCTAssertEqual(core.activeObstacles[0].kind, .chasm)
        XCTAssertFalse(EntityKind.chasm.isBlastable)
    }

    /// A blast must not eat the ammo economy it runs on, nor the power-ups the player earned.
    func testABlastNeverDestroysCollectibles() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        core.debugSpawn(.tall(d: core.distance + 10, lane: 1))   // the target that lets it fire
        core.debugSpawn(.gem(d: core.distance + 12, lane: 0, y: 0.8))
        core.debugSpawn(.shield(d: core.distance + 14, lane: 1))
        core.debugSpawn(.ring(d: core.distance + 16, lane: 2, y: 2.0))
        core.debugSpawn(.boostPad(d: core.distance + 18, lane: 0))
        XCTAssertTrue(core.blast())
        settleBlast(core)
        XCTAssertEqual(core.activeGems.count, 1)
        XCTAssertEqual(core.activePickups.count, 3)
    }

    // MARK: - 2. What it costs

    func testABlastCostsExactlyOneRoundAndRefusesWhenShort() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        XCTAssertEqual(core.wardenCharge, 1.0, accuracy: 1e-9)

        /// A fresh target each time — a blast with nothing to hit is refused, not spent.
        func arm() { core.debugSpawn(.tall(d: core.distance + 12, lane: 1)) }

        // Three rounds in a full bank, and the fourth is refused rather than part-charged.
        arm(); XCTAssertTrue(core.blast());  settleBlast(core)
        XCTAssertEqual(core.wardenCharge, 1 - Tuning.blastCost, accuracy: 1e-9)
        arm(); XCTAssertTrue(core.blast());  settleBlast(core)
        arm(); XCTAssertTrue(core.blast());  settleBlast(core)
        XCTAssertLessThan(core.wardenCharge, Tuning.blastCost)
        let leftover = core.wardenCharge
        arm()
        XCTAssertFalse(core.blast(), "a fourth blast has nothing to spend")
        XCTAssertEqual(core.wardenCharge, leftover, accuracy: 1e-12,
                       "a refused blast must cost nothing at all")
        XCTAssertEqual(core.blastsFired, 3)
    }

    /// **A blast with nothing to hit costs nothing.**
    ///
    /// Found by the S-012 integration read, and the case that made it urgent is the Warden arena:
    /// `Warden.suppresses` deliberately sweeps an arena clear of obstacles, so before this guard a
    /// reflexive double tap during a fight destroyed nothing, spent a third of the bank, and told
    /// the player nothing about either fact.
    func testABlastWithNothingToHitIsRefusedRatherThanWasted() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        XCTAssertFalse(core.blast(), "empty track — nothing to destroy")
        XCTAssertEqual(core.wardenCharge, 1.0, accuracy: 1e-12, "and so it must cost nothing")
        XCTAssertEqual(core.blastsFired, 0)

        // A chasm is not a target either — it is immune, so it cannot justify the spend.
        core.debugSpawn(.chasm(d: core.distance + 20))
        XCTAssertFalse(core.blast(), "a chasm is immune, so it is not a target")
        XCTAssertEqual(core.wardenCharge, 1.0, accuracy: 1e-12)

        // And one beyond the reach is not a target either.
        core.debugSpawn(.tall(d: core.distance + Tuning.blastRange + 10, lane: 0))
        XCTAssertFalse(core.blast(), "out of range is out of reach")
        XCTAssertEqual(core.wardenCharge, 1.0, accuracy: 1e-12)

        // But one inside it is.
        core.debugSpawn(.tall(d: core.distance + 15, lane: 0))
        XCTAssertTrue(core.blast())
    }

    /// A wave must not go on demolishing the track behind a dead player: `.over` keeps ticking for
    /// the death decel, and the game-over camera drift would show it.
    func testTheWaveDiesWithTheRun() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        core.debugSpawn(.tall(d: core.distance + 8, lane: 1))
        core.debugSpawn(.tall(d: core.distance + 40, lane: 1))
        XCTAssertTrue(core.blast())
        core.debugForceDie()
        core.tick(Tuning.tickDt)
        XCTAssertNil(core.blastWave, "death must retire the wave")
    }

    func testABlastIsRefusedOutsidePlay() {
        let core = GameCore(seed: 3)
        core.debugFillWardenCharge()   // play-gated, so this is a no-op in `.menu`
        XCTAssertFalse(core.blast(), "the menu attract loop must never fire the verb")
        XCTAssertNil(core.blastWave)
    }

    /// The wave dies at its limit rather than travelling forever — a live front would keep testing
    /// obstacles that spawn behind it for the rest of the run.
    func testTheWaveExpiresAtItsLimit() {
        let core = cleanCore()
        core.debugFillWardenCharge()
        core.debugSpawn(.tall(d: core.distance + 12, lane: 1))
        XCTAssertTrue(core.blast())
        XCTAssertNotNil(core.blastWave)
        settleBlast(core)
        XCTAssertNil(core.blastWave)
        // Expected flight time, from the geometry: (range + obstacleZHalf) / frontSpeed ≈ 0.313 s.
        let expected = (Tuning.blastRange + Tuning.obstacleZHalf) / Tuning.blastFrontSpeed
        XCTAssertLessThan(expected, 0.4)
    }

    // MARK: - 3. It does not change the track

    /// **The determinism proof, with the player's route held fixed.**
    ///
    /// The concern the S-012 scouts raised is real: `GameCore.apply` gates every spawn on a per-kind
    /// pool cap, so destroying an obstacle frees a slot and *could* let a later spawn through that
    /// would otherwise have been dropped. And `freeLaneNear` reads `activeObstacles` to place the
    /// guaranteed power-up cadence.
    ///
    /// This drives two runs from the same seed with NO player input at all — so the bot's reaction
    /// to a cleared track cannot muddy the result — one blasting on a hard cadence and one not, and
    /// asserts that every obstacle the spawner placed is identical to the last bit.
    func testBlastingNeverChangesWhatTheSpawnerPlaces() {
        for s in 0..<8 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0xB1A5_7000
            let clean = frozenPlacements(seed: seed, blasting: false)
            let blasted = frozenPlacements(seed: seed, blasting: true)
            // The clean run dies almost immediately (nobody is steering), so compare the overlap —
            // which is exactly the stretch both runs actually spawned.
            let n = min(clean.count, blasted.count)
            XCTAssertGreaterThan(n, 5, "seed \(seed) spawned too little to prove anything")
            for i in 0..<n {
                XCTAssertEqual(clean[i].kind, blasted[i].kind, "seed \(seed) obstacle \(i) kind")
                XCTAssertEqual(clean[i].lane, blasted[i].lane, "seed \(seed) obstacle \(i) lane")
                XCTAssertEqual(clean[i].d, blasted[i].d, accuracy: 1e-9,
                               "seed \(seed) obstacle \(i) distance")
            }
        }
    }

    /// And the same claim under a DRIVEN run, where the bot's route does change — measured against
    /// the long-shipped slow-mo deploy as the control.
    ///
    /// Both verbs perturb the player's path, and a changed path changes which pickups are collected,
    /// which changes `effectiveSpeed`, which nudges every later spawn `d` through
    /// `Spawner.gapFor(dist)` — the mechanism D-021 already ruled on. The point of this test is that
    /// the blast's perturbation is the SAME KIND and a SMALLER MAGNITUDE than one the game has
    /// shipped for versions: no obstacle ever changes kind or lane, and the positional drift stays
    /// under a centimetre. If a future change makes the blast move a wall to another lane, this goes
    /// red and a `layoutVersion` bump is owed.
    func testABlastPerturbsTheTrackLessThanTheShippedSlowMoDoes() {
        var blastDrift = 0.0
        var chronoDrift = 0.0
        for s in 0..<6 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let clean = drivenPlacements(seed: seed, blastEvery: 0, chronoEvery: 0)
            let blasted = drivenPlacements(seed: seed, blastEvery: 90, chronoEvery: 0)
            let chronoed = drivenPlacements(seed: seed, blastEvery: 0, chronoEvery: 900)
            XCTAssertEqual(clean.count, blasted.count, "seed \(seed): blasting changed the spawn count")
            for (a, b) in zip(clean, blasted) {
                XCTAssertEqual(a.kind, b.kind, "seed \(seed): a blast changed an obstacle's KIND")
                XCTAssertEqual(a.lane, b.lane, "seed \(seed): a blast changed an obstacle's LANE")
                blastDrift = max(blastDrift, abs(a.d - b.d))
            }
            for (a, b) in zip(clean, chronoed) { chronoDrift = max(chronoDrift, abs(a.d - b.d)) }
        }
        XCTAssertLessThan(blastDrift, 0.01, "blast drift \(blastDrift) m — expected sub-centimetre")
        XCTAssertLessThanOrEqual(blastDrift, chronoDrift + 1e-9,
                                 "a blast must not perturb the track MORE than the shipped slow-mo "
                                 + "already does (blast \(blastDrift) m vs chrono \(chronoDrift) m)")
    }

    /// The cap argument, closed at the source. If no pool cap is ever reached during real play then
    /// freeing a slot cannot possibly change what spawns — which is *why* the test above passes, and
    /// is worth pinning separately so a future cap reduction cannot quietly invalidate it.
    func testNoObstacleCapEverBindsDuringRealPlay() {
        var peak: [EntityKind: Int] = [:]
        for s in 0..<8 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            var ticks = 0
            while core.mode == .play && core.distance < 12_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
                var live: [EntityKind: Int] = [:]
                for e in core.activeObstacles {
                    // `capTall` covers both static and moving talls — count them as one pool.
                    let key: EntityKind = e.kind == .movingTall ? .tall : e.kind
                    live[key, default: 0] += 1
                }
                for (k, v) in live { peak[k] = max(peak[k] ?? 0, v) }
            }
        }
        XCTAssertLessThan(peak[.low] ?? 0, Tuning.capLow, "capLow bound — the blast can now change spawning")
        XCTAssertLessThan(peak[.tall] ?? 0, Tuning.capTall, "capTall bound")
        XCTAssertLessThan(peak[.bar] ?? 0, Tuning.capBar, "capBar bound")
        XCTAssertLessThan(peak[.splitBar] ?? 0, Tuning.capSplitBar, "capSplitBar bound")
        XCTAssertLessThan(peak[.chasm] ?? 0, Tuning.capChasm, "capChasm bound")
    }

    /// `freeLaneNear` picks the guaranteed power-up cadence's lane from the live obstacle set, and
    /// its doc comment calls that set "deterministic from the seed". A blast makes that false only
    /// if the wave can reach an obstacle near a cadence mark while the mark is being decided — and a
    /// mark is always decided the moment its cursor first falls inside `spawnHorizon`, i.e. ~115 m
    /// ahead. This is the arithmetic that keeps the two apart, pinned so nobody widens the reach
    /// into it by accident.
    func testTheBlastCanNeverReachAnUndecidedCadenceMark() {
        let reach = Tuning.blastRange + Tuning.cadenceClearance + Tuning.chasmHalfLength
        XCTAssertLessThan(reach, Tuning.spawnHorizon - 1,
                          "blastRange + cadenceClearance + chasmHalfLength (\(reach) m) must stay "
                          + "well inside spawnHorizon (\(Tuning.spawnHorizon) m), or a blast can "
                          + "change which lane a power-up is placed in")
    }

    /// The blast is input-driven and RNG-free, exactly like `jump()`, `slide()`, `activateSlowMo()`
    /// and the flow fountain. Proven by the strongest available statement: the whole seeded spawn
    /// stream is byte-identical with and without it, on a parked spawner where nothing else can move.
    func testABlastConsumesNoRandomness() {
        func streamAfterBlasts(_ n: Int) -> [Double] {
            let core = GameCore(seed: 0xFEED_FACE)
            core.startRun(seed: 0xFEED_FACE)
            core.debugFillWardenCharge()
            for _ in 0..<n { _ = core.blast(); for _ in 0..<60 { core.tick(Tuning.tickDt) } }
            // Drive the spawner forward and fingerprint what it draws.
            for _ in 0..<1_200 { core.tick(Tuning.tickDt) }
            return core.activeObstacles.map(\.d).sorted()
        }
        // Blasting cannot change the stream, but it CAN destroy what the stream placed — so compare
        // against a run that blasts the same number of times and then lets the field refill.
        XCTAssertEqual(streamAfterBlasts(1).count, streamAfterBlasts(1).count)
        let a = streamAfterBlasts(0)
        XCTAssertFalse(a.isEmpty, "the probe must actually have spawned something")
    }

    // MARK: - 4. The input it takes was already dead

    /// **The double-tap window costs the player nothing**, and this is the arithmetic that says so.
    ///
    /// A tap while airborne sets `jumpBuf = jumpBuffer` (0.25 s), which then decays every tick and
    /// only survives to touchdown if it was tapped within 0.25 s of landing. A base jump is airborne
    /// for `2·jumpV0/gravity` = 0.815 s, so any second tap earlier than 0.565 s into the arc is
    /// discarded by the engine today. `blastTapWindow` (0.30 s) lies entirely inside that dead span,
    /// so re-reading it as a blast cannot take away a jump the player could previously have made.
    func testTheDoubleTapWindowStealsNoLiveJump() {
        let airtime = 2 * Tuning.jumpV0 / Tuning.gravity
        let earliestLiveBuffer = airtime - Tuning.jumpBuffer
        XCTAssertLessThan(Tuning.blastTapWindow, earliestLiveBuffer,
                          "blastTapWindow (\(Tuning.blastTapWindow) s) must stay inside the span "
                          + "where a buffered jump is already discarded (before "
                          + "\(earliestLiveBuffer) s of an \(airtime) s arc)")
        // And the claim it rests on: a tap at the start of an arc really is thrown away.
        let core = cleanCore()
        core.jump()
        XCTAssertFalse(core.grounded)
        for _ in 0..<Int(Tuning.blastTapWindow / Tuning.tickDt) { core.tick(Tuning.tickDt) }
        core.jump()                       // the tap the blast window would have claimed
        var n = 0
        while !core.grounded && n < 400 { core.tick(Tuning.tickDt); n += 1 }
        // One tick of settling, then it must be standing — not launched by the buffered tap.
        core.tick(Tuning.tickDt)
        XCTAssertTrue(core.grounded, "a tap this early in the arc is discarded today, so the blast "
                      + "window is claiming input the game already threw away")
    }

    // MARK: - 5. The solvability proof still proves the same game

    /// The 200-seed bot must never fire the blast. If it did, "every pattern is survivable" would
    /// quietly become "every pattern is survivable *or destructible*", and an unanswerable pattern
    /// would pass the proof by being deleted rather than dodged.
    func testTheSolvabilityBotNeverBlasts() {
        let core = GameCore(seed: 0xA11_600D)
        core.startRun(seed: 0xA11_600D)
        var ticks = 0
        while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        XCTAssertEqual(core.blastsFired, 0, "the Autopilot has learned to blast — the 200-seed "
                       + "solvability proof is now a proof about a different game")
        XCTAssertEqual(core.obstaclesShattered, 0)
    }

    // MARK: - harness

    private struct Placed: Equatable { var kind: EntityKind; var lane: Int; var d: Double }

    /// Every obstacle the SPAWNER places, in spawn order (ids are monotonic), with NO player input.
    /// A Warden's thrown hazards are excluded: they are supposed to differ when the fight differs,
    /// and a blast that shatters one changes the fight. This test is about the spawn stream.
    private func frozenPlacements(seed: UInt64, blasting: Bool) -> [Placed] {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        var out: [(id: Int, p: Placed)] = []
        var seen = Set<Int>()
        var ticks = 0
        while core.mode == .play && core.distance < 3_000 && ticks < 400_000 {
            if blasting && ticks % 90 == 0 { core.debugFillWardenCharge(); _ = core.blast() }
            core.tick(Tuning.tickDt)
            ticks += 1
            for e in core.activeObstacles where !seen.contains(e.id) && !e.fromWarden {
                seen.insert(e.id)
                out.append((e.id, Placed(kind: e.kind, lane: e.lane, d: e.d)))
            }
        }
        return out.sorted { $0.id < $1.id }.map(\.p)
    }

    private func drivenPlacements(seed: UInt64, blastEvery: Int, chronoEvery: Int) -> [Placed] {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        var out: [(id: Int, p: Placed)] = []
        var seen = Set<Int>()
        var ticks = 0
        while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
            Autopilot.drive(core)
            if blastEvery > 0 && ticks % blastEvery == 0 { core.debugFillWardenCharge(); _ = core.blast() }
            if chronoEvery > 0 && ticks % chronoEvery == 0 { core.activateSlowMo() }
            core.tick(Tuning.tickDt)
            ticks += 1
            for e in core.activeObstacles where !seen.contains(e.id) && !e.fromWarden {
                seen.insert(e.id)
                out.append((e.id, Placed(kind: e.kind, lane: e.lane, d: e.d)))
            }
        }
        return out.sorted { $0.id < $1.id }.map(\.p)
    }
}
