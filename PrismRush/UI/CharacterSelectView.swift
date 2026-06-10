import SwiftUI

/// Grid of procedural skins — tap to equip an owned one or buy with coins. Premium skins are
/// unlocked in the Shop (IAP). Reads the live `ProfileStore` so it updates as you buy/equip.
struct CharacterSelectView: View {
    let model: GameModel

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
                        model.buyOrEquipSkin(skin)
                    }
                }
            }
        }
    }
}

private struct SkinCard: View {
    let skin: Skin
    let owned: Bool
    let equipped: Bool
    let affordable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                    .strokeBorder(equipped ? Theme.color(0x00F5FF) : .white.opacity(0.12),
                                  lineWidth: equipped ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var status: some View {
        if equipped {
            label("EQUIPPED", Theme.color(0x00F5FF))
        } else if owned {
            label("TAP TO EQUIP", .white.opacity(0.7))
        } else if skin.premium {
            label("★ PREMIUM", Theme.color(0xFFD23D))
        } else {
            CoinBadge(amount: skin.cost)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(affordable ? .white : .white.opacity(0.45))
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}
