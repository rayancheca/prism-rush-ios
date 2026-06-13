import SwiftUI

/// Pre-run loadout chips on the hub: arm a consumable to bring into the NEXT run. Shown only when
/// the player owns at least one (no dead UI — decree 4). Reads `ProfileStore.shared` (counts) and
/// the `GameModel` (arm state + toggles) directly in `body` (G3). Armed chips glow; tapping toggles.
/// The armed consumables are spent at run start (`beginRun`), never on the competitive Daily run.
struct LoadoutStrip: View {
    let model: GameModel

    var body: some View {
        // Scalar reads at point of use (G3 — never snapshot the whole `profile` into a let).
        let headStart = ProfileStore.shared.profile.headStartCharges
        let coinSurge = ProfileStore.shared.profile.coinSurgeCharges
        return Group {
            if headStart > 0 || coinSurge > 0 {
                HStack(spacing: Theme.Space.s) {
                    if headStart > 0 {
                        chip(icon: "bolt.horizontal.fill", name: "HEAD START", count: headStart,
                             tint: Theme.color(0xFF9F1C), armed: model.armedHeadStart,
                             action: { model.toggleHeadStart() },
                             a11y: "Head Start, \(headStart) in stock. Launch the run with an overdrive boost.")
                    }
                    if coinSurge > 0 {
                        chip(icon: "dollarsign.circle.fill", name: "COIN SURGE", count: coinSurge,
                             tint: Theme.color(0xFFD23D), armed: model.armedCoinSurge,
                             action: { model.toggleCoinSurge() },
                             a11y: "Coin Surge, \(coinSurge) in stock. Doubles coins for the whole run.")
                    }
                }
            }
        }
    }

    private func chip(icon: String, name: String, count: Int, tint: Color, armed: Bool,
                      action: @escaping () -> Void, a11y: String) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: armed ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 13, weight: .bold))
                Text(armed ? "ARMED" : name).typeScale(.micro)
                Text("×\(count)").typeScale(.micro).monospacedDigit().opacity(0.8)
            }
            .foregroundStyle(armed ? AnyShapeStyle(.black) : AnyShapeStyle(tint))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(armed ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.Role.surface), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(armed ? 0 : 0.5), lineWidth: 1))
            .shadow(color: armed ? tint.opacity(0.55) : .clear, radius: 8)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.neon)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(armed ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(a11y)
        .accessibilityHint(armed ? "Armed for the next run. Tap to put it away." : "Tap to arm it for the next run.")
    }
}
