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
}
