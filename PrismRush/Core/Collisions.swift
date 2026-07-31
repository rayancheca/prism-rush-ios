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

    /// Hanging bar (v2.2): a full-span wall dropped from the sky with **no ceiling**.
    ///
    /// The unreachable ceiling is the whole obstacle. `barHit` kills between 0.95 and 1.65, so a
    /// base jump puts the body's underside above the band for 0.434 s and every bar in the game up
    /// to v2.1 could be jumped — which made SLIDE the catalogue's only optional verb. This band runs
    /// 0.95 → 4.0, and the highest a body's underside ever reaches is 3.748 m (a Super Sneakers
    /// apex), so no vertical state clears it. The only answer is to be low.
    ///
    /// Sliding clears it on exactly the same numbers as an ordinary bar, so nothing new is taught.
    static func hangingBarHit(playerTop: Double, playerBottom: Double, z: Double) -> Bool {
        abs(z) < Tuning.obstacleZHalf
            && playerTop > Tuning.hangingBarKillBottom
            && playerBottom < Tuning.hangingBarKillTop
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

    // NOTE (v2.2): `wardenStrikeHit` is gone, along with the three abstract shapes it tested.
    // A Warden no longer fires anything at the player's own plane — it throws real obstacles down
    // the real track, and those resolve through `tallHit`, `chasmHit` and `hangingBarHit` above,
    // exactly as the same obstacles do anywhere else in the game. The boss now has no collision rule
    // of its own at all, which is the most literal possible statement of "it can never kill you".

    // MARK: - The stumble: how DEEP was the contact? (v2.0)
    //
    // Every predicate above answers "did they touch it". These answer "by how much did they miss",
    // and they are kept strictly separate on purpose: not one line of the kill geometry above
    // changes, so the 200-seed solvability proof, the daily-challenge goldens and the Autopilot's
    // world are all byte-identical. A stumble is a second, independent question asked only after a
    // contact has already registered.
    //
    // The measure is always **the smallest displacement that would have made it a clean pass**, on
    // the axis whose verb answers that obstacle. That framing is what makes the split bar correct:
    // per-lane penetration would call a player standing dead between two covered lanes "shallow in
    // both", when in truth they are 2.35 units from any safe position.

    /// Lateral distance still to travel to clear a single-lane obstacle. 0 when already clear.
    static func lateralEscape(playerX: Double, obstacleX: Double) -> Double {
        max(0, Tuning.laneHitHalfWidth - abs(playerX - obstacleX))
    }

    /// Lateral distance still to travel to clear EVERY lane a split bar covers, moving toward the
    /// open lane (which is always safe — lane pitch 2.2 exceeds `laneHitHalfWidth`). The binding
    /// lane is the deepest one, not the nearest.
    static func splitBarEscape(playerX px: Double, openLane: Int) -> Double {
        let dir: Double = (Tuning.laneX[openLane] >= px) ? 1 : -1
        var need: Double = 0
        for l in 0..<Tuning.laneX.count where l != openLane {
            let xc = Tuning.laneX[l]
            guard abs(px - xc) < Tuning.laneHitHalfWidth else { continue }
            let d = dir > 0 ? (xc + Tuning.laneHitHalfWidth - px)
                            : (px - (xc - Tuning.laneHitHalfWidth))
            need = max(need, d)
        }
        return need
    }

    /// Height still to gain for the feet to clear a low block. 0 when already clear.
    static func lowVerticalEscape(playerBottom: Double) -> Double {
        max(0, Tuning.lowKillTop - playerBottom)
    }

    /// A bar has TWO answers — duck under it or clear it over the top — so the escape is whichever
    /// is nearer. Both readings are "you clipped an edge".
    static func barVerticalEscape(playerTop: Double, playerBottom: Double) -> Double {
        max(0, min(playerTop - Tuning.barKillBottom, Tuning.barKillTop - playerBottom))
    }

    /// Whether a registered contact was shallow enough to stagger rather than kill.
    ///
    /// `obstacleX` is ignored by the full-span kinds and `openLane` by the single-lane kinds; both
    /// are passed unconditionally so the call site stays one line and cannot forget one.
    ///
    /// `.chasm` never grazes (see `Tuning.stumbleGrazeDX`). `.tall`/`.movingTall` are lateral only:
    /// their vertical answer exists only while Super Sneakers is held, and making a rescue depend on
    /// a buff would teach an inconsistent rule.
    static func grazes(kind: EntityKind, playerX: Double, obstacleX: Double,
                       playerTop: Double, playerBottom: Double, openLane: Int) -> Bool {
        let dx = Tuning.stumbleGrazeDX, dy = Tuning.stumbleGrazeDY
        switch kind {
        case .tall, .movingTall:
            return lateralEscape(playerX: playerX, obstacleX: obstacleX) <= dx
        case .low:
            return lateralEscape(playerX: playerX, obstacleX: obstacleX) <= dx
                || lowVerticalEscape(playerBottom: playerBottom) <= dy
        case .bar:
            return barVerticalEscape(playerTop: playerTop, playerBottom: playerBottom) <= dy
        case .hangingBar:
            // ONE edge, not two. A bar has two answers so the escape is whichever is nearer; this
            // has exactly one — get low — so the only shallow miss is "almost low enough". The
            // ceiling is deliberately NOT offered as a second escape: it is unreachable, and a
            // graze rule that measured against it would forgive a jump that was never going to work.
            return max(0, playerTop - Tuning.hangingBarKillBottom) <= dy
        case .splitBar:
            return splitBarEscape(playerX: playerX, openLane: openLane) <= dx
                || barVerticalEscape(playerTop: playerTop, playerBottom: playerBottom) <= dy
        case .chasm:
            return false
        default:
            return false
        }
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
