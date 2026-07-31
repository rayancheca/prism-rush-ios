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

    /// How far away an obstacle **effectively** is: the distance a STATIC obstacle would have to sit
    /// at to reach the player at the same moment (v2.3).
    ///
    /// Every lead in this file (`jumpLead`, `slideCommit`, `chasmLead`, `reach`, the `< 15` move
    /// horizon) is a distance standing in for a TIME — "how long do I have". That substitution was
    /// exact while every obstacle was pinned to the deck, and a Warden's closing hazards break it:
    /// a wall 30 m out closing at +20 m/s arrives in the time a static wall 18 m out would.
    ///
    /// So convert once, here, and leave every lead alone. `gap × v / (v + close)` is
    /// `timeToArrival × v`, which is **identically `gap` when `close == 0`** — so the bot's
    /// behaviour on ordinary track is not merely similar to before, it is bit-identical, and the
    /// 200-seed solvability proof and every daily-challenge golden are untouched.
    ///
    /// Note this deliberately reads `effectiveSpeed`, so it composes with chrono slow-mo the same
    /// way `GameCore.advanceClosingHazards` does: both sides scale by the same factor and the ratio
    /// is unchanged.
    static func effectiveArrival(_ o: CoreEntity, _ c: GameCore) -> Double {
        (o.d - c.distance) * closingRatio(o, c)
    }

    /// The factor that turns a real gap into an effective one. Exactly `1` for anything the spawner
    /// placed, which is what keeps ordinary play bit-identical. Exposed separately because the chasm
    /// needs it applied to its RIM rather than to its centre.
    /// **Both terms must carry the same chrono factor or they do not cancel.** `GameCore` advances a
    /// hazard's own motion by `hazardCloseScale`, so the denominator has to use the scaled closing
    /// speed against the already-scaled `effectiveSpeed`. Getting this wrong does not merely bias the
    /// bot slightly — it makes it read a closing chasm as nearer than it is, launch early into the
    /// catalogue's only two-sided window, and air-slam into the hole. Caught by the 200-seed proof.
    ///
    /// With it right, `d(effective)/dt` is exactly `−effectiveSpeed` — identical to a static
    /// obstacle — so every distance-as-time lead in this file keeps meaning what it meant.
    static func closingRatio(_ o: CoreEntity, _ c: GameCore) -> Double {
        guard o.closeSpeed > 0 else { return 1 }
        let v = max(0.001, c.effectiveSpeed)
        return v / (v + o.closeSpeed * c.hazardCloseScale)
    }

    static func decide(_ c: GameCore) -> Decision {
        // 1) Lane choice: score each lane by the distance to the nearest *blocking* obstacle
        //    (a tall in that lane, or a moving wall predicted to arrive over it). Higher = safer.
        var laneScore = [Double](repeating: .infinity, count: 3)   // distance to nearest upcoming tall
        var blockedNow = [Bool](repeating: false, count: 3)        // tall physically in the kill band
        for o in c.activeObstacles {
            // TWO different questions, and conflating them is a real bug rather than a rounding one.
            // "Is it physically on top of me right now" is asked of the REAL gap — a closing wall
            // 6 m away is 6 m away, whatever it is about to do. "How long have I got" is asked of
            // the effective gap. Identical for everything the spawner places (`closeSpeed == 0`).
            let realGap = o.d - c.distance
            let arrival = effectiveArrival(o, c)
            let lanes: [Int]
            switch o.kind {
            case .tall, .bolt:
                // A shot closes one lane exactly as a wall does — the bot needs no new rule for it,
                // only to be told it exists. Without this arm the `default: continue` below would
                // drop it silently and the bot would stand still while being shot. (v2.3)
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
            // REAL gap: this is a question about geometry, not about time.
            if realGap > -1.3 && realGap < 1.0 {
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

        // NOTE (v2.2): the two Warden-specific override blocks that used to live here and below
        // are GONE, and their absence is the clearest statement of what the rebuild did. v1.9–v2.1
        // needed them because a Warden's attacks were abstract shapes resolved on the player's own
        // plane — invisible to every line of obstacle logic in this file, so a bot inside an arena
        // scored every lane `.infinity`, settled on "stay put", and walked into every telegraph.
        //
        // A Warden now throws REAL obstacles onto the REAL deck. The lane scan above sees its walls,
        // the chasm logic below sees its holes, and the bar-slide commit below sees its hanging bars,
        // because they are the same entities the spawner places. The bot did not need to be taught
        // the boss; the boss was taught to speak the track.

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
            let realGap = o.d - c.distance
            let arrival = effectiveArrival(o, c)
            if o.kind == .chasm {
                // The rims are REAL geometry, so the extent is subtracted before the time
                // conversion — never after. "Am I over the void" is a question about where the
                // body is; "must I launch now" is a question about when the near rim gets here.
                let realLead = realGap - Tuning.chasmHalfLength    // leading rim
                let realTrail = realGap + Tuning.chasmHalfLength   // trailing rim
                if realLead <= 0 && realTrail > 0 { overChasm = true }
                let lead = realLead * closingRatio(o, c)
                if lead > 0 && lead <= reach { nearestChasmEdge = min(nearestChasmEdge, lead) }
                continue
            }
            guard arrival > 0, arrival <= reach else { continue }
            if o.kind == .bar || o.kind == .splitBar || o.kind == .hangingBar {
                // Sliding clears all three: a split bar in ANY lane, and a hanging bar from any
                // lane at all — a hanging bar has no top, so slide is not merely the cheap answer,
                // it is the ONLY one. The bot must never try to jump it, and it cannot: the jump
                // branch below only ever fires for a chasm or a low.
                nearestBar = min(nearestBar, arrival)
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
