import XCTest
@testable import PrismRush

/// THE WARDENS — the per-world antagonist, rebuilt in v2.2 (S-012, D-028) so that **it can never
/// kill you.**
///
/// v1.9–v2.1 fired three abstract shapes on the player's own plane and ended the run on the second
/// one that landed. The owner's verdict was that the fight is "a red thing that covers the screen",
/// and the S-011 render audit agreed in numbers: a full-width opaque red band on screen for 92–95%
/// of the exposed phase, a 100 ms dark gap between shapes, a curtain erasing every pixel of track
/// beyond 5.3 m. Every shipped runner boss the research pass examined models the boss as an
/// OPPORTUNITY layer instead — no kill move, the lethal thing is the obstacle it places, and failure
/// means the boss escapes with the reward.
///
/// So the Warden now throws REAL obstacles down the REAL track, and inside the arena they stagger
/// rather than kill. The properties worth pinning are the ones that make that fair:
///
///   1. It has no kill move at all — not "forgives once", never.
///   2. Standing still still loses, so it cannot be beaten by ignoring it.
///   3. Every throw is answerable, and the answers stay disjoint (lane / jump / slide).
///   4. Arming or fighting one can never move a single spawned obstacle.
///   5. The whole fight still fits inside its arena, in distance and in time.
@MainActor
final class WardenTests: XCTestCase {

    // MARK: - the arena

    func testArenasSitAtEveryThirdWorldAndNowhereElse() async {
        for w in 0...12 {
            let head = Double(w) * Tuning.worldLength
            let guarded = w > 0 && w % Tuning.wardenEveryWorlds == 0
            XCTAssertEqual(Warden.arenaWorld(forDistance: head), guarded ? w : nil,
                           "world \(w) at \(head) m")
        }
        XCTAssertNil(Warden.arenaWorld(forDistance: 0), "world 0 is never guarded")
    }

    func testAnArenaEndsWellInsideItsOwnWorld() async {
        XCTAssertLessThan(Tuning.wardenArenaLength, Tuning.worldLength)
        let head = 3 * Tuning.worldLength
        XCTAssertEqual(Warden.arenaWorld(forDistance: head), 3)
        XCTAssertEqual(Warden.arenaWorld(forDistance: head + Tuning.wardenArenaLength - 1), 3)
        XCTAssertNil(Warden.arenaWorld(forDistance: head + Tuning.wardenArenaLength))
        XCTAssertNil(Warden.arenaWorld(forDistance: head + Tuning.worldLength - 1))
    }

    /// The arena is swept of PROCEDURAL obstacles and kept as a gem field — gems are the blast bank,
    /// so the fight is fought with ammunition earned inside it.
    func testTheArenaClearsSpawnedObstaclesAndKeepsEveryGem() async {
        let inside = 3 * Tuning.worldLength + 100
        let outside = 3 * Tuning.worldLength + Tuning.wardenArenaLength + 100
        let obstacles: [SpawnCmd] = [
            .low(d: inside, lane: 0), .tall(d: inside, lane: 1), .bar(d: inside),
            .splitBar(d: inside, openLane: 2), .movingTall(d: inside, phase: 0),
            .chasm(d: inside), .boostPad(d: inside, lane: 1), .hangingBar(d: inside),
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

    /// The arena filter is about the SPAWNER only. A Warden's own throws go in through
    /// `applyThrown`, which bypasses it — they are the reason the deck is being kept clear, not
    /// something to be cleared off it. If this ever regressed, every fight would be a craft hanging
    /// silently over an empty deck.
    func testAWardenSHazardsReachTheDeckTheArenaIsKeepingClear() async {
        let core = wardenCore()
        let thrown = driveUntilThrown(core)
        XCTAssertGreaterThan(thrown, 0, "the Warden never put anything on the deck")
    }

    // MARK: - 1. it can never kill you

    /// **The headline invariant.** A player who does nothing at all inside an arena must come out
    /// alive, every time, at every rank — staggered, robbed and having lost the fight, but alive.
    ///
    /// This is the exact case v2.1 got wrong in the worst way: its lethal branch required
    /// `stumbleT <= 0`, and `stumbleT` runs 0.90 s against a 0.15 s grace, so any wall clip in the
    /// 60 m before the arena mouth made the FIRST Warden hit lethal — the "forgives once" promise
    /// was skippable.
    func testAPlayerWhoNeverMovesInsideAnArenaAlwaysSurvivesIt() async {
        for world in [3, 6, 9, 12] {
            let core = wardenCore(world: world)
            var ticks = 0
            var stumbles = 0
            while core.warden != nil && ticks < 400_000 {
                core.tick(Tuning.tickDt)   // no input at all
                ticks += 1
                stumbles = core.stumbles
            }
            XCTAssertEqual(core.mode, .play,
                           "world \(world): a Warden ended the run — it must never be able to")
            XCTAssertGreaterThan(stumbles, 0,
                                 "world \(world): standing still was not punished at all")
        }
    }

    /// …and it stays true when the player enters already staggered, which is the specific hole the
    /// old rule had.
    func testAWardenCannotKillEvenAPlayerWhoArrivesAlreadyStumbling() async {
        let core = wardenCore()
        core.debugStumble()
        XCTAssertGreaterThan(core.stumbleT, 0)
        var ticks = 0
        while core.warden != nil && ticks < 400_000 {
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        XCTAssertEqual(core.mode, .play, "arriving mid-stumble must not make a Warden lethal")
    }

    /// What a landed hazard costs instead: the multiplier, the tempo, and a blast round.
    func testALandedHazardCostsTheMultiplierAndARound() async {
        let core = wardenCore()
        core.debugFillWardenCharge()
        // Bank a multiplier the fight can take away.
        for i in 0..<Tuning.streakPerMult * 2 {
            core.debugSpawn(.gem(d: core.distance + 3 + Double(i) * 3, lane: 1, y: 0.66))
        }
        var ticks = 0
        while core.mult < 2 && ticks < 4_000 { core.tick(Tuning.tickDt); ticks += 1 }
        XCTAssertGreaterThan(core.mult, 1, "the probe never banked a multiplier")
        let chargeBefore = core.wardenCharge

        ticks = 0
        while core.stumbles == 0 && core.warden != nil && ticks < 400_000 {
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        XCTAssertGreaterThan(core.stumbles, 0, "nothing ever landed on the stationary player")
        XCTAssertEqual(core.mult, 1, "a landed hazard must reset the multiplier")
        XCTAssertLessThan(core.wardenCharge, chargeBefore,
                          "a landed hazard must cost a blast round")
    }

    // MARK: - 2. standing still still loses

    /// The Warden cannot be beaten by ignoring it. Every lance leaves open a lane the player is NOT
    /// standing in when it launches, so a stationary player is always asked to move — the same
    /// invariant v1.9's beam had, for the same reason: an earlier build that merely *usually*
    /// stalked let a motionless player win outright whenever three consecutive attacks happened to
    /// pick an empty lane, because "wasn't in the beam" was being scored as a dodge. It isn't one.
    func testNoFixedStanceCanWinAFight() async {
        for lane in 0...2 {
            for world in [3, 6, 9] {
                let core = wardenCore(world: world)
                core.changeLane(lane - 1)
                var ticks = 0
                while core.warden != nil && ticks < 400_000 {
                    core.changeLane(0)   // hold the stance
                    core.tick(Tuning.tickDt)
                    ticks += 1
                }
                XCTAssertEqual(core.wardensDefeatedThisRun, 0,
                               "lane \(lane), world \(world): standing still killed a Warden")
                XCTAssertGreaterThan(core.stumbles, 0,
                                     "lane \(lane), world \(world): standing still went unpunished")
            }
        }
    }

    /// Failing to damage is not failing to survive: the clock runs out, it leaves with the bounty,
    /// and the run continues. This is the whole failure state of the rebuild.
    func testFailingToDamageCostsTheRewardAndNotTheRun() async {
        let core = wardenCore()
        var ticks = 0
        var brokeOff = false
        core.onFX = { if case .wardenBrokeOff = $0 { brokeOff = true } }
        while core.warden != nil && ticks < 400_000 {
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        XCTAssertTrue(brokeOff, "an unfought Warden must break off")
        XCTAssertEqual(core.mode, .play, "…and the run must continue")
        XCTAssertEqual(core.wardensDefeatedThisRun, 0, "…with no bounty paid")
    }

    /// And nothing it threw may be left standing when it goes. A thrown hazard that outlived its
    /// fight would be a wall that cannot kill you — a free pass through act-two track, visually
    /// identical to one that can.
    func testNothingItThrewOutlivesTheFight() async {
        let core = wardenCore()
        var ticks = 0
        while core.warden != nil && ticks < 400_000 { core.tick(Tuning.tickDt); ticks += 1 }
        XCTAssertTrue(core.activeObstacles.allSatisfy { !$0.fromWarden },
                      "a thrown hazard survived the encounter that threw it")
    }

    // MARK: - 3. every throw is answerable, and the answers stay disjoint

    /// The trichotomy S-009 established survives the rebuild intact — that was never the problem.
    /// A lance closes lanes, a chasm demands height, a hanging bar demands the opposite. No single
    /// motor pattern answers two of them.
    func testTheThreeThrowsHaveDisjointAnswers() async {
        XCTAssertEqual(Tuning.wardenThrowKind(.lance), .tall)
        XCTAssertEqual(Tuning.wardenThrowKind(.floor), .chasm)
        XCTAssertEqual(Tuning.wardenThrowKind(.curtain), .hangingBar)

        // JUMP answers the chasm and is fatal against the hanging bar.
        let apex = Collisions.playerBounds(jumpY: Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity),
                                           scaleY: Tuning.airHoldY)
        XCTAssertTrue(Collisions.hangingBarHit(playerTop: apex.top, playerBottom: apex.bottom, z: 0),
                      "a hanging bar must be unjumpable — that is the entire obstacle")
        // SLIDE answers the hanging bar and is fatal over the chasm.
        let slid = Collisions.playerBounds(jumpY: 0, scaleY: Tuning.slideScaleY)
        XCTAssertFalse(Collisions.hangingBarHit(playerTop: slid.top, playerBottom: slid.bottom, z: 0))
        XCTAssertTrue(Collisions.chasmHit(playerY: 0, z: 0), "sliding does not clear a hole")
    }

    /// **The hanging bar cannot be jumped from ANY state**, including under Super Sneakers, which is
    /// the only buff that changes launch velocity. If a ceiling were ever added, its airborne window
    /// would become a strict superset of an ordinary bar's, one jump would answer both, and slide
    /// would go back to being decorative — with the solvability bot certifying the degenerate
    /// strategy, because "jump on any vertical band" would clear both.
    func testTheHangingBarCannotBeJumpedFromAnyState() async {
        let sneakerApex = pow(Tuning.jumpV0 * Tuning.superSneakersJumpMult, 2) / (2 * Tuning.gravity)
        // Going UP never helps, at any height the game can produce, in any body posture that is not
        // a slide. This is the whole claim.
        for y in stride(from: 0.0, through: sneakerApex, by: 0.05) {
            for sy in [1.0, Tuning.airHoldY] {
                let b = Collisions.playerBounds(jumpY: y, scaleY: sy)
                XCTAssertTrue(Collisions.hangingBarHit(playerTop: b.top, playerBottom: b.bottom, z: 0),
                              "cleared a hanging bar by being at y=\(y) sy=\(sy) (bottom \(b.bottom))")
            }
        }
        // The ceiling is UNREACHABLE rather than absent, so what actually keeps this true is a
        // margin. Pin it: the highest a body's underside ever gets is a Super Sneakers apex, and if
        // a future buff raises that past the ceiling the obstacle silently gains a way over it.
        let highestUnderside = Collisions.playerBounds(jumpY: sneakerApex, scaleY: Tuning.airHoldY).bottom
        XCTAssertLessThan(highestUnderside, Tuning.hangingBarKillTop, String(format:
            "a Super Sneakers apex puts the body's underside at %.3f m against a %.2f m ceiling — "
            + "the hanging bar is now jumpable, and slide is optional again",
            highestUnderside, Tuning.hangingBarKillTop))
        // Going DOWN is the only answer, and it works from the ground and from a low air-slam alike
        // — which is what makes the slam a real recovery rather than a separate trick to learn.
        for y in stride(from: 0.0, through: 0.4, by: 0.05) {
            let b = Collisions.playerBounds(jumpY: y, scaleY: Tuning.slideScaleY)
            XCTAssertFalse(Collisions.hangingBarHit(playerTop: b.top, playerBottom: b.bottom, z: 0),
                           "sliding at y=\(y) must clear it (top \(b.top))")
        }
        // …and an ordinary bar does NOT have this property — which is exactly why the catalogue
        // needed a second one. If this line ever goes red, slide has become optional again.
        let apexBounds = Collisions.playerBounds(
            jumpY: Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity), scaleY: Tuning.airHoldY)
        XCTAssertFalse(Collisions.barHit(playerTop: apexBounds.top,
                                         playerBottom: apexBounds.bottom, z: 0),
                       "an ordinary bar IS jumpable — that is the gap the hanging bar fills")
    }

    /// A lance always leaves exactly one lane open, and never the one the player is in.
    func testALanceAlwaysLeavesOneLaneOpenAndNeverTheOneYouAreIn() async {
        for lane in 0...2 {
            var enc = WardenEncounter(world: 3, runSeed: 0xC0FFEE)
            var opens: Set<Int> = []
            var throwsSeen = 0
            for _ in 0..<4_000 {
                let ev = enc.step(Tuning.tickDt, playerLane: lane)
                guard ev.threw else { continue }
                throwsSeen += 1
                guard ev.throwBand == .lance else { continue }
                XCTAssertNotEqual(ev.throwOpenLane, lane,
                                  "a lance left open the lane the player was standing in")
                opens.insert(ev.throwOpenLane)
            }
            XCTAssertGreaterThan(throwsSeen, 0, "lane \(lane): nothing was thrown at all")
            XCTAssertFalse(opens.isEmpty, "lane \(lane): no lance ever launched")
        }
    }

    /// Two hazards demanding opposite verbs must never be on the deck together — that is the
    /// decree-6 failure the whole shape system exists to avoid. The guarantee is arithmetic: the
    /// throw interval exceeds the longest possible travel time.
    func testTwoThrowsAreNeverInFlightAtOnce() async {
        // The slowest a player can ever be inside an arena: arenas start at world 3 (2,400 m), where
        // the ramp has already reached 29.5 m/s, and a checkpoint start relaxes toward it within the
        // 0.9 s arrival. `speedStart` (17) is the launch speed at 0 m and is unreachable here.
        let slowestArenaSpeed = min(Tuning.speedCap,
                                    Tuning.speedStart + 3 * Tuning.worldLength * Tuning.speedRamp)
        for rank in 1...Tuning.wardenRankCap {
            let longestTravel = Tuning.wardenThrowLeadFar / slowestArenaSpeed
            XCTAssertGreaterThan(Tuning.wardenThrowInterval(rank: rank), longestTravel, String(format:
                "rank %d: %.2f s between throws against %.2f s of flight — two hazards demanding "
                + "opposite verbs can be on the deck at once",
                rank, Tuning.wardenThrowInterval(rank: rank), longestTravel))
        }
        // And measured, in a driven fight: never more than one throw's worth on the deck.
        let core = wardenCore()
        var ticks = 0
        var worstDistinctThrows = 0
        while core.warden != nil && ticks < 400_000 {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            ticks += 1
            let ds = Set(core.activeObstacles.filter(\.fromWarden).map { Int($0.d * 100) })
            worstDistinctThrows = max(worstDistinctThrows, ds.count)
        }
        XCTAssertLessThanOrEqual(worstDistinctThrows, 1,
                                 "\(worstDistinctThrows) separate throws were on the deck at once")
    }

    /// A `.lance` places TWO walls at one distance, and both cross the player plane on the same
    /// tick. Without the twin guard the Warden would take two hits for one dodge and every fight
    /// would be half as long as its own arithmetic says.
    func testALanceIsOneAnswerNotTwo() async {
        let core = wardenCore()
        var coreHitEvents = 0
        core.onFX = { if case .wardenCoreHit = $0 { coreHitEvents += 1 } }
        var ticks = 0
        var lances = 0
        core.onFX = { fx in
            if case .wardenCoreHit = fx { coreHitEvents += 1 }
            if case let .wardenThrew(band, _) = fx, band == .lance { lances += 1 }
        }
        while core.warden != nil && ticks < 400_000 {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        XCTAssertGreaterThan(lances, 0, "no lance was ever thrown")
        // Total damage events can never exceed the number of throws — one answer per throw.
        XCTAssertLessThanOrEqual(coreHitEvents, Tuning.wardenAnswersToKill(rank: 1),
                                 "more damage was registered than the fight has hit points")
    }

    // MARK: - the bot can fight one

    /// The proof that the rebuild is playable at all: the deterministic Autopilot, which was never
    /// taught anything Warden-specific in v2.2, kills a Warden using only the three evasive verbs.
    /// If this goes red, the fight has become unanswerable by the moveset it is built from.
    func testThePerfectBotKillsEveryWardenItMeets() async {
        for world in [3, 6, 9] {
            let core = wardenCore(world: world)
            var ticks = 0
            while core.warden != nil && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
            }
            XCTAssertEqual(core.wardensDefeatedThisRun, 1,
                           "world \(world): a perfect bot failed to kill the Warden")
            XCTAssertEqual(core.stumbles, 0,
                           "world \(world): a perfect bot was hit — the fight is not cleanly answerable")
        }
    }

    /// A later Warden is a harder Warden: more answers to kill, thrown faster.
    func testALaterWardenIsAHarderWarden() async {
        for rank in 1..<Tuning.wardenRankCap {
            XCTAssertLessThan(Tuning.wardenCoreHits(rank: rank), Tuning.wardenCoreHits(rank: rank + 1))
            XCTAssertGreaterThan(Tuning.wardenThrowInterval(rank: rank),
                                 Tuning.wardenThrowInterval(rank: rank + 1))
        }
        XCTAssertEqual(Tuning.wardenRank(world: 3), 1)
        XCTAssertEqual(Tuning.wardenRank(world: 6), 2)
        XCTAssertEqual(Tuning.wardenRank(world: 9), 3)
        XCTAssertEqual(Tuning.wardenRank(world: 30), Tuning.wardenRankCap, "rank flattens, never climbs forever")
    }

    /// The throw lead closes as the Warden takes damage — the fight escalates, the craft grows, and
    /// the boss's health becomes something the player can see rather than read.
    func testTheThrowLeadClosesAsItTakesDamage() async {
        var enc = WardenEncounter(world: 3, runSeed: 1)
        // Walk it out of `.arriving` — `registerAnswer` is a no-op before the fight starts, which is
        // correct (nothing can damage a craft that has not landed) and would silently make this
        // test measure nothing.
        while !enc.isFighting { _ = enc.step(Tuning.tickDt, playerLane: 1) }
        let atFullHealth = enc.throwLead
        XCTAssertEqual(atFullHealth, Tuning.wardenThrowLeadFar, accuracy: 1e-9)
        var last = atFullHealth
        for _ in 0..<Tuning.wardenAnswersToKill(rank: 1) {
            _ = enc.registerAnswer()
            XCTAssertLessThanOrEqual(enc.throwLead, last + 1e-9, "the lead must never widen")
            last = enc.throwLead
        }
        XCTAssertEqual(last, Tuning.wardenThrowLeadNear, accuracy: 1e-9)
        XCTAssertLessThan(Tuning.wardenThrowLeadNear, Tuning.wardenThrowLeadFar)
    }

    /// The shape order is scripted, not rolled — so every player's first Warden is the same designed
    /// introduction and no fight is a dice roll.
    func testTheShapeOrderIsDesignedNotRolled() async {
        for rank in 1...Tuning.wardenRankCap {
            let script = WardenEncounter.script(rank: rank)
            XCTAssertGreaterThanOrEqual(script.count, 4)
            for i in 1..<script.count {
                XCTAssertNotEqual(script[i], script[i - 1],
                                  "rank \(rank): two consecutive throws share a verb at index \(i)")
            }
            XCTAssertEqual(Set(script).count, 3, "rank \(rank) never uses all three shapes")
        }
    }

    // MARK: - 4. determinism (iron rule 2)

    func testTheSameSeedFightsTheIdenticalFight() async {
        for s in 0..<6 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0xFEED
            XCTAssertEqual(throwTrace(seed: seed, world: 3), throwTrace(seed: seed, world: 3))
        }
        XCTAssertNotEqual(throwTrace(seed: 1, world: 3), throwTrace(seed: 2, world: 3),
                          "different seeds must fight different fights")
        XCTAssertNotEqual(throwTrace(seed: 1, world: 3), throwTrace(seed: 1, world: 6),
                          "consecutive worlds must get unrelated streams")
    }

    /// **Iron rule 2 for the boss.** Arming a Warden, fighting one, and being hit by one must all
    /// cost zero draws from the run's spawn stream. Filtered to what the SPAWNER placed: the
    /// Warden's own throws are supposed to differ when the player behaves differently.
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

    // MARK: - 5. the encounter meets its budget

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

    func testAnEncounterCanNeverOutrunItsArena() async {
        let exitSeconds = Tuning.wardenMaxSeconds + Tuning.wardenDieTime + Tuning.wardenLeaveTime
        let worst = Tuning.wardenArmWindow + exitSeconds * Tuning.boostSpeedMax
        XCTAssertLessThanOrEqual(worst, Tuning.wardenArenaLength, String(format:
            "%.0f m arm window + %.1f s at %.0f m/s = %.1f m of fight inside a %.0f m arena",
            Tuning.wardenArmWindow, exitSeconds, Tuning.boostSpeedMax, worst,
            Tuning.wardenArenaLength))

        // And the cap must still fit the longest DESIGNED fight, or a fight the player is winning
        // could be cut off by the ceiling — which reads as the game giving up. The budget is:
        // arrival + one throw interval per answer + the last hazard's flight time.
        for rank in 1...Tuning.wardenRankCap {
            let longest = Tuning.wardenArriveTime
                + Double(Tuning.wardenAnswersToKill(rank: rank)) * Tuning.wardenThrowInterval(rank: rank)
                + Tuning.wardenThrowLeadFar / Tuning.speedStart
            XCTAssertLessThanOrEqual(longest, Tuning.wardenMaxSeconds, String(format:
                "rank %d's shortest possible winning fight is %.2f s against a %.1f s cap",
                rank, longest, Tuning.wardenMaxSeconds))
        }
    }

    func testAWardenNeverArmsWithoutRoomToFightIt() async {
        let head = 3 * Tuning.worldLength
        XCTAssertEqual(Warden.armableWorld(forDistance: head), 3)
        XCTAssertEqual(Warden.armableWorld(forDistance: head + Tuning.wardenArmWindow - 1), 3)
        XCTAssertNil(Warden.armableWorld(forDistance: head + Tuning.wardenArmWindow))
        XCTAssertNil(Warden.armableWorld(forDistance: head + Tuning.wardenArenaLength - 10))
        XCTAssertLessThanOrEqual(Tuning.wardenArmWindow + Tuning.wardenMaxSeconds * Tuning.boostSpeedMax,
                                 Tuning.wardenArenaLength,
                                 "arming this late leaves the fight without arena to finish in")
    }

    /// A solvability proof that never meets the hazard is not a proof — the same guard the chasm
    /// has, for the same reason.
    func testTheSoakActuallyDrivesTheBotThroughWardens() async {
        var armed = 0, killed = 0, throwsSeen = 0
        var byBand: [WardenBand: Int] = [:]
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x51A0_0001
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            core.onFX = { fx in
                switch fx {
                case .wardenArrived: armed += 1
                case .wardenDefeated: killed += 1
                case let .wardenThrew(band, _): throwsSeen += 1; byBand[band, default: 0] += 1
                default: break
                }
            }
            var ticks = 0
            while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
            }
        }
        XCTAssertGreaterThan(armed, 0, "the soak never met a Warden")
        XCTAssertGreaterThan(throwsSeen, 0, "no Warden ever threw anything")
        XCTAssertGreaterThan(killed, 0, "the bot never won a fight")
        for band in WardenBand.allCases {
            XCTAssertGreaterThan(byBand[band] ?? 0, 0, "\(band) was never thrown across 24 seeds")
        }
    }

    // MARK: - helpers

    /// A run parked at the mouth of a Warden arena with the encounter armed and the spawner quiet,
    /// so a fight can be driven in isolation.
    private func wardenCore(world: Int = 3, seed: UInt64 = 0xB055) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed, startDistance: Double(world) * Tuning.worldLength + 5)
        // A checkpoint start grants charge; clear the track so only the Warden's throws are on it.
        core.debugClearTrack()
        var n = 0
        while core.warden == nil && n < 4_000 { core.tick(Tuning.tickDt); n += 1 }
        XCTAssertNotNil(core.warden, "the probe failed to arm a Warden at world \(world)")
        return core
    }

    private func driveUntilThrown(_ core: GameCore) -> Int {
        var thrown = 0
        var ticks = 0
        core.onFX = { if case .wardenThrew = $0 { thrown += 1 } }
        while core.warden != nil && ticks < 400_000 {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        return thrown
    }

    /// The full throw script one encounter produces, as (band, open lane) pairs.
    private func throwTrace(seed: UInt64, world: Int) -> [String] {
        var enc = WardenEncounter(world: world, runSeed: seed)
        var out: [String] = []
        for i in 0..<4_000 {
            let ev = enc.step(Tuning.tickDt, playerLane: i % 3)
            if ev.threw { out.append("\(ev.throwBand):\(ev.throwOpenLane)") }
        }
        return out
    }

    /// Every obstacle the SPAWNER placed in a run, as (kind, distance). Thrown hazards are excluded
    /// on purpose: they are supposed to differ when the player behaves differently.
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
            for o in core.activeObstacles where !o.fromWarden { seen[o.id] = ("\(o.kind)", o.d) }
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
        case .hangingBar: return .hangingBar(d: d)
        case let .boostPad(_, lane): return .boostPad(d: d, lane: lane)
        default: return cmd
        }
    }
}
