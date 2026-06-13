import SwiftUI

/// Pre-run loadout chips on the hub: arm a consumable to bring into the NEXT run. Shown only when
/// the player owns at least one (no dead UI — decree 4). Reads `ProfileStore.shared` (counts) and
/// the `GameModel` (arm state + toggles) directly in `body` (G3). Armed chips glow; tapping toggles.
/// The armed consumables are spent at run start (`beginRun`), never on the competitive Daily run.
struct LoadoutStrip: View {
    let model: GameModel

    var body: some View {
        let p = ProfileStore.shared.profile
        let showHeadStart = p.headStartCharges > 0
        let showCoinSurge = p.coinSurgeCharges > 0
        return Group {
            if showHeadStart || showCoinSurge {
                HStack(spacing: Theme.Space.s) {
                    if showHeadStart {
                        chip(icon: "bolt.horizontal.fill", name: "HEAD START", count: p.headStartCharges,
                             tint: Theme.color(0xFF9F1C), armed: model.armedHeadStart,
                             action: { model.toggleHeadStart() },
                             a11y: "Head Start, \(p.headStartCharges) in stock. Launch the run with an overdrive boost.")
                    }
                    if showCoinSurge {
                        chip(icon: "dollarsign.circle.fill", name: "COIN SURGE", count: p.coinSurgeCharges,
                             tint: Theme.color(0xFFD23D), armed: model.armedCoinSurge,
                             action: { model.toggleCoinSurge() },
                             a11y: "Coin Surge, \(p.coinSurgeCharges) in stock. Doubles coins for the whole run.")
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
