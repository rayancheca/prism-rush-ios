import SwiftUI

/// In-app-purchase shop: coin packs (consumable) + Double Coins and premium skins (non-consumable).
/// Prices come from StoreKit when loaded, else the catalog fallback. Purchases grant via IAPManager.
/// Store states are surfaced explicitly: loading, unavailable (with retry), and inline errors.
struct ShopView: View {
    let model: GameModel
    private let iap = IAPManager.shared    // read directly so @Observable product loads re-render
    @State private var busy: String?
    @State private var successPulse = 0    // drives the purchase chime + success haptic

    @ScaledMetric(relativeTo: .footnote) private var copySize: CGFloat = 13

    var body: some View {
        let profile = ProfileStore.shared.profile
        MetaScreenScaffold(title: "Shop", coins: profile.coins, onClose: { model.closeSheet() }) {
            VStack(spacing: 14) {
                Text("Top up coins or unlock perks. Purchases restore automatically.")
                    .font(.system(size: copySize, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 2)

                storeStatus

                ForEach(IAPCatalog.products) { product in
                    ShopRow(
                        product: product,
                        price: iap.displayPrice(product.id),
                        owned: !product.isConsumable && profile.ownedProducts.contains(product.id),
                        busy: busy == product.id
                    ) {
                        buy(product.id)
                    }
                }
            }
        }
        .sensoryFeedback(trigger: successPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    private func buy(_ id: String) {
        guard busy == nil else { return }
        busy = id
        Task {
            // IAPManager retries the product load first when the catalog never arrived (offline
            // launch), so a tap with an empty store is a reload + purchase in one gesture.
            let ok = await iap.purchase(id)
            busy = nil
            if ok {
                successPulse += 1
                model.synth.play(.purchaseChime)
            }
        }
    }

    /// Loading / unavailable / error chrome above the product list.
    @ViewBuilder private var storeStatus: some View {
        if iap.isLoading, iap.products.isEmpty {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Loading prices…")
                    .font(.system(size: copySize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Loading store prices")
        } else if iap.hasLoaded, iap.products.isEmpty {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 15, weight: .bold))
                    Text("Store unavailable")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.4))
                if let error = iap.lastError {
                    Text(error)
                        .font(.system(size: copySize - 1, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    Task { await iap.loadProducts() }
                } label: {
                    Text("RETRY")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 9)
                        .background(Theme.actionGradient, in: Capsule())
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("storeRetryButton")
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(red: 1, green: 0.55, blue: 0.4).opacity(0.4)))
        } else if let error = iap.lastError {
            // Products are present but the last purchase/restore failed — inline, dismissible by retrying.
            Text(error)
                .font(.system(size: copySize - 1, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(red: 1, green: 0.55, blue: 0.4).opacity(0.35)))
                .accessibilityLabel("Store error: \(error)")
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
                    .background(Theme.actionGradient, in: Capsule())
                }
                .buttonStyle(.neon)
                .disabled(busy)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(owned ? [] : .isButton)
        .accessibilityAction { if !owned, !busy { action() } }
    }

    private var a11yLabel: String {
        if owned { return "\(product.title). \(product.blurb). Owned." }
        if busy { return "\(product.title). Purchasing." }
        return "\(product.title). \(product.blurb). Buy for \(price)."
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
