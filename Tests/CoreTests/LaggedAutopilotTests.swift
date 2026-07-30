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
    private func survives(seed: UInt64, reaction: Double) -> (survived: Bool, encounters: Int, caught: Int) {
        let core = GameCore(seed: 1)
        var encounters = 0
        var caught = 0
        core.onFX = {
            if case .wardenArrived = $0 { encounters += 1 }
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

            if let w = core.warden, w.isTelegraphing {
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
        return (core.mode != .over, encounters, caught)
    }

    /// A player reacting at genuine human speed must never be killed by a Warden. If this fails the
    /// fight is unfair, and the fix is a LONGER wind-up — never a smaller player hitbox.
    func testAPlayerReactingAtHumanSpeedSurvivesEveryWarden() async {
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
            "\(died)/24 runs died while reacting in \(Self.humanFloor) s — the fight is UNFAIR. "
            + "Lengthen Tuning.wardenTelegraphByRank; do not shrink the player.")
        // **Surviving is no longer the same claim as being untouched (v2.0).** A landed beam now
        // staggers instead of killing the first time, so `died == 0` above could stay green while a
        // human-speed player is being hit in every single fight and rescued by the stumble. This is
        // the assertion that keeps the fairness floor meaning what it says: at genuine human
        // reaction speed the Warden must not land a shot at all.
        XCTAssertEqual(caught, 0,
            "\(caught) beams landed on players reacting in \(Self.humanFloor) s. They survived only "
            + "because the stumble caught them, which is the stumble hiding an unfair fight — "
            + "exactly the failure mode it was warned about. Lengthen the wind-up.")
    }

    /// …and a player who is NOT reading the telegraph must lose. This is the assertion that would
    /// have caught v1.9's "takes no effort" before the owner had to.
    ///
    /// **v2.0 raised this bar rather than lowering it.** A Warden now forgives its first landed shot,
    /// so a sluggish player has to be caught TWICE inside one encounter to die. The test is unchanged
    /// in form and the margin is reported below, because a gate that only just passes is a gate about
    /// to start lying.
    func testAPlayerWhoIsNotWatchingTheTelegraphLoses() async {
        var died = 0, caught = 0
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let out = survives(seed: seed, reaction: Self.sluggish)
            caught += out.caught
            if !out.survived { died += 1 }
        }
        XCTAssertGreaterThan(died, 0,
            "nobody died at a \(Self.sluggish) s reaction time — the encounter is passable without "
            + "reading it, which is exactly the verdict this redesign exists to answer. "
            + "(\(caught) beams did land, so if this is red the STUMBLE is what is carrying them, "
            + "not the fight being fair.) Tighten Tuning.wardenTelegraphByRank / wardenRecoverByRank.")
        print("[lagged] sluggish (\(Self.sluggish) s): \(died)/24 died, \(caught) beams landed")
    }
}
