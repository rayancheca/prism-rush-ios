import SwiftUI

/// The menu hub — redesigned in S-005 (PR-0452) after the owner's *"it just doesn't feel right"*.
///
/// The v1.3 hub was nine centre-aligned rows ending in six identically-sized tiles, which put
/// "claim your coins" and "go to the shop" in the same visual class and left PLAY sandwiched
/// between two equally-tappable chips. The fix is not nicer padding: it is to stop drawing three
/// different KINDS of thing the same way. The hub now has **three species of surface**, and a
/// player can tell them apart without reading a word:
///
/// 1. **Gradient — the verb.** PLAY, and nothing else. A lit claim ribbon is the one other filled
///    surface and it is gold, the money role, never the action gradient.
/// 2. **Cards — objects you act on.** The claim ribbon, the Daily Rush launcher, the loadout chips.
///    Surface fill + hairline. They appear, change and disappear with your state.
/// 3. **Bare rail — exits.** Characters / Shop / Worlds / Missions sit under a hairline at the
///    bottom edge with no card chrome at all. Navigation looks like navigation.
///
/// The centre axis is broken by an editorial masthead: wordmark hard left, world dateline hard
/// right, a rule under both. Only the hero and PLAY stay centred, which is what makes them read
/// as the two focal objects instead of as two more rows in a stack.
///
/// Decrees: the hero resolves through `SkinCatalog` so the stage always shows the skin the run
/// actually plays (2); every element routes somewhere (4); nothing pulses and one gradient family
/// owns the screen (6). All profile state is read from `ProfileStore.shared` directly in `body`,
/// and `loadout` stays a concrete typed child — `AnyView` there severed observation once and
/// shipped the "Head Start does nothing" bug (G3 / invariant 6).
struct MenuView<Loadout: View>: View {
    let best: Int
    let coins: Int
    let onPlay: () -> Void
    let onCharacters: () -> Void
    let onShop: () -> Void
    let onLevels: () -> Void
    let onProfile: () -> Void
    var onSettings: () -> Void = {}
    /// Missions is a *destination* now, not a reward cell — it sits in the nav rail and carries a
    /// gold count badge when the board has claimables.
    var onMissions: () -> Void = {}
    /// Daily Rush is a *way to start a run*, so it sits beside PLAY rather than in a rewards rail.
    /// Routes through the model's first-run tutorial gate exactly as before.
    var onDailyRush: () -> Void = {}
    var onClaimDaily: () -> Void = {}
    var onOpenChest: () -> Void = {}
    /// Pre-run loadout chips (LoadoutStrip) — a CONCRETE typed child (not AnyView) so its
    /// @Observable arm-state reads update reactively when tapped.
    let loadout: Loadout
    /// FIRST RUN › destination when best == 0 (HowToPlay). Falls back to `onPlay`, whose first-run
    /// gate already routes through the tutorial.
    var onHowToPlay: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            masthead        // A — identity + wordmark + world dateline, under one rule
            heroZone        // B — the equipped character on its stage (takes the slack)
            launchDeck      // C — claim ribbon, loadout, PLAY | DAILY
            navRail         // D — the four exits, no card chrome
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // The sanctioned 6% world-tinted ambient that tracks the deepest startable world —
            // the 3D scene glows through it.
            RadialGradient(colors: [furthestAccent.opacity(0.06), .clear],
                           center: .bottom, startRadius: 10, endRadius: 520).ignoresSafeArea()
        )
    }

    /// Deepest STARTABLE world (reach OR purchase) — the same expression `LevelSelectView` uses for
    /// its header, so the hub can never disagree with the screen it routes to.
    private var furthestStartableWorld: Int { ProfileStore.shared.highestStartableWorld }

    private var furthestAccent: Color {
        Theme.color(Theme.evolvedPalette(ordinal: furthestStartableWorld).accent)
    }

    // MARK: - A · masthead

    /// Two tiers under a hairline rule. Tier one is two balanced clusters — identity on the left
    /// (level ring + best), resources on the right (coins + gear) — which fixes the old hub's lone
    /// ring facing a coin pill and a gear. Tier two is the editorial line: wordmark hard left,
    /// world dateline hard right. Nothing here is centred.
    private var masthead: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                levelRing
                bestChip
                Spacer(minLength: Theme.Space.s)
                coinBadge
                settingsGear
            }
            .frame(height: 44)

            HStack(alignment: .center, spacing: Theme.Space.m) {
                LogoMark(size: 24)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                worldDateline
            }

            Rectangle()
                .fill(Theme.Role.hairline)
                .frame(height: 1)
        }
    }

    /// Profile entry as a level-ring avatar: the player's level inside a cyan XP-progress ring.
    private var levelRing: some View {
        let store = ProfileStore.shared
        let level = store.playerLevel
        let (cur, needed) = XPCurve.xpIntoLevel(for: store.profile.totalXP)
        let progress = needed > 0 ? Double(cur) / Double(needed) : 1
        return Button(action: onProfile) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(Theme.Role.interactive, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .typeScale(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textPrimary)
            }
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("profileButton")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level >= XPCurve.maxLevel
                            ? "Profile. Level \(level), max level."
                            : "Profile. Level \(level), \(Int(progress * 100)) percent to level \(level + 1).")
        .accessibilityHint("Opens your profile and stats.")
    }

    /// BEST / FIRST RUN — promoted out of the old chip sandwich under PLAY and into the identity
    /// cluster, where it belongs: it is a fact about the player, not a second call to action.
    /// Carries a full 44 pt target now (PR-0150); it was ~25 pt while every sibling was 44.
    private var bestChip: some View {
        Button(action: best == 0 ? (onHowToPlay ?? onPlay) : onProfile) {
            HStack(spacing: 4) {
                Text(best == 0 ? "FIRST RUN" : "BEST \(best.formatted())")
                    .foregroundStyle(Theme.Role.textSecondary)
                    .monospacedDigit()
                Text("›").foregroundStyle(.white.opacity(0.55))
            }
            .typeScale(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.Role.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("bestChip")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(best == 0 ? "First run." : "Best score \(best).")
        .accessibilityHint(best == 0 ? "Shows how to play." : "Opens your stats.")
    }

    private var coinBadge: some View {
        Button(action: onShop) {
            CoinBadge(amount: coins)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Role.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Role.hairline))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coins) coins")
        .accessibilityHint("Opens the shop.")
    }

    private var settingsGear: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Role.textSecondary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Role.hairline))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("settingsButton")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens settings.")
    }

    /// The masthead's dateline: two right-aligned micro lines opposite the wordmark, magazine-style.
    /// Framed as FURTHEST — deliberately not "current world", which would contradict the Pulse City
    /// backdrop PLAY actually launches into. The numeral is the single sanctioned spot of world
    /// colour on the hub. Replaces the full-width chip that used to sit directly above PLAY.
    private var worldDateline: some View {
        let worldIdx = furthestStartableWorld
        let palette = Theme.evolvedPalette(ordinal: worldIdx)
        let checkpointM = Int(Double(worldIdx) * Tuning.worldLength)
        return Button(action: onLevels) {
            VStack(alignment: .trailing, spacing: 2) {
                // Label line, then the data line carrying the affordance — a chevron on the label
                // left both lines ragged and pushed the world name into the page margin.
                Text("FURTHEST").foregroundStyle(Theme.Role.textTertiary)
                HStack(spacing: 5) {
                    Text(String(format: "%02d", worldIdx + 1))
                        .foregroundStyle(Theme.color(palette.accent2))
                        .fontWeight(.heavy)
                        .monospacedDigit()
                    Text(palette.name.uppercased())
                        .foregroundStyle(Theme.Role.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.Role.textTertiary)
                }
            }
            .typeScale(.micro)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldProgressChip")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Furthest world \(worldIdx + 1), \(palette.name), checkpoint at \(checkpointM) meters.")
        .accessibilityHint("Opens world select.")
    }

    // MARK: - B · hero stage

    /// The character gets the slack now that the wordmark and the world chip have moved into the
    /// masthead. The stage takes the slot EXACTLY — no floor and no cap. A floor is what let the old
    /// `max(140, …)` overflow a short screen (PR-0149); a cap left a dead band between the name pill
    /// and the launch deck on a tall one. `CharacterHeroStage` derives every measurement from the
    /// height it is handed, so "whatever the slot offers" is the only correct argument.
    private var heroZone: some View {
        GeometryReader { geo in
            heroStageButton(height: geo.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The whole stage (character + glow disc + name pill) is ONE button → Characters.
    private func heroStageButton(height: CGFloat) -> some View {
        // The resolver, never raw `selectedSkin` (decree 2): the stage must show the skin the run
        // actually plays, so "Running as X. Equipped." can't claim a locked cosmetic.
        let skin = SkinCatalog.skin(ProfileStore.shared.equippedSkinID)
        return Button(action: onCharacters) {
            CharacterHeroStage(skin: skin, height: height)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("heroStage")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running as \(skin.name). Equipped.")
        .accessibilityHint("Opens characters.")
    }

    // MARK: - C · launch deck

    /// Everything that is about *the next run*, in the order you decide it: what's waiting for you,
    /// what you're bringing, how you start, and then the one alternative way to start.
    ///
    /// **PLAY takes the full width** (the owner's call, S-005): a Daily Rush block beside it was
    /// eating a third of the primary verb's span to say something secondary. Daily Rush drops
    /// underneath as a light 48 pt row, which also puts the reading order the right way round —
    /// primary first, alternative second — while keeping the two run-starting verbs adjacent.
    private var launchDeck: some View {
        VStack(spacing: Theme.Space.s) {
            ClaimRibbon(onClaimDaily: onClaimDaily, onOpenChest: onOpenChest)
            // Pinned to the deck's left edge rather than centred: the ribbon, the chips and PLAY
            // now share one leading edge, which is the same spine the masthead's wordmark sits on.
            // The `Spacer` wrapper keeps `loadout` a concrete typed child — only `AnyView` severs
            // observation (G3).
            // Centred and sitting directly on PLAY: the loadout IS the run's cargo, so it reads as
            // part of the launch control rather than as its own half-empty bar (S-007, owner call).
            loadout
            playButton
            DailyRushRow(onDailyRush: onDailyRush)
        }
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Text("PLAY")
                .font(.system(size: 28, weight: .black, design: .rounded)).tracking(4)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 78)
                .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                // A one-pixel light edge along the top: the only depth cue on the screen that isn't
                // a shadow, and what stops the gradient reading as a flat sticker. Static — the
                // repeatForever pulse stays deleted (decree 6).
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: 1)
                )
                .shadow(color: Theme.Role.interactive.opacity(0.38), radius: 26, y: 6)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("playButton")
    }

    // MARK: - D · nav rail

    /// The four exits, under a hairline, with no card chrome — the single change that stops
    /// navigation and rewards reading as the same class of object. Each keeps the neon hue it owned
    /// as a tile (the owner's "so light gray I'd have to click each to know what it is"), but the
    /// hue now rides the glyph alone.
    private var navRail: some View {
        VStack(spacing: Theme.Space.s) {
            Rectangle()
                .fill(Theme.Role.hairline)
                .frame(height: 1)
            // Slow tick so the Missions badge survives a UTC day rollover while the player sits on
            // the hub — `unclaimedCount` is date-dependent, and profile observation alone would not
            // fire when the only thing that changed is the date.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 0) {
                    navItem("person.fill", "Characters", tint: Theme.color(0x00F5FF),
                            action: onCharacters, dot: hasUnseenSkins,
                            identifier: "charactersButton")
                    navItem("cart.fill", "Shop", tint: Theme.color(0xFFD23D),
                            action: onShop, identifier: "shopButton")
                    navItem("map.fill", "Worlds", tint: Theme.color(0xFF2BD6),
                            action: onLevels, identifier: "worldsButton")
                    navItem("target", "Missions", tint: Theme.color(0xB26BFF),
                            action: onMissions,
                            count: ProfileStore.shared.unclaimedCount(now: context.date),
                            identifier: "railMissions")
                }
            }
        }
    }

    /// Cyan badge-dot on Characters when an owned skin hasn't been seen yet (derived from
    /// `seenSkins`, no new profile field).
    private var hasUnseenSkins: Bool {
        !ProfileStore.shared.profile.ownedSkins
            .subtracting(ProfileStore.shared.profile.seenSkins).isEmpty
    }

    private func navItem(_ symbol: String, _ title: String, tint: Color,
                         action: @escaping () -> Void, dot: Bool = false, count: Int = 0,
                         identifier: String) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 26)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(minWidth: 16)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Theme.goldGradient, in: Capsule())
                                .offset(x: 8, y: -4)
                        } else if dot {
                            Circle().fill(tint).frame(width: 7, height: 7).offset(x: 4, y: -1)
                        }
                    }
                Text(title.uppercased())
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        // NO `.accessibilityElement(children: .ignore)` here, unlike the rail: it stops the item
        // surfacing as a `.button`, and `InteractionUITests` looks every nav exit up as one.
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(count > 0 ? "\(title). \(count) rewards ready to claim."
                            : dot ? "\(title). New character available."
                            : title)
    }
}
