import SwiftUI

/// Missions hub, v1.4 re-skin. Same mechanics as v1.3 — claim-once through
/// `ProfileStore.claimMission` (which refreshes the daily/weekly boards before paying), 3 daily +
/// 3 weekly deterministic slots, per-run feats, tiered achievement ladders, CLAIM ALL at ≥2 —
/// wrapped in a board that sells the work: a summary strip up top ("3 CLAIMABLE · 1,240 COINS
/// WAITING", gold only while something waits), four sections with their own identity (TODAY =
/// gold timer ring, THIS WEEK = purple day-dots, CHALLENGES = cyan one-run feats, ACHIEVEMENTS =
/// green tier ladders), and ring-progress cards that fill on appear and collapse on claim with a
/// coin fly-up. Reads `ProfileStore.shared` directly in `body` (G3); Reduce Motion renders every
/// ring static and skips the fly-up.
struct MissionsView: View {
    let model: GameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var claimPulse = 0   // drives success haptics on claim
    // Dynamic Type: rings and dots scale with the user's text size (a fixed 44 pt ring next to
    // XL text reads as a misprint).
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var headerRingSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var dayDotSize: CGFloat = 6

    /// Section identity tints (uiux §2: cyan = tap accent, gold = money; purple/green carry the
    /// week + lifetime ladders so the four boards scan apart at a glance).
    private static let todayTint = Theme.color(0xFFB13D)
    private static let weekTint = Theme.color(0xB26BFF)
    private static let featTint = Theme.color(0x00F5FF)
    private static let ladderTint = Theme.color(0x00FF88)

    var body: some View {
        let store = ProfileStore.shared
        MetaScreenScaffold(title: "Missions", coins: store.profile.coins,
                           onClose: { model.closeSheet() }, onCoins: { model.open(.shop) }) {
            // Countdowns tick per minute, not per second (uiux §5.10 — the demoted countdown).
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = context.date
                let claimables = claimableMissions(store: store, now: now)
                VStack(spacing: 22) {
                    summaryStrip(store: store, now: now)
                    claimAllRow(claimables: claimables, store: store, now: now)
                    sectionBlock(missions: store.dailyMissionSlots(now: now), tint: Self.todayTint,
                                 store: store, now: now) { todayHeader(now: now) }
                    sectionBlock(missions: store.weeklyMissionSlots(now: now), tint: Self.weekTint,
                                 store: store, now: now) { weekHeader(now: now) }
                    sectionBlock(missions: MissionCatalog.perRun, tint: Self.featTint,
                                 store: store, now: now) { featsHeader }
                    sectionBlock(missions: MissionCatalog.achievements, tint: Self.ladderTint,
                                 store: store, now: now) { laddersHeader }
                }
                // Claim choreography: both values change exactly when a claim lands, so claimed
                // rows collapse (and CLAIM ALL cascades, one row per 80 ms beat) with a spring.
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15),
                           value: store.profile.claimedMissions)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15),
                           value: store.profile.achievementTier)
            }
        }
        // The board is rendered from PURE reads (`dailyMissionSlots` / `weeklyMissionSlots`, and a
        // `missionState` that applies the rollover rule without writing), so `body` never persists.
        // The actual wipe of a rolled-over board happens HERE, once, off the render pass — PR-0006.
        // It must not simply disappear: the hub badge and this board both have to survive a UTC
        // rollover that lands while the screen is open, and the read side handles the display half.
        .task {
            ProfileStore.shared.refreshDailyMissions()
            ProfileStore.shared.refreshWeeklyMissions()
        }
        .sensoryFeedback(trigger: claimPulse) { _, _ in
            ProfileStore.shared.profile.hapticsEnabled ? .success : nil
        }
    }

    // MARK: summary strip

    /// One-line board status. Three states, not two: gold ONLY while a reward waits (Role rules —
    /// gold means money), a neutral live count while the board is simply unfinished, and ALL CLEAR
    /// reserved for a board with genuinely nothing left on it. See `MissionBoardSummary` for why
    /// the middle state has to exist (PR-0304).
    private func summaryStrip(store: ProfileStore, now: Date) -> some View {
        let summary = ProfileStore.MissionBoardSummary.of(activeStates(store: store, now: now))
        let isReward = summary.isClaimable
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: summary.symbol)
                .font(.system(size: 12, weight: .bold))
            Text(summaryText(summary, now: now))
                .typeScale(.caption)
                .fontWeight(.heavy)
                .monospacedDigit()
            Spacer(minLength: 0)
            if summary.showsCoinGlyph { CoinGlyph(size: 13) }
        }
        .foregroundStyle(isReward ? Theme.Role.reward : summary.tint)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(isReward ? Theme.Role.reward.opacity(0.08) : Theme.Role.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
            .strokeBorder(isReward ? Theme.Role.reward.opacity(0.4) : Theme.Role.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("missionsSummary")
        .accessibilityLabel(summarySpoken(summary, now: now))
    }

    private func summaryText(_ s: ProfileStore.MissionBoardSummary, now: Date) -> String {
        switch s {
        case let .claimable(count, coins): "\(count) CLAIMABLE · \(coins.formatted()) COINS WAITING"
        case let .open(count, coins):      "\(count) OPEN · UP TO \(coins.formatted()) COINS"
        case .allClear:                    "ALL CLEAR · NEW BOARD IN \(dailyCountdown(now: now))"
        }
    }

    private func summarySpoken(_ s: ProfileStore.MissionBoardSummary, now: Date) -> String {
        switch s {
        case let .claimable(count, coins): "\(count) rewards claimable, \(coins) coins waiting."
        case let .open(count, coins):      "\(count) missions open, up to \(coins) coins available."
        case .allClear:                    "All clear. New board in \(dailyCountdownSpoken(now: now))."
        }
    }

    /// Every mission on the board, resolved to its state — the input the summary is pure over.
    private func activeStates(store: ProfileStore, now: Date) -> [ProfileStore.MissionState] {
        activeMissions(store: store, now: now).map { store.missionState($0, now: now) }
    }

    // MARK: claim all

    /// Gold CLAIM ALL pill when ≥2 rewards are ready (uiux §6.5). v1.4: one chime, then the
    /// claims land one per 80 ms — a haptic per landing, rows collapsing in cascade.
    @ViewBuilder private func claimAllRow(claimables: [Mission], store: ProfileStore, now: Date) -> some View {
        if claimables.count >= 2 {
            let total = claimables.reduce(0) { $0 + store.missionState($1, now: now).reward }
            Button {
                model.synth.play(.purchaseChime)
                let queue = claimables
                // Unstructured on purpose: the claims must finish even if the sheet closes
                // mid-cascade — they land on the shared store, not on this view.
                // AUDIT D5-2: every claim resolves against `now`, the SAME clock that built the
                // rendered board and its advertised "+total". A live Date() per claim let a
                // UTC-midnight rollover mid-cascade refresh the boards and nil the remaining
                // daily claims — the player would receive less than the button promised.
                Task { @MainActor in
                    for mission in queue {
                        if store.claimMission(mission.id, now: now) != nil {
                            claimPulse += 1
                        }
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("CLAIM ALL +\(total)")
                        .typeScale(.body)
                        .fontWeight(.heavy)
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

    /// Every mission the board is currently showing, in render order.
    private func activeMissions(store: ProfileStore, now: Date) -> [Mission] {
        MissionCatalog.perRun + store.dailyMissionSlots(now: now)
            + store.weeklyMissionSlots(now: now) + MissionCatalog.achievements
    }

    private func claimableMissions(store: ProfileStore, now: Date) -> [Mission] {
        activeMissions(store: store, now: now).filter { store.missionState($0, now: now).claimable }
    }

    // MARK: sections

    /// One section: identity header + ring cards. Claims route back through `registerClaim` so
    /// the haptic/chime stay centralized (same `.sensoryFeedback` pattern as v1.3).
    private func sectionBlock(missions: [Mission], tint: Color, store: ProfileStore, now: Date,
                              @ViewBuilder header: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            ForEach(missions) { mission in
                MissionCard(mission: mission,
                            state: store.missionState(mission, now: now),
                            tint: tint,
                            ringSize: ringSize,
                            onClaim: { registerClaim() })
            }
        }
    }

    /// Per-claim feedback (single claims; CLAIM ALL drives its own cascade).
    private func registerClaim() {
        claimPulse += 1
        model.synth.play(.purchaseChime)
    }

    /// TODAY — gold, with a live timer ring draining toward UTC midnight (per-minute tick).
    private func todayHeader(now: Date) -> some View {
        let remaining = max(0, min(1, ProfileStore.secondsUntilUTCMidnight(now: now) / 86_400))
        return HStack(spacing: Theme.Space.s) {
            ZStack {
                Circle().stroke(Theme.Role.reward.opacity(0.18), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(Theme.Role.reward, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: headerRingSize, height: headerRingSize)
            Text("TODAY")
                .typeScale(.caption).fontWeight(.heavy)
                .foregroundStyle(Self.todayTint)
            Text("· RESETS \(dailyCountdown(now: now))")
                .typeScale(.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.Role.textTertiary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's missions. New board in \(dailyCountdownSpoken(now: now)).")
    }

    /// THIS WEEK — purple, with seven day-dots walking the UTC week (today ringed in white).
    private func weekHeader(now: Date) -> some View {
        let dayIndex = ProfileStore.daysSinceEpoch(now) % 7   // 0…6 inside the UTC week key
        return HStack(spacing: Theme.Space.s) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    Circle()
                        .fill(day <= dayIndex
                              ? Self.weekTint.opacity(day == dayIndex ? 1 : 0.45)
                              : Color.white.opacity(0.14))
                        .frame(width: dayDotSize, height: dayDotSize)
                        .overlay(Circle().strokeBorder(
                            day == dayIndex ? Color.white.opacity(0.75) : .clear, lineWidth: 1))
                }
            }
            Text("THIS WEEK")
                .typeScale(.caption).fontWeight(.heavy)
                .foregroundStyle(Self.weekTint)
            Text("· RESETS \(weeklyCountdown(now: now))")
                .typeScale(.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.Role.textTertiary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week's missions. Day \(dayIndex + 1) of 7. New board in \(weeklyCountdown(now: now)).")
    }

    /// CHALLENGES — cyan one-run feats (claim once, forever).
    private var featsHeader: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.featTint)
            Text("CHALLENGES")
                .typeScale(.caption).fontWeight(.heavy)
                .foregroundStyle(Self.featTint)
            Text("· ONE-RUN FEATS")
                .typeScale(.micro)
                .foregroundStyle(Theme.Role.textTertiary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Challenges. One-run feats — claim once, forever.")
    }

    /// ACHIEVEMENTS — green lifetime ladders; each card highlights its current tier.
    private var laddersHeader: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.ladderTint)
            Text("ACHIEVEMENTS")
                .typeScale(.caption).fontWeight(.heavy)
                .foregroundStyle(Self.ladderTint)
            Text("· EVERY TIER PAYS")
                .typeScale(.micro)
                .foregroundStyle(Theme.Role.textTertiary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Achievements. Lifetime ladders — every tier pays out.")
    }

    // MARK: helpers

    /// Unit-suffixed so it can't be misread as minutes:seconds, and so it sits in the same format
    /// family as the weekly "3D" it appears beside on this screen (PR-0304's second half).
    private func dailyCountdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        let hours = secs / 3600, minutes = (secs / 60) % 60
        return hours > 0 ? "\(hours)H \(minutes)M" : "\(minutes)M"
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
}

/// Presentation for the board summary. Lives here, not beside the enum: `MissionBoardSummary` is
/// in the Linux-testable Meta layer and must not learn about `Theme`.
private extension ProfileStore.MissionBoardSummary {
    var isClaimable: Bool { if case .claimable = self { true } else { false } }

    /// The coin glyph is money language — it belongs only where coins are actually waiting.
    var showsCoinGlyph: Bool { isClaimable }

    var symbol: String {
        switch self {
        case .claimable: "sparkles"
        case .open:      "target"
        case .allClear:  "checkmark.circle"
        }
    }

    /// An unfinished board is live content, not a footnote; a finished one is genuinely quiet.
    var tint: Color {
        switch self {
        case .claimable: Theme.Role.reward
        case .open:      Theme.Role.textSecondary
        case .allClear:  Theme.Role.textTertiary
        }
    }
}

/// One mission as a ring card: circular progress (animated fill on appear; Reduce Motion =
/// static), title, tier ladder for achievements (current tier highlighted), and the reward pill /
/// gold CLAIM button. A landed claim fires a coin fly-up; a fully exhausted mission collapses to
/// a slim receipt row (the card keeps its ForEach identity, so the collapse animates in place).
/// Renders entirely from the `state` value its parent recomputes off the live store each pass.
private struct MissionCard: View {
    let mission: Mission
    let state: ProfileStore.MissionState
    let tint: Color
    let ringSize: CGFloat
    let onClaim: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false      // drives the on-appear ring fill (0 → fraction)
    @State private var flyAmount = 0         // last claim's reward, shown by the fly-up
    @State private var flyTrigger = 0        // re-fires the fly-up per claim

    var body: some View {
        Group {
            if state.claimed {
                receiptRow
            } else {
                activeCard
            }
        }
        // The fly-up lives OUT here, not on `activeCard`: a final claim flips `state.claimed` in
        // the same transaction, so an overlay on the active card would die with it mid-rise —
        // daily/weekly/per-run claims would never show the "+N". Here it survives the
        // active → receipt swap (review fix).
        .overlay(alignment: .topTrailing) {
            if flyAmount > 0 {
                CoinFlyUp(amount: flyAmount, trigger: flyTrigger)
                    .padding(.trailing, 18)
            }
        }
        .accessibilityIdentifier("missionCard_\(mission.id)")
    }

    // MARK: active

    private var activeCard: some View {
        HStack(spacing: 12) {
            progressRing
            VStack(alignment: .leading, spacing: 5) {
                Text(mission.title)
                    .typeScale(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if mission.isTiered { tierLadder }
                    Text("\(compactCount(state.progress))/\(compactCount(state.target))")
                        .typeScale(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: Theme.Space.s)
            claimControl
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(state.claimable ? Theme.Role.reward.opacity(0.55) : .white.opacity(0.12),
                              lineWidth: state.claimable ? 1.5 : 1)
        )
        .onAppear { appeared = true }   // ring fills 0 → fraction (the .animation below rides it)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowA11y)
    }

    /// Circular progress ring: section-tinted while in progress, gold once claimable (a claim
    /// bursts it to full before the row collapses). Center carries the metric's glyph.
    private var progressRing: some View {
        let fraction = state.target > 0 ? min(1, state.progress / state.target) : 0
        let shown = appeared ? fraction : 0
        return ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(state.claimable ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(tint),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: metricGlyph)
                .font(.system(size: ringSize * 0.3, weight: .semibold))
                .foregroundStyle(state.claimable ? Theme.Role.reward : .white.opacity(0.7))
        }
        .frame(width: ringSize, height: ringSize)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: shown)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(state.progress.rounded())) of \(Int(state.target.rounded()))")
    }

    /// Achievement ladder pips: paid tiers gold, the CURRENT tier wide + tinted, the rest dim.
    private var tierLadder: some View {
        HStack(spacing: 3) {
            ForEach(0..<state.tierCount, id: \.self) { tier in
                Capsule()
                    .fill(tier < state.tier ? Theme.Role.reward.opacity(0.8)
                          : tier == state.tier ? tint
                          : Color.white.opacity(0.14))
                    .frame(width: tier == state.tier ? 16 : 8, height: 4)
            }
            Text("T\(min(state.tier + 1, state.tierCount))")
                .typeScale(.micro)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder private var claimControl: some View {
        if state.claimable {
            Button(action: claim) {
                HStack(spacing: 4) {
                    Text("CLAIM +\(state.reward)")
                        .typeScale(.caption)
                        .fontWeight(.heavy)
                        .monospacedDigit()
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
                    .typeScale(.caption)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                CoinGlyph(size: 11)
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Role.hairline))
        }
    }

    /// The claim lands on the store FIRST (mechanics over choreography — a mid-animation
    /// dismissal must never lose coins), then the FX ride the resulting state change.
    private func claim() {
        let reward = state.reward
        guard ProfileStore.shared.claimMission(mission.id, now: Date()) != nil else { return }
        onClaim()
        if !reduceMotion {
            flyAmount = reward
            flyTrigger += 1
        }
    }

    // MARK: receipt

    /// Fully exhausted mission — collapses to a slim, dim receipt line (history, not noise).
    private var receiptRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.color(0x00FF88).opacity(0.8))
            Text(mission.title)
                .typeScale(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.45))
                .strikethrough(true, color: .white.opacity(0.3))
            Spacer()
            if mission.isTiered {
                Text("ALL TIERS")
                    .typeScale(.micro)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mission.title). Completed and claimed.")
    }

    // MARK: helpers

    private var metricGlyph: String {
        switch mission.metric {
        case .gems: "diamond.fill"
        case .distance: "arrow.forward"
        case .nearMisses: "wind"
        case .slides: "arrow.down.to.line"
        case .slickBonuses: "sparkles"
        case .runsFinished: "flag.checkered"
        case .streakBest: "flame.fill"
        case .worldReached: "globe"
        case .chestsOpened: "gift.fill"
        case .wardensDefeated: "shield.lefthalf.filled.slash"
        case .revives: "heart.fill"
        case .multiplierHit: "multiply"
        }
    }

    private var rowA11y: String {
        let tierPart = mission.isTiered ? " Tier \(state.tier + 1) of \(state.tierCount)." : ""
        let status = state.claimable
            ? "Complete — \(state.reward) coins ready to claim."
            : "Progress \(Int(state.progress)) of \(Int(state.target)). Reward \(state.reward) coins."
        return "\(mission.title).\(tierPart) \(status)"
    }

    private func compactCount(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.0fk", v / 1_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return "\(Int(v))"
    }
}

/// "+N ⬤" rising off a just-claimed card — re-fired per claim via `.id(trigger)`, invisible once
/// the rise completes. Purely decorative (hidden from a11y, no hit testing).
private struct CoinFlyUp: View {
    let amount: Int
    let trigger: Int

    var body: some View {
        FlyUpBody(amount: amount)
            .id(trigger)   // a fresh claim restarts the rise from scratch
    }

    private struct FlyUpBody: View {
        let amount: Int
        @State private var risen = false

        var body: some View {
            HStack(spacing: 3) {
                Text("+\(amount)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                CoinGlyph(size: 12)
            }
            .foregroundStyle(Theme.Role.reward)
            .offset(y: risen ? -38 : -4)
            .opacity(risen ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.8)) { risen = true } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
