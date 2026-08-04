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
    @State private var showMysteryBox = false   // presents the full Mystery Box reveal sequence
    @State private var packReward: CoinSpendItem?   // drives the pack-purchase reveal burst (S1)

    /// Featured rotation pool (hero priority 3): premium + coin skins by id. Double Coins left
    /// the pool — it owns hero priority 1 outright until purchased.
    private static let featuredPool = ["aurora", "midas", "toxic", "mono"]

    var body: some View {
        MetaScreenScaffold(title: "Shop", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                // Exhaustive on purpose: every store state gets exactly one header presentation,
                // and the compiler — not a reader — guarantees the next state added gets one too.
                // As two loose `if`s, `.notConfigured` fell through both and the pre-launch store
                // said nothing above the fold (PR-0306).
                switch iap.availability {
                case .offline:       offlineCard
                case .notConfigured: setupPendingCard
                case .loading:       EmptyView()
                case .ready:         if let error = iap.lastError { inlineErrorStrip(error) }
                }
                heroSection
                if showsStarterCard { starterOfferCard }
                coinsSection
                if showsPerksSection { perksSection }
                consumablesSection
                charactersSection
                footer
            }
        }
        .overlay(alignment: .bottom) {
            if let toast { toastView(toast) }
        }
        .overlay {
            if showMysteryBox { MysteryBoxView(model: model) { showMysteryBox = false } }
        }
        .overlay {
            if let packReward {
                PackRewardBurst(item: packReward) { self.packReward = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: packReward)
        .onAppear {
            iap.refreshIfUnavailable()   // the one sheet-open re-check (no retry spam)
            if ProcessInfo.processInfo.environment["PR_MYSTERYBOX"] == "1" { showMysteryBox = true }
            if let id = ProcessInfo.processInfo.environment["PR_BUYPACK"] {   // screenshot hook (S1)
                packReward = ShopConsumables.packs.first { $0.id == id } ?? ShopConsumables.packs.first
            }
        }
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

    /// Pre-launch = the request SUCCEEDED and App Store Connect has no (full) catalog yet. Normal,
    /// not broken (decree 3): no red, and no RETRY, because the manager already re-checks on every
    /// Shop open and app foreground — a button here could only ever answer "still not live"
    /// (decree 4). Not a `Button` for the same reason the signed-out leaderboard isn't.
    ///
    /// This state used to say nothing above the fold at all: the only disclosure was a grey footnote
    /// six screens down, so the first thing a player met was six real-looking dollar prices that
    /// could not be bought (PR-0306). It states the one fact they can act on — the coin shop below
    /// is fully live.
    private var setupPendingCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                Text("Store opens with the App Store listing")
                    .typeScale(.body)
            }
            .foregroundStyle(Theme.Role.textSecondary)
            Text("Real-money prices arrive then. Everything priced in coins below works right now.")
                .typeScale(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Role.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.m)
        .neonCard(radius: Theme.Radius.l)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("storeSetupPendingCard")
        .accessibilityLabel("Store opens with the App Store listing. Real-money prices arrive then. Everything priced in coins below works right now.")
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
    /// pure + Linux-tested in `ShopValue.featuredSkin` (rule 2 safe). All owned → the medium pack.
    private var featuredID: String {
        ShopValue.featuredSkin(daySeed: ProfileStore.daysSinceEpoch(Date()),
                               pool: Self.featuredPool,
                               owned: ProfileStore.shared.profile.ownedSkins,
                               fallback: "coins.medium")
    }

    @ViewBuilder private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            switch heroOffer {
            case .doubler:
                kicker("PERMANENT PERK")
                heroShell(title: "Double Coins", blurb: "Every run pays double. Forever.",
                          preview: doubleCoinsGlyph(size: 56),
                          pill: goldPricePill(productID: Self.doublerID),
                          tag: "ONE PURCHASE · EVERY RUN",
                          a11y: "Double Coins. Every run pays double, forever. \(iap.spokenPrice(Self.doublerID))") {
                    buy(Self.doublerID)
                }
            case .starter:
                kicker("FIRST PURCHASE OFFER")
                heroShell(title: "Starter Bundle", blurb: starterBlurb,
                          preview: coinStack(2, size: 26),
                          pill: goldPricePill(productID: IAPCatalog.starterID),
                          tag: "FIRST PURCHASE",
                          a11y: "Starter Bundle. \(starterBlurb) \(iap.spokenPrice(IAPCatalog.starterID))") {
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
                      preview: coinStack(3, size: 26),
                      pill: goldPricePill(productID: Self.mediumPackID),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: Bag of Coins, 7,000 coins.") {
                buy(Self.mediumPackID)
            }
        case "aurora":
            // Featured = always a locked skin (rotation skips owned ones): render the same
            // tease as the select grid, never an owned-bright storefront lie (AUDIT D6-5).
            let skin = SkinCatalog.skin("aurora")
            heroShell(title: skin.name, blurb: skin.flavor,
                      preview: AnimatedCharacterSwatch(
                          skin: skin, size: 52,
                          silhouette: !ProfileStore.shared.profile.ownedSkins.contains(skin.id),
                          heightScale: CGFloat(CharacterSwatchSlot.tight.height),
                          widthScale: CGFloat(CharacterSwatchSlot.tight.width),
                          verticalAnchor: CGFloat(CharacterSwatchSlot.tight.anchor)),
                      pill: goldPricePill(productID: Self.auroraID),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: \(skin.name), premium character.") {
                buy(Self.auroraID)
            }
        default:
            // Coin-priced character: the shop never charges coins without showing the stage —
            // the tap routes to Characters for the preview-before-buy commit (uiux §4.1).
            // Locked tease render, consistent with the select grid it routes to (AUDIT D6-5).
            let skin = SkinCatalog.skin(id)
            heroShell(title: skin.name, blurb: skin.flavor,
                      preview: AnimatedCharacterSwatch(
                          skin: skin, size: 52,
                          silhouette: !ProfileStore.shared.profile.ownedSkins.contains(skin.id),
                          heightScale: CGFloat(CharacterSwatchSlot.tight.height),
                          widthScale: CGFloat(CharacterSwatchSlot.tight.width),
                          verticalAnchor: CGFloat(CharacterSwatchSlot.tight.anchor)),
                      pill: coinPricePill(skin.cost),
                      tag: "TODAY'S FEATURE",
                      a11y: "Today's feature: \(skin.name), \(skin.cost) coins. Opens characters to preview.") {
                model.open(.characters, focusSkin: skin.id)   // stage THAT skin (uiux §4.1)
            }
        }
    }

    /// Shared hero chrome: 120 pt spotlight, preview left, copy + price pill right, corner tag.
    /// The pill carries the screen's gold/claim gradient (money language — gradient law: no new
    /// gradient family on this screen).
    private func heroShell<Preview: View, Pill: View>(
        title: String, blurb: String, preview: Preview, pill: Pill,
        tag: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                // 96, not 72: the tight slot that stops the featured character bleeding onto
                // the copy column beside it is `52 * CharacterSwatchSlot.tight.width`. The old 72
                // was sized for a swatch that was cropping its own aura to fit.
                preview.frame(width: 52 * CGFloat(CharacterSwatchSlot.tight.width))
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
        .accessibilityLabel("Starter Bundle, first purchase offer. \(starterBlurb) \(iap.spokenPrice(IAPCatalog.starterID))")
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
            // Stated ONCE, as the account-level rule it actually is. All four packs used to carry
            // `FIRST PURCHASE +50%` simultaneously, which reads as a per-pack property when only
            // one of them can ever be true (PR-0316, decree 5).
            if firstPurchaseBonusEligible {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    Text("YOUR FIRST PURCHASE GETS +50% EXTRA COINS").typeScale(.micro)
                }
                .foregroundStyle(Theme.Role.reward)
                .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Role.reward.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .strokeBorder(Theme.Role.reward.opacity(0.35)))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("firstPurchaseBanner")
                .accessibilityLabel("Your first purchase gets 50 percent extra coins.")
            }
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
    /// or coin-amount edit can't desync a badge). The math is pure and Linux-tested in `ShopValue`
    /// (v1.4.3); this view only resolves each product to a `ShopPack` with a UNIFORM price source.
    ///
    /// Coins-per-price from that uniform source: live storefront prices only once the FULL catalog
    /// is loaded (`.ready`), otherwise the USD fallbacks for EVERY pack. A partial load on a
    /// non-USD storefront must never mix currencies across packs — that could crown the wrong BEST
    /// VALUE and break the +N% math (v1.4.1 review).
    private func shopPack(_ p: IAPProduct) -> ShopPack {
        let price = iap.availability == .ready
            ? (iap.priceValue(p.id) ?? p.fallbackValue)
            : p.fallbackValue
        return ShopPack(id: p.id, coins: p.coinAmount, price: price)
    }

    private func badge(for product: IAPProduct) -> PackBadge {
        ShopValue.badge(for: shopPack(product), in: coinPacks.map(shopPack), mediumID: Self.mediumPackID)
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
                // The per-pack badge is gone — the section banner states the bonus once (PR-0316).
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
        parts.append(iap.spokenPrice(product.id))
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
                    // Copy must say RUN payout, not all coins: `coinMultiplier` is consumed at
                    // exactly one site (GameView.swift:696), so daily rewards, the chest, level
                    // grants, mission claims and challenge tiers are NOT doubled (PR-0411).
                    Text("Every run pays 2× coins. Forever.")
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
                                ? "Double Coins. Every run pays two times coins, forever. Owned."
                                : "Double Coins. Every run pays two times coins, forever. \(iap.spokenPrice(Self.doublerID))")
            .accessibilityAddTraits(owned ? [] : .isButton)
            .accessibilityAction { if !owned, busy == nil { buy(Self.doublerID) } }
        }
    }

    // MARK: power-up packs + Mystery Box (coin-spend — works in every store state)

    /// Coin-spend power-up packs and the Mystery Box gacha. These never touch StoreKit — they spend
    /// EARNED coins via `ProfileStore`, so they're shoppable even pre-launch / offline (decree 4).
    private var consumablesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("POWER-UP PACKS")
            mysteryBoxCard
            ForEach(ShopConsumables.packs) { item in packRow(item) }
        }
    }

    private var mysteryBoxCard: some View {
        let cost = ShopConsumables.mysteryBoxCost
        // Read the prize rather than retyping it: both strings below said 1,200 against a real
        // 1,400 until S-019, and one of them is the VoiceOver label (PR-0486).
        let jackpot = ShopConsumables.mysteryJackpotCoins
        // Always tappable — it opens the reveal screen, which shows the odds + handles the spend
        // (so the player can see what's inside even when they can't afford it yet).
        return Button { showMysteryBox = true } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.Role.reward)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mystery Box").typeScale(.heading).foregroundStyle(Theme.Role.textPrimary)
                    Text("Coins, slow-mo, or a loadout boost — \(jackpot.formatted())-coin jackpot!")
                        .typeScale(.body).foregroundStyle(Theme.Role.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                coinPricePill(cost)
            }
            .padding(Theme.Space.m)
            .neonCard()
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("mysteryBoxButton")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mystery Box. Win coins, slow-mo, or a loadout boost — up to a \(jackpot.formatted()) coin jackpot. \(cost) coins.")
        .accessibilityHint("Opens the Mystery Box reveal.")
        .accessibilityAddTraits(.isButton)
    }

    private func packRow(_ item: CoinSpendItem) -> some View {
        let tint = Theme.color(item.hex)
        let afford = ProfileStore.shared.profile.coins >= item.cost
        return Button { spendOnPack(item) } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).typeScale(.heading).foregroundStyle(Theme.Role.textPrimary)
                    Text(item.blurb).typeScale(.body).foregroundStyle(Theme.Role.textSecondary)
                }
                Spacer()
                coinPricePill(item.cost)
            }
            .padding(Theme.Space.m)
            .neonCard()
            .opacity(afford ? 1 : 0.55)
        }
        .buttonStyle(.neon)
        .disabled(!afford)   // unaffordable → disabled + dimmed (matches the reviveForCoins affordance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.blurb). \(item.cost) coins.\(afford ? "" : " Not enough coins.")")
        .accessibilityAddTraits(.isButton)
    }

    private func spendOnPack(_ item: CoinSpendItem) {
        if ProfileStore.shared.buyConsumablePack(item) {
            successPulse += 1
            model.synth.play(.purchaseChime)
            packReward = item   // fire the reveal burst (S1) — confirms exactly what landed
        } else {
            showToast("Not enough coins — keep running to earn more.")
            model.synth.play(.uiTick)
        }
    }

    // MARK: characters (the collection IS the storefront)

    /// Coin-priced roster + premium Aurora as 96×128 rail cards. Tap → CharacterSelect, where the
    /// stage previews before any coins move (the shop never charges coins blind, uiux §4.1).
    @ViewBuilder private var charactersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            kicker("CHARACTERS")
            ScrollView(.horizontal, showsIndicators: false) {
                // LAZY, not eager. A plain `HStack` builds all 13 cards the moment the shop
                // opens, and each one holds an `AnimatedCharacterSwatch` whose
                // `TimelineView(.animation)` redraws it 30 times a second — including the ~9 that
                // are off-screen. Roughly three quarters of this rail's per-frame cost was being
                // spent on cards nobody was looking at, on the screen the owner named as slow
                // (D-050: "just browsing the characters and catalog").
                LazyHStack(spacing: Theme.Space.s) {
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
        // EQUIPPED from the resolver — same truth as the run and the select stage (AUDIT D3-1).
        let equipped = ProfileStore.shared.equippedSkinID == skin.id
        // Tap → CharacterSelect focused to THIS skin (uiux §4.1) — never the equipped one.
        return Button { model.open(.characters, focusSkin: skin.id) } label: {
            VStack(spacing: Theme.Space.xs) {
                // Locked skins wear the SAME tease as the select grid they route to (AUDIT
                // D6-5): a skin must not read owned-bright here and locked-dim one tap later.
                AnimatedCharacterSwatch(skin: skin, size: 42, silhouette: !owned)
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
        if skin.premium { return "\(skin.name). Premium. \(iap.spokenPrice(Self.auroraID))" }
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
            // The pre-launch footnote that used to live here is gone: `setupPendingCard` states
            // the same fact in the FIRST viewport, and saying it twice is the PR-0316 sin.
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
