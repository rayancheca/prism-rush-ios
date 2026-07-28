import SwiftUI

/// The hub's claimables ribbon — what the old 3-cell rewards rail should have been (PR-0452).
///
/// The rail put DAILY RUSH, REWARDS and MISSIONS in three identical cells, but they are three
/// different kinds of thing: a way to start a run, coins waiting for you, and a board you visit.
/// They are split by kind now — Daily Rush sits beside PLAY (`DailyRushLauncher`), Missions is a
/// nav-rail exit, and this ribbon owns exactly the one thing the mini-sheet behind it owns: the
/// daily login bonus and the free chest.
///
/// Two states, deliberately different in size as well as colour, so "there are coins here" is
/// legible in a single frame (decree 6):
/// - **Claimable** → a full-width gold bar with a black CTA pill. The only gold on the hub.
/// - **Idle** → a slim tertiary strip with the chest countdown. Calm and intentional rather than a
///   dimmed version of a button (decree 3) — and still tappable, so the timers stay reachable
///   (decree 4).
///
/// Priority matches the old ladder: an unclaimed daily login outranks a ready chest. Reads
/// `ProfileStore.shared` live in `body` (G3); the countdown ticks per half-minute, not per second —
/// the per-second ring lives in the mini-sheet.
struct ClaimRibbon: View {
    var onClaimDaily: () -> Void = {}
    var onOpenChest: () -> Void = {}

    @State private var showRewardsSheet = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let store = ProfileStore.shared
            let dailyAvail = store.dailyRewardAvailable(now: now)
            let chestReady = store.chestReady(now: now)

            Button {
                if dailyAvail { onClaimDaily() }
                else if chestReady { onOpenChest() }
                else { showRewardsSheet = true }
            } label: {
                if dailyAvail || chestReady {
                    litBar(store: store, now: now, dailyAvail: dailyAvail)
                } else {
                    idleStrip(store: store, now: now)
                }
            }
            .buttonStyle(.neon)
            // `.accessibilityElement(children: .ignore)` must land BEFORE the identifier and label:
            // it rebuilds the element, and anything applied under it is discarded. The rail cells
            // this replaces relied on that order, and `InteractionUITests` documents it.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("railRewards")
            .accessibilityLabel(dailyAvail
                                ? "Rewards. Daily bonus ready, \(store.dailyReward(forStreak: store.pendingDailyStreak(now: now))) coins."
                                : chestReady ? "Rewards. Free chest ready."
                                : "Rewards. Next free chest in \(Int(store.secondsUntilChest(now: now)) / 60) minutes.")
            .accessibilityHint(dailyAvail ? "Claims your daily bonus."
                               : chestReady ? "Opens the free chest."
                               : "Shows the daily bonus and chest timers.")
        }
        .sheet(isPresented: $showRewardsSheet) {
            RewardsMiniSheet(onClaimDaily: onClaimDaily, onOpenChest: onOpenChest)
        }
    }

    /// Gold bar, 54 pt: glyph, a two-line subject, and a black CTA pill hard right. Static fill —
    /// never pulses, so Reduce Motion and the default render identically.
    private func litBar(store: ProfileStore, now: Date, dailyAvail: Bool) -> some View {
        let streak = store.pendingDailyStreak(now: now)
        let amount = store.dailyReward(forStreak: streak)
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: "gift.fill")
                .font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(dailyAvail ? "DAILY BONUS" : "FREE CHEST")
                    .typeScale(.caption)
                Text(dailyAvail ? "DAY \(streak) · +\(amount) COINS" : "READY TO OPEN")
                    .typeScale(.micro)
                    .opacity(0.75)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: Theme.Space.s)
            Text(dailyAvail ? "CLAIM" : "OPEN")
                .typeScale(.caption)
                .foregroundStyle(Theme.Role.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.black.opacity(0.82), in: Capsule())
        }
        .foregroundStyle(.black)
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .contentShape(Rectangle())
    }

    /// Idle strip, 40 pt: deliberately a different HEIGHT as well as a different colour, so the hub
    /// visibly relaxes once everything is claimed instead of holding a dimmed button in reserve.
    private func idleStrip(store: ProfileStore, now: Date) -> some View {
        let mins = max(1, Int(store.secondsUntilChest(now: now)) / 60 + 1)
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "gift")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Role.textTertiary)
            Text("NEXT FREE CHEST")
                .typeScale(.micro)
                .foregroundStyle(Theme.Role.textTertiary)
            Text("\(mins)M")
                .typeScale(.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.Role.textSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Role.textTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Role.hairline))
        .contentShape(Rectangle())
    }
}

/// Daily Rush, standing beside PLAY where a second way to start a run belongs — not in a rewards
/// rail, which is what made it look like something to collect. Narrower than PLAY and unfilled, so
/// the primary verb keeps its weight; the amber hairline brightens while today's track is unplayed.
/// Starts the seeded daily challenge through the model, which interposes the first-run tutorial
/// gate exactly as the rail cell did.
struct DailyRushLauncher: View {
    var onDailyRush: () -> Void = {}

    /// Fixed width: PLAY takes the remaining span, so the deck reads as one dominant block and one
    /// secondary block rather than two halves.
    private static let width: CGFloat = 112

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let store = ProfileStore.shared
            let bestToday = store.todaysChallengeBest(now: now)
            let unplayed = !store.playedChallenge(daysAgo: 0, now: now)
            let amber = Theme.color(0xFF9F1C)

            Button(action: onDailyRush) {
                VStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(amber)
                    Text("DAILY")
                        .typeScale(.caption)
                        .foregroundStyle(Theme.Role.textPrimary)
                    // The verb, not a bare countdown: "NEW 8:43" reads as "locked for 8:43".
                    Text(bestToday > 0 ? "BEST \(bestToday)" : "PLAY · \(endsCountdown(now: now))")
                        .typeScale(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
                .frame(width: Self.width, height: 78)
                .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .strokeBorder(amber.opacity(unplayed ? 0.75 : 0.28), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.neon)
            .accessibilityElement(children: .ignore)   // before the identifier — see ClaimRibbon
            .accessibilityIdentifier("railDaily")
            .accessibilityLabel(bestToday > 0
                                ? "Daily Rush. Best today \(bestToday)."
                                : "Daily Rush, playable now. Today's track ends in \(endsA11y(now: now)).")
            .accessibilityHint("Starts today's shared challenge run.")
        }
    }

    /// H:MM until today's track expires (UTC midnight — the moment the next one begins).
    private func endsCountdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        return String(format: "%d:%02d", secs / 3600, (secs / 60) % 60)
    }

    private func endsA11y(now: Date) -> String {
        let mins = Int(ProfileStore.secondsUntilUTCMidnight(now: now)) / 60
        return "\(mins / 60) hours \(mins % 60) minutes"
    }
}

/// 280 pt mini-sheet behind the idle ribbon: Daily Login streak row + free-chest timer ring, each
/// with its own claim button. Per-second ticking is allowed here — it's the detail surface, not
/// the hub.
private struct RewardsMiniSheet: View {
    var onClaimDaily: () -> Void
    var onOpenChest: () -> Void

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
                Button(action: onClaimDaily) {
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
            Button { if ready { onOpenChest() } } label: {
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
