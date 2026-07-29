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
        XCTAssertTrue(breaksShield(startingCharge: 1.00), "a full bank must win the shield race")
        XCTAssertTrue(breaksShield(startingCharge: 0.85))
        XCTAssertFalse(breaksShield(startingCharge: 0.75))
        XCTAssertFalse(breaksShield(startingCharge: 0.00),
                       "a player who banked nothing must not be able to break a shield at all")
    }

    /// The design's safety valve, and the single property that keeps a Warden from ever costing a
    /// good run: being HIT abducts you, but failing to DAMAGE does not. An unbroken shield means it
    /// leaves — you lose the reward, not the run.
    func testFailingToDamageIsNotFailingToSurvive() async {
        var enc = WardenEncounter(world: 3, runSeed: 99)
        var charge = 0.0
        var brokeOff = false, finished = false
        for _ in 0..<(120 * 30) {
            let ev = enc.step(Tuning.tickDt, playerLane: 1, playerX: 0, charge: &charge)
            if ev.brokeOff { brokeOff = true }
            if ev.caughtPlayer { XCTFail("an unbroken shield must never produce an attack") }
            if ev.finished { finished = true; break }
        }
        XCTAssertTrue(brokeOff, "the shield window must expire when the gun cannot break it")
        XCTAssertTrue(finished, "and the encounter must then end rather than hang")
    }

    /// Auto-fire alone can never kill. A player who stands perfectly still, fully charged, breaks
    /// the shield and is then caught by the first beam that stalks them — the gun opens the fight,
    /// dodging is the only thing that finishes it.
    func testTheGunAloneCanNeverKill() async {
        var killed = 0, caught = 0
        for seed in UInt64(1)...40 {
            var enc = WardenEncounter(world: 3, runSeed: seed)
            var charge = 1.0
            for _ in 0..<(120 * 40) {
                // Parked in lane 1 and never moving — the player does nothing but shoot.
                let ev = enc.step(Tuning.tickDt, playerLane: 1, playerX: Tuning.laneX[1],
                                  charge: &charge)
                if ev.caughtPlayer { caught += 1; break }
                if ev.killed { killed += 1; break }
                if ev.finished { break }
            }
        }
        XCTAssertEqual(killed, 0, "the gun must never be a win button")
        XCTAssertGreaterThan(caught, 0, "and standing still must be punished")
    }

    /// Three clean dodges kill it — never more, never a war of attrition.
    func testThreeCleanDodgesKillAndNoMore() async {
        var enc = WardenEncounter(world: 3, runSeed: 7)
        var charge = 1.0
        var cores = 0, killed = false
        for _ in 0..<(120 * 40) {
            // Always stand clear of every lane the beam has closed.
            let dodge = (0..<3).first { !enc.closes($0) } ?? 1
            let ev = enc.step(Tuning.tickDt, playerLane: dodge, playerX: Tuning.laneX[dodge],
                              charge: &charge)
            if ev.coreHit { cores += 1 }
            XCTAssertFalse(ev.caughtPlayer, "a player standing clear must never be caught")
            if ev.killed { killed = true; break }
        }
        XCTAssertTrue(killed)
        XCTAssertEqual(cores, Tuning.wardenCoreHits)
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
        let worstCaseMetres = Tuning.wardenMaxSeconds * Tuning.boostSpeedMax
        XCTAssertLessThanOrEqual(worstCaseMetres, Tuning.wardenArenaLength, String(format:
            "%.0f s at %.0f m/s = %.0f m of fight inside a %.0f m arena",
            Tuning.wardenMaxSeconds, Tuning.boostSpeedMax, worstCaseMetres, Tuning.wardenArenaLength))
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
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let core = GameCore(seed: 1)
            core.onFX = { fx in
                switch fx {
                case .wardenArrived: armed += 1
                case .wardenDefeated: killed += 1
                case .wardenStruck: strikes += 1
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
        XCTAssertGreaterThanOrEqual(strikes, armed * Tuning.wardenCoreHits,
                                    "each kill takes at least \(Tuning.wardenCoreHits) beams")
        XCTAssertEqual(killed, armed, "a fully-charged bot that dodges cleanly must win every fight")
    }

    // MARK: - helpers

    /// Run an encounter to its conclusion with a fixed starting bank; true if the shield fell.
    private func breaksShield(startingCharge: Double) -> Bool {
        var enc = WardenEncounter(world: 3, runSeed: 1)
        var charge = startingCharge
        for _ in 0..<(120 * 30) {
            let ev = enc.step(Tuning.tickDt, playerLane: 1, playerX: 0, charge: &charge)
            if ev.shieldBroke { return true }
            if ev.brokeOff || ev.finished { return false }
        }
        return false
    }

    /// The sequence of lane masks an encounter's beams take, given a player who never moves.
    private func beamTrace(seed: UInt64, world: Int) -> [UInt8] {
        var enc = WardenEncounter(world: world, runSeed: seed)
        var charge = 1.0
        var masks: [UInt8] = []
        for _ in 0..<(120 * 40) {
            let ev = enc.step(Tuning.tickDt, playerLane: 1, playerX: 9_999, charge: &charge)
            if ev.telegraphBegan { masks.append(enc.beamMask) }
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
