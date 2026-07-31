import Foundation

/// A deterministic greedy bot that plays the game from the core's public state.
///
/// Two jobs: (1) prove every spawned pattern is survivable (`SolvabilityBotTests`), and
/// (2) drive the in-app attract/autoplay mode (Phase 7). Policy, per the design spec:
/// steer toward the emptiest lane scanning ahead, jump lows, slide bars, and dodge moving
/// walls by predicting their arrival position.
@MainActor
enum Autopilot {
    struct Decision: Equatable {
        var laneDir: Int = 0
        var jump = false
        var slide = false
    }

    /// How far ahead (world units) the bot reasons about lane threats. Comfortably exceeds the
    /// 12-unit reaction-distance invariant so commitments happen early.
    static let reach: Double = 30

    static func decide(_ c: GameCore) -> Decision {
        // 1) Lane choice: score each lane by the distance to the nearest *blocking* obstacle
        //    (a tall in that lane, or a moving wall predicted to arrive over it). Higher = safer.
        var laneScore = [Double](repeating: .infinity, count: 3)   // distance to nearest upcoming tall
        var blockedNow = [Bool](repeating: false, count: 3)        // tall physically in the kill band
        for o in c.activeObstacles {
            let arrival = o.d - c.distance
            let lanes: [Int]
            switch o.kind {
            case .tall:
                lanes = [o.lane]
            case .splitBar:
                // Covered lanes steer the bot toward the gap (o.lane is the OPEN lane); the bar
                // slide-commit below remains the fallback when the gap can't be reached in time.
                lanes = [0, 1, 2].filter { $0 != o.lane }
            case .movingTall:
                // At the collision plane (dist ≈ d) the wall sits at sin(phase)*amplitude; the
                // blocked band is widened to cover its sweep across the ~1.9-unit kill depth.
                // Shared with the spawner so the bot and the coin lines can never disagree about
                // which lanes a swung act-two wall closes.
                lanes = Spawner.movingWallLanes(o.phase)
            default:
                continue
            }
            // Still in (or astride) the kill band — never move into or stay drifting through it.
            // The band lingers ~1.3 units PAST the plane because |z| < 0.95 is still fatal.
            if arrival > -1.3 && arrival < 1.0 {
                for l in lanes { blockedNow[l] = true }
            }
            if arrival > 0 && arrival <= reach {
                for l in lanes { laneScore[l] = min(laneScore[l], arrival) }
            }
        }

        // Stay put unless a tall is actually bearing down on the CURRENT lane within the move
        // horizon. Chasing a far-future-optimal lane only risks crossing a nearer obstacle (and
        // dropping into a low we can no longer clear). 15 units still beats the 12-unit invariant.
        let mustMove = blockedNow[c.laneIndex] || laneScore[c.laneIndex] < 15.0
        var target = c.laneIndex
        if mustMove {
            // Among lanes not physically blocked now, prefer the farthest upcoming tall; on ties
            // the least movement, then the center.
            var candidates = (0..<3).filter { !blockedNow[$0] }
            if candidates.isEmpty { candidates = [c.laneIndex] }
            let maxScore = candidates.map { laneScore[$0] }.max() ?? .infinity
            var bestMoves = Int.max
            for l in candidates where laneScore[l] >= maxScore - 1e-9 {
                let moves = abs(l - c.laneIndex)
                if moves < bestMoves || (moves == bestMoves && l == 1) {
                    bestMoves = moves
                    target = l
                }
            }
        }
        var laneDir = target > c.laneIndex ? 1 : (target < c.laneIndex ? -1 : 0)
        // Never cross THROUGH a lane whose tall is in (or about to enter) its kill band — being
        // airborne over a low doesn't save you from a full-height block. Hold position unless our
        // own lane is itself imminently blocked, in which case moving is the lesser evil.
        if laneDir != 0 {
            let nextLane = c.laneIndex + laneDir
            let nextDangerous = blockedNow[nextLane] || laneScore[nextLane] < 6.0
            let stayingForced = blockedNow[c.laneIndex] || laneScore[c.laneIndex] < 2.0
            if nextDangerous && !stayingForced { laneDir = 0 }
        }

        // 1b) A Warden's LANCE (v1.9) OUTRANKS the obstacle read, and has to.
        //
        // A Warden arena is swept clear of obstacles, so every lane scores `.infinity`, nothing is
        // blocked, and the logic above settles on "stay put" — which is the single answer a lance
        // punishes, because it always closes the lane the player is standing in. Without this the
        // bot walks into every telegraph and the 200-seed solvability proof turns red for a reason
        // that has nothing to do with the spawner.
        //
        // Only a strike that is still WINDING UP is dodged (`isTelegraphing`); the lit afterglow of
        // a shot already fired is ignored, so the bot never chases a spent one. The full-width
        // shapes are handled vertically in (2b) — there is no lane to move to.
        if let w = c.warden, w.pendingBand == .lance, w.closes(target) {
            // Least movement first, centre as the tie-break — the same preference order the
            // obstacle logic above uses. Ascending iteration keeps the choice deterministic.
            // A lance never closes more than two of three lanes, so an escape always exists.
            var pick = -1
            var bestCost = Int.max
            for l in 0..<3 where !w.closes(l) && !blockedNow[l] {
                let cost = abs(l - c.laneIndex) * 2 + (l == 1 ? 0 : 1)
                if cost < bestCost { bestCost = cost; pick = l }
            }
            if pick >= 0 {
                target = pick
                laneDir = target > c.laneIndex ? 1 : (target < c.laneIndex ? -1 : 0)
            }
        }

        // 2) Vertical: jump lows in the target lane, slide (or air-slam) bars. Leads scale with
        //    the EFFECTIVE speed — under chrono slow-mo, obstacles arrive at the slowed rate.
        let jumpLead = clampD(c.effectiveSpeed * 0.17, 4.5, 6.5)
        // Commit to (and hold) a slide from this far out. Generous so that when the bot is still
        // airborne from a preceding low, the air-slam has time to drop it under the bar.
        let slideCommit = clampD(c.effectiveSpeed * 0.42, 8, 14)
        // The chasm (v1.8) is the only obstacle with an extent, and the only one whose jump has a
        // window on BOTH sides: launching too early lands the bot in the hole. So it is tracked by
        // its LEADING edge (the point the jump must already have cleared) and by its TRAILING edge
        // (while that is still ahead of us, we are over the void).
        let chasmLead = Tuning.chasmBotLead(speed: c.effectiveSpeed)
        var nearestBar = Double.infinity
        var nearestLowTarget = Double.infinity
        var nearestChasmEdge = Double.infinity
        var overChasm = false
        for o in c.activeObstacles {
            let arrival = o.d - c.distance
            if o.kind == .chasm {
                let lead = arrival - Tuning.chasmHalfLength    // leading rim
                let trail = arrival + Tuning.chasmHalfLength   // trailing rim
                if lead <= 0 && trail > 0 { overChasm = true }
                if lead > 0 && lead <= reach { nearestChasmEdge = min(nearestChasmEdge, lead) }
                continue
            }
            guard arrival > 0, arrival <= reach else { continue }
            if o.kind == .bar || o.kind == .splitBar {
                nearestBar = min(nearestBar, arrival)   // sliding clears a split bar in ANY lane
            } else if o.kind == .low && o.lane == target {
                nearestLowTarget = min(nearestLowTarget, arrival)
            }
        }

        // A low still right in front must be cleared by staying airborne — never drop into it.
        let lowImminentAhead = nearestLowTarget <= 2.5

        var decision = Decision(laneDir: laneDir)
        if c.grounded {
            // The chasm outranks everything: it is the only obstacle that cannot be slid, steered
            // around, or absorbed by arriving late, and its launch window closes behind us.
            if nearestChasmEdge <= chasmLead {
                decision.jump = true
            } else if nearestLowTarget <= jumpLead && nearestLowTarget <= nearestBar {
                decision.jump = true
            } else if nearestBar <= slideCommit {
                decision.slide = true   // continuous low slide, re-armed each tick
            }
        } else {
            // Airborne: a jump's arc spans ~27 units at top speed — long enough to land on the
            // NEXT obstacle. So the instant we're descending (and not mid-clear of a low), air-slam
            // (vy = -14) to land early and be grounded & ready to time the next jump precisely.
            // Also slam to duck under an imminent bar.
            //
            // NEVER slam while over the void — the slam is what makes the bot land, and landing is
            // exactly the failure here. `overChasm` is the one condition that outranks the bar duck.
            if (c.vy < 0 || nearestBar <= slideCommit) && !lowImminentAhead && !overChasm {
                decision.slide = true
            }
        }

        // 2b) The Warden's VERTICAL shapes (S-009). Deliberately LAST, so it overrides everything
        //     above — in particular the airborne branch, which sets `slide` on any descent and would
        //     otherwise slam the bot out of a jump it needs to hold to clear a floor.
        //
        // The arena is swept clear, so `nearestLow`/`nearestBar`/`nearestChasmEdge` are all
        // `.infinity` inside a fight and none of the obstacle-derived logic above can ever fire a
        // jump or a slide. Without this block a floor is 100% bot death and the encounter is
        // unprovable — which is why the bot learns the verbs in the same change that gives the
        // Warden them, never after.
        if let band = c.warden?.pendingBand, let w = c.warden {
            switch band {
            case .lance:
                break   // answered laterally in (1b)
            case .floor:
                // Sliding LOWERS the body's underside, so it is strictly worse against a floor —
                // clearing it while sliding needs jumpY ≥ 0.7748 rather than 0.750. Never slide.
                decision.slide = false
                if c.grounded && w.secondsToStrike <= Tuning.wardenBotJumpLead { decision.jump = true }
            case .curtain:
                // Un-jumpable by construction, from any height. Slide — and from mid-air the slide
                // doubles as the air-slam that brings the body back down under it.
                decision.jump = false
                if w.secondsToStrike <= Tuning.wardenBotSlideLead { decision.slide = true }
            }
        }
        return decision
    }

    /// Decide and apply, in order: lane → jump → slide.
    static func drive(_ c: GameCore) {
        let d = decide(c)
        if d.laneDir != 0 { c.changeLane(d.laneDir) }
        if d.jump { c.jump() }
        if d.slide { c.slide() }
    }
}
