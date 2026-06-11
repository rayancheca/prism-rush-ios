import SwiftUI

/// Missions hub: today's 3 daily slots, THIS WEEK's 3 big-payout weekly slots (v1.3), the per-run
/// skill missions, and the tiered lifetime achievements (tier ticks live ON the progress bar).
/// CLAIM ALL appears when ≥2 rewards are ready. Claims pay coins through
/// `ProfileStore.claimMission`; reads `ProfileStore.shared` directly in `body` (G3).
struct MissionsView: View {
    let model: GameModel

    @State private var claimPulse = 0   // drives success haptics on claim
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 10

    var body: some View {
        let store = ProfileStore.shared
        MetaScreenScaffold(title: "Missions", coins: store.profile.coins,
                           onClose: { model.closeSheet() }, onCoins: { model.open(.shop) }) {
            // Countdowns tick per minute, not per second (uiux §5.10 — the demoted countdown).
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = context.date
                VStack(spacing: 22) {
                    claimAllRow(store: store, now: now)
                    dailySection(store: store, now: now)
                    weeklySection(store: store, now: now)
                    section("CHALLENGES", subtitle: "One run, one feat — claim once, forever.") {
                        ForEach(MissionCatalog.perRun) { mission in
                            missionRow(mission, store: store, now: now)
                        }
                    }
                    section("ACHIEVEMENTS", subtitle: "Lifetime ladders — every tier pays out.") {
                        ForEach(MissionCatalog.achievements) { mission in
                            missionRow(mission, store: store, now: now)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(trigger: claimPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    // MARK: claim all

    /// Gold CLAIM ALL pill when ≥2 rewards are ready (uiux §6.5). One tap claims everything;
    /// feedback is a single chime + haptic (the per-claim stagger is parked, V13_SPEC §P).
    @ViewBuilder private func claimAllRow(store: ProfileStore, now: Date) -> some View {
        let claimables = claimableMissions(store: store, now: now)
        if claimables.count >= 2 {
            let total = claimables.reduce(0) { $0 + store.missionState($1, now: now).reward }
            Button {
                var paid = 0
                for mission in claimables {
                    paid += store.claimMission(mission.id, now: Date()) ?? 0
                }
                if paid > 0 {
                    claimPulse += 1
                    model.synth.play(.purchaseChime)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("CLAIM ALL +\(total)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .monospacedDigit()
                    CoinGlyph(size: 13)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.goldGradient, in: Capsule())
                .shadow(color: Theme.Role.reward.opacity(0.45), radius: 12)
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("claimAllButton")
            .accessibilityLabel("Claim all \(claimables.count) rewards, \(total) coins total")
        }
    }

    private func claimableMissions(store: ProfileStore, now: Date) -> [Mission] {
        let active = MissionCatalog.perRun + store.dailyMissions(now: now)
            + store.weeklyMissions(now: now) + MissionCatalog.achievements
        return active.filter { store.missionState($0, now: now).claimable }
    }

    // MARK: sections

    private func dailySection(store: ProfileStore, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(Theme.color(0xFFB13D))
                // The countdown joins the kicker line at micro weight, per-minute (uiux §6.5).
                Text("· RESETS \(dailyCountdown(now: now))")
                    .typeScale(.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textTertiary)
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today's missions. New board in \(dailyCountdownSpoken(now: now)).")
            ForEach(store.dailyMissions(now: now)) { mission in
                missionRow(mission, store: store, now: now)
            }
        }
    }

    /// THIS WEEK — 3 deterministic weekly slots, 6–7× daily targets, 600–900 coin payouts.
    private func weeklySection(store: ProfileStore, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(Theme.color(0xB26BFF))
                Text("· RESETS \(weeklyCountdown(now: now))")
                    .typeScale(.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Role.textTertiary)
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week's missions. New board in \(weeklyCountdown(now: now)).")
            ForEach(store.weeklyMissions(now: now)) { mission in
                missionRow(mission, store: store, now: now)
            }
        }
    }

    private func section(_ title: String, subtitle: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.system(size: captionSize + 1, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, -6)
            rows()
        }
    }

    // MARK: rows

    @ViewBuilder
    private func missionRow(_ mission: Mission, store: ProfileStore, now: Date = Date()) -> some View {
        let state = store.missionState(mission, now: now)
        if state.claimed {
            claimedRow(mission, state: state)
        } else {
            activeRow(mission, state: state, store: store, now: now)
        }
    }

    /// Fully exhausted mission — collapses to a slim, dim receipt line (history, not noise).
    private func claimedRow(_ mission: Mission, state: ProfileStore.MissionState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.color(0x00FF88).opacity(0.8))
            Text(mission.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .strikethrough(true, color: .white.opacity(0.3))
            Spacer()
            if mission.isTiered {
                Text("ALL TIERS")
                    .font(.system(size: captionSize, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mission.title). Completed and claimed.")
    }

    private func activeRow(_ mission: Mission, state: ProfileStore.MissionState,
                           store: ProfileStore, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(mission.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if state.claimable {
                    Button {
                        if store.claimMission(mission.id, now: Date()) != nil {
                            claimPulse += 1
                            model.synth.play(.purchaseChime)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("CLAIM +\(state.reward)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                            CoinGlyph(size: 12)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.goldGradient, in: Capsule())
                        .shadow(color: Theme.Role.reward.opacity(0.45), radius: 10)
                    }
                    .buttonStyle(.neon)
                    .accessibilityIdentifier("claim_\(mission.id)")
                    .accessibilityLabel("Claim \(state.reward) coins for \(mission.title)")
                } else {
                    HStack(spacing: 4) {
                        Text("+\(state.reward)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        CoinGlyph(size: 12)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            // Tiered ladders print TIER n/m once, right-aligned above the bar; the ticks live ON
            // the bar (uiux §6.5 — the redundant subtitle label is deleted).
            if mission.isTiered {
                HStack {
                    Spacer()
                    Text("TIER \(min(state.tier + 1, state.tierCount))/\(state.tierCount)")
                        .typeScale(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(0xB26BFF))
                }
                .padding(.bottom, -4)
            }
            progressBar(mission, state: state, store: store)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(state.claimable ? Theme.Role.reward.opacity(0.55) : .white.opacity(0.12),
                              lineWidth: state.claimable ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowA11y(mission, state: state))
    }

    /// Progress bar; for tiered achievements the bar spans the FINAL tier with tick marks at
    /// every tier boundary, so one glance shows the whole ladder.
    private func progressBar(_ mission: Mission, state: ProfileStore.MissionState,
                             store: ProfileStore) -> some View {
        let tierTargets: [Double] = {
            if case .lifetimeTiered(let targets, _) = mission.scope { return targets }
            return []
        }()
        let finalTarget = tierTargets.last ?? state.target
        let rawProgress = mission.isTiered
            ? (store.profile.missionProgress[mission.id] ?? 0) : state.progress
        let fraction = finalTarget > 0 ? min(1, rawProgress / finalTarget) : 0

        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(state.claimable
                              ? AnyShapeStyle(Theme.goldGradient)
                              : AnyShapeStyle(Theme.actionGradient))
                        .frame(width: max(6, geo.size.width * fraction))
                    // Tier ticks (all but the final target, which is the bar's end).
                    ForEach(tierTargets.dropLast(), id: \.self) { target in
                        Rectangle()
                            .fill(.white.opacity(0.55))
                            .frame(width: 1.5, height: 7)
                            .offset(x: geo.size.width * (target / max(finalTarget, 1)))
                    }
                }
            }
            .frame(height: 7)
            Text("\(compact(min(rawProgress, finalTarget)))/\(compact(mission.isTiered ? finalTarget : state.target))")
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize()
        }
        .accessibilityHidden(true)   // folded into the row's combined label
    }

    // MARK: helpers

    private func compact(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.0fk", v / 1_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return "\(Int(v))"
    }

    private func dailyCountdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        return String(format: "%d:%02d", secs / 3600, (secs / 60) % 60)
    }

    private func dailyCountdownSpoken(now: Date) -> String {
        let mins = Int(ProfileStore.secondsUntilUTCMidnight(now: now)) / 60
        return "\(mins / 60) hours \(mins % 60) minutes"
    }

    /// Days (rounded up) until the UTC week (daysSinceEpoch / 7) rolls over.
    private func weeklyCountdown(now: Date) -> String {
        let days = 7 - ProfileStore.daysSinceEpoch(now) % 7
        return days <= 1 ? dailyCountdown(now: now) : "\(days)D"
    }

    private func rowA11y(_ mission: Mission, state: ProfileStore.MissionState) -> String {
        let tierPart = mission.isTiered ? " Tier \(state.tier + 1) of \(state.tierCount)." : ""
        let status = state.claimable
            ? "Complete — \(state.reward) coins ready to claim."
            : "Progress \(Int(state.progress)) of \(Int(state.target)). Reward \(state.reward) coins."
        return "\(mission.title).\(tierPart) \(status)"
    }
}
