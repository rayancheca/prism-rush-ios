import SwiftUI

/// Characters as "the stage and the shelf" (R7): the hero stage previews the FOCUSED skin
/// (defaults to equipped on open); tapping any card focuses it; commitment happens on the state
/// button (EQUIP / BUY / requirement). Locked skins render as silhouettes with pinned requirement
/// copy, and every locked tap leads somewhere (DESIGN_characters §3.4 routing). All profile state
/// is read from `ProfileStore.shared` at the point of use inside `body` (G3 — no snapshot `let`).
struct CharacterSelectView: View {
    let model: GameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Local UI focus (selection ≠ commitment). nil = follow the equipped skin.
    @State private var focusedID: String?
    @State private var stageShake: CGFloat = 0
    @State private var stageDenied = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    /// One-shot capture of which owned skins were unseen when the screen opened, so NEW badges
    /// stay visible during this visit while `markSkinsSeen()` clears the persistent flag.
    /// (Transient presentation state — not a live-store snapshot; reads in body stay direct.)
    @State private var newThisVisit: Set<String> = []

    private var focusedSkin: Skin {
        SkinCatalog.skin(focusedID ?? ProfileStore.shared.profile.selectedSkin)
    }

    var body: some View {
        MetaScreenScaffold(title: "Characters",
                           coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() },
                           onCoins: { model.open(.shop) }) {
            VStack(spacing: Theme.Space.l) {
                heroSection
                ForEach([Skin.Rarity.common, .rare, .epic, .legendary], id: \.rawValue) { rarity in
                    raritySection(rarity)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3),
                       value: ProfileStore.shared.profile.selectedSkin)
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
            newThisVisit = ProfileStore.shared.profile.ownedSkins
                .subtracting(ProfileStore.shared.profile.seenSkins)
            ProfileStore.shared.markSkinsSeen()   // clears the nav badge-dot + future NEW badges
        }
    }

    // MARK: the stage

    private var heroSection: some View {
        let skin = focusedSkin
        return VStack(spacing: Theme.Space.s) {
            CharacterHeroStage(skin: skin, height: 192, showsNamePill: false)
                .frame(maxWidth: .infinity)
                .id(skin.id)   // crossfade between characters, not in-place morph
            HStack(spacing: Theme.Space.s) {
                Text(skin.name)
                    .typeScale(.title)
                    .foregroundStyle(Theme.Role.textPrimary)
                rarityChip(skin.rarity)
            }
            Text(skin.flavor)
                .typeScale(.body)
                .italic()
                .foregroundStyle(Theme.Role.textSecondary)
                .multilineTextAlignment(.center)
            stateButton
                .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
        .neonCard(radius: Theme.Radius.l)
    }

    /// The single commitment control. Label + action both derive from the focused skin's state.
    private var stateButton: some View {
        let skin = focusedSkin
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        let equipped = ProfileStore.shared.profile.selectedSkin == skin.id
        return Button { stateAction(for: skin) } label: {
            stateLabel(for: skin, owned: owned, equipped: equipped)
        }
        .buttonStyle(.neon)
        .disabled(equipped)
        .modifier(ShakeEffect(trigger: stageShake))
        .accessibilityIdentifier("skinStageButton")
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
            // the menu where the Daily Rush rail cell sits.
            showToast("PLAY TODAY'S CHALLENGE")
            Task {
                try? await Task.sleep(for: .milliseconds(900))
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

    // MARK: the shelf

    private func raritySection(_ rarity: Skin.Rarity) -> some View {
        let skins = SkinCatalog.all.filter { $0.rarity == rarity }
        return VStack(alignment: .leading, spacing: Theme.Space.s + 4) {
            HStack(spacing: Theme.Space.s) {
                Text(rarityName(rarity))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(rarityColor(rarity))
                Rectangle().fill(rarityColor(rarity).opacity(0.25)).frame(height: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rarityName(rarity)) characters")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(skins) { skin in
                    shelfCard(skin)
                }
            }
        }
    }

    private func shelfCard(_ skin: Skin) -> some View {
        // Card-level state reads happen here, per render, straight off the live store (G3).
        let owned = ProfileStore.shared.profile.ownedSkins.contains(skin.id)
        let equipped = ProfileStore.shared.profile.selectedSkin == skin.id
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
                AnimatedCharacterSwatch(skin: skin, size: 56, silhouette: !owned)
                    .frame(height: 84)
                    .overlay(alignment: .bottomTrailing) {
                        if !owned, skin.cost == 0, !skin.premium {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Role.lock)
                        }
                    }
                Text(skin.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
