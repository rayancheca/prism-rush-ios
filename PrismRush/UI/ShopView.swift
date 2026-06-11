import SwiftUI

/// The shop, reframed for conversion (v1.4.1): a HERO offer slot (Double Coins → Starter Bundle →
/// featured-skin rotation), COIN PACKS as a 2×2 value grid with COMPUTED value badges (price or
/// coin edits can never desync them; one curated BALANCED PICK tag — no fabricated popularity
/// claims), PERKS with owned state, the CHARACTERS rail, and a trust
/// line. Pre-launch store states are honest: loading shimmers over fallback prices, a store that
/// isn't configured in App Store Connect yet shows a quiet footnote (no red banner, no retry
/// spam), and only a genuinely unreachable App Store gets the neutral retry card — coin-priced
/// items work in every state. Reads `IAPManager.shared` / `ProfileStore.shared` directly in
/// `body` (G3).
struct ShopView: View {
    let model: GameModel
    private let iap = IAPManager.shared    // read directly so @Observable product loads re-render
    @State private var busy: String?
    @State private var successPulse = 0    // drives the purchase chime + success haptic
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    /// Featured rotation pool (hero priority 3): premium + coin skins by id. Double Coins left
    /// the pool — it owns hero priority 1 outright until purchased.
    private static let featuredPool = ["aurora", "midas", "toxic", "mono"]

    var body: some View {
        MetaScreenScaffold(title: "Shop", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if iap.availability == .offline { offlineCard }
                if iap.availability == .ready, let error = iap.lastError { inlineErrorStrip(error) }
                heroSection
                if showsStarterCard { starterOfferCard }
                coinsSection
                if showsPerksSection { perksSection }
                charactersSection
                footer
            }
        }
        .overlay(alignment: .bottom) {
            if let toast { toastView(toast) }
        }
        .onAppear { iap.refreshIfUnavailable() }   // the one sheet-open re-check (no retry spam)
        .sensoryFeedback(trigger: successPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    // MARK: store states (v1.4.1 — loading / ready / notConfigured / offline)

    private var isShimmering: Bool { iap.availability == .loading }

    /// Offline = the load THREW. Neutral card (no danger red — nothing is the player's fault),
    /// manual RETRY on top of the manager's own backoff. Everything below stays shoppable.
    private var offlineCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                Text("App Store unreachable — coin shop still open")
                    .typeScale(.body)
            }
            .foregroundStyle(Theme.Role.textSecondary)
            Button {
                iap.retryNow()
            } label: {
                Group {
                    if iap.isLoading { ProgressView().tint(.white) }
                    else { Text("RETRY").typeScale(.caption).foregroundStyle(Theme.Role.interactive) }
                }
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
        .accessibilityLabel("App Store unreachable. The coin shop is still open.")
    }

    /// Purchase/restore failure as a dismissible-by-retry inline strip, never a modal (uiux §4.2).
    /// Rendered in the READY state only — pre-launch states use the friendly toast instead.
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

    private func toastView(_ text: String) -> some View {
        Text(text)
            .typeScale(.body)
            .foregroundStyle(Theme.Role.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
            .neonCard(radius: Theme.Radius.l, raised: true)
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("shopToast")
    }

    // MARK: hero slot — the highest-leverage offer (uiux: one spotlight, never a wall)

    private enum HeroOffer: Equatable { case doubler, starter, rotation(String) }

    private var heroOffer: HeroOffer {
        let p = ProfileStore.shared.profile
        if !p.doubleCoins { return .doubler }
        if starterOfferAvailable { return .starter }
        return .rotation(featuredID)
    }

    /// The one-time offer shows only while NO purchase exists AND no starter purchase is sitting
    /// in ask-to-buy limbo — a "FIRST PURCHASE OFFER" must never queue a second pending charge
    /// (v1.4.1 review; the rare cross-device pre-iCloud-sync window is accepted).
    private var starterOfferAvailable: Bool {
        ProfileStore.shared.profile.totalIAPPurchases == 0
            && !iap.isPendingApproval(IAPCatalog.starterID)
    }

    /// Today's rotation pick: first non-owned skin from a UTC-day-seeded shuffle of the pool —
    /// UI-local SplitMix64, never feeds run RNG (rule 2). All owned → the medium coin pack.
    private var featuredID: String {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(ProfileStore.daysSinceEpoch(Date()))))
        var pool = Self.featuredPool
        for i in (1..<pool.count).reversed() { pool.swapAt(i, rng.int(0, i)) }
        let p = ProfileStore.shared.profile
        return pool.first { !p.ownedSkins.contains($0) } ?? "coins.medium"
    }

    @ViewBuilder private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            switch heroOffer {
            case .doubler:
                kicker("PERMANENT PERK")
                heroShell(title: "Double Coins", blurb: "Every run pays double. Forever.",
                          preview: AnyView(doubleCoinsGlyph(size: 56)),
                          pill: AnyView(goldPricePill(productID: Self.doublerID)),
                          tag: "ONE PURCHASE · EVERY RUN",
                          a11y: "Double Coins. Every run pays double, forever. Buy for \(iap.displayPrice(Self.doublerID)).") {
                    buy(Self.doublerID)
                }
            case .starter:
                kicker("FIRST PURCHASE OFFER")
                heroShell(title: "Starter Bundle", blurb: starterBlurb,
                          preview: AnyView(coinStack(2, size: 26)),
                          pill: AnyView(goldPricePill(productID: IAPCatalog.starterID)),
                          tag: "FIRST PURCHASE",
                          a11y: "Starter Bundle. \(starterBlurb) Buy for \(iap.displayPrice(IAPCatalog.starterID)).") {
                    buy(IAPCatalog.starterID)
                }
            case .rotation(let id):
                kicker("FEATURED")
                rotationHero(id: id)
            }
        }
    }

    @ViewBuilder private func rotationHero(id: String) -> some View {
        switch id {
        case "coins.medium":
            heroShell(title: "Bag of Coins", blurb: "7,000 coins — the collector's top-up.",
                      preview: AnyView(coinStack(3, size: 26)),
                      pill: AnyView(goldPricePill(productID: Self.mediumPackID)),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: Bag of Coins, 7,000 coins.") {
                buy(Self.mediumPackID)
            }
        case "aurora":
            let skin = SkinCatalog.skin("aurora")
            heroShell(title: skin.name, blurb: skin.flavor,
                      preview: AnyView(AnimatedCharacterSwatch(skin: skin, size: 52)),
                      pill: AnyView(goldPricePill(productID: Self.auroraID)),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: \(skin.name), premium character.") {
                buy(Self.auroraID)
            }
        default:
            // Coin-priced character: the shop never charges coins without showing the stage —
            // the tap routes to Characters for the preview-before-buy commit (uiux §4.1).
            let skin = SkinCatalog.skin(id)
            heroShell(title: skin.name, blurb: skin.flavor,
                      preview: AnyView(AnimatedCharacterSwatch(skin: skin, size: 52)),
                      pill: AnyView(coinPricePill(skin.cost)),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: \(skin.name), \(skin.cost) coins. Opens characters to preview.") {
                model.open(.characters, focusSkin: skin.id)   // stage THAT skin (uiux §4.1)
            }
        }
    }

    /// Shared hero chrome: 120 pt spotlight, preview left, copy + price pill right, corner tag.
    /// The pill carries the screen's gold/claim gradient (money language — gradient law: no new
    /// gradient family on this screen).
    private func heroShell(title: String, blurb: String, preview: AnyView, pill: AnyView,
                           tag: String, a11y: String, action: @escaping () -> Void) -> some View {
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
                Text(tag)
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .padding(Theme.Space.s)
            }
        }
        .buttonStyle(.neon)
        .disabled(busy != nil)
        .accessibilityIdentifier("shopHero")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    // MARK: starter offer (own card when the hero slot is taken by Double Coins)

    private var showsStarterCard: Bool {
        starterOfferAvailable && heroOffer != .starter
    }

    private var starterBlurb: String {
        let base = IAPCatalog.product(IAPCatalog.starterID)?.coinAmount ?? 0
        guard firstPurchaseBonusEligible else { return "\(base.formatted()) coins to kickstart the roster." }
        let payout = ProfileStore.coinPackPayout(base: base, bonusUsed: false)
        return "\(base.formatted()) → \(payout.formatted()) with the +50% bonus."
    }

    private var starterOfferCard: some View {
        Button { buy(IAPCatalog.starterID) } label: {
            HStack(spacing: Theme.Space.m) {
                coinStack(2, size: 22).frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Starter Bundle")
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.textPrimary)
                    Text(starterBlurb)
                        .typeScale(.body)
                        .foregroundStyle(Theme.Role.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                goldPricePill(productID: IAPCatalog.starterID)
            }
            .padding(Theme.Space.m)
            .padding(.top, 6)   // room for the corner tag above the title
            .neonCard()
            .overlay(alignment: .topTrailing) {
                Text("FIRST PURCHASE OFFER")
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.reward)
                    .padding(Theme.Space.s)
            }
        }
        .buttonStyle(.neon)
        .disabled(busy != nil)
        .accessibilityIdentifier("starterCard")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starter Bundle, first purchase offer. \(starterBlurb) Buy for \(iap.displayPrice(IAPCatalog.starterID)).")
    }

    // MARK: coin packs — tight 2×2 grid with computed value framing

    /// The four standing packs, cheapest first. The starter SKU is the offer slot, never a grid cell.
    private var coinPacks: [IAPProduct] {
        IAPCatalog.products
            .filter { $0.isConsumable && $0.id != IAPCatalog.starterID }
            .sorted { $0.coinAmount < $1.coinAmount }
    }

    @ViewBuilder private var coinsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("COIN PACKS")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.s),
                                GridItem(.flexible(), spacing: Theme.Space.s)],
                      spacing: Theme.Space.m) {
                ForEach(Array(coinPacks.enumerated()), id: \.element.id) { idx, product in
                    coinPackCard(product, stack: idx + 1)
                }
            }
            .padding(.top, 6)   // breathing room for the -8pt badge overhang on row 1
        }
    }

    /// Per-pack value framing, COMPUTED from the catalog + prices (never hardcoded, so a price
    /// or coin-amount edit can't desync a badge): the cheapest pack is the baseline, the best
    /// coins-per-price pack wins BEST VALUE, everything else better than baseline gets its
    /// computed +N% BONUS. The designated mid pack carries the curated BALANCED PICK tag — a
    /// claim that is true by construction; never a fabricated popularity stat in a pre-launch
    /// app (Decree 5: monetization is honest, v1.4.1 review).
    private enum PackBadge: Equatable { case none, bonus(Int), balancedPick, bestValue }

    /// Coins-per-price from a UNIFORM price source per render: live storefront prices only once
    /// the FULL catalog is loaded (`.ready`), otherwise the USD fallbacks for EVERY pack. A
    /// partial load on a non-USD storefront must never mix currencies across packs — that could
    /// crown the wrong BEST VALUE and break the +N% math (v1.4.1 review).
    private func coinsPerUnit(_ p: IAPProduct) -> Double {
        let price = iap.availability == .ready
            ? (iap.priceValue(p.id) ?? p.fallbackValue)
            : p.fallbackValue
        return price > 0 ? Double(p.coinAmount) / price : 0
    }

    private func badge(for pack: IAPProduct) -> PackBadge {
        let packs = coinPacks
        guard let baseline = packs.first, pack.id != baseline.id,
              let best = packs.max(by: { coinsPerUnit($0) < coinsPerUnit($1) }) else { return .none }
        if pack.id == best.id { return .bestValue }
        if pack.id == Self.mediumPackID { return .balancedPick }
        let pct = Int((((coinsPerUnit(pack) / max(coinsPerUnit(baseline), 0.001)) - 1) * 100).rounded())
        return pct > 0 ? .bonus(pct) : .none
    }

    @ViewBuilder private func badgeTag(_ badge: PackBadge) -> some View {
        switch badge {
        case .none:
            EmptyView()
        case .bonus(let pct):
            tagCapsule("+\(pct)% BONUS", fill: AnyShapeStyle(Theme.Role.surfaceHi),
                       text: Theme.Role.reward, stroked: true)
        case .balancedPick:
            tagCapsule("BALANCED PICK", fill: AnyShapeStyle(Theme.Role.surfaceHi),
                       text: Theme.Role.textPrimary, stroked: true)
        case .bestValue:
            tagCapsule("BEST VALUE", fill: AnyShapeStyle(Theme.Role.reward), text: .black)
        }
    }

    private func tagCapsule(_ text: String, fill: AnyShapeStyle, text textColor: Color,
                            stroked: Bool = false) -> some View {
        Text(text)
            .typeScale(.micro)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(fill, in: Capsule())
            .overlay { if stroked { Capsule().strokeBorder(Theme.Role.hairline) } }
            .offset(y: -8)
    }

    private var firstPurchaseBonusEligible: Bool {
        !ProfileStore.shared.profile.firstPurchaseBonusUsed
    }

    private func coinPackCard(_ product: IAPProduct, stack: Int) -> some View {
        let amount = product.coinAmount
        let packBadge = badge(for: product)
        return Button { buy(product.id) } label: {
            VStack(spacing: Theme.Space.s) {
                coinStack(stack, size: 18)
                    .frame(height: 26)
                Text(amount.formatted())
                    .typeScale(.heading)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.reward)
                if firstPurchaseBonusEligible {
                    Text("FIRST PURCHASE +50%")
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.reward)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                pricePill(productID: product.id)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .neonCard()
            .overlay(alignment: .top) { badgeTag(packBadge) }
        }
        .buttonStyle(.neon)
        .disabled(busy != nil)
        .accessibilityIdentifier("coinPack_\(product.id)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(packA11y(product, badge: packBadge))
    }

    private func packA11y(_ product: IAPProduct, badge: PackBadge) -> String {
        var parts = ["\(product.title), \(product.coinAmount) coins."]
        switch badge {
        case .bestValue: parts.append("Best value.")
        case .balancedPick: parts.append("Balanced pick.")
        case .bonus(let pct): parts.append("\(pct) percent more coins per dollar.")
        case .none: break
        }
        if firstPurchaseBonusEligible { parts.append("Plus fifty percent first purchase bonus.") }
        parts.append("Buy for \(iap.displayPrice(product.id)).")
        return parts.joined(separator: " ")
    }

    // MARK: perks (hidden while Double Coins owns the hero slot — no double placement)

    private var showsPerksSection: Bool { heroOffer != .doubler }

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
                        pricePill(productID: Self.doublerID)
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

    // MARK: characters (the collection IS the storefront)

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

    // MARK: footer — honest pre-launch footnote + the trust line

    @ViewBuilder private var footer: some View {
        VStack(spacing: Theme.Space.s) {
            if iap.availability == .notConfigured {
                // Quiet, factual, caption-weight: the request SUCCEEDED, the products just don't
                // exist in App Store Connect yet. Not an error, so no red, no RETRY button.
                Text("PRICES SHOWN · APP STORE SETUP PENDING")
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Prices shown. App Store setup pending.")
                    .accessibilityIdentifier("storePendingFootnote")
            }
            Text("No ads. Ever. Purchases support development.")
                .typeScale(.caption)
                .foregroundStyle(Theme.Role.textTertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("shopTrustLine")
        }
        .padding(.top, Theme.Space.s)
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

    /// Gold/claim pill — money language for the hero + starter offers (gradient law: the shop
    /// reuses the existing gold family, no new gradients).
    private func goldPricePill(productID: String) -> some View {
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
        .background(Theme.goldGradient, in: Capsule())
        .shimmerPulse(isShimmering)
    }

    /// Neutral price pill (grid + perks) — shimmers while the first load is in flight.
    private func pricePill(productID: String) -> some View {
        Group {
            if busy == productID { ProgressView().tint(.white) }
            else {
                Text(iap.displayPrice(productID))
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textPrimary)
            }
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.Role.surfaceHi, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Role.hairline))
        .shimmerPulse(isShimmering)
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

    // MARK: purchase plumbing

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
            } else if iap.availability != .ready, !iap.isPurchasable(id) {
                // Pre-launch / offline: this product genuinely isn't purchasable yet. Friendly
                // transient toast — never the red strip, never a crash path.
                showToast(unavailableCopy)
            }
        }
    }

    private var unavailableCopy: String {
        switch iap.availability {
        case .offline:
            "Can't reach the App Store right now — coins and characters below still work."
        case .loading:
            "Prices are still loading — give it a second and try again."
        default:
            "The App Store isn't ready for purchases yet — coin items still work."
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}

// MARK: - loading shimmer (state a: placeholder cards with fallback prices, no error)

/// Gentle opacity pulse on price pills while the FIRST product load is in flight. Static dim
/// under Reduce Motion (no repeat-forever animation), full opacity once any load round-trips.
private struct ShimmerPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(!active ? 1 : (reduceMotion ? 0.7 : (dim ? 0.45 : 0.95)))
            .animation(active && !reduceMotion
                       ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                       : .default, value: dim)
            .onAppear { if active { dim = true } }
            .onChange(of: active) { _, nowActive in dim = nowActive }
    }
}

private extension View {
    func shimmerPulse(_ active: Bool) -> some View { modifier(ShimmerPulse(active: active)) }
}
