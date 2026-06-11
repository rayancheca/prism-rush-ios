import SwiftUI

/// Death panel: counted-up final score, NEW BEST / delta-to-best, a run-stats grid, the coin
/// breakdown, CONTINUE (always visible while revives remain; unaffordable = "NEED N MORE" +
/// GET COINS), and the READY-IN-gated RUN AGAIN.
///
/// Every new field is defaulted so the pre-overhaul `GameView` call site still compiles; the full
/// wiring (run stats, previousBest, revivesLeft, restartCountdown, onGetCoins) is specced in
/// reports/AGENT_meta.md.
struct GameOverView: View {
    let snapshot: GameSnapshot
    let coinsEarned: Int
    let canRestart: Bool
    let canRevive: Bool
    let reviveCost: Int
    let onRevive: () -> Void
    let onRestart: () -> Void
    let onHome: () -> Void

    // — New, defaulted (see AGENT_meta.md §GameView wiring) —
    /// Best score BEFORE this run started. By death time the profile best already includes this
    /// run, so `snapshot.score >= snapshot.best` is true for ties — only a strict beat is a record.
    var previousBest: Int? = nil
    /// `core.traveledDistance` — excludes the checkpoint head start (snapshot.distance includes it).
    var runDistance: Double? = nil
    /// Wall-clock seconds spent in `.play` this run (0 hides the tile's value as 0:00 gracefully).
    var timeSurvived: Double = 0
    var bestStreak: Int = 0
    var nearMisses: Int = 0
    /// Exact coin breakdown (post-revive deltas make local derivation wrong — pass all three or none).
    var coinsFromGems: Int? = nil
    var coinsFromDistance: Int? = nil
    var coinsFromWorlds: Int? = nil
    /// Revives still available this run (`2 - core.revivesUsed`). nil → legacy gating on `canRevive`.
    var revivesLeft: Int? = nil
    /// Whole seconds until RUN AGAIN unlocks (`GameModel.restartCountdown`).
    var restartCountdown: Int = 0
    /// Routes to the Shop when the player can't afford a revive. nil hides GET COINS.
    var onGetCoins: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var statSize: CGFloat = 13
    @State private var countedUp = false

    private var effectiveBest: Int { previousBest ?? snapshot.best }
    private var isNewBest: Bool {
        guard snapshot.score > 0 else { return false }
        if let pb = previousBest { return snapshot.score > pb }
        return snapshot.score >= snapshot.best   // legacy heuristic until previousBest is wired
    }
    private var distance: Double { runDistance ?? snapshot.distance }
    private var topMult: Int { min(Tuning.multCap, 1 + bestStreak / Tuning.streakPerMult) }
    private var balance: Int { ProfileStore.shared.profile.coins }
    private var revivesRemain: Bool { revivesLeft.map { $0 > 0 } ?? canRevive }
    private var affordable: Bool { balance >= reviveCost }
    private var doubled: Bool { ProfileStore.shared.profile.doubleCoins }

    private var worldReached: String {
        let ordinal = max(0, Int((snapshot.distance / Tuning.worldLength).rounded(.down)))
        return "World \(ordinal + 1) · \(Theme.worlds[ordinal % 3].name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SHATTERED")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.37))
                .shadow(color: Color(red: 1, green: 0.37, blue: 0.37).opacity(0.5), radius: 18)

            // Score counts up from 0 (numeric content transition); instant under Reduce Motion.
            Text("\(countedUp ? snapshot.score : 0)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(countedUp ? snapshot.score : 0)))
                .padding(.top, 8)
                .accessibilityLabel("Score \(snapshot.score)")

            if isNewBest {
                Text("★ NEW BEST ★")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.24))
                    .shadow(color: Color(red: 1, green: 0.82, blue: 0.24), radius: 10)
                    .padding(.top, 2)
            } else if effectiveBest > snapshot.score {
                Text("BEST \(effectiveBest) · \(effectiveBest - snapshot.score) TO GO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 2)
            }

            coinLine

            statsGrid
                .padding(.top, 14)

            VStack(spacing: 0) {
                statRow("Reached", worldReached)
                statRow("Balance", "\(balance)")
            }
            .padding(.top, 6)

            if revivesRemain {
                continueSection
                    .padding(.top, 16)
            }

            Button(action: onRestart) {
                Text(restartLabel)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.color(0x00F5FF).opacity(0.35), radius: 20)
            }
            .buttonStyle(.neon)
            .disabled(!canRestart)
            .opacity(canRestart ? 1 : 0.55)
            .accessibilityIdentifier("runAgainButton")
            .padding(.top, revivesRemain ? 12 : 22)

            Button(action: onHome) {
                Text("BACK TO MENU")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("backToMenuButton")
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45).ignoresSafeArea())
        .onAppear {
            if reduceMotion { countedUp = true }
            else { withAnimation(.easeOut(duration: 0.7)) { countedUp = true } }
        }
    }

    // MARK: coins

    @ViewBuilder private var coinLine: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                CoinBadge(amount: countedUp ? coinsEarned : 0, prefix: "+")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.24))
                if doubled {
                    Text("×2")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.goldGradient, in: Capsule())
                        .accessibilityLabel("Double coins active")
                }
            }
            if let gems = coinsFromGems, let dist = coinsFromDistance, let world = coinsFromWorlds {
                Text(breakdown(gems: gems, dist: dist, world: world))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if !doubled, let onGetCoins {
                Button(action: onGetCoins) {
                    Text("EARN ×2 WITH DOUBLE COINS →")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.color(0xFFD23D).opacity(0.9))
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("doublerUpsell")
            }
        }
        .padding(.top, 10)
    }

    private func breakdown(gems: Int, dist: Int, world: Int) -> String {
        var parts: [String] = []
        if gems > 0 { parts.append("\(gems) gems") }
        if dist > 0 { parts.append("\(dist) distance") }
        if world > 0 { parts.append("\(world) world") }
        guard !parts.isEmpty else { return "" }
        return "= " + parts.joined(separator: " · ")
    }

    // MARK: stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statTile("DISTANCE", "\(Int(distance))m")
            statTile("TIME", timeString(timeSurvived))
            statTile("STREAK", bestStreak > 0 ? "\(bestStreak) · ×\(topMult)" : "—")
            statTile("NEAR MISSES", "\(nearMisses)")
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized): \(value)")
    }

    private func timeString(_ secs: Double) -> String {
        let s = max(0, Int(secs.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: continue

    @ViewBuilder private var continueSection: some View {
        Button(action: onRevive) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.heart.fill")
                Text(affordable ? "CONTINUE" : "NEED \(reviveCost - balance) MORE").tracking(2)
                Spacer()
                Text("\(reviveCost)")
                CoinGlyph(size: 16)
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.color(0xFFD23D).opacity(affordable ? 0.4 : 0.15), radius: 18)
        }
        .buttonStyle(.neon)
        .disabled(!affordable)
        .opacity(affordable ? 1 : 0.55)
        .accessibilityIdentifier("continueButton")
        .accessibilityLabel(affordable
                            ? "Continue for \(reviveCost) coins"
                            : "Continue costs \(reviveCost) coins — you need \(reviveCost - balance) more")

        if !affordable, let onGetCoins {
            Button(action: onGetCoins) {
                HStack(spacing: 6) {
                    Image(systemName: "cart.fill")
                    Text("GET COINS").tracking(2)
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.color(0xFFD23D))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.color(0xFFD23D).opacity(0.45)))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("getCoinsButton")
            .padding(.top, 8)
        }
    }

    private var restartLabel: String {
        if canRestart { return "RUN AGAIN" }
        return restartCountdown > 0 ? "READY IN \(restartCountdown)…" : "READY…"
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: statSize, design: .rounded))
        .padding(.vertical, 7)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.12)), alignment: .top)
        .accessibilityElement(children: .combine)
    }
}
