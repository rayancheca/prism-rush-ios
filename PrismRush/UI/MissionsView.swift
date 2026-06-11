import SwiftUI

/// Missions hub: today's 3 rotating daily slots (UTC countdown), the per-run skill missions, and
/// the tiered lifetime achievements. CLAIM pays coins through `ProfileStore.claimMission`.
/// Reads `ProfileStore.shared` directly in `body` (G3 — snapshotting breaks re-render on claim).
struct MissionsView: View {
    let model: GameModel

    @State private var claimPulse = 0   // drives success haptics on claim
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 10

    var body: some View {
        let store = ProfileStore.shared
        MetaScreenScaffold(title: "Missions", coins: store.profile.coins, onClose: { model.closeSheet() }) {
            VStack(spacing: 22) {
                dailySection(store: store)
                section("CHALLENGES", subtitle: "One run, one feat — claim once, forever.") {
                    ForEach(MissionCatalog.perRun) { mission in
                        missionRow(mission, store: store)
                    }
                }
                section("ACHIEVEMENTS", subtitle: "Lifetime ladders — every tier pays out.") {
                    ForEach(MissionCatalog.achievements) { mission in
                        missionRow(mission, store: store)
                    }
                }
            }
        }
        .sensoryFeedback(trigger: claimPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    // MARK: sections

    private func dailySection(store: ProfileStore) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TODAY")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundStyle(Theme.color(0xFFB13D))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .bold))
                        Text(countdown(now: now))
                            .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("New daily missions in \(countdownSpoken(now: now))")
                }
                ForEach(store.dailyMissions(now: now)) { mission in
                    missionRow(mission, store: store, now: now)
                }
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

    /// Fully exhausted mission — collapses to a slim, dim receipt line.
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(mission.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if mission.isTiered {
                        Text("TIER \(state.tier + 1) OF \(state.tierCount)")
                            .font(.system(size: captionSize, weight: .heavy, design: .rounded)).tracking(1)
                            .foregroundStyle(Theme.color(0xB26BFF))
                    }
                }
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
                        .shadow(color: Theme.color(0xFFD23D).opacity(0.45), radius: 10)
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
            progressBar(state)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(state.claimable ? Theme.color(0xFFD23D).opacity(0.55) : .white.opacity(0.12),
                              lineWidth: state.claimable ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowA11y(mission, state: state))
    }

    private func progressBar(_ state: ProfileStore.MissionState) -> some View {
        let fraction = state.target > 0 ? min(1, state.progress / state.target) : 0
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(state.claimable
                              ? AnyShapeStyle(Theme.goldGradient)
                              : AnyShapeStyle(Theme.actionGradient))
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 7)
            Text("\(compact(state.progress))/\(compact(state.target))")
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

    private func countdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        return String(format: "%d:%02d:%02d", secs / 3600, (secs / 60) % 60, secs % 60)
    }

    private func countdownSpoken(now: Date) -> String {
        let mins = Int(ProfileStore.secondsUntilUTCMidnight(now: now)) / 60
        return "\(mins / 60) hours \(mins % 60) minutes"
    }

    private func rowA11y(_ mission: Mission, state: ProfileStore.MissionState) -> String {
        let tierPart = mission.isTiered ? " Tier \(state.tier + 1) of \(state.tierCount)." : ""
        let status = state.claimable
            ? "Complete — \(state.reward) coins ready to claim."
            : "Progress \(Int(state.progress)) of \(Int(state.target)). Reward \(state.reward) coins."
        return "\(mission.title).\(tierPart) \(status)"
    }
}
