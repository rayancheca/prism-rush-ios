import SwiftUI
import AuthenticationServices

/// Profile hub — the progression home base (uiux §6.6): the level card (big numeral, XP ring,
/// next-unlock teaser) with the relocated settings gear, account sign-in, the stats grid (5+
/// runs) or the Next Milestone card, and the Game Center leaderboard row.
/// @Observable singletons are read directly in `body` so observation tracks them (G3 — wrapping
/// them in @State or snapshotting `profile` broke re-render in v1.0).
struct ProfileView: View {
    let model: GameModel
    private let account = AccountService.shared
    private let gc = GameCenterService.shared

    @ScaledMetric(relativeTo: .footnote) private var copySize: CGFloat = 13

    var body: some View {
        MetaScreenScaffold(title: "Profile", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }, onCoins: { model.open(.shop) }) {
            VStack(spacing: 18) {
                levelCard
                accountCard
                statsArea
                leaderboard
            }
        }
    }

    // MARK: level card (uiux §6.6 — the progression home base)

    private var levelCard: some View {
        let store = ProfileStore.shared
        let level = store.playerLevel
        let (cur, needed) = XPCurve.xpIntoLevel(for: store.profile.totalXP)
        let progress = needed > 0 ? Double(cur) / Double(needed) : 1
        return HStack(spacing: Theme.Space.m) {
            // The menu's level ring, grown up to 64 pt.
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(Theme.Role.interactive, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .scaledFont(26, weight: .heavy)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textPrimary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text("LEVEL \(level)")
                    .typeScale(.heading)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textPrimary)
                Text(needed > 0 ? "\(cur.formatted()) / \(needed.formatted()) XP" : "MAX LEVEL")
                    .typeScale(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textSecondary)
                nextUnlockTeaser(level: level)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .padding(.trailing, 36)   // room for the gear
        .neonCard(radius: Theme.Radius.l, raised: true)
        .overlay(alignment: .topTrailing) { settingsGear }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("levelCard")
        .accessibilityLabel(needed > 0
                            ? "Level \(level). \(cur) of \(needed) experience."
                            : "Level \(level). Max level.")
    }

    /// The relocated settings gear (uiux §1.2 — secondary chrome hides until a secondary place).
    private var settingsGear: some View {
        Button { model.open(.settings) } label: {
            Image(systemName: "gearshape.fill")
                .scaledFont(15, weight: .semibold, design: .default)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("settingsButton")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens settings.")
    }

    /// "LVL 12 · SHARD" chip with the skin's swatch dot → CharacterSelect (pull-forward).
    @ViewBuilder private func nextUnlockTeaser(level: Int) -> some View {
        if let nextLevel = XPCurve.xpUnlockLevels.first(where: { $0 > level }),
           let skin = SkinCatalog.all.first(where: { $0.unlock == .level(nextLevel) }) {
            Button { model.open(.characters) } label: {
                HStack(spacing: 5) {
                    Circle().fill(Theme.color(skin.bodyHex)).frame(width: 6, height: 6)
                    Text("LVL \(nextLevel) · \(skin.name.uppercased())")
                        .typeScale(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.interactive)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.Role.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Role.interactive.opacity(0.4)))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("nextUnlockTeaser")
            .accessibilityLabel("Next unlock at level \(nextLevel): \(skin.name).")
            .accessibilityHint("Opens characters.")
        }
    }

    // MARK: account

    @ViewBuilder private var accountCard: some View {
        VStack(spacing: 12) {
            if account.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .scaledFont(34, design: .default).foregroundStyle(Theme.Role.interactive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? "Signed in").scaledFont(16, weight: .bold).foregroundStyle(.white)
                        Text("Saves sync via iCloud").scaledFont(12).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button("Sign out") { account.signOut() }
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text("Sign in to secure your account across devices.")
                    .font(.system(size: copySize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                SignInWithAppleButton(.signIn, onRequest: { account.configure($0) }, onCompletion: { account.handle($0) })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if let error = account.lastError {
                    Text(error)
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(Theme.Role.danger)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .neonCard(radius: Theme.Radius.l)
    }

    // MARK: stats — milestone card below 5 runs, the grid once it earns its place (uiux §5.7)

    @ViewBuilder private var statsArea: some View {
        let runs = ProfileStore.shared.profile.totalRuns
        if runs == 0 {
            firstRunCard
        } else if runs < 5 {
            milestoneCard(runs: runs)
        } else {
            statsGrid
        }
    }

    /// Friendly zero-state instead of a wall of zeros before the first run.
    private var firstRunCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .scaledFont(26, design: .default)
                .foregroundStyle(Theme.Role.reward)
            Text("Your story starts with one run.")
                .scaledFont(16, weight: .bold)
                .foregroundStyle(.white)
            Text("Stats, streaks and worlds will fill in here the moment you hit PLAY.")
                .font(.system(size: copySize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 16)
        .neonCard(radius: Theme.Radius.l)
        .accessibilityElement(children: .combine)
    }

    /// <5 runs: a Next Milestone card replaces the early-game zero grid; tap → Missions.
    private func milestoneCard(runs: Int) -> some View {
        Button { model.open(.missions) } label: {
            VStack(spacing: 8) {
                Text("NEXT MILESTONE")
                    .typeScale(.micro)
                    .foregroundStyle(Theme.Role.textTertiary)
                Text("Finish 5 runs to light up your stats")
                    .typeScale(.heading)
                    .foregroundStyle(Theme.Role.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(runs) OF 5 RUNS · MISSIONS ARE LIVE NOW ›")
                    .typeScale(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.interactive)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22).padding(.horizontal, 16)
            .neonCard(radius: Theme.Radius.l)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("milestoneCard")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next milestone: finish 5 runs to light up your stats. \(runs) of 5 done.")
        .accessibilityHint("Opens missions.")
    }

    private var statsGrid: some View {
        let p = ProfileStore.shared.profile
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Tiles tap through where a destination exists (uiux §6.6): BEST → leaderboard
            // (when authenticated), WORLDS → the Worlds tab. The rest stay display-only.
            if gc.authenticated {
                Button { gc.showLeaderboard() } label: { statTile("BEST", "\(p.bestScore)") }
                    .buttonStyle(.neon)
                    .accessibilityHint("Opens the leaderboard.")
            } else {
                statTile("BEST", "\(p.bestScore)")
            }
            statTile("RUNS", "\(p.totalRuns)")
            Button { model.open(.levels) } label: { statTile("WORLDS", "\(p.maxWorldReached + 1)") }
                .buttonStyle(.neon)
                .accessibilityHint("Opens world select.")
            statTile("GEMS", "\(p.totalGems)")
            statTile("BEST STREAK", "\(p.bestStreak)")
            statTile("DISTANCE", "\(Int(p.totalDistance))m")
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).scaledFont(19, weight: .heavy).monospacedDigit().foregroundStyle(.white)
            Text(label).scaledFont(10, weight: .semibold).tracking(1).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .neonCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized): \(value)")
    }

    // MARK: leaderboard

    @ViewBuilder private var leaderboard: some View {
        if gc.authenticated {
            Button { gc.showLeaderboard() } label: {
                row("trophy.fill", "Friends Leaderboard", Theme.Role.reward)
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("leaderboardRow")
        } else {
            // Inline signed-out state instead of a row that silently does nothing.
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .scaledFont(17, weight: .semibold, design: .default)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboards need Game Center")
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Sign in from the Settings app, then relaunch.")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(16)
            .neonCard()
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).scaledFont(17, weight: .semibold, design: .default).foregroundStyle(tint).frame(width: 24)
            Text(title).scaledFont(15, weight: .semibold).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").scaledFont(13, weight: .bold, design: .default).foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .neonCard()
    }
}
