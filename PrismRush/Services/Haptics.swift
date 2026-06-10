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
    var enabled = true

    func prepare() {
        light.prepare(); medium.prepare(); selection.prepare()
    }

    /// Advance the internal clock (used to rate-limit the gem tick).
    func tick(_ dt: Double) { clock += dt }

    func handle(_ fx: FXEvent) {
        guard enabled else { return }
        switch fx {
        case .laneChanged:
            light.impactOccurred(intensity: 0.7)
        case .jumped:
            light.impactOccurred(intensity: 0.9)
        case .landed:
            medium.impactOccurred()
        case .gemCollected:
            if clock - lastGem > 0.06 { selection.selectionChanged(); lastGem = clock }
        case .pickup:
            notify.notificationOccurred(.success)
        case .nearMiss:
            rigid.impactOccurred(intensity: 0.8)
        case .shieldAbsorbed:
            notify.notificationOccurred(.warning)
        case .died:
            notify.notificationOccurred(.error)
            heavy.impactOccurred()
        case .slid, .worldChanged:
            break
        }
    }
}
