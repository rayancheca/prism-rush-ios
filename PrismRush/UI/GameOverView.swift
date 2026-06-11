import SwiftUI

/// Death panel in three bands (uiux §6.7): the score you read, the money + XP you earned, then
/// the verbs. Band 2 carries the tap-to-expand coin breakdown (GEMS & BONUSES / DISTANCE /
/// WORLDS / STYLE), the XP line + level-up burst, the NEW CHARACTER deep link, and — on challenge
/// deaths — the 7-day dot strip and tier payout line. Reached/Balance rows are deleted (the world
/// lives in the distance chip; the balance lives in the coin badge).
///
/// Every v1.3 field is defaulted so the v1.2 `GameView` call site still compiles (R13); wave 5
/// passes `levelUp` / `styleCoins` / `challengePayout` / `isChallengeRun` and the two routes.
struct GameOverView: View {
    let snapshot: GameSnapshot
    let coinsEarned: Int
    let canRestart: Bool
    let canRevive: Bool
    let reviveCost: Int
    let onRevive: () -> Void
    let onRestart: () -> Void
    let onHome: () -> Void

    // — v1.2 wiring (kept verbatim — R13) —
    /// Best score BEFORE this run started. By death time the profile best already includes this
    /// run, so `snapshot.score >= snapshot.best` is true for ties — only a strict beat is a record.
    var previousBest: Int? = nil
    /// `core.traveledDistance` — excludes the checkpoint head start (snapshot.distance includes it).
    var runDistance: Double? = nil
    /// Legacy (v1.2): the TIME tile is gone in the 3-band layout; accepted-but-ignored (R13).
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

    // — v1.3 (all defaulted; wave 5 wires them — V13_SPEC §C.4) —
    /// XP/level outcome of this run (`ProfileStore.applyRunSummary`). nil hides the XP band.
    var levelUp: LevelUpResult? = nil
    /// The 4th per-death coin delta (CLOSE/SLICK style coins) — its own breakdown line.
    var styleCoins: Int = 0
    /// Challenge-tier payout from `recordChallengeRun` (0 = no new tier crossed).
    var challengePayout: Int = 0
    /// Challenge deaths only: shows the 7-day dot strip + tier line.
    var isChallengeRun: Bool = false
    /// NEW CHARACTER UNLOCKED · TAP → Characters (wave 5 routes it; nil = inert label).
    var onCharacters: (() -> Void)? = nil
    /// FULL STATS › → ProfileView (hidden until wave 5 wires it — sheets over `.over` are gated).
    var onFullStats: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var countedUp = false
    @State private var breakdownExpanded = false

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
    private var hasBreakdown: Bool { coinsFromGems != nil && coinsFromDistance != nil && coinsFromWorlds != nil }

    private var worldOrdinal: Int {
        max(0, Int((snapshot.distance / Tuning.worldLength).rounded(.down)))
    }

    var body: some View {
        VStack(spacing: 0) {
            scoreBand          // 1 — the number you read
            earnBand           // 2 — the number you earned (+ XP)
            statsBand          // 3 — two chips + FULL STATS
                .padding(.top, 14)

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
                    .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .shadow(color: Theme.Role.interactive.opacity(0.35), radius: 20)
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
            // Count-up + XP-bar fill ride the same flag; instant under Reduce Motion.
            if reduceMotion { countedUp = true }
            else { withAnimation(.easeOut(duration: 0.7)) { countedUp = true } }
        }
    }

    // MARK: band 1 — score

    @ViewBuilder private var scoreBand: some View {
        Text("SHATTERED")
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(Theme.Role.danger)
            .shadow(color: Theme.Role.danger.opacity(0.5), radius: 18)

        // Score counts up from 0 (numeric content transition); instant under Reduce Motion.
        Text("\(countedUp ? snapshot.score : 0)")
            .font(.system(size: 56, weight: .black, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(countedUp ? snapshot.score : 0)))
            .padding(.top, 8)
            .accessibilityLabel("Score \(snapshot.score)")

        // ONE context line: the record, or the gap to it.
        if isNewBest {
            Text("★ NEW BEST ★")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.Role.reward)
                .shadow(color: Theme.Role.reward, radius: 10)
                .padding(.top, 2)
        } else if effectiveBest > snapshot.score {
            Text("BEST \(effectiveBest) · \(effectiveBest - snapshot.score) TO GO")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)
        }
    }

    // MARK: band 2 — coins + XP

    @ViewBuilder private var earnBand: some View {
        VStack(spacing: 6) {
            coinLine
            if breakdownExpanded, hasBreakdown { breakdownRows }
            if challengePayout > 0 { challengeTierLine }
            if let levelUp { xpBlock(levelUp) }
            if isChallengeRun { challengeDots }
        }
        .padding(.top, 10)
    }

    /// `+240 ⌄` — the earn line is the disclosure for its own itemized breakdown (uiux §5.3).
    @ViewBuilder private var coinLine: some View {
        VStack(spacing: 4) {
            Button {
                guard hasBreakdown else { return }
                withAnimation(.spring(duration: 0.25)) { breakdownExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    CoinBadge(amount: countedUp ? coinsEarned : 0, prefix: "+")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Role.reward)
                    if doubled {
                        Text("×2")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.goldGradient, in: Capsule())
                    }
                    if hasBreakdown {
                        Image(systemName: breakdownExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.neon)
            .disabled(!hasBreakdown)
            .accessibilityIdentifier("coinBreakdownToggle")
            .accessibilityLabel("Earned \(coinsEarned) coins\(doubled ? ", doubled" : "")")
            .accessibilityHint(hasBreakdown ? "Shows the coin breakdown." : "")

            if !doubled, let onGetCoins {
                // The ×2 state taps through to the shop's Double Coins row when not owned.
                Button(action: onGetCoins) {
                    Text("EARN ×2 WITH DOUBLE COINS →")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.Role.reward.opacity(0.9))
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("doublerUpsell")
            }
        }
    }

    /// Itemized rows — gem-channel money is labeled GEMS & BONUSES because ring coins, boost gem
    /// bonuses and flow fountains all flow through the gem channel (R8).
    private var breakdownRows: some View {
        VStack(spacing: 0) {
            breakdownRow("GEMS & BONUSES", coinsFromGems ?? 0)
            breakdownRow("DISTANCE", coinsFromDistance ?? 0)
            breakdownRow("WORLDS", coinsFromWorlds ?? 0)
            if styleCoins > 0 { breakdownRow("STYLE", styleCoins) }
        }
        .padding(.vertical, 4)
        .transition(.opacity)
    }

    private func breakdownRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text("+\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Role.reward.opacity(0.9))
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var challengeTierLine: some View {
        Text("CHALLENGE TIER \(ProfileStore.shared.profile.challengeRewardTier) · +\(challengePayout)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .monospacedDigit()
            .foregroundStyle(Theme.Role.reward)
            .shadow(color: Theme.Role.reward.opacity(0.6), radius: 8)
            .accessibilityLabel("Challenge tier \(ProfileStore.shared.profile.challengeRewardTier) reached, plus \(challengePayout) coins")
    }

    /// XP line + 4 pt sliver; on level-up the burst sells the grant and any character unlock —
    /// the death screen sells the level system every run (DESIGN_progression §4.1).
    @ViewBuilder private func xpBlock(_ result: LevelUpResult) -> some View {
        let totalXP = ProfileStore.shared.profile.totalXP   // already includes this run
        let target = Self.levelFraction(totalXP: totalXP)
        let start = result.levelAfter == result.levelBefore
            ? Self.levelFraction(totalXP: totalXP - result.xpGained) : 0

        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("+\(result.xpGained) XP")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.interactive)
                Text("▸ LVL \(result.levelAfter)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Theme.Role.interactive)
                        .frame(width: max(3, geo.size.width * (countedUp ? target : start)))
                }
            }
            .frame(height: 4)

            if result.levelAfter > result.levelBefore {
                HStack(spacing: 8) {
                    Text("LEVEL \(result.levelAfter)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Theme.Role.interactive)
                        .shadow(color: Theme.Role.interactive.opacity(0.7), radius: 10)
                    if result.coinsGranted > 0 {
                        HStack(spacing: 4) {
                            Text("+\(result.coinsGranted)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                            CoinGlyph(size: 12)
                        }
                        .foregroundStyle(Theme.Role.reward)
                    }
                }
                .padding(.top, 2)
                .transition(.scale.combined(with: .opacity))
            }

            if !result.unlockedLevels.isEmpty {
                Button { onCharacters?() } label: {
                    Text("NEW CHARACTER UNLOCKED · TAP")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.goldGradient, in: Capsule())
                        .shadow(color: Theme.Role.reward.opacity(0.5), radius: 10)
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("newCharacterUnlock")
                .accessibilityHint("Opens characters.")
            }
        }
        .padding(.top, 6)
        .accessibilityIdentifier("xpLine")
        .accessibilityElement(children: .combine)
    }

    /// Fraction of the way through the current level (full bar at the cap).
    private static func levelFraction(totalXP: Int) -> Double {
        let (cur, needed) = XPCurve.xpIntoLevel(for: totalXP)
        return needed > 0 ? Double(cur) / Double(needed) : 1
    }

    /// Challenge deaths only: the 7-day played calendar, relocated here from the old menu card.
    private var challengeDots: some View {
        let store = ProfileStore.shared
        var playedCount = 0
        for d in 0..<7 where store.playedChallenge(daysAgo: d) { playedCount += 1 }
        return HStack(spacing: 7) {
            ForEach((0..<7).reversed(), id: \.self) { daysAgo in
                Circle()
                    .fill(store.playedChallenge(daysAgo: daysAgo)
                          ? Theme.Role.reward : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Challenge calendar: played \(playedCount) of the last 7 days")
    }

    // MARK: band 3 — two chips + FULL STATS

    @ViewBuilder private var statsBand: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statChip("\(Int(distance))m · World \(worldOrdinal + 1)")
                statChip(bestStreak > 0
                         ? "×\(topMult) streak · \(nearMisses) close call\(nearMisses == 1 ? "" : "s")"
                         : "\(nearMisses) close call\(nearMisses == 1 ? "" : "s")")
            }
            if let onFullStats {
                Button(action: onFullStats) {
                    Text("FULL STATS ›")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("fullStatsLink")
                .accessibilityHint("Opens your profile and stats.")
            }
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            .accessibilityLabel(text)
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
            .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .shadow(color: Theme.Role.reward.opacity(affordable ? 0.4 : 0.15), radius: 18)
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
                .foregroundStyle(Theme.Role.reward)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.Role.reward.opacity(0.45)))
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
}
