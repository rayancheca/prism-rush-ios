import SwiftUI

/// The menu hub, reframed as "Hero, Verb, Rail, Nav" (uiux §1): a level-ring avatar and tappable
/// coin badge up top, the equipped character idling on its glow stage as the identity carrier,
/// PLAY as the only gradient on screen, the 3-cell rewards rail, and a demoted nav row.
/// Everything on screen is tappable and leads somewhere; all profile-derived state is read from
/// `ProfileStore.shared` directly in `body` (G3).
struct MenuView: View {
    let best: Int
    let coins: Int
    let onPlay: () -> Void
    let onCharacters: () -> Void
    let onShop: () -> Void
    let onLevels: () -> Void
    let onProfile: () -> Void
    var rewards: AnyView = AnyView(EmptyView())
    /// Legacy (v1.2) — the settings gear moved to ProfileView's header; kept defaulted so
    /// GameView's call site compiles until the wave-5 rewire prunes it (R13).
    var onSettings: () -> Void = {}
    /// Legacy (v1.2) — Daily Rush now lives inside the rewards rail (RewardsBar starts it).
    var onDailyChallenge: () -> Void = {}
    /// FIRST RUN › destination when best == 0 (HowToPlay). Falls back to `onPlay`, whose
    /// first-run gate already routes through the tutorial; wave 5 wires it directly.
    var onHowToPlay: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            statusStrip          // A — level ring ←→ coin badge (44 pt)
            heroZone             // B — wordmark, idle character stage, world chip (flex)
            playZone             // C — PLAY + best chip
            rewards              // D — the 3-cell rewards rail (RewardsBar)
            navRow               // E — Characters | Shop | Worlds
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // The magenta radial is gone (uiux §2.1): just the sanctioned 6% world-tinted
            // ambient that tracks the furthest world — the 3D scene glows through.
            RadialGradient(colors: [furthestAccent.opacity(0.06), .clear],
                           center: .bottom, startRadius: 10, endRadius: 520).ignoresSafeArea()
        )
    }

    private var furthestAccent: Color {
        Theme.color(Theme.worlds[(ProfileStore.shared.unlockedWorldCount - 1) % 3].accent)
    }

    // MARK: zone A — status strip

    private var statusStrip: some View {
        HStack {
            levelRing
            Spacer()
            Button(action: onShop) {
                CoinBadge(amount: coins)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Role.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
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
        .frame(height: 44)
    }

    /// Profile entry as a level-ring avatar: the player's level inside a cyan XP-progress ring
    /// (reads `ProfileStore.shared.playerLevel` + `XPCurve.xpIntoLevel` live in body).
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

    // MARK: zone B — hero stage

    private var heroZone: some View {
        VStack(spacing: Theme.Space.s) {
            // One-line lockup — the wordmark's gradient allowance (same family as PLAY).
            Text("PRISM RUSH")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .tracking(6)
                .foregroundStyle(Theme.actionGradient)
                .shadow(color: Theme.color(0xFF2BD6).opacity(0.5), radius: 10)
            GeometryReader { geo in
                heroStageButton(height: min(260, max(140, geo.size.height)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            worldProgressChip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The whole stage (character + glow disc + name pill) is ONE button → Characters. The hero
    /// stage IS the buddy chip (R6) — "Running as …" survives as its VoiceOver label.
    private func heroStageButton(height: CGFloat) -> some View {
        let skin = SkinCatalog.skin(ProfileStore.shared.profile.selectedSkin)
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

    /// One world-progress chip replaces the three dead world chips: the numeral is the single
    /// sanctioned spot of world color on the menu (uiux §1.3). Tap → Worlds.
    private var worldProgressChip: some View {
        let worldIdx = ProfileStore.shared.unlockedWorldCount - 1   // furthest start world, 0-based
        let palette = Theme.worlds[worldIdx % 3]
        let checkpointM = Int(Double(worldIdx) * Tuning.worldLength)
        return Button(action: onLevels) {
            HStack(spacing: 5) {
                Text("WORLD").foregroundStyle(Theme.Role.textSecondary)
                Text(String(format: "%02d", worldIdx + 1))
                    .foregroundStyle(Theme.color(palette.accent2))
                    .fontWeight(.heavy)
                Text("· \(palette.name.uppercased())\(checkpointM > 0 ? " · \(checkpointM.formatted())M" : "")")
                    .foregroundStyle(Theme.Role.textSecondary)
            }
            .typeScale(.micro)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.Role.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldProgressChip")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World \(worldIdx + 1), \(palette.name), checkpoint at \(checkpointM) meters.")
        .accessibilityHint("Opens world select.")
    }

    // MARK: zone C — PLAY + best chip

    private var playZone: some View {
        VStack(spacing: Theme.Space.s) {
            Button(action: onPlay) {
                Text("PLAY")
                    .font(.system(size: 24, weight: .black, design: .rounded)).tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 64)
                    .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                    // The repeatForever pulse is deleted — a static cyan glow carries the verb.
                    .shadow(color: Theme.Role.interactive.opacity(0.35), radius: 24)
            }
            .buttonStyle(.neon)
            .padding(.horizontal, Theme.Space.s)
            .accessibilityIdentifier("playButton")
            bestChip
        }
    }

    private var bestChip: some View {
        Button(action: best == 0 ? (onHowToPlay ?? onPlay) : onProfile) {
            HStack(spacing: 4) {
                Text(best == 0 ? "FIRST RUN" : "BEST \(best.formatted())")
                    .foregroundStyle(Theme.Role.textSecondary)
                    .monospacedDigit()
                Text("›").foregroundStyle(.white.opacity(0.55))
            }
            .typeScale(.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.Role.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("bestChip")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(best == 0 ? "First run." : "Best score \(best).")
        .accessibilityHint(best == 0 ? "Shows how to play." : "Opens your stats.")
    }

    // MARK: zone E — nav row

    private var navRow: some View {
        HStack(spacing: Theme.Space.m - 4) {
            navButton("person.fill", "Characters", action: onCharacters, badge: hasUnseenSkins)
            navButton("cart.fill", "Shop", action: onShop)
            navButton("map.fill", "Worlds", action: onLevels)
        }
    }

    /// Cyan badge-dot on Characters when an owned skin hasn't been seen yet (R11 — derived from
    /// `seenSkins`, no new profile field).
    private var hasUnseenSkins: Bool {
        !ProfileStore.shared.profile.ownedSkins
            .subtracting(ProfileStore.shared.profile.seenSkins).isEmpty
    }

    private func navButton(_ symbol: String, _ title: String,
                           action: @escaping () -> Void, badge: Bool = false) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title.uppercased()).typeScale(.micro)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Role.hairline))
            .overlay(alignment: .topTrailing) {
                if badge {
                    Circle().fill(Theme.Role.interactive)
                        .frame(width: 6, height: 6)
                        .padding(Theme.Space.s)
                }
            }
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("\(title.lowercased())Button")
        .accessibilityLabel(badge ? "\(title). New character available." : title)
    }
}
