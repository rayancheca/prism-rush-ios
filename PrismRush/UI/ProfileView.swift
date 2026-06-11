import SwiftUI
import AuthenticationServices

/// Profile / account hub: lifetime stats, Sign in with Apple, and the Game Center friends
/// leaderboard. (Restore Purchases lives in Settings.)
struct ProfileView: View {
    let model: GameModel
    // @Observable singletons are read directly in `body` so observation tracks them. (Wrapping them
    // in @State snapshots the reference and breaks re-render on change — the sign-in/equip bugs.)
    private let account = AccountService.shared
    private let gc = GameCenterService.shared

    @ScaledMetric(relativeTo: .footnote) private var copySize: CGFloat = 13

    var body: some View {
        let p = ProfileStore.shared.profile
        MetaScreenScaffold(title: "Profile", coins: p.coins, onClose: { model.closeSheet() }) {
            VStack(spacing: 18) {
                accountCard
                if p.totalRuns == 0 {
                    firstRunCard
                } else {
                    statsGrid(p)
                }
                leaderboard
            }
        }
    }

    @ViewBuilder private var accountCard: some View {
        VStack(spacing: 12) {
            if account.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(Theme.color(0x00F5FF))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? "Signed in").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("Saves sync via iCloud").font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button("Sign out") { account.signOut() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.4))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
    }

    /// Friendly zero-state instead of a wall of zeros before the first run.
    private var firstRunCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(Theme.color(0xFFD23D))
            Text("Your story starts with one run.")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Stats, streaks and worlds will fill in here the moment you hit PLAY.")
                .font(.system(size: copySize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    private func statsGrid(_ p: Profile) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile("BEST", "\(p.bestScore)")
            statTile("RUNS", "\(p.totalRuns)")
            statTile("WORLDS", "\(p.maxWorldReached + 1)")
            statTile("GEMS", "\(p.totalGems)")
            statTile("BEST STREAK", "\(p.bestStreak)")
            statTile("DISTANCE", "\(Int(p.totalDistance))m")
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized): \(value)")
    }

    @ViewBuilder private var leaderboard: some View {
        if gc.authenticated {
            Button { gc.showLeaderboard() } label: {
                row("trophy.fill", "Friends Leaderboard", Theme.color(0xFFD23D))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("leaderboardRow")
        } else {
            // Inline signed-out state instead of a row that silently does nothing.
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboards need Game Center")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Sign in from the Settings app, then relaunch.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
    }
}
