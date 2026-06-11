import SwiftUI

/// Grid of procedural skins — tap to equip an owned one or buy with coins. Premium skins route to
/// the Shop (IAP). Reads the live `ProfileStore` so it updates as you buy/equip; the equip ring
/// animates between cards (SwiftUI diffs the stable card identities — no grid `.id` rebuild).
struct CharacterSelectView: View {
    let model: GameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let profile = ProfileStore.shared.profile
        MetaScreenScaffold(title: "Characters", coins: profile.coins, onClose: { model.closeSheet() }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(SkinCatalog.all) { skin in
                    SkinCard(
                        skin: skin,
                        owned: profile.ownedSkins.contains(skin.id),
                        equipped: profile.selectedSkin == skin.id,
                        affordable: profile.coins >= skin.cost
                    ) {
                        // Premium skins are bought in the Shop; a coin skin you can't afford is a
                        // denied tap (the card shakes). Returns whether the tap succeeded.
                        if skin.premium, !profile.ownedSkins.contains(skin.id) {
                            model.open(.shop)
                            return true
                        }
                        return model.buyOrEquipSkin(skin)
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3),
                       value: profile.selectedSkin)
        }
    }
}

private struct SkinCard: View {
    let skin: Skin
    let owned: Bool
    let equipped: Bool
    let affordable: Bool
    /// Returns false when the tap was denied (can't afford) → shake + red badge flash.
    let action: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0
    @State private var denied = false

    var body: some View {
        Button {
            guard !action() else { return }
            denied = true
            if reduceMotion {
                Task { try? await Task.sleep(for: .milliseconds(450)); denied = false }
            } else {
                withAnimation(.linear(duration: 0.4)) { shake += 1 }
                withAnimation(.easeOut(duration: 0.45)) { denied = false }
            }
        } label: {
            VStack(spacing: 10) {
                CharacterSwatch(bodyHex: skin.bodyHex, antennaHex: skin.antennaHex, followsWorld: skin.followsWorld, size: 62)
                    .frame(height: 96)
                Text(skin.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                status
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(ringColor, lineWidth: equipped || denied ? 2.5 : 1)
            )
        }
        .buttonStyle(.neon)
        .modifier(ShakeEffect(trigger: shake))
        .accessibilityIdentifier("skin_\(skin.id)")
        .accessibilityValue(equipped ? "equipped" : (owned ? "owned" : "locked"))
        .accessibilityHint(a11yHint)
    }

    private var ringColor: Color {
        if denied { return Color(red: 1, green: 0.37, blue: 0.37) }
        if equipped { return Theme.color(0x00F5FF) }
        return .white.opacity(0.12)
    }

    private var a11yHint: String {
        if equipped { return "" }
        if owned { return "Equips this skin" }
        if skin.premium { return "Opens the shop" }
        return affordable ? "Buys this skin for \(skin.cost) coins"
                          : "Costs \(skin.cost) coins — not enough coins"
    }

    @ViewBuilder private var status: some View {
        if equipped {
            label("EQUIPPED", Theme.color(0x00F5FF))
        } else if owned {
            label("TAP TO EQUIP", .white.opacity(0.7))
        } else if skin.premium {
            label("★ PREMIUM · SHOP", Theme.color(0xFFD23D))
        } else {
            CoinBadge(amount: skin.cost)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(denied
                                 ? Color(red: 1, green: 0.37, blue: 0.37)
                                 : (affordable ? .white : .white.opacity(0.45)))
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}
