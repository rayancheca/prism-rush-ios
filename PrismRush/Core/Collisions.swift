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

    /// Full-height block (static or moving): any lane overlap is fatal — UNLESS Super Sneakers is
    /// active and the player's feet have cleared the wall's top, in which case it's vaulted (no hit).
    /// `canVault`/`playerBottom` default to the lethal-everywhere behaviour so existing callers and
    /// the solvability bot (which never holds the buff) are byte-identical.
    static func tallHit(playerX: Double, obstacleX: Double, z: Double,
                        playerBottom: Double = -.greatestFiniteMagnitude, canVault: Bool = false) -> Bool {
        guard abs(z) < Tuning.obstacleZHalf, abs(playerX - obstacleX) < Tuning.laneHitHalfWidth else { return false }
        if canVault && playerBottom > Tuning.tallVaultClearance { return false }   // sneakers vault
        return true
    }

    /// Overhead bar spanning all lanes: kills if the body intersects the vertical kill band.
    static func barHit(playerTop: Double, playerBottom: Double, z: Double) -> Bool {
        abs(z) < Tuning.obstacleZHalf
            && playerTop > Tuning.barKillBottom
            && playerBottom < Tuning.barKillTop
    }

    /// Split bar covering two lanes with one open gap: the bar's vertical kill band applies only
    /// while the player overlaps a COVERED lane — standing in the gap (or sliding) is safe.
    static func splitBarHit(playerTop: Double, playerBottom: Double, playerX: Double, openLane: Int, z: Double) -> Bool {
        guard abs(z) < Tuning.obstacleZHalf,
              playerTop > Tuning.barKillBottom,
              playerBottom < Tuning.barKillTop else { return false }
        for l in 0..<3 where l != openLane {
            if abs(playerX - Tuning.laneX[l]) < Tuning.laneHitHalfWidth { return true }
        }
        return false
    }

    /// Chasm (v1.8): a full-width gap in the deck. Unlike every other obstacle this one occupies a
    /// RANGE of track — `z` is measured from its centre and it is lethal across `±chasmHalfLength` —
    /// and it is the only predicate that reads the player's height off the ground rather than the
    /// bounds of their body: you are over the gap or you are in it, and crouching does not help.
    ///
    /// It is therefore the catalogue's first TWO-SIDED timing window. Every other jump in the game
    /// is one-sided (clear a plane; jumping early is free), so nothing until now punished going too
    /// soon. Here, launching too early lands you inside the gap.
    ///
    /// Full-span, so there is no `x` term — the whole deck is missing.
    static func chasmHit(playerY: Double, z: Double) -> Bool {
        abs(z) < Tuning.chasmHalfLength && playerY < Tuning.chasmClearance
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

    /// CLOSE near-miss band for a passed tall: a genuine squeeze, never a full lane (pitch 2.2) away.
    static func closeNearMiss(dx: Double) -> Bool {
        dx >= Tuning.nearMissInner && dx < Tuning.nearMissOuter
    }

    /// Prism ring (v1.3): pass = threading the torus near the player plane; PERFECT = the player's
    /// center within ±ringPerfectDY of the bullseye at that moment. Never lethal.
    static func ringPass(playerCenterY pcy: Double, playerX: Double,
                         ringX: Double, ringY: Double, z: Double) -> (pass: Bool, perfect: Bool) {
        guard abs(z) < Tuning.ringZHalf,
              abs(playerX - ringX) < Tuning.ringPassDX,
              abs(pcy - ringY) < Tuning.ringPassDY else { return (false, false) }
        return (true, abs(pcy - ringY) < Tuning.ringPerfectDY)
    }

    /// Overdrive pad trigger (v1.3): grounded floor contact — slides count (they're grounded),
    /// an airborne crossing does not.
    static func boostPadHit(playerX: Double, padX: Double, z: Double, grounded: Bool) -> Bool {
        grounded
            && abs(z) < Tuning.pickupZHalf
            && abs(playerX - padX) < Tuning.pickupXHalf
    }
}
