import XCTest
@testable import PrismRush

/// **The gate that can actually fail** (S-009).
///
/// `SolvabilityBotTests` and `WardenTests.testTheSoakActuallyDrivesTheBotThroughWardens` prove a
/// Warden is *fair*. They cannot prove it is *hard*, and it is worth being precise about why:
/// `Autopilot` reads the encounter's state directly and reacts on the same tick, so it has perfect
/// information and zero latency. A 0.70 s wind-up is exactly as easy for it as a 0.85 s one. Every
/// assertion in this program would have stayed green while the telegraph was shaved to a frame.
///
/// That is not hypothetical — it is how v1.9 shipped. 228 tests were green and the owner's verdict
/// on playing it was *"its too easy. its just three hits and takes no effort to pass."* Nothing in
/// the suite disagreed, because nothing in the suite was measuring the thing he was measuring.
///
/// `LaggedAutopilot` inserts a human being into the proof: it withholds any response to a telegraph
/// for `reactionSeconds` after that telegraph locks, then plays perfectly. That single parameter
/// turns the fight into a two-sided, deterministic, falsifiable claim:
///
///   - at `humanFloor` (0.40 s) the bot must SURVIVE every encounter → the fight is fair
///   - at `sluggish`   (0.75 s) the bot must DIE somewhere            → the fight is hard
///
/// If the first goes red the fight has become unfair and needs a longer wind-up. If the second goes
/// green the fight has drifted back to being passable without paying attention, and the telegraph
/// tables want tightening. Both directions are load-bearing; neither alone is.
///
/// Lives entirely in the test target and never in `Core/`, so it cannot touch a seeded run.
@MainActor
final class LaggedAutopilotTests: XCTestCase {

    /// Display latency (~0.05 s) + simple visual reaction time (~0.22 s) + the gesture itself
    /// (~0.13 s). A player at this latency is reacting *at human speed with nothing to spare*, so
    /// surviving here is the fairness floor — not a comfortable margin.
    private static let humanFloor = 0.40
    /// Distracted, or not watching the telegraph. Must not be good enough.
    private static let sluggish = 0.75

    /// Drive one run to 6,000 m (worlds 3 and 6, so both a rank-1 and a rank-2 Warden) with every
    /// Warden response delayed by `reaction` seconds. Returns whether the player survived.
    ///
    /// The delay is applied ONLY to Warden reactions. Ordinary obstacle play stays perfect, so a
    /// death can only ever be attributed to an encounter — which is what makes the result readable.
    private func survives(seed: UInt64, reaction: Double) -> (survived: Bool, encounters: Int, caught: Int, kills: Int) {
        let core = GameCore(seed: 1)
        var encounters = 0
        var caught = 0
        var kills = 0
        core.onFX = {
            if case .wardenArrived = $0 { encounters += 1 }
            if case .wardenDefeated = $0 { kills += 1 }
            // Counted from the EVENT, not from `core.stumbles`, so a wall clip at the arena mouth
            // can never be misread as the boss landing a shot.
            if case let .stumbled(_, fromWarden) = $0, fromWarden { caught += 1 }
        }
        core.startRun(seed: seed)

        var lockedAt: Double? = nil     // when the telegraph in flight locked
        var elapsed = 0.0
        var ticks = 0
        while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
            elapsed += Tuning.tickDt
            ticks += 1

            if let w = core.warden, w.isFighting, core.activeObstacles.contains(where: \.fromWarden) {
                if lockedAt == nil { lockedAt = elapsed }
                // Inside the reaction window the player has SEEN nothing yet: they keep running as
                // they were. Deliberately not "do nothing" — a frozen player is not a slow player,
                // and freezing would make lane play artificially safe.
                if elapsed - (lockedAt ?? 0) < reaction {
                    core.tick(Tuning.tickDt)
                    continue
                }
            } else {
                lockedAt = nil
            }
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
        }
        return (core.mode != .over, encounters, caught, kills)
    }

    /// A player reacting at genuine human speed must never be TOUCHED by a Warden.
    ///
    /// **v2.2 re-points this rather than relaxing it.** A Warden can no longer kill anybody, so
    /// `died == 0` has become trivially true and would be a gate that cannot fail. The fairness
    /// floor is now the `caught` assertion alone, and it is the stronger of the two claims anyway:
    /// at human reaction speed the boss must not land a single hazard. If this goes red the fix is a
    /// LONGER throw lead (`wardenThrowLeadFar` / `wardenThrowLeadNear`) — never a smaller hitbox.
    func testAPlayerReactingAtHumanSpeedIsNeverTouchedByAWarden() async {
        var died = 0, encounters = 0, caught = 0
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let out = survives(seed: seed, reaction: Self.humanFloor)
            encounters += out.encounters
            caught += out.caught
            if !out.survived { died += 1 }
        }
        XCTAssertEqual(encounters, 24 * 2, "every run must meet both Wardens or this proves nothing")
        XCTAssertEqual(died, 0,
            "\(died)/24 runs died at a \(Self.humanFloor) s reaction. A Warden cannot kill, so a "
            + "death here means its hazards outlived the encounter or leaked outside the arena.")
        // The real floor. Surviving is not the same claim as being untouched, and since v2.2 the
        // survival claim is free — this is the one that still has teeth.
        XCTAssertEqual(caught, 0,
            "\(caught) hazards landed on players reacting in \(Self.humanFloor) s — the fight is "
            + "UNFAIR. Lengthen Tuning.wardenThrowLeadFar / wardenThrowLeadNear; do not shrink the "
            + "player.")
    }

    /// …and a player who is NOT reading the throw must LOSE THE FIGHT. This is the assertion that
    /// would have caught v1.9's "takes no effort" before the owner had to.
    ///
    /// **v2.2 re-points the failure currency, not the bar.** Death is no longer available as a
    /// consequence, so the hardness gate is now expressed in the two things a Warden can still take:
    /// a sluggish player must be hit, and must fail to kill it. Both directions of the original
    /// two-sided gate survive — 0.40 s untouched above, 0.75 s punished here — and the margin is
    /// still printed, because a gate that only just passes is a gate about to start lying.
    func testAPlayerWhoIsNotWatchingTheThrowLosesTheFight() async {
        var caught = 0, kills = 0, encounters = 0
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let out = survives(seed: seed, reaction: Self.sluggish)
            caught += out.caught
            kills += out.kills
            encounters += out.encounters
        }
        XCTAssertGreaterThan(caught, 0,
            "no hazard landed on ANY player reacting in \(Self.sluggish) s — the encounter is "
            + "passable without reading it, which is exactly the verdict this redesign exists to "
            + "answer. Shorten Tuning.wardenThrowLeadNear or wardenThrowIntervalByRank.")
        XCTAssertLessThan(kills, encounters,
            "a \(Self.sluggish) s player killed every Warden they met (\(kills)/\(encounters)) — "
            + "the fight has no failure state left.")
        print("[lagged] sluggish (\(Self.sluggish) s): \(caught) hazards landed, "
              + "\(kills)/\(encounters) Wardens killed")
    }
}
