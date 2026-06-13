import SwiftUI

/// Characters as "the stage and the shelf" (R7): the hero stage previews the FOCUSED skin
/// (defaults to equipped on open); tapping any card focuses it; commitment happens on the state
/// button (EQUIP / BUY / requirement). Locked skins render as full-color TEASES (v1.4 — reduced
/// opacity + lock chip, so players see what they're missing) with pinned requirement copy, and
/// every locked tap leads somewhere (DESIGN_characters §3.4 routing). A NEXT UNLOCK spotlight
/// above the 24-skin grid names the nearest goal. All profile state is read from
/// `ProfileStore.shared` at the point of use inside `body` (G3 — no snapshot `let`).
struct CharacterSelectView: View {
    let model: GameModel
    /// Pre-focus the stage on this skin (shop rail / featured-card routing — uiux §4.1
    /// "tap card → CharacterSelect focused to that skin"). nil = open on the equipped skin.
    var initialFocus: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Local UI focus (selection ≠ commitment). nil = follow the equipped skin.
    @State private var focusedID: String?
    @State private var stageShake: CGFloat = 0
    @State private var stageDenied = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    /// The challengeDays "back to the menu" close, tracked so re-routing inside its 900 ms window
    /// (e.g. GET IN SHOP swaps the sheet) cancels it instead of closing the WRONG sheet later.
    @State private var closeTask: Task<Void, Never>?
    /// One-shot capture of which owned skins were unseen when the screen opened, so NEW badges
    /// stay visible during this visit while `markSkinsSeen()` clears the persistent flag.
    /// (Transient presentation state — not a live-store snapshot; reads in body stay direct.)
    @State private var newThisVisit: Set<String> = []

    private var focusedSkin: Skin {
        // Falls back to the RESOLVED equipped skin (AUDIT D3-1): opening on a raw unowned
        // `selectedSkin` would stage a locked tease as if it were the player's character.
        SkinCatalog.skin(focusedID ?? ProfileStore.shared.equippedSkinID)
    }

    var body: some View {
        MetaScreenScaffold(title: "Characters",
                           coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() },
                           onCoins: { model.open(.shop) }) {
            VStack(spacing: Theme.Space.l) {
                carousel
                pageDots
                nextUnlockRow
                ForEach([Skin.Rarity.common, .rare, .epic, .legendary], id: \.rawValue) { rarity in
                    raritySection(rarity)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3),
                       value: ProfileStore.shared.equippedSkinID)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3),
                       value: focusedID)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textPrimary)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Role.interactive.opacity(0.5)))
                    .padding(.bottom, Theme.Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: toast)
        .onAppear {
            // The carousel needs a concrete page — default to the shop-routed skin, else equipped.
            if focusedID == nil { focusedID = initialFocus ?? ProfileStore.shared.equippedSkinID }
            newThisVisit = ProfileStore.shared.profile.ownedSkins
                .subtracting(ProfileStore.shared.profile.seenSkins)
            ProfileStore.shared.markSkinsSeen()   // clears the nav badge-dot + future NEW badges
        }
        .onDisappear { closeTask?.cancel() }      // a dismissed sheet must never close its successor
    }

    // MARK: the stage — a swipeable carousel through ALL characters (C3)

    /// The big hero card is now a paged slider (owner C3): swipe through every character — owned and
    /// locked, all rarities — each showing its unlock requirement + a progress bar toward it. Modern
    /// paging ScrollView (`scrollPosition(id:)`) so a swipe updates `focusedID` and a grid/shelf tap
    /// scrolls the carousel to that skin. `containerRelativeFrame` makes each page exactly one width.
    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(SkinCatalog.all) { skin in
                    carouselPage(skin)
                        .containerRelativeFrame(.horizontal)
                        .id(skin.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $focusedID, anchor: .center)
        .scrollClipDisabled()                  // let the focused card's glow/aura breathe past edges
        .frame(height: 372)
    }

    private func carouselPage(_ skin: Skin) -> some View {
        // Per-page state reads live off the store at point of use (G3 — no snapshot let).
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        return VStack(spacing: Theme.Space.s) {
            CharacterHeroStage(skin: skin, height: 176, showsNamePill: false, locked: !owned)
                .frame(maxWidth: .infinity)
            HStack(spacing: Theme.Space.s) {
                Text(skin.name)
                    .typeScale(.title)
                    .foregroundStyle(Theme.Role.textPrimary)
                rarityChip(skin.rarity)
            }
            Text(skin.flavor)
                .typeScale(.caption)
                .italic()
                .foregroundStyle(Theme.Role.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 30)
            stateButton(skin)
            unlockProgress(skin)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
        .padding(.horizontal, Theme.Space.s)
        .neonCard(radius: Theme.Radius.l)
        .padding(.horizontal, Theme.Space.l)   // breathing room between adjacent pages
    }

    /// A slim position indicator under the carousel: one dot per character, coloured by rarity, the
    /// current page enlarged + bright. Communicates "all characters, across every rarity" + where
    /// you are in the slider at a glance.
    private var pageDots: some View {
        HStack(spacing: 3) {
            ForEach(SkinCatalog.all) { skin in
                Circle()
                    .fill(rarityColor(skin.rarity))
                    .frame(width: 5, height: 5)
                    .scaleEffect(focusedSkin.id == skin.id ? 1.7 : 1)
                    .opacity(focusedSkin.id == skin.id ? 1 : 0.35)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: focusedID)
        .accessibilityHidden(true)
    }

    /// Progress toward a locked skin's gate (owner C3 "a progression of the next unlock"): a labelled
    /// bar showing how close the player is. Owned/free/iap skins show nothing (premium routes via the
    /// state button). All reads are live off the store at point of use (G3).
    @ViewBuilder private func unlockProgress(_ skin: Skin) -> some View {
        if !ProfileStore.shared.profile.ownedSkins.contains(skin.id),
           let p = unlockFraction(skin) {
            VStack(spacing: 4) {
                ProgressView(value: p.fraction)
                    .progressViewStyle(.linear)
                    .tint(p.fraction >= 1 ? Theme.Role.reward : rarityColor(skin.rarity))
                    .frame(maxWidth: 200)
                Text(p.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.fraction >= 1 ? Theme.Role.reward : Theme.Role.textTertiary)
            }
            .padding(.top, 2)
        }
    }

    /// Numeric unlock progress (fraction 0…1 + a human label) for the gates that have a measurable
    /// path: coins, level (XP), achievement tiers, daily-challenge days. iap returns nil (no bar).
    private func unlockFraction(_ skin: Skin) -> (fraction: Double, label: String)? {
        let profile = ProfileStore.shared.profile
        switch skin.unlock {
        case .free, .iap:
            return nil
        case .coins(let c):
            let have = profile.coins
            return (min(1, Double(have) / Double(max(1, c))),
                    "\(have.formatted()) / \(c.formatted()) coins")
        case .level(let n):
            let need = XPCurve.cumulativeXP[min(n, XPCurve.maxLevel) - 1]
            let have = profile.totalXP
            return (min(1, Double(have) / Double(max(1, need))),
                    have >= need ? "Level \(n) reached" : "\((need - have).formatted()) XP to level \(n)")
        case .achievement(let id, let tier):
            guard let m = MissionCatalog.mission(id),
                  case .lifetimeTiered(let targets, _) = m.scope,
                  tier >= 1, tier <= targets.count else { return nil }
            let target = targets[tier - 1]                                  // Double metric target
            let have = min(profile.missionProgress[id] ?? 0, target)
            return (target <= 0 ? 1 : min(1, have / target),
                    "\(Int(have).formatted()) / \(Int(target).formatted())")
        case .challengeDays(let n):
            let have = profile.challengeDaysPlayed.count
            return (min(1, Double(have) / Double(max(1, n))),
                    "\(min(have, n)) / \(n) daily challenges")
        }
    }

    /// The single commitment control. Label + action both derive from the skin's state.
    private func stateButton(_ skin: Skin) -> some View {
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        // Equipped = the RESOLVED truth, not raw `selectedSkin` (AUDIT D3-1): an unowned
        // selection must read BUY/requirement (routable), never a disabled EQUIPPED dead-end.
        let equipped = ProfileStore.shared.equippedSkinID == skin.id
        return Button { stateAction(for: skin) } label: {
            stateLabel(for: skin, owned: owned, equipped: equipped)
        }
        .buttonStyle(.neon)
        .disabled(equipped)
        .modifier(ShakeEffect(trigger: stageShake))
        // Only the FOCUSED (centred) carousel page carries the stage id — the carousel renders
        // several pages, so without this the id would be ambiguous (one per page).
        .accessibilityIdentifier(focusedSkin.id == skin.id ? "skinStageButton" : "")
        .accessibilityLabel(stateA11y(for: skin, owned: owned, equipped: equipped))
    }

    @ViewBuilder
    private func stateLabel(for skin: Skin, owned: Bool, equipped: Bool) -> some View {
        if equipped {
            pillText("EQUIPPED", color: .black)
                .background(Theme.Role.interactive, in: Capsule())
        } else if owned {
            pillText("EQUIP", color: Theme.Role.interactive)
                .background(Theme.Role.surfaceHi, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Role.interactive.opacity(0.7), lineWidth: 1.5))
        } else {
            switch skin.unlock {
            case .free, .coins:
                HStack(spacing: 6) {
                    CoinGlyph(size: 14)
                    Text("BUY · \(skin.cost)").monospacedDigit()
                }
                .typeScale(.caption)
                .fontWeight(.heavy)
                .foregroundStyle(.black)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, 12)
                .background(Theme.goldGradient, in: Capsule())
                .overlay(Capsule().strokeBorder(stageDenied ? Theme.Role.danger : .clear, lineWidth: 2))
            case .iap:
                pillText("GET IN SHOP ›", color: Theme.Role.reward)
                    .background(Theme.Role.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            case .level, .achievement, .challengeDays:
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                    Text(SkinUnlocks.requirementText(skin))
                }
                .typeScale(.caption)
                .foregroundStyle(Theme.Role.lock)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, 12)
                .background(Theme.Role.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            }
        }
    }

    private func pillText(_ text: String, color: Color) -> some View {
        Text(text)
            .typeScale(.caption)
            .fontWeight(.heavy)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.l).padding(.vertical, 12)
    }

    private func stateA11y(for skin: Skin, owned: Bool, equipped: Bool) -> String {
        if equipped { return "\(skin.name) equipped" }
        if owned { return "Equip \(skin.name)" }
        switch skin.unlock {
        case .free, .coins: return "Buy \(skin.name) for \(skin.cost) coins"
        case .iap:          return "\(skin.name) is premium. Opens the shop"
        default:            return "\(skin.name) locked. \(SkinUnlocks.requirementText(skin))"
        }
    }

    /// Locked-tap routing (DESIGN_characters §3.4) — nothing on screen is dead.
    private func stateAction(for skin: Skin) {
        closeTask?.cancel()   // any new commitment supersedes a pending challengeDays close
        let store = ProfileStore.shared
        if store.profile.ownedSkins.contains(skin.id) {
            model.buyOrEquipSkin(skin)
            return
        }
        switch skin.unlock {
        case .free:
            model.buyOrEquipSkin(skin)
        case .coins:
            if !model.buyOrEquipSkin(skin) { deny() }
        case .iap:
            model.open(.shop)
        case .achievement:
            model.open(.missions)   // lands on the ladder that unlocks it
        case .level(let n):
            let need = max(0, XPCurve.cumulativeXP[min(n, XPCurve.maxLevel) - 1] - store.profile.totalXP)
            showToast("REACH LEVEL \(n) · \(need.formatted()) XP TO GO")
        case .challengeDays:
            // Toast first (rendered in-sheet — GameModel's toast API is private), then back to
            // the menu where the Daily Rush rail cell sits. Tracked + cancellation-checked, same
            // pattern as toastTask: re-routing or dismissal must not close a successor sheet.
            showToast("PLAY TODAY'S CHALLENGE")
            closeTask = Task {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                model.closeSheet()
            }
        }
    }

    /// Can't-afford feedback on the STAGE button (uiux §6.2): shake + red border flash.
    private func deny() {
        stageDenied = true
        if reduceMotion {
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                stageDenied = false
            }
        } else {
            withAnimation(.linear(duration: 0.4)) { stageShake += 1 }
            withAnimation(.easeOut(duration: 0.45)) { stageDenied = false }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: the next-unlock spotlight

    /// The roster's nearest goal (v1.4 — 24 skins need a "start here"): the cheapest locked skin
    /// the player can buy RIGHT NOW; else the lowest level-gate still ahead; else the cheapest
    /// coin pull to save toward. Achievement/challenge/iap skins are journeys, not next steps.
    private var nextUnlockSkin: Skin? {
        // Store reads stay inline at point of use (G3 — no snapshot let): evaluated from
        // `nextUnlockRow` during body, so observation keeps tracking ownedSkins/coins.
        let locked = SkinCatalog.all.filter { !ProfileStore.shared.profile.ownedSkins.contains($0.id) }
        let coinSkins = locked.filter { $0.cost > 0 }.sorted { $0.cost < $1.cost }
        if let affordable = coinSkins.first(where: { $0.cost <= ProfileStore.shared.profile.coins }) {
            return affordable
        }
        let levelGates = locked.compactMap { skin -> (skin: Skin, level: Int)? in
            if case .level(let n) = skin.unlock { (skin, n) } else { nil }
        }
        if let nearest = levelGates.min(by: { $0.level < $1.level }) { return nearest.skin }
        return coinSkins.first
    }

    /// Subtle spotlight row above the grid — tap focuses the hero on that skin (preview, never
    /// commit). The reward pill goes gold only when the coins are already in the bank.
    @ViewBuilder private var nextUnlockRow: some View {
        if let skin = nextUnlockSkin {
            let affordable = skin.cost > 0 && ProfileStore.shared.profile.coins >= skin.cost
            Button { stateAction(focus: skin) } label: {
                HStack(spacing: Theme.Space.m) {
                    AnimatedCharacterSwatch(skin: skin, size: 36, silhouette: true, animated: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT UNLOCK")
                            .typeScale(.micro)
                            .foregroundStyle(affordable ? Theme.Role.reward : Theme.Role.textTertiary)
                        Text(skin.name)
                            .typeScale(.heading)
                            .foregroundStyle(Theme.Role.textPrimary)
                    }
                    Spacer()
                    nextUnlockTag(skin, affordable: affordable)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Role.textTertiary)
                }
                .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            }
            .buttonStyle(.neon)
            .neonCard(raised: affordable)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(affordable ? Theme.Role.reward.opacity(0.5) : .clear, lineWidth: 1.5))
            .accessibilityIdentifier("nextUnlockRow")
            .accessibilityLabel("Next unlock: \(skin.name). \(nextUnlockA11y(skin, affordable: affordable))")
            .accessibilityHint("Shows it on the stage")
        }
    }

    @ViewBuilder private func nextUnlockTag(_ skin: Skin, affordable: Bool) -> some View {
        if case .level(let n) = skin.unlock {
            Text("REACH LVL \(n)")
                .typeScale(.micro)
                .foregroundStyle(Theme.Role.lock)
        } else {
            HStack(spacing: 4) {
                CoinGlyph(size: 12)
                Text("\(skin.cost)").monospacedDigit()
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(affordable ? .black : Theme.Role.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(affordable ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.Role.surfaceHi),
                        in: Capsule())
        }
    }

    private func nextUnlockA11y(_ skin: Skin, affordable: Bool) -> String {
        if case .level(let n) = skin.unlock { return "Reach level \(n)." }
        return affordable ? "\(skin.cost) coins — you can afford it." : "\(skin.cost) coins."
    }

    /// Spotlight tap = focus the stage on that skin (same contract as a first shelf-card tap).
    private func stateAction(focus skin: Skin) {
        focusedID = skin.id
    }

    // MARK: the shelf

    private func raritySection(_ rarity: Skin.Rarity) -> some View {
        let skins = SkinCatalog.all.filter { $0.rarity == rarity }
        // Owned-count read lives here, per render, straight off the live store (G3).
        let ownedCount = skins.count { ProfileStore.shared.profile.ownedSkins.contains($0.id) }
        return VStack(alignment: .leading, spacing: Theme.Space.s + 4) {
            HStack(spacing: Theme.Space.s) {
                Text(rarityName(rarity))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(rarityColor(rarity))
                Text("· \(ownedCount)/\(skins.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textTertiary)
                Rectangle().fill(rarityColor(rarity).opacity(0.25)).frame(height: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rarityName(rarity)) characters, \(ownedCount) of \(skins.count) owned")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(skins) { skin in
                    shelfCard(skin)
                }
            }
        }
    }

    private func shelfCard(_ skin: Skin) -> some View {
        // Card-level state reads happen here, per render, straight off the live store (G3).
        // EQUIPPED rings/labels come from the resolver, same truth as the run (AUDIT D3-1).
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        let equipped = ProfileStore.shared.equippedSkinID == skin.id
        let focused = focusedSkin.id == skin.id
        return ShelfCard(skin: skin,
                         owned: owned,
                         equipped: equipped,
                         focused: focused,
                         isNew: owned && newThisVisit.contains(skin.id),
                         rarityTint: rarityColor(skin.rarity)) {
            if focused {
                stateAction(for: skin)   // second tap on the focused card = commit/route
            } else {
                focusedID = skin.id      // first tap = focus the stage (preview before commit)
            }
        }
    }

    private func rarityChip(_ rarity: Skin.Rarity) -> some View {
        Text(rarityName(rarity))
            .typeScale(.micro)
            .foregroundStyle(rarityColor(rarity))
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
            .background(rarityColor(rarity).opacity(0.12), in: Capsule())
    }

    private func rarityName(_ rarity: Skin.Rarity) -> String {
        switch rarity {
        case .common: "COMMON"
        case .rare: "RARE"
        case .epic: "EPIC"
        case .legendary: "LEGENDARY"
        }
    }

    private func rarityColor(_ rarity: Skin.Rarity) -> Color {
        switch rarity {
        case .common: Theme.color(0x9BA6B5)
        case .rare: Theme.color(0x00B3FF)
        case .epic: Theme.color(0xB26BFF)
        case .legendary: Theme.color(0xFFD23D)
        }
    }
}

/// One shelf card: animated swatch (silhouette while locked), name, single-word/requirement
/// status, NEW badge for freshly-granted characters. Tap = focus; the parent decides whether a
/// tap is focus or commit.
private struct ShelfCard: View {
    let skin: Skin
    let owned: Bool
    let equipped: Bool
    let focused: Bool
    let isNew: Bool
    let rarityTint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Tease render (v1.4): full color at 0.45 opacity — the swatch overlays its own
                // lock chip, so the old per-card lock glyph is gone.
                AnimatedCharacterSwatch(skin: skin, size: 56, silhouette: !owned)
                    .frame(height: 84)
                Text(skin.name)
                    .typeScale(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(owned ? Theme.Role.textPrimary : Theme.Role.textSecondary)
                status
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(focused ? Theme.Role.surfaceHi : Theme.Role.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(ringColor, lineWidth: equipped ? 2.5 : (focused ? 2 : 1))
            )
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.goldGradient, in: Capsule())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("skin_\(skin.id)")
        .accessibilityValue(a11yValue)
        .accessibilityHint(focused ? "" : "Shows preview")
    }

    private var ringColor: Color {
        if equipped { return Theme.Role.interactive }
        if focused { return rarityTint.opacity(0.9) }
        return rarityTint.opacity(0.35)
    }

    private var a11yValue: String {
        if equipped { return "equipped" }
        if owned { return "owned" }
        let req = SkinUnlocks.requirementText(skin)
        if skin.cost > 0 { return "locked — costs \(skin.cost) coins" }
        return "locked — \(req)"
    }

    @ViewBuilder private var status: some View {
        if equipped {
            statusText("EQUIPPED", Theme.Role.interactive)
        } else if owned {
            statusText("OWNED", Theme.Role.textTertiary)
        } else if skin.cost > 0 {
            CoinBadge(amount: skin.cost)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Role.textSecondary)
        } else if skin.premium {
            statusText("★ SHOP", Theme.Role.reward)
        } else {
            Text(SkinUnlocks.requirementText(skin))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Theme.Role.lock)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 4)
        }
    }

    private func statusText(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(color)
    }
}
