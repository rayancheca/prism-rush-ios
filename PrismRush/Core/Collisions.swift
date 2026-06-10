import Foundation

/// Pure collision & pickup predicates, extracted so they can be unit-tested at boundary values
/// independently of the running simulation. `GameCore` calls these same functions (DRY).
enum Collisions {
    /// Vertical extent of the player's sphere body for the current jump height & vertical scale.
    /// Mirrors the prototype: small insets (`+0.06` / `-0.04`) forgive pixel-perfect grazes.
    static func playerBounds(jumpY: Double, scaleY sy: Double) -> (bottom: Double, top: Double) {
        let cy = jumpY + Tuning.groundedCenterY * sy
        let r = Tuning.bodyRadius * sy
        return (cy - r + 0.06, cy + r - 0.04)
    }

    /// Center-Y of the player's body (used for gem/pickup vertical matching).
    static func playerCenterY(jumpY: Double, scaleY sy: Double) -> Double {
        jumpY + Tuning.groundedCenterY * sy
    }

    /// Low block: clips the feet unless the player is high enough.
    static func lowHit(playerBottom: Double, playerX: Double, obstacleX: Double, z: Double) -> Bool {
        abs(z) < Tuning.obstacleZHalf
            && abs(playerX - obstacleX) < Tuning.laneHitHalfWidth
            && playerBottom < Tuning.lowKillTop
    }

    /// Full-height block (static or moving): any lane overlap is fatal.
    static func tallHit(playerX: Double, obstacleX: Double, z: Double) -> Bool {
        abs(z) < Tuning.obstacleZHalf && abs(playerX - obstacleX) < Tuning.laneHitHalfWidth
    }

    /// Overhead bar spanning all lanes: kills if the body intersects the vertical kill band.
    static func barHit(playerTop: Double, playerBottom: Double, z: Double) -> Bool {
        abs(z) < Tuning.obstacleZHalf
            && playerTop > Tuning.barKillBottom
            && playerBottom < Tuning.barKillTop
    }

    /// Gem pickup window (uses the gem's *base* Y, before cosmetic bob).
    static func gemPickup(playerCenterY pcy: Double, playerX: Double, gemX: Double, gemBaseY: Double, z: Double) -> Bool {
        abs(z) < Tuning.gemPickup.dz
            && abs(playerX - gemX) < Tuning.gemPickup.dx
            && abs(pcy - gemBaseY) < Tuning.gemPickup.dy
    }

    /// Shield / magnet pickup window (slightly larger than a gem).
    static func pickupHit(playerCenterY pcy: Double, playerX: Double, pickupX: Double, pickupY: Double, z: Double) -> Bool {
        abs(z) < Tuning.pickupZHalf
            && abs(playerX - pickupX) < Tuning.pickupXHalf
            && abs(pcy - pickupY) < Tuning.pickupYHalf
    }

    /// Whether a gem at relative `z` is inside the magnet's pull window.
    static func magnetActive(z: Double) -> Bool { z > -Tuning.magnetRange && z < 2 }
}
