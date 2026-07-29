import UIKit

/// Maps gameplay effects to haptics using `UIFeedbackGenerator` (the documented fallback path;
/// robust and sufficient for v1). No-ops on hardware without a Taptic Engine (e.g. the simulator).
@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notify = UINotificationFeedbackGenerator()

    private var clock: Double = 0
    private var lastGem: Double = -1
    private var prepareT: Double = 0
    var enabled = true

    /// Warm every generator. The Taptic Engine's prepared state decays after a couple of idle
    /// seconds, so `tick` calls this periodically during live play to keep impacts low-latency.
    func prepare() {
        light.prepare(); medium.prepare(); rigid.prepare()
        heavy.prepare(); selection.prepare(); notify.prepare()
    }

    /// Advance the internal clock (used to rate-limit the gem tick). While `playing`, re-prepare
    /// all generators every few seconds (no-op cost when already prepared; idle in menus).
    func tick(_ dt: Double, playing: Bool = false) {
        clock += dt
        guard playing else { prepareT = 0; return }
        prepareT -= dt
        if prepareT <= 0 { prepare(); prepareT = 6 }
    }

    func handle(_ fx: FXEvent) {
        guard enabled else { return }
        switch fx {
        case .laneChanged:
            light.impactOccurred(intensity: 0.7)
        case .jumped:
            light.impactOccurred(intensity: 0.9)
        case .landed:
            medium.impactOccurred()
        case .slid:
            medium.impactOccurred(intensity: 0.7)
        case .gemCollected:
            if clock - lastGem > 0.06 { selection.selectionChanged(); lastGem = clock }
        case .pickup:
            notify.notificationOccurred(.success)
        case .nearMiss:
            rigid.impactOccurred(intensity: 0.8)
        case .shieldAbsorbed:
            notify.notificationOccurred(.error)   // a hard knock — the shield just shattered
            heavy.impactOccurred()
        case .died:
            notify.notificationOccurred(.error)
            heavy.impactOccurred()

        // MARK: Wardens (v1.9)
        //
        // The telegraph gets its own distinct tap on purpose: it is the one Warden event the player
        // must act on, and a cue they can feel means they can start moving before their eyes have
        // finished parsing which lanes are lit. Arrival and defeat are announcements, so they get
        // the same double-tap grammar as a world change.
        case .wardenTelegraph:
            rigid.impactOccurred(intensity: 0.65)
        case let .wardenStruck(_, caught):
            if caught {
                notify.notificationOccurred(.error)
                heavy.impactOccurred()
            } else {
                medium.impactOccurred(intensity: 0.8)   // a clean dodge lands a hit — it should thump
            }
        case .wardenArrived:
            heavy.impactOccurred(intensity: 0.9)
        case .wardenShieldBroke:
            rigid.impactOccurred(intensity: 1.0)
        case .wardenCoreHit:
            rigid.impactOccurred(intensity: 0.85)
        case .wardenDefeated:
            notify.notificationOccurred(.success)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                self?.heavy.impactOccurred()
            }
        case .wardenBrokeOff:
            light.impactOccurred(intensity: 0.5)   // it gives up: a soft release, not a punishment
        case .worldChanged:
            // Double-tap: a hard hit now, a lighter echo a beat later (UIFeedbackGenerator has no
            // pattern API; a short MainActor sleep is the documented-safe equivalent).
            rigid.impactOccurred(intensity: 1.0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                self?.rigid.impactOccurred(intensity: 0.6)
            }
        case .chronoEnded:
            light.impactOccurred(intensity: 0.5)   // soft "time resumes" tap
        case .sneakersEnded:
            light.impactOccurred(intensity: 0.45)  // soft "spring fades" tap
        // v1.3 mechanic map (R17): ring = light, perfect/boost = medium, flow surge = success.
        case let .ringPassed(_, _, perfect):
            if perfect { medium.impactOccurred() } else { light.impactOccurred(intensity: 0.8) }
        case .boostStarted:
            medium.impactOccurred()
        case .boostEnded:
            break   // the speed restore is its own feedback — no haptic on the down-edge
        case .flowSurge:
            notify.notificationOccurred(.success)
        }
    }

    /// Level-up / character-grant celebration (R17 success class). Not an `FXEvent` — the level
    /// outcome only exists after `applyRunSummary`, so GameView calls this directly.
    func levelUp() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }
}
