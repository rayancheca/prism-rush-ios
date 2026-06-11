import SwiftUI

/// The shop, reframed as a 4-section board (uiux §4): FEATURED (UTC-day rotation), COINS (three
/// compact pack cards), PERKS (Double Coins), and CHARACTERS (the coin roster as a rail — five
/// IAPs become ~12 visible items with two currencies, no new SKUs). StoreKit outages degrade ONLY
/// the StoreKit-priced sections; coin characters stay shoppable. Reads `IAPManager.shared` /
/// `ProfileStore.shared` directly in `body` (G3).
struct ShopView: View {
    let model: GameModel
    private let iap = IAPManager.shared    // read directly so @Observable product loads re-render
    @State private var busy: String?
    @State private var successPulse = 0    // drives the purchase chime + success haptic

    /// Featured rotation pool, in catalog terms: skins by id + the Double Coins perk.
    private static let featuredPool = ["aurora", "doubleCoins", "midas", "toxic", "mono"]

    var body: some View {
        MetaScreenScaffold(title: "Shop", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if storeLoading {
                    loadingRow
                } else if storeOffline {
                    // Sections 1–3 collapse into one banner; coin characters below still work.
                    offlineBanner
                } else {
                    if let error = iap.lastError { inlineErrorStrip(error) }
                    featuredSection
                    coinsSection
                    perksSection
                }
                charactersSection
            }
        }
        .sensoryFeedback(trigger: successPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    // MARK: store state

    private var storeOffline: Bool { iap.hasLoaded && iap.products.isEmpty }
    private var storeLoading: Bool { iap.isLoading && iap.products.isEmpty }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Loading prices…")
                .typeScale(.body)
                .foregroundStyle(Theme.Role.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
        .neonCard()
        .accessibilityLabel("Loading store prices")
    }

    /// Store-unavailable fallback, integrated (uiux §4.2): one compact banner instead of a
    /// whole-screen wifi void — the coin-priced characters below remain fully shoppable.
    private var offlineBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                Text("Store is offline — coin items still work")
                    .typeScale(.body)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Theme.Role.danger)
            if let error = iap.lastError {
                Text(error)
                    .typeScale(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Role.textSecondary)
            }
            Button {
                Task { await iap.loadProducts() }
            } label: {
                Text("RETRY")
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.interactive)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(Theme.Role.interactive, lineWidth: 1.5))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("storeRetryButton")
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.m)
        .neonCard(radius: Theme.Radius.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Store offline. Coin purchases still available.")
    }

    /// Purchase/restore failure as a dismissible-by-retry inline strip, never a modal (uiux §4.2).
    private func inlineErrorStrip(_ error: String) -> some View {
        Text(error)
            .typeScale(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Role.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, Theme.Space.m)
            .neonCard()
            .accessibilityLabel("Store error: \(error)")
    }

    // MARK: section 1 — FEATURED (UTC-day rotation)

    /// Today's feature: first non-owned item from a UTC-day-seeded shuffle of the pool — UI-local
    /// SplitMix64, never feeds run RNG (rule 2). All owned → the medium coin pack.
    private var featuredID: String {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(ProfileStore.daysSinceEpoch(Date()))))
        var pool = Self.featuredPool
        for i in (1..<pool.count).reversed() { pool.swapAt(i, rng.int(0, i)) }
        let p = ProfileStore.shared.profile
        let pick = pool.first { id in
            id == "doubleCoins" ? !p.doubleCoins : !p.ownedSkins.contains(id)
        }
        return pick ?? "coins.medium"
    }

    @ViewBuilder private var featuredSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("FEATURED")
            featuredCard(id: featuredID)
        }
    }

    @ViewBuilder private func featuredCard(id: String) -> some View {
        switch id {
        case "doubleCoins":
            featuredShell(title: "Double Coins", blurb: "Earn 2× coins, forever.",
                          preview: AnyView(doubleCoinsGlyph(size: 56)),
                          pill: AnyView(storePricePill(productID: Self.doublerID)),
                          a11y: "Today's feature: Double Coins. Earn two times coins, forever.") {
                buy(Self.doublerID)
            }
        case "coins.medium":
            featuredShell(title: "Bag of Coins", blurb: "7,000 coins — the collector's top-up.",
                          preview: AnyView(coinStack(3, size: 26)),
                          pill: AnyView(storePricePill(productID: Self.mediumPackID)),
                          a11y: "Today's feature: Bag of Coins, 7,000 coins.") {
                buy(Self.mediumPackID)
            }
        case "aurora":
            let skin = SkinCatalog.skin("aurora")
            featuredShell(title: skin.name, blurb: skin.flavor,
                          preview: AnyView(AnimatedCharacterSwatch(skin: skin, size: 52)),
                          pill: AnyView(storePricePill(productID: Self.auroraID)),
                          a11y: "Today's feature: \(skin.name), premium character.") {
                buy(Self.auroraID)
            }
        default:
            // Coin-priced character: the shop never charges coins without showing the stage —
            // the tap routes to Characters for the preview-before-buy commit (uiux §4.1).
            let skin = SkinCatalog.skin(id)
            featuredShell(title: skin.name, blurb: skin.flavor,
                          preview: AnyView(AnimatedCharacterSwatch(skin: skin, size: 52)),
                          pill: AnyView(coinPricePill(skin.cost)),
                          a11y: "Today's feature: \(skin.name), \(skin.cost) coins. Opens characters to preview.") {
                model.open(.characters, focusSkin: skin.id)   // stage THAT skin (uiux §4.1)
            }
        }
    }

    /// Shared featured-card chrome: 120 pt spotlight, preview left, copy + price pill right,
    /// TODAY'S FEATURE corner tag. The pill carries the section's actionGradient budget.
    private func featuredShell(title: String, blurb: String, preview: AnyView, pill: AnyView,
                               a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                preview.frame(width: 72)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .typeScale(.title)
                        .foregroundStyle(Theme.Role.textPrimary)
                    Text(blurb)
                        .typeScale(.body)
                        .foregroundStyle(Theme.Role.textSecondary)
                        .lineLimit(2)
                    pill.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .neonCard(radius: Theme.Radius.l, raised: true)
            .overlay(alignment: .topTrailing) {
                Text("TODAY'S FEATURE")
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .padding(Theme.Space.s)
            }
        }
        .buttonStyle(.neon)
        .disabled(busy != nil)
        .accessibilityIdentifier("shopFeatured")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    // MARK: section 2 — COINS (three compact cards in a row)

    @ViewBuilder private var coinsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("COINS")
            HStack(spacing: Theme.Space.s) {
                ForEach(Array(coinPacks.enumerated()), id: \.element.id) { idx, product in
                    coinPackCard(product, stack: idx + 1, bestValue: idx == coinPacks.count - 1)
                }
            }
        }
    }

    private var coinPacks: [IAPProduct] { IAPCatalog.products.filter(\.isConsumable) }

    private func coinPackCard(_ product: IAPProduct, stack: Int, bestValue: Bool) -> some View {
        let amount: Int = { if case .coins(let n) = product.kind { return n } else { return 0 } }()
        return Button { buy(product.id) } label: {
            VStack(spacing: Theme.Space.s) {
                coinStack(stack, size: 18)
                    .frame(height: 26)
                Text(amount.formatted())
                    .typeScale(.heading)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.reward)
                Group {
                    if busy == product.id { ProgressView().tint(.white) }
                    else {
                        Text(iap.displayPrice(product.id))
                            .typeScale(.caption)
                            .foregroundStyle(Theme.Role.textPrimary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.Role.surfaceHi, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Role.hairline))
                if ProfileStore.shared.profile.doubleCoins {
                    Text("EARNS 2× IN RUNS")
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .neonCard()
            .overlay(alignment: .top) {
                if bestValue {
                    Text("BEST VALUE")
                        .typeScale(.micro)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.Role.reward, in: Capsule())
                        .offset(y: -8)
                }
            }
        }
        .buttonStyle(.neon)
        .disabled(busy != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.title), \(amount) coins."
                            + (bestValue ? " Best value." : "")
                            + " Buy for \(iap.displayPrice(product.id)).")
    }

    // MARK: section 3 — PERKS

    @ViewBuilder private var perksSection: some View {
        let owned = ProfileStore.shared.profile.doubleCoins
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("PERKS")
            HStack(spacing: Theme.Space.m) {
                doubleCoinsGlyph(size: 40).frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Double Coins")
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.textPrimary)
                    Text("Earn 2× coins, forever")
                        .typeScale(.body)
                        .foregroundStyle(Theme.Role.textSecondary)
                }
                Spacer()
                if owned {
                    // Owned rows stay visible — status, not a ghost (uiux §4.1).
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("OWNED").typeScale(.caption)
                    }
                    .foregroundStyle(Theme.Role.interactive)
                } else {
                    Button { buy(Self.doublerID) } label: {
                        Group {
                            if busy == Self.doublerID { ProgressView().tint(.white) }
                            else {
                                Text(iap.displayPrice(Self.doublerID))
                                    .typeScale(.caption)
                                    .foregroundStyle(Theme.Role.textPrimary)
                            }
                        }
                        .frame(minWidth: 56)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.Role.surfaceHi, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Role.hairline))
                    }
                    .buttonStyle(.neon)
                    .disabled(busy != nil)
                }
            }
            .padding(Theme.Space.m)
            .neonCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(owned
                                ? "Double Coins. Earn two times coins, forever. Owned."
                                : "Double Coins. Earn two times coins, forever. Buy for \(iap.displayPrice(Self.doublerID)).")
            .accessibilityAddTraits(owned ? [] : .isButton)
            .accessibilityAction { if !owned, busy == nil { buy(Self.doublerID) } }
        }
    }

    // MARK: section 4 — CHARACTERS (the collection IS the storefront)

    /// Coin-priced roster + premium Aurora as 96×128 rail cards. Tap → CharacterSelect, where the
    /// stage previews before any coins move (the shop never charges coins blind, uiux §4.1).
    @ViewBuilder private var charactersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("CHARACTERS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(railSkins) { skin in
                        miniSkinCard(skin)
                    }
                    allCharactersCard
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var railSkins: [Skin] {
        let coins = SkinCatalog.all
            .filter { if case .coins = $0.unlock { return true }; return false }
            .sorted { $0.cost < $1.cost }
        let premium = SkinCatalog.all.filter { $0.unlock == .iap }
        return coins + premium
    }

    private func miniSkinCard(_ skin: Skin) -> some View {
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        let equipped = ProfileStore.shared.profile.selectedSkin == skin.id
        // Tap → CharacterSelect focused to THIS skin (uiux §4.1) — never the equipped one.
        return Button { model.open(.characters, focusSkin: skin.id) } label: {
            VStack(spacing: Theme.Space.xs) {
                AnimatedCharacterSwatch(skin: skin, size: 42)
                Text(skin.name.uppercased())
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textPrimary)
                    .lineLimit(1)
                Group {
                    if equipped {
                        Label("EQUIPPED", systemImage: "checkmark")
                            .labelStyle(.titleOnly)
                            .foregroundStyle(Theme.Role.interactive)
                    } else if owned {
                        Text("OWNED").foregroundStyle(Theme.Role.interactive)
                    } else if skin.premium {
                        Text(iap.displayPrice(Self.auroraID)).foregroundStyle(Theme.Role.textSecondary)
                    } else {
                        HStack(spacing: 3) {
                            CoinGlyph(size: 9)
                            Text(skin.cost.formatted()).foregroundStyle(Theme.Role.reward)
                        }
                    }
                }
                .typeScale(.micro)
                .monospacedDigit()
            }
            .frame(width: 96, height: 128)
            .neonCard()
            .overlay {
                if equipped {
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .strokeBorder(Theme.Role.interactive, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("shopSkin_\(skin.id)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(railA11y(skin, owned: owned, equipped: equipped))
        .accessibilityHint("Shows the preview in characters.")
    }

    private func railA11y(_ skin: Skin, owned: Bool, equipped: Bool) -> String {
        if equipped { return "\(skin.name). Equipped." }
        if owned { return "\(skin.name). Owned." }
        if skin.premium { return "\(skin.name). Premium, \(iap.displayPrice(Self.auroraID))." }
        return "\(skin.name). \(skin.cost) coins."
    }

    private var allCharactersCard: some View {
        Button { model.open(.characters) } label: {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Role.textSecondary)
                Text("ALL\nCHARACTERS ›")
                    .typeScale(.micro)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Role.textSecondary)
            }
            .frame(width: 96, height: 128)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(Theme.Role.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("allCharactersCard")
        .accessibilityLabel("All characters")
        .accessibilityHint("Opens the character collection.")
    }

    // MARK: shared bits

    private static let doublerID = "com.rayancheca.prismrush.doublecoins"
    private static let mediumPackID = "com.rayancheca.prismrush.coins.medium"
    private static let auroraID = "com.rayancheca.prismrush.skin.aurora"

    private func kicker(_ text: String) -> some View {
        Text(text)
            .typeScale(.micro)
            .foregroundStyle(Theme.Role.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }

    /// StoreKit price on the actionGradient pill (the screen's single gradient allowance).
    private func storePricePill(productID: String) -> some View {
        Group {
            if busy == productID { ProgressView().tint(.black) }
            else {
                Text(iap.displayPrice(productID))
                    .typeScale(.caption)
                    .foregroundStyle(.black)
            }
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.actionGradient, in: Capsule())
    }

    private func coinPricePill(_ cost: Int) -> some View {
        HStack(spacing: 5) {
            CoinGlyph(size: 12)
            Text(cost.formatted())
                .typeScale(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Role.reward)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.Role.surfaceHi, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Role.reward.opacity(0.45)))
    }

    private func coinStack(_ count: Int, size: CGFloat) -> some View {
        HStack(spacing: -size * 0.45) {
            ForEach(0..<count, id: \.self) { i in
                CoinGlyph(size: size).offset(y: CGFloat(i % 2) * -size * 0.15)
            }
        }
        .accessibilityHidden(true)
    }

    private func doubleCoinsGlyph(size: CGFloat) -> some View {
        ZStack {
            CoinGlyph(size: size)
            Text("2×")
                .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
        .accessibilityHidden(true)
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
}
