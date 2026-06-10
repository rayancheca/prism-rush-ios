import SwiftUI

/// In-app-purchase shop: coin packs (consumable) + Double Coins and premium skins (non-consumable).
/// Prices come from StoreKit when loaded, else the catalog fallback. Purchases grant via IAPManager.
struct ShopView: View {
    let model: GameModel
    private let iap = IAPManager.shared    // read directly so @Observable product loads re-render
    @State private var busy: String?

    var body: some View {
        let profile = ProfileStore.shared.profile
        MetaScreenScaffold(title: "Shop", coins: profile.coins, onClose: { model.closeSheet() }) {
            VStack(spacing: 14) {
                Text("Top up coins or unlock perks. Purchases restore automatically.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 2)

                ForEach(IAPCatalog.products) { product in
                    ShopRow(
                        product: product,
                        price: iap.displayPrice(product.id),
                        owned: !product.isConsumable && profile.ownedProducts.contains(product.id),
                        busy: busy == product.id
                    ) {
                        busy = product.id
                        Task { await iap.purchase(product.id); busy = nil }
                    }
                }
            }
        }
    }
}

private struct ShopRow: View {
    let product: IAPProduct
    let price: String
    let owned: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(product.blurb).font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if owned {
                Text("OWNED")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.color(0x00F5FF))
            } else {
                Button(action: action) {
                    Group {
                        if busy { ProgressView().tint(.black) }
                        else { Text(price).font(.system(size: 14, weight: .heavy, design: .rounded)) }
                    }
                    .foregroundStyle(.black)
                    .frame(minWidth: 64)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient(colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6)],
                                               startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
    }

    @ViewBuilder private var icon: some View {
        switch product.kind {
        case .coins:
            CoinGlyph(size: 34)
        case .doubleCoins:
            ZStack {
                CoinGlyph(size: 34)
                Text("2×").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.black)
            }
        case .skin(let id):
            let skin = SkinCatalog.skin(id)
            CharacterSwatch(bodyHex: skin.bodyHex == 0 ? 0x00FFC8 : skin.bodyHex, antennaHex: skin.antennaHex, followsWorld: false, size: 30)
        }
    }
}
