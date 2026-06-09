import XCTest
@testable import PrismRush

/// Phase 1 smoke test: proves the test target links against the app module and that the
/// load-bearing `Tuning` / `Models` contracts are reachable. Real Core tests land in Phase 2.
final class SmokeTests: XCTestCase {
    func testTuningLanesAreCentred() {
        XCTAssertEqual(Tuning.laneX.count, 3)
        XCTAssertEqual(Tuning.laneX[1], 0, accuracy: 1e-9)
        XCTAssertEqual(Tuning.laneX[0], -Tuning.laneX[2], accuracy: 1e-9)
    }

    func testInitialSnapshotIsMenu() {
        let snap = GameSnapshot.initial
        XCTAssertEqual(snap.mode, .menu)
        XCTAssertEqual(snap.speed, Tuning.menuSpeed, accuracy: 1e-9)
        XCTAssertEqual(snap.mult, 1)
        XCTAssertTrue(snap.entities.isEmpty)
    }
}
