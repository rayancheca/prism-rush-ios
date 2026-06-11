import SwiftUI

/// The menu's single 3-cell rewards rail (uiux §1.5): Daily Rush | Rewards | Missions. Replaces
/// the stacked DailyChallengeCard + 3-button bar. At most ONE cell is "lit" (gold) at a time,
/// chosen by the deterministic priority ladder: unclaimed daily login > ready chest > claimable
/// missions > unplayed Daily Rush. Reads `ProfileStore.shared` live in body (G3); countdowns tick
/// per half-minute, not per second (the per-second timer ring lives in the mini-sheet).
struct RewardsBar: View {
    let model: GameModel
    /// Opens MissionsView (the owner routes `model.open(.missions)`).
    var onMissions: () -> Void = {}

    @State private var showRewardsSheet = false

    private enum Lit { case rewards, missions, daily, none }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let store = ProfileStore.shared
            let dailyAvail = store.dailyRewardAvailable(now: now)
            let chestReady = store.chestReady(now: now)
            let unclaimed = store.unclaimedCount(now: now)
            let playedToday = store.playedChallenge(daysAgo: 0, now: now)
            let lit: Lit = (dailyAvail || chestReady) ? .rewards
                : unclaimed > 0 ? .missions
                : !playedToday ? .daily
                : .none

            HStack(spacing: Theme.Space.s) {
                dailyCell(store: store, now: now, lit: lit == .daily)
                rewardsCell(store: store, now: now, dailyAvail: dailyAvail,
                            chestReady: chestReady, lit: lit == .rewards)
                missionsCell(unclaimed: unclaimed, lit: lit == .missions)
            }
            .frame(height: 64)
        }
        .sheet(isPresented: $showRewardsSheet) {
            RewardsMiniSheet(model: model)
        }
    }

    // MARK: cells

    /// DAILY RUSH — starts the seeded daily challenge directly. Sub-line: today's best, or the
    /// per-minute countdown to the next track (the per-second countdown is demoted, uiux §5.10).
    private func dailyCell(store: ProfileStore, now: Date, lit: Bool) -> some View {
        let bestToday = store.todaysChallengeBest(now: now)
        let sub = bestToday > 0 ? "BEST \(bestToday)" : "NEW \(newTrackCountdown(now: now))"
        return railCell(glyph: "bolt.fill", title: "DAILY RUSH", sub: sub, lit: lit) {
            model.startDailyChallenge()
        }
        .accessibilityIdentifier("railDaily")
        .accessibilityLabel(bestToday > 0
                            ? "Daily Rush. Best today \(bestToday)."
                            : "Daily Rush, not played yet. New track in \(newTrackA11y(now: now)).")
        .accessibilityHint("Starts today's shared challenge run.")
    }

    /// REWARDS — merges the daily-login claim + free chest. Lit → claims/opens inline; otherwise
    /// opens the 280 pt mini-sheet with both rows.
    private func rewardsCell(store: ProfileStore, now: Date, dailyAvail: Bool,
                             chestReady: Bool, lit: Bool) -> some View {
        let amount = store.dailyReward(forStreak: store.pendingDailyStreak(now: now))
        let sub = dailyAvail ? "CLAIM +\(amount)"
            : chestReady ? "CHEST READY"
            : "CHEST \(max(1, Int(store.secondsUntilChest(now: now)) / 60 + 1))M"
        return railCell(glyph: "gift.fill", title: "REWARDS", sub: sub, lit: lit) {
            if dailyAvail { model.claimDailyReward() }
            else if chestReady { model.openChest() }
            else { showRewardsSheet = true }
        }
        .accessibilityIdentifier("railRewards")
        .accessibilityLabel(dailyAvail ? "Rewards. Daily bonus ready, \(amount) coins."
                            : chestReady ? "Rewards. Free chest ready."
                            : "Rewards. Next free chest in \(Int(store.secondsUntilChest(now: now)) / 60) minutes.")
        .accessibilityHint(dailyAvail ? "Claims your daily bonus."
                           : chestReady ? "Opens the free chest."
                           : "Shows the daily bonus and chest timers.")
    }

    /// MISSIONS — gold count badge while anything is claimable. The count comes from
    /// `unclaimedCount`, the SAME source MissionsView's v1.4 summary strip reads — the menu cell
    /// and the in-sheet "N CLAIMABLE" strip can never disagree.
    private func missionsCell(unclaimed: Int, lit: Bool) -> some View {
        railCell(glyph: "target", title: "MISSIONS",
                 sub: unclaimed > 0 ? "CLAIM \(unclaimed)" : "BOARD",
                 lit: lit, badge: lit ? 0 : unclaimed, action: onMissions)
            .accessibilityIdentifier("railMissions")
            .accessibilityLabel(unclaimed > 0
                                ? "Missions — \(unclaimed) rewards ready to claim."
                                : "Missions.")
            .accessibilityHint("Opens the missions board.")
    }

    /// Shared cell anatomy: 64 pt, equal widths, surface fill + hairline; lit = static gold
    /// (never pulses — Reduce Motion and default render identically, uiux §1.8).
    private func railCell(glyph: String, title: String, sub: String, lit: Bool,
                          badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: glyph).font(.system(size: 15, weight: .semibold))
                Text(title).typeScale(.micro)
                Text(sub).typeScale(.micro).monospacedDigit()
                    .opacity(lit ? 0.85 : 0.6)
            }
            .foregroundStyle(lit ? Color.black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(lit ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.Role.surface),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(lit ? .clear : Theme.Role.hairline))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(minWidth: 17)
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(Theme.goldGradient, in: Capsule())
                        .offset(x: 5, y: -6)
                }
            }
        }
        .buttonStyle(.neon)
        .accessibilityElement(children: .ignore)
    }

    private func newTrackCountdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        return String(format: "%d:%02d", secs / 3600, (secs / 60) % 60)
    }

    private func newTrackA11y(now: Date) -> String {
        let mins = Int(ProfileStore.secondsUntilUTCMidnight(now: now)) / 60
        return "\(mins / 60) hours \(mins % 60) minutes"
    }
}

/// 280 pt mini-sheet behind the (un-lit) Rewards cell: Daily Login streak row + free-chest timer
/// ring, each with its own claim button. Per-second ticking is allowed here — it's the detail
/// surface, not the menu.
private struct RewardsMiniSheet: View {
    let model: GameModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let store = ProfileStore.shared
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("REWARDS")
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textTertiary)
                dailyLoginRow(store: store, now: now)
                chestRow(store: store, now: now)
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.l)
        }
        .presentationDetents([.height(280)])
        .presentationBackground(Theme.Role.bg)
    }

    private func dailyLoginRow(store: ProfileStore, now: Date) -> some View {
        let available = store.dailyRewardAvailable(now: now)
        let streak = store.pendingDailyStreak(now: now)
        let amount = store.dailyReward(forStreak: streak)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY LOGIN · DAY \(streak)")
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textPrimary)
                Text(available ? "+\(amount) COINS READY" : "CLAIMED — BACK TOMORROW")
                    .typeScale(.micro)
                    .foregroundStyle(available ? Theme.Role.reward : Theme.Role.textTertiary)
            }
            Spacer()
            if available {
                Button { model.claimDailyReward() } label: {
                    Text("CLAIM")
                        .typeScale(.caption)
                        .foregroundStyle(.black)
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                        .background(Theme.goldGradient, in: Capsule())
                }
                .buttonStyle(.neon)
                .accessibilityIdentifier("dailyRewardButton")
                .accessibilityLabel("Claim daily reward, day \(streak), \(amount) coins")
            }
        }
        .padding(Theme.Space.m)
        .neonCard()
    }

    private func chestRow(store: ProfileStore, now: Date) -> some View {
        let ready = store.chestReady(now: now)
        let secs = Int(store.secondsUntilChest(now: now))
        let progress = 1 - min(1, max(0, store.secondsUntilChest(now: now) / ProfileStore.chestInterval))
        return HStack {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: ready ? 1 : progress)
                    .stroke(ready ? Theme.Role.reward : Theme.Role.interactive,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: ready ? "gift.fill" : "gift")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("FREE CHEST")
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textPrimary)
                Text(ready ? "READY TO OPEN" : String(format: "%02d:%02d", secs / 60, secs % 60))
                    .typeScale(.micro)
                    .monospacedDigit()
                    .foregroundStyle(ready ? Theme.Role.reward : Theme.Role.textTertiary)
            }
            Spacer()
            Button { if ready { model.openChest() } } label: {
                Text("OPEN")
                    .typeScale(.caption)
                    .foregroundStyle(ready ? .black : Theme.Role.lock)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(ready ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.Role.surface),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(ready ? .clear : Theme.Role.hairline))
            }
            .buttonStyle(.neon)
            .disabled(!ready)
            .accessibilityIdentifier("chestButton")
            .accessibilityLabel(ready
                                ? "Free chest ready to open"
                                : "Free chest in \(secs / 60) minutes \(secs % 60) seconds")
        }
        .padding(Theme.Space.m)
        .neonCard()
    }
}
