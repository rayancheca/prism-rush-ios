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
        // A tall is fatal even at the top of a jump (no vertical escape).
        XCTAssertTrue(Collisions.tallHit(playerX: 2.2, obstacleX: 2.2, z: 0.5))
    }

    func testTallLateralEscape() {
        XCTAssertFalse(Collisions.tallHit(playerX: 0, obstacleX: 2.2, z: 0))
        XCTAssertTrue(Collisions.tallHit(playerX: 1.1, obstacleX: 0, z: 0))   // |dx|=1.1 < 1.25
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
        XCTAssertTrue(Collisions.magnetActive(z: -12.9))
        XCTAssertFalse(Collisions.magnetActive(z: -13.0))
        XCTAssertTrue(Collisions.magnetActive(z: 1.9))
        XCTAssertFalse(Collisions.magnetActive(z: 2.0))
    }
}
