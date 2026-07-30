import XCTest
@testable import PrismRush

/// Boundary-value tables for the pure collision predicates. These pin the exact thresholds
/// the whole game balances on, independent of the running simulation.
final class CollisionTests: XCTestCase {

    func testPlayerBoundsGrounded() {
        let b = Collisions.playerBounds(jumpY: 0, scaleY: 1)
        XCTAssertEqual(b.bottom, 0.10, accuracy: 1e-9)   // 0.66 - 0.62 + 0.06
        XCTAssertEqual(b.top, 1.24, accuracy: 1e-9)      // 0.66 + 0.62 - 0.04
    }

    func testPlayerBoundsSlidingClearsLow() {
        let b = Collisions.playerBounds(jumpY: 0, scaleY: Tuning.slideScaleY)
        // Sliding lowers the body, but a slide does NOT clear a low (bottom still below 0.85).
        XCTAssertLessThan(b.bottom, Tuning.lowKillTop)
    }

    // MARK: Low blocks

    func testLowHitGroundedIsFatal() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: 1).bottom
        XCTAssertTrue(Collisions.lowHit(playerBottom: pb, playerX: 0, obstacleX: 0, z: 0))
    }

    func testLowClearedByJump() {
        // High enough that the feet are above the low's kill top.
        let pb = Collisions.playerBounds(jumpY: 1.0, scaleY: 1.1).bottom
        XCTAssertGreaterThanOrEqual(pb, Tuning.lowKillTop)
        XCTAssertFalse(Collisions.lowHit(playerBottom: pb, playerX: 0, obstacleX: 0, z: 0))
    }

    func testLowLateralBoundary() {
        let grounded = Collisions.playerBounds(jumpY: 0, scaleY: 1).bottom
        XCTAssertTrue(Collisions.lowHit(playerBottom: grounded, playerX: 1.24, obstacleX: 0, z: 0))
        XCTAssertFalse(Collisions.lowHit(playerBottom: grounded, playerX: 1.26, obstacleX: 0, z: 0))
    }

    func testLowDepthBoundary() {
        let grounded = Collisions.playerBounds(jumpY: 0, scaleY: 1).bottom
        XCTAssertTrue(Collisions.lowHit(playerBottom: grounded, playerX: 0, obstacleX: 0, z: 0.94))
        XCTAssertFalse(Collisions.lowHit(playerBottom: grounded, playerX: 0, obstacleX: 0, z: 0.96))
    }

    // MARK: Tall blocks

    func testTallHitAnyHeight() {
        XCTAssertTrue(Collisions.tallHit(playerX: 0, obstacleX: 0, z: 0))
        // Without Super Sneakers a tall is fatal even at the top of a jump (no vertical escape).
        XCTAssertTrue(Collisions.tallHit(playerX: 2.2, obstacleX: 2.2, z: 0.5))
    }

    func testTallLateralEscape() {
        XCTAssertFalse(Collisions.tallHit(playerX: 0, obstacleX: 2.2, z: 0))
        XCTAssertTrue(Collisions.tallHit(playerX: 1.1, obstacleX: 0, z: 0))   // |dx|=1.1 < 1.25
    }

    func testTallVaultWithSneakers() {
        // Feet clear the wall top + Super Sneakers active → vault (no hit).
        let high = Collisions.playerBounds(jumpY: 3.4, scaleY: 1).bottom
        XCTAssertGreaterThan(high, Tuning.tallVaultClearance)
        XCTAssertFalse(Collisions.tallHit(playerX: 0, obstacleX: 0, z: 0, playerBottom: high, canVault: true),
                       "Super Sneakers vaults a tall once the feet clear its top")
        // Same height WITHOUT the buff → still fatal (bot-identical; the bot never holds the buff).
        XCTAssertTrue(Collisions.tallHit(playerX: 0, obstacleX: 0, z: 0, playerBottom: high, canVault: false),
                      "without the buff a tall is fatal at any height")
        // Buff active but jump too low → still fatal (you must actually clear it).
        let low = Collisions.playerBounds(jumpY: 1.0, scaleY: 1).bottom
        XCTAssertLessThan(low, Tuning.tallVaultClearance)
        XCTAssertTrue(Collisions.tallHit(playerX: 0, obstacleX: 0, z: 0, playerBottom: low, canVault: true),
                      "a low jump does not vault — feet have not cleared the wall")
    }

    // MARK: Bars

    func testBarHitGrounded() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: 1)
        XCTAssertTrue(Collisions.barHit(playerTop: pb.top, playerBottom: pb.bottom, z: 0))
    }

    func testBarClearedBySlide() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: Tuning.slideScaleY)
        XCTAssertFalse(Collisions.barHit(playerTop: pb.top, playerBottom: pb.bottom, z: 0))
    }

    func testBarClearedByHighJump() {
        let pb = Collisions.playerBounds(jumpY: 2.0, scaleY: 1)
        // Above the bar's kill ceiling → bottom > 1.65.
        XCTAssertGreaterThan(pb.bottom, Tuning.barKillTop)
        XCTAssertFalse(Collisions.barHit(playerTop: pb.top, playerBottom: pb.bottom, z: 0))
    }

    // MARK: Split bars

    func testSplitBarHitInCoveredLane() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: 1)
        // Open lane 0: standing in covered lanes 1 / 2 is fatal, the gap is safe.
        XCTAssertTrue(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 0, openLane: 0, z: 0))
        XCTAssertTrue(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 2.2, openLane: 0, z: 0))
        XCTAssertFalse(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: -2.2, openLane: 0, z: 0))
    }

    func testSplitBarLateralBoundary() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: 1)
        // Open lane 2: covered lane at x=0 kills within |dx| < 1.25, exactly like a tall's width.
        XCTAssertTrue(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 1.24, openLane: 2, z: 0))
        XCTAssertFalse(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 2.2, openLane: 2, z: 0))
    }

    func testSplitBarClearedBySlide() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: Tuning.slideScaleY)
        // Sliding clears the vertical kill band even directly under a covered lane.
        XCTAssertFalse(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 0, openLane: 2, z: 0))
    }

    func testSplitBarDepthBoundary() {
        let pb = Collisions.playerBounds(jumpY: 0, scaleY: 1)
        XCTAssertTrue(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 0, openLane: 2, z: 0.94))
        XCTAssertFalse(Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: 0, openLane: 2, z: 0.96))
    }

    // MARK: Gems

    func testGemPickupWindow() {
        let pcy = Collisions.playerCenterY(jumpY: 0, scaleY: 1)   // 0.66
        XCTAssertTrue(Collisions.gemPickup(playerCenterY: pcy, playerX: 0, gemX: 0, gemBaseY: 0.8, z: 0))
        XCTAssertFalse(Collisions.gemPickup(playerCenterY: pcy, playerX: 0, gemX: 1.01, gemBaseY: 0.8, z: 0)) // |dx|>1.0
        XCTAssertFalse(Collisions.gemPickup(playerCenterY: pcy, playerX: 0, gemX: 0, gemBaseY: 0.8, z: 1.01)) // |z|>1.0
    }

    func testGemVerticalBoundary() {
        let pcy = Collisions.playerCenterY(jumpY: 0, scaleY: 1)   // 0.66
        // |pcy - gemBaseY| < 1.15
        XCTAssertTrue(Collisions.gemPickup(playerCenterY: pcy, playerX: 0, gemX: 0, gemBaseY: 0.66 + 1.14, z: 0))
        XCTAssertFalse(Collisions.gemPickup(playerCenterY: pcy, playerX: 0, gemX: 0, gemBaseY: 0.66 + 1.16, z: 0))
    }

    // MARK: Magnet window

    func testMagnetWindow() {
        XCTAssertTrue(Collisions.magnetActive(z: -(Tuning.magnetRange - 0.1)))
        XCTAssertFalse(Collisions.magnetActive(z: -Tuning.magnetRange))
        XCTAssertTrue(Collisions.magnetActive(z: 1.9))
        XCTAssertFalse(Collisions.magnetActive(z: 2.0))
    }

    // MARK: Overdrive pad trigger (v1.3)

    func testBoostPadTriggerBoundaries() {
        XCTAssertTrue(Collisions.boostPadHit(playerX: 0, padX: 0, z: 0, grounded: true))
        XCTAssertFalse(Collisions.boostPadHit(playerX: 0, padX: 0, z: 0, grounded: false),
                       "airborne crossing must not trigger the pad")
        // Lateral edge ±1.1 (pickupXHalf).
        XCTAssertTrue(Collisions.boostPadHit(playerX: 1.09, padX: 0, z: 0, grounded: true))
        XCTAssertFalse(Collisions.boostPadHit(playerX: 1.11, padX: 0, z: 0, grounded: true))
        // Depth edge ±1.1 (pickupZHalf).
        XCTAssertTrue(Collisions.boostPadHit(playerX: 0, padX: 0, z: 1.09, grounded: true))
        XCTAssertFalse(Collisions.boostPadHit(playerX: 0, padX: 0, z: 1.11, grounded: true))
    }

    // MARK: CLOSE near-miss band

    func testCloseNearMissBand() {
        XCTAssertFalse(Collisions.closeNearMiss(dx: 1.24), "inside the kill width is not a near-miss")
        XCTAssertTrue(Collisions.closeNearMiss(dx: 1.25))
        XCTAssertTrue(Collisions.closeNearMiss(dx: 1.6))
        XCTAssertFalse(Collisions.closeNearMiss(dx: 1.95))
        XCTAssertFalse(Collisions.closeNearMiss(dx: 2.2), "a full lane away must NOT award CLOSE")
        XCTAssertLessThan(Tuning.nearMissOuter, Tuning.laneX[2] - Tuning.laneX[1],
                          "outer band must stay below the lane pitch")
    }

    // MARK: - The stumble band (v2.0)

    /// The three lateral zones, in order, with the two boundaries pinned to the constant that
    /// derives them. A wall is either missed, half-hit, or hit.
    func testTallStumbleBandSitsBetweenTheKillLineAndTheNearMiss() {
        let inner = Tuning.laneHitHalfWidth - Tuning.stumbleGrazeDX   // 0.90
        func graze(_ dx: Double) -> Bool {
            Collisions.grazes(kind: .tall, playerX: dx, obstacleX: 0,
                              playerTop: 1.24, playerBottom: 0.10, openLane: -1)
        }
        XCTAssertEqual(inner, 0.90, accuracy: 1e-9)
        XCTAssertFalse(graze(inner - 0.01), "deeper than half the body in — that is a crash")
        XCTAssertTrue(graze(inner + 0.01), "the outer half-squeeze, on the wrong side of the line")
        XCTAssertTrue(graze(Tuning.laneHitHalfWidth - 0.01), "the last lethal millimetre still grazes")

        // …and the band is strictly INSIDE the kill width, so the CLOSE near-miss reward is untouched:
        // nothing that used to pay a bonus now costs a multiplier instead.
        XCTAssertFalse(Collisions.tallHit(playerX: Tuning.nearMissInner, obstacleX: 0, z: 0),
                       "the near-miss band must remain a clean pass, not a stumble")
        XCTAssertEqual(Tuning.nearMissInner, Tuning.laneHitHalfWidth, accuracy: 1e-9)
    }

    /// A `low` is answered by jumping, so it forgives on BOTH axes — you almost steered round it,
    /// or you almost got your feet over it.
    func testLowGrazesOnEitherAxis() {
        func graze(bottom: Double, x: Double) -> Bool {
            Collisions.grazes(kind: .low, playerX: x, obstacleX: 0,
                              playerTop: bottom + 1.14, playerBottom: bottom, openLane: -1)
        }
        let edge = Tuning.lowKillTop - Tuning.stumbleGrazeDY        // 0.65
        XCTAssertTrue(graze(bottom: edge + 0.01, x: 0), "feet almost cleared it")
        XCTAssertFalse(graze(bottom: edge - 0.01, x: 0), "flat-footed straight into it")
        XCTAssertTrue(graze(bottom: 0.10, x: 1.0), "grounded, but almost round the side of it")
    }

    /// A bar has two answers, so it has two graze edges: slid almost low enough, or jumped almost
    /// high enough. Both read as clipping an edge.
    func testBarGrazesAtBothEdges() {
        func graze(top: Double, bottom: Double) -> Bool {
            Collisions.grazes(kind: .bar, playerX: 0, obstacleX: 0,
                              playerTop: top, playerBottom: bottom, openLane: -1)
        }
        // Almost ducked under: top just above barKillBottom (0.95).
        XCTAssertTrue(graze(top: 1.10, bottom: 0.05))
        XCTAssertFalse(graze(top: 1.40, bottom: 0.30), "squarely into the middle of it")
        // Almost cleared the top: bottom just below barKillTop (1.65).
        XCTAssertTrue(graze(top: 2.80, bottom: 1.50))
    }

    /// The split bar is the case that per-lane penetration gets WRONG. A player standing dead
    /// between two covered lanes is 0.15 into each of them and 2.35 units from any safe position;
    /// calling that a graze would hand a free rescue to the worst possible answer.
    func testSplitBarMeasuresTheEscapeNotThePenetration() {
        // Open lane 0 (x = −2.2) → lanes 1 and 2 are covered, safe set is px ≤ −1.25.
        XCTAssertEqual(Collisions.splitBarEscape(playerX: 1.1, openLane: 0), 2.35, accuracy: 1e-9)
        XCTAssertFalse(Collisions.grazes(kind: .splitBar, playerX: 1.1, obstacleX: 0,
                                         playerTop: 1.24, playerBottom: 0.10, openLane: 0),
                       "dead between two covered lanes is the deepest possible miss, not a graze")
        // Open lane 1 (x = 0) → safe set is |px| ≤ 0.95, so px 1.1 is 0.15 outside it.
        XCTAssertEqual(Collisions.splitBarEscape(playerX: 1.1, openLane: 1), 0.15, accuracy: 1e-9)
        XCTAssertTrue(Collisions.grazes(kind: .splitBar, playerX: 1.1, obstacleX: 0,
                                        playerTop: 1.24, playerBottom: 0.10, openLane: 1),
                      "just short of the gap IS the half-hit this feature exists for")
        XCTAssertEqual(Collisions.splitBarEscape(playerX: 0, openLane: 1), 0, accuracy: 1e-9)
    }

    /// There is no shallow overlap in an eight-metre hole. Keeping one obstacle unconditionally
    /// fatal is also what stops the catalogue losing its only two-sided timing window.
    func testTheChasmNeverGrazes() {
        for y in stride(from: 0.0, through: 0.30, by: 0.05) {
            XCTAssertFalse(Collisions.grazes(kind: .chasm, playerX: 0, obstacleX: 0,
                                             playerTop: y + 1.14, playerBottom: y, openLane: -1),
                           "a chasm must kill at every height it kills at (y = \(y))")
        }
    }
}
