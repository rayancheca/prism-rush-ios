import XCTest
@testable import PrismRush

/// THE WARDENS (v1.9, PR-0457) — the per-world antagonist designed with the owner in S-007.
///
/// The properties worth pinning are the ones that make the fight *fair* rather than the ones that
/// make it work: the gun can never kill, failing to damage can never kill the run, and arming a
/// Warden can never move a single spawned obstacle.
@MainActor
final class WardenTests: XCTestCase {

    // MARK: - the arena

    func testArenasSitAtEveryThirdWorldAndNowhereElse() async {
        // Worlds 3, 6, 9 are guarded; 1, 2, 4, 5, 7 are not. World 0 never is — a Warden in the
        // first 600 m would meet a player who has not yet been taught the verbs it tests.
        for w in 0...12 {
            let head = Double(w) * Tuning.worldLength
            let guarded = w > 0 && w % Tuning.wardenEveryWorlds == 0
            XCTAssertEqual(Warden.arenaWorld(forDistance: head), guarded ? w : nil,
                           "world \(w) at \(head) m")
        }
        XCTAssertNil(Warden.arenaWorld(forDistance: 0), "world 0 is never guarded")
    }

    func testAnArenaEndsWellInsideItsOwnWorld() async {
        // If an arena could spill into the next world, `arenaWorld` would report the wrong owner and
        // two encounters could overlap. The margin is what makes the one-arena-per-world claim true.
        XCTAssertLessThan(Tuning.wardenArenaLength, Tuning.worldLength)
        let head = 3 * Tuning.worldLength
        XCTAssertEqual(Warden.arenaWorld(forDistance: head), 3)
        XCTAssertEqual(Warden.arenaWorld(forDistance: head + Tuning.wardenArenaLength - 1), 3)
        XCTAssertNil(Warden.arenaWorld(forDistance: head + Tuning.wardenArenaLength))
        XCTAssertNil(Warden.arenaWorld(forDistance: head + Tuning.worldLength - 1))
    }

    func testTheArenaClearsObstaclesAndKeepsEveryGem() async {
        // The arena is a gem field on purpose: gems are the ammunition, so the shield phase is spent
        // collecting with verbs the player already owns rather than watching a bar empty.
        let inside = 3 * Tuning.worldLength + 100
        let outside = 3 * Tuning.worldLength + Tuning.wardenArenaLength + 100
        let obstacles: [SpawnCmd] = [
            .low(d: inside, lane: 0), .tall(d: inside, lane: 1), .bar(d: inside),
            .splitBar(d: inside, openLane: 2), .movingTall(d: inside, phase: 0),
            .chasm(d: inside), .boostPad(d: inside, lane: 1),
        ]
        for cmd in obstacles {
            XCTAssertTrue(Warden.suppresses(cmd), "\(cmd) must be cleared from the arena")
        }
        let kept: [SpawnCmd] = [
            .gem(d: inside, lane: 1, y: 0.8), .shield(d: inside, lane: 0),
            .magnet(d: inside, lane: 0), .doubler(d: inside, lane: 0),
            .chrono(d: inside, lane: 0), .superSneakers(d: inside, lane: 0),
            .ring(d: inside, lane: 1, y: Tuning.ringY),
        ]
        for cmd in kept {
            XCTAssertFalse(Warden.suppresses(cmd), "\(cmd) must survive inside the arena")
        }
        for cmd in obstacles.map({ shift($0, to: outside) }) {
            XCTAssertFalse(Warden.suppresses(cmd), "\(cmd) is outside every arena and must survive")
        }
    }

    // MARK: - the fight

    /// The gun is a timer the player earned, and the arithmetic behind it is load-bearing enough to
    /// pin: `wardenBaseDPS + charge × wardenChargeDPS` against a bank draining at
    /// `wardenChargeDrain` must break `wardenShieldHP` inside `wardenShieldWindow` at charge 0.85
    /// and fail at 0.75. If a tuning edit moves that threshold, this says so.
    func testTheChargeThresholdIsWhereTheArithmeticSaysItIs() async {
        // S-009 moved HP 100→80 and the window 9.0→7.0 together, which re-solves the threshold from
        // 0.804 to 0.744. Derived in Python from the closed form c = (HP/W + 0.64W − 4)/16, having
        // first reproduced the OLD pins with the same model so the model itself is trusted.
        XCTAssertTrue(breaksShield(startingCharge: 1.00), "a full bank must win the shield race")
        XCTAssertTrue(breaksShield(startingCharge: 0.85))
        XCTAssertTrue(breaksShield(startingCharge: 0.75), "just above the threshold")
        XCTAssertFalse(breaksShield(startingCharge: 0.70), "just below it")
        XCTAssertFalse(breaksShield(startingCharge: 0.00),
                       "a player who banked nothing must not be able to break a shield at all")
    }

    /// The shield phase is the one stretch of an encounter with nothing to DO in it, and the owner's
    /// verdict on v1.9 was that the fight takes no effort. Watching a bar is not effort, so the
    /// bar-watch is pinned SHORT — if a future retune quietly lengthens it, this says so.
    func testTheShieldPhaseIsNotAnAgencyFreeMinute() async {
        var enc = WardenEncounter(world: 3, runSeed: 1)
        var charge = 1.0
        var t = 0.0
        for _ in 0..<(120 * 30) {
            let ev = step(&enc, .standing, charge: &charge)
            t += Tuning.tickDt
            if ev.shieldBroke { break }
        }
        // 0.9 s of arrival + the shield race. Was 7.15 s in v1.9; must stay comfortably under 6.
        XCTAssertLessThan(t, 6.0, "the fully-charged shield race must not become a bar-watch again")
        XCTAssertGreaterThan(t, 3.0, "…but it must still be long enough to be a phase, not a blink")
    }

    /// The design's safety valve, and the single property that keeps a Warden from ever costing a
    /// good run: being HIT abducts you, but failing to DAMAGE does not. An unbroken shield means it
    /// leaves — you lose the reward, not the run.
    func testFailingToDamageIsNotFailingToSurvive() async {
        var enc = WardenEncounter(world: 3, runSeed: 99)
        var charge = 0.0
        var brokeOff = false, finished = false
        for _ in 0..<(120 * 30) {
            let ev = step(&enc, .standing, charge: &charge)
            if ev.brokeOff { brokeOff = true }
            if ev.caughtPlayer { XCTFail("an unbroken shield must never produce an attack") }
            if ev.finished { finished = true; break }
        }
        XCTAssertTrue(brokeOff, "the shield window must expire when the gun cannot break it")
        XCTAssertTrue(finished, "and the encounter must then end rather than hang")
    }

    /// **THE test for the owner's verdict: "it takes no effort to pass."**
    ///
    /// No fixed stance survives a fight. v1.9 asked for one verb — change lane — so a player had a
    /// single motor pattern and three chances to use it. With three shapes whose answers are
    /// disjoint, every posture a player could hold is killed by something:
    ///
    ///   standing still → the lance always closes your lane, and the floor is under you
    ///   holding a slide → clears the curtain, but a slide LOWERS you into the floor
    ///   jumping every beat → clears the floor, but nothing clears a curtain from the air
    ///
    /// If a future edit ever makes one posture answer everything, the fight silently collapses back
    /// to what the owner rejected. This is the guard for that, and it is deliberately expressed as
    /// "each of these must die" rather than as a hit count.
    func testNoFixedStanceCanSurviveAFight() async {
        let postures: [(String, Stance)] = [
            ("standing still", .standing),
            ("holding a slide", .sliding),
            ("parked at the apex of a jump", .atApex),
        ]
        for (name, posture) in postures {
            var caught = 0, killed = 0
            for seed in UInt64(1)...40 {
                var enc = WardenEncounter(world: 3, runSeed: seed)
                var charge = 1.0
                for _ in 0..<(120 * 40) {
                    let ev = step(&enc, posture, charge: &charge)
                    if ev.caughtPlayer { caught += 1; break }
                    if ev.killed { killed += 1; break }
                    if ev.finished { break }
                }
            }
            XCTAssertEqual(killed, 0, "\(name) must never win a fight — the gun is not a win button")
            XCTAssertEqual(caught, 40, "\(name) must be punished in every single fight")
        }
    }

    /// A player who answers every shape correctly always wins, in exactly the number of clean
    /// answers the rank asks for — never more, never a war of attrition.
    func testAnsweringEveryShapeKillsItInExactlyTheRankedCount() async {
        for (world, rank) in [(3, 1), (6, 2), (9, 3), (12, 3), (300, 3)] {
            let r = try! XCTUnwrap(Optional(rank))
            let out = runPerfectFight(world: world, seed: 7)
            XCTAssertTrue(out.killed, "world \(world): a perfect answer set must kill it")
            XCTAssertFalse(out.caught, "world \(world): a correct answer must never be caught")
            XCTAssertEqual(out.cores, Tuning.wardenCoreHits(rank: r),
                           "world \(world) is rank \(r)")
            XCTAssertLessThan(out.seconds, Tuning.wardenMaxSeconds,
                              "world \(world): a won fight must finish well inside the cap")
        }
    }

    /// The fight gets harder the deeper you meet it — v1.9 used `world` for nothing but the RNG
    /// seed, so every Warden in the game was literally the same encounter.
    func testALaterWardenIsAHarderWarden() async {
        let r1 = runPerfectFight(world: 3, seed: 11)
        let r2 = runPerfectFight(world: 6, seed: 11)
        let r3 = runPerfectFight(world: 9, seed: 11)
        XCTAssertLessThan(r1.cores, r2.cores)
        XCTAssertLessThan(r2.cores, r3.cores)
        XCTAssertLessThan(Tuning.wardenTelegraphTime(rank: 3), Tuning.wardenTelegraphTime(rank: 1),
                          "a rank-3 wind-up must be tighter than a rank-1")
        // …and it must flatten, or it eventually stops being beatable ("not impossible").
        XCTAssertEqual(Tuning.wardenRank(world: 12), Tuning.wardenRank(world: 300))
    }

    /// Every shape must be answerable from EVERY vertical state, or some frame is unwinnable — the
    /// owner's "not impossible" bar. Checked directly against the predicate rather than through a
    /// simulation, so a geometry change is caught even if no seed happens to produce the case.
    func testEveryShapeHasAnAnswerAndTheAnswersAreDisjoint() async {
        func hit(_ s: Stance, _ band: WardenBand, mask: UInt8 = 0b111) -> Bool {
            let b = s.bounds
            return Collisions.wardenStrikeHit(playerX: s.x, playerTop: b.top,
                                              playerBottom: b.bottom, mask: mask, band: band)
        }
        // Each shape HAS an answer.
        XCTAssertFalse(hit(.jumping, .floor), "a jump must clear a floor")
        XCTAssertFalse(hit(.sliding, .curtain), "a slide must clear a curtain")

        // …and the answers are DISJOINT, which is what stops one input answering everything.
        XCTAssertTrue(hit(.sliding, .floor),
                      "sliding must NOT clear a floor — it lowers you into it")
        XCTAssertTrue(hit(.jumping, .curtain),
                      "jumping must NOT clear a curtain")
        XCTAssertTrue(hit(.standing, .floor))
        XCTAssertTrue(hit(.standing, .curtain))
    }

    /// **The single most load-bearing property in the redesign.**
    ///
    /// The curtain has no ceiling, so it cannot be jumped from any height the player can reach. If
    /// someone ever gives it a top — the obvious "reuse `barKillTop`" edit — the floor's clearance
    /// window becomes a superset of the curtain's, one jump answers both shapes, slide becomes
    /// optional and the verb ladder collapses straight back to the binary the owner rejected.
    /// The bot would then certify the degenerate strategy, because "jump on any band" clears both.
    func testTheCurtainCannotBeJumpedFromAnyState() async {
        let apex = Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity)
        for step in 0...100 {
            let jumpY = apex * Double(step) / 100
            for sy in [1.0, Tuning.slideScaleY] {
                let b = Collisions.playerBounds(jumpY: jumpY, scaleY: sy)
                if sy == 1.0 || jumpY > 0.51 {
                    XCTAssertTrue(
                        Collisions.wardenStrikeHit(playerX: 0, playerTop: b.top,
                                                   playerBottom: b.bottom, mask: 0b111,
                                                   band: .curtain),
                        "a curtain must catch a player at jumpY \(jumpY), scaleY \(sy)")
                }
            }
        }
        // Being AIRBORNE AND SLIDING at the apex — the most favourable jump state there is — must
        // still be caught, or the curtain is jumpable after all.
        let b = Stance(jumpY: apex, sy: Tuning.slideScaleY, grounded: false).bounds
        XCTAssertGreaterThan(b.top, Tuning.wardenCurtainKillBottom)
    }

    /// The reachability substitution must never be a free ride. If a player is airborne when a floor
    /// would have locked, they get a CURTAIN instead — and a curtain is a strictly *harder* demand
    /// (it must be answered from a state they have to slam out of), bought with a jump they did not
    /// need. If the substitution ever became the easier branch, jumping on the beat would be a
    /// degenerate strategy that farms it.
    func testDodgingIntoTheSubstitutionIsNeverAnEasierFight() async {
        // Grounded with time to spare: a floor is reachable, so the script stands.
        XCTAssertTrue(WardenEncounter.floorIsReachable(jumpY: 0, vy: 0, grounded: true,
                                                       secondsToStrike: 0.80))
        // Grounded but far too late to complete a launch: not reachable.
        XCTAssertFalse(WardenEncounter.floorIsReachable(jumpY: 0, vy: 0, grounded: true,
                                                        secondsToStrike: 0.05))
        // LOW and falling fast with no time to land and re-jump: the genuine unwinnable case, and
        // the only reason the substitution exists.
        XCTAssertFalse(WardenEncounter.floorIsReachable(jumpY: 0.30, vy: -8, grounded: false,
                                                        secondsToStrike: 0.10))
        // High and descending, but still above the clearance height when the strike lands — that is
        // reachable and must NOT substitute, or a player who jumped early would be handed a softer
        // shape for free.
        XCTAssertTrue(WardenEncounter.floorIsReachable(jumpY: 2.0, vy: -6, grounded: false,
                                                       secondsToStrike: 0.10))
        // Low, but with a full wind-up to land and launch again: reachable.
        XCTAssertTrue(WardenEncounter.floorIsReachable(jumpY: 0.5, vy: -5, grounded: false,
                                                       secondsToStrike: 0.60))
        // The substitution's answer (slide) does not also clear the floor it replaced — that is
        // what makes it a harder demand rather than a softer one.
        let sliding = Stance.sliding.bounds
        XCTAssertTrue(Collisions.wardenStrikeHit(playerX: 0, playerTop: sliding.top,
                                                 playerBottom: sliding.bottom, mask: 0b111,
                                                 band: .floor))
    }

    /// A spent strike must always clear before the next telegraph locks, at every rank — otherwise
    /// `beamMask` means two things at once and the lit shape on screen is a lie. This was only a
    /// comment in v1.9; the per-rank recover table makes it one edit away from being false.
    func testASpentStrikeAlwaysClearsBeforeTheNextTelegraphLocks() async {
        for rank in 1...Tuning.wardenRankCap {
            XCTAssertLessThan(Tuning.wardenStrikeShowTime, Tuning.wardenAttackRecover(rank: rank),
                              "rank \(rank): the afterglow outlasts the recovery")
        }
    }

    /// The shape ORDER is scripted and consumes no RNG, so every player's first Warden is the same
    /// designed introduction rather than a dice roll that might open with the hardest shape.
    func testTheShapeOrderIsDesignedNotRolled() async {
        let a = runPerfectFight(world: 3, seed: 1).bands
        let b = runPerfectFight(world: 3, seed: 999_999).bands
        XCTAssertEqual(a, b, "two different seeds must meet the same rank-1 shape order")
        XCTAssertEqual(a.first, .lance,
                       "the first shape a player ever sees must be the one v1.9 already taught")
        XCTAssertTrue(a.contains(.floor) && a.contains(.curtain),
                      "…and the first fight must still introduce both new shapes")
    }

    // MARK: - determinism (iron rule 2)

    /// A Warden must be a pure function of the run seed and the world ordinal.
    ///
    /// The per-world check is aggregated on purpose. A single fight is only three beams and each
    /// carries little entropy (one coin flip, then one of two lanes), so two unrelated streams
    /// coincide on a given seed often enough that asserting per-seed inequality is a coin toss. If
    /// the world ordinal were NOT mixed into the derivation, every seed would match; requiring most
    /// of them to differ catches that without depending on luck.
    func testTheSameSeedFightsTheIdenticalFight() async {
        var differing = 0
        for seed in UInt64(1)...24 {
            XCTAssertEqual(beamTrace(seed: seed, world: 3), beamTrace(seed: seed, world: 3),
                           "the same seed and world must replay the identical fight")
            if beamTrace(seed: seed, world: 3) != beamTrace(seed: seed, world: 6) { differing += 1 }
        }
        XCTAssertGreaterThan(differing, 12, "each world's Warden must draw its own stream")
    }

    /// **The one that protects every seeded run in the game.**
    ///
    /// A Warden draws from its OWN stream, derived from the run seed — never from the spawn stream.
    /// If that were ever violated, the player's lane choices during a fight would feed back into
    /// `rng` and the track behind them would change: same seed, different obstacles, and every
    /// daily-challenge guarantee silently void.
    ///
    /// This runs one seed twice, diverging the player's behaviour ONLY inside arenas (which are
    /// swept clear, so the extra lane changes are always safe), then compares every obstacle the
    /// spawner actually placed. Identical positions prove the fight cannot reach the spawn stream.
    /// The KIND SEQUENCE is asserted exactly — that is what the seeded stream decides, and a single
    /// stolen `rng` draw would reshuffle it immediately. Positions are asserted to within a
    /// centimetre rather than bit-for-bit, because `Spawner.gap(forDistance:)` reads the player's
    /// live distance, so any behaviour that touches speed (taking a boost pad in a different lane
    /// after the arena) moves a pattern by fractions of a millimetre. That drift predates the
    /// Wardens and is not a determinism break; a stolen draw would move things by metres.
    func testAFightCanNeverPerturbTheSpawnStream() async {
        for s in 0..<6 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0xDEAD_BEEF_5EED
            let calm = obstacleTrace(seed: seed, fidgetInArena: false)
            let fought = obstacleTrace(seed: seed, fidgetInArena: true)
            XCTAssertEqual(calm.map(\.0), fought.map(\.0),
                           "seed \(seed): a Warden fight changed which patterns the spawner drew")
            let drift = zip(calm, fought).map { abs($0.1 - $1.1) }.max() ?? 0
            XCTAssertLessThan(drift, 0.01,
                              "seed \(seed): a Warden fight moved a spawned obstacle by \(drift) m")
        }
    }

    // MARK: - the encounter meets its budget

    /// The arena has to outlast the encounter in DISTANCE, because the encounter is timed and the
    /// arena is not. If a fight could outrun its arena, obstacles would resume mid-fight — beams and
    /// walls at once, which is precisely the unfair combination the arena exists to prevent.
    func testEveryEncounterFinishesInsideItsArena() async {
        var worst = 0.0
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            var start = 0.0
            var active = false
            var ticks = 0
            while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
                let now = core.warden != nil
                if now && !active { start = core.distance }
                if !now && active { worst = max(worst, core.distance - start) }
                active = now
            }
        }
        XCTAssertGreaterThan(worst, 0, "no encounter ran at all — this test proves nothing")
        XCTAssertLessThan(worst, Tuning.wardenArenaLength,
                          "the longest encounter must finish before its arena does")
    }

    /// The arithmetic behind the arena guarantee, independent of any particular run: even the
    /// worst-case encounter, travelled at the fastest speed the game can produce, has to fit.
    /// `wardenMaxSeconds` is the term that makes this provable — without it a player trading
    /// shields could extend a fight indefinitely.
    func testAnEncounterCanNeverOutrunItsArena() async {
        // **The v1.9 form of this test was wrong and passed anyway (S-009).** It computed
        // `wardenMaxSeconds × boostSpeedMax` alone, omitting both the arm window (a Warden can arm
        // up to 60 m into the arena) and the `.dying`/`.leaving` phases, which the cap in
        // `WardenEncounter.step` explicitly exempts. The honest worst case at the old 16 s cap was
        // 704.4 m inside a 660 m arena — reachable by a player chaining banked Speed Ups, since
        // `deployOverdrive` guards only `boostT <= 0`. Lowering the cap to 14.5 closes it for real.
        let exitSeconds = Tuning.wardenMaxSeconds + Tuning.wardenDieTime + Tuning.wardenLeaveTime
        let worst = Tuning.wardenArmWindow + exitSeconds * Tuning.boostSpeedMax
        XCTAssertLessThanOrEqual(worst, Tuning.wardenArenaLength, String(format:
            "%.0f m arm window + %.1f s at %.0f m/s = %.1f m of fight inside a %.0f m arena",
            Tuning.wardenArmWindow, exitSeconds, Tuning.boostSpeedMax, worst,
            Tuning.wardenArenaLength))

        // And the cap must still clear the longest DESIGNED encounter, or a fight the player is
        // winning could be cut off by the ceiling — which would read as the game giving up.
        for rank in 1...Tuning.wardenRankCap {
            let longest = Tuning.wardenArriveTime + Tuning.wardenShieldWindow
                + Double(Tuning.wardenCoreHits(rank: rank))
                * (Tuning.wardenTelegraphTime(rank: rank) + Tuning.wardenAttackRecover(rank: rank))
            XCTAssertLessThanOrEqual(longest, Tuning.wardenMaxSeconds,
                "rank \(rank)'s longest winnable fight is \(longest) s against a \(Tuning.wardenMaxSeconds) s cap")
        }
    }

    /// A checkpoint run that begins deep inside an arena must not summon a Warden it has no room to
    /// fight — it runs the rest of the arena out as clear track instead.
    func testAWardenNeverArmsWithoutRoomToFightIt() async {
        let head = 3 * Tuning.worldLength
        XCTAssertEqual(Warden.armableWorld(forDistance: head), 3)
        XCTAssertEqual(Warden.armableWorld(forDistance: head + Tuning.wardenArmWindow - 1), 3)
        XCTAssertNil(Warden.armableWorld(forDistance: head + Tuning.wardenArmWindow),
                     "past the arm window the arena is still clear, but no Warden appears")
        XCTAssertNil(Warden.armableWorld(forDistance: head + Tuning.wardenArenaLength - 10))
        // And the window must leave the full worst-case fight inside the arena.
        XCTAssertLessThanOrEqual(Tuning.wardenArmWindow + Tuning.wardenMaxSeconds * Tuning.boostSpeedMax,
                                 Tuning.wardenArenaLength,
                                 "arming this late leaves the fight without arena to finish in")
    }

    /// A solvability proof that never meets the hazard is not a proof — the same guard the chasm
    /// has, for the same reason. If a future edit stops arming Wardens, the 200-seed soak would stay
    /// green and mean nothing; this turns red instead.
    func testTheSoakActuallyDrivesTheBotThroughWardens() async {
        var armed = 0, killed = 0, strikes = 0, deaths = 0
        var byBand: [WardenBand: Int] = [:]
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let core = GameCore(seed: 1)
            core.onFX = { fx in
                switch fx {
                case .wardenArrived: armed += 1
                case .wardenDefeated: killed += 1
                case let .wardenStruck(_, band, _): strikes += 1; byBand[band, default: 0] += 1
                default: break
                }
            }
            core.startRun(seed: seed)
            var ticks = 0
            while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
            }
            if core.mode == .over { deaths += 1 }
        }
        // 6,000 m crosses worlds 3 and 6, so every seed must meet exactly two.
        XCTAssertEqual(armed, 24 * 2, "every 6,000 m run must meet both Wardens")
        XCTAssertEqual(deaths, 0, "the bot must survive every encounter it is driven through")
        // 6,000 m crosses worlds 3 (rank 1, 4 hits) and 6 (rank 2, 5 hits).
        let perRun = Tuning.wardenCoreHits(rank: 1) + Tuning.wardenCoreHits(rank: 2)
        XCTAssertGreaterThanOrEqual(strikes, 24 * perRun,
                                    "each pair of kills takes at least \(perRun) strikes")
        XCTAssertEqual(killed, armed, "a fully-charged bot that answers cleanly must win every fight")

        // **The guard that keeps the proof honest**, and the reason this test exists at all: a green
        // 200-seed soak means nothing if the bot never actually MET the hazard. If a future edit
        // stopped the vertical shapes ever firing — or quietly substituted every floor away — every
        // assertion above would stay green while the fight silently reverted to the one-verb
        // encounter the owner rejected. Same guard as the chasm's, for the same reason.
        for band in WardenBand.allCases {
            XCTAssertGreaterThan(byBand[band, default: 0], 0,
                "the soak never fired a \(band) — the bot is not being tested on that verb")
        }
        let vertical = byBand[.floor, default: 0] + byBand[.curtain, default: 0]
        XCTAssertGreaterThan(vertical, strikes / 3,
            "vertical shapes are \(vertical)/\(strikes) of all strikes — the fight has drifted back "
            + "toward being answerable with lane changes alone")
    }

    // MARK: - helpers

    /// A player's whole tick-relevant state, so a test can express "standing", "at the top of a
    /// jump" or "sliding" without threading six arguments through every call.
    struct Stance {
        var lane = 1
        var jumpY = 0.0
        var sy = 1.0          // 1 standing, `Tuning.slideScaleY` sliding
        var vy = 0.0
        var grounded = true

        var x: Double { Tuning.laneX[lane] }
        var bounds: (bottom: Double, top: Double) {
            Collisions.playerBounds(jumpY: jumpY, scaleY: sy)
        }

        static let standing = Stance()
        /// High enough for the body's underside to clear a floor slab.
        static let jumping = Stance(jumpY: 0.9, sy: 1.0, vy: 1.0, grounded: false)
        /// Low enough for the body's top to pass under a curtain.
        static let sliding = Stance(jumpY: 0, sy: Tuning.slideScaleY, grounded: true)
        /// At the apex of a jump — the worst case for a curtain, and the case that proves it is
        /// un-jumpable rather than merely hard to jump.
        static let atApex = Stance(jumpY: Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity),
                                   sy: 1.0, vy: 0, grounded: false)

        /// The stance that correctly answers `band` — the thing a perfect player would be in.
        static func answering(_ band: WardenBand, safeLane: Int) -> Stance {
            switch band {
            case .lance:   return Stance(lane: safeLane)
            case .floor:   return jumping
            case .curtain: return sliding
            }
        }
    }

    /// One tick of an encounter with the player in `stance`.
    @discardableResult
    private func step(_ enc: inout WardenEncounter, _ stance: Stance,
                      charge: inout Double) -> WardenTick {
        let b = stance.bounds
        return enc.step(Tuning.tickDt, playerLane: stance.lane, playerX: stance.x,
                        playerTop: b.top, playerBottom: b.bottom,
                        jumpY: stance.jumpY, vy: stance.vy, grounded: stance.grounded,
                        charge: &charge)
    }

    /// Drive an encounter with a player who answers every strike correctly, and report what
    /// happened. The stance is chosen from the band the moment it locks, which is exactly the
    /// information a human has.
    private func runPerfectFight(world: Int, seed: UInt64, startingCharge: Double = 1.0)
        -> (killed: Bool, caught: Bool, cores: Int, bands: [WardenBand], seconds: Double) {
        var enc = WardenEncounter(world: world, runSeed: seed)
        var charge = startingCharge
        var stance = Stance.standing
        var bands: [WardenBand] = []
        var cores = 0, ticks = 0
        var killed = false, caught = false
        while ticks < 120 * 40 {
            let ev = step(&enc, stance, charge: &charge)
            ticks += 1
            if ev.telegraphBegan {
                bands.append(ev.telegraphBand)
                let safe = (0..<3).first { !enc.closes($0) } ?? stance.lane
                stance = .answering(ev.telegraphBand, safeLane: safe)
            }
            if ev.coreHit { cores += 1 }
            if ev.caughtPlayer { caught = true }
            if ev.killed { killed = true }
            if ev.finished { break }
        }
        return (killed, caught, cores, bands, Double(ticks) * Tuning.tickDt)
    }

    /// Run an encounter to its conclusion with a fixed starting bank; true if the shield fell.
    private func breaksShield(startingCharge: Double) -> Bool {
        var enc = WardenEncounter(world: 3, runSeed: 1)
        var charge = startingCharge
        for _ in 0..<(120 * 30) {
            let ev = step(&enc, .standing, charge: &charge)
            if ev.shieldBroke { return true }
            if ev.brokeOff || ev.finished { return false }
        }
        return false
    }

    /// The sequence of (shape, lane mask) an encounter's strikes take, given a player who never
    /// moves. Off in lane-space so a lance always locks the same lane and only the RNG varies.
    private func beamTrace(seed: UInt64, world: Int) -> [UInt8] {
        var enc = WardenEncounter(world: world, runSeed: seed)
        var charge = 1.0
        var masks: [UInt8] = []
        var stance = Stance.standing
        stance.lane = 1
        for _ in 0..<(120 * 40) {
            let ev = enc.step(Tuning.tickDt, playerLane: 1, playerX: 9_999,
                              playerTop: 9_999, playerBottom: 9_999,
                              jumpY: 0, vy: 0, grounded: true, charge: &charge)
            if ev.telegraphBegan, ev.telegraphBand == .lance { masks.append(enc.beamMask) }
            if ev.finished { break }
        }
        return masks
    }

    /// Every obstacle the spawner actually placed in a run, as (kind, distance) rounded to the
    /// millimetre. `fidgetInArena` diverges the player's lane choices, but only where it is safe.
    private func obstacleTrace(seed: UInt64, fidgetInArena: Bool) -> [(String, Double)] {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        var seen: [Int: (String, Double)] = [:]
        var ticks = 0
        while core.mode == .play && core.distance < 5_600 && ticks < 400_000 {
            Autopilot.drive(core)
            if fidgetInArena && Warden.isArena(core.distance) && ticks % 17 == 0 {
                core.changeLane(ticks % 34 == 0 ? 1 : -1)
            }
            core.tick(Tuning.tickDt)
            ticks += 1
            for o in core.activeObstacles { seen[o.id] = ("\(o.kind)", o.d) }
        }
        return seen.keys.sorted().map { seen[$0]! }
    }

    private func shift(_ cmd: SpawnCmd, to d: Double) -> SpawnCmd {
        switch cmd {
        case let .low(_, lane): return .low(d: d, lane: lane)
        case let .tall(_, lane): return .tall(d: d, lane: lane)
        case .bar: return .bar(d: d)
        case let .splitBar(_, openLane): return .splitBar(d: d, openLane: openLane)
        case let .movingTall(_, phase): return .movingTall(d: d, phase: phase)
        case .chasm: return .chasm(d: d)
        case let .boostPad(_, lane): return .boostPad(d: d, lane: lane)
        default: return cmd
        }
    }
}
