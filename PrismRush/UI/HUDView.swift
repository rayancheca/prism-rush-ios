import SwiftUI

/// In-run heads-up display, on a diet (uiux §6.8): score top-left (BEST hidden during play — it
/// returns only as the ghost-chase chip when you're within 10% of it), the merged gem/multiplier
/// pill top-right, icon timer rings for the power-ups, and flow pips. Reads the observed
/// `core.snapshot`, refreshes per frame, and stays strictly non-interactive.
struct HUDView: View {
    let core: GameCore

    var body: some View {
        let snap = core.snapshot
        VStack {
            HStack(alignment: .top) {
                // Meters is the primary readout — "how far am I", matching the world labels
                // ("…3,200 m in" starts the counter at 3,200, not a confusing 0). Score is the
                // separate earned-points number (the leaderboard value) below it.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(snap.distance))")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text("M")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .shadow(color: .white.opacity(0.35), radius: 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Int(snap.distance)) meters")
                    .accessibilityAddTraits(.updatesFrequently)
                    Text("SCORE \(snap.score)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.68))
                        .accessibilityLabel("Score \(snap.score)")
                    ghostChaseChip(snap)
                }

                Spacer()

                // Starts below the mute/pause cluster anchored in the top-trailing corner.
                VStack(alignment: .trailing, spacing: 8) {
                    gemMultPill(snap)
                    powerUpStack(snap)
                    flowPips(snap)
                }
                .padding(.top, 38)
            }
            Spacer()
            xpBar(snap)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .animation(.spring(duration: 0.25), value: snap.mult)
        .animation(.spring(duration: 0.25), value: snap.shieldActive)
        .opacity(snap.mode == .play ? 1 : 0)
        .allowsHitTesting(false)   // the run is the UI — pause is the only in-play button
    }

    // MARK: live level / XP bar (the owner wants to watch level + XP grow mid-run)

    /// A thin level + XP bar along the bottom edge. XP is only BANKED at game over, so this is a
    /// live estimate (the dominant run terms — distance + gems — added to the lifetime total); it
    /// climbs as you play and matches the eventual grant closely. Reads `ProfileStore.shared` live
    /// in body (G3). At max level the bar reads full.
    private func xpBar(_ snap: GameSnapshot) -> some View {
        let liveXP = ProfileStore.shared.profile.totalXP + liveRunXP(snap)
        let level = XPCurve.level(for: liveXP)
        let (cur, needed) = XPCurve.xpIntoLevel(for: liveXP)
        let progress = needed > 0 ? Double(cur) / Double(needed) : 1
        return HStack(spacing: 9) {
            Text("LV \(level)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Theme.Role.interactive)
                        .frame(width: max(2, geo.size.width * progress))
                        .shadow(color: Theme.Role.interactive.opacity(0.7), radius: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level >= XPCurve.maxLevel
                            ? "Level \(level), max level"
                            : "Level \(level), \(Int(progress * 100)) percent to level \(level + 1)")
    }

    /// Live XP estimate from the two dominant `XPCurve.xp` terms available each frame (1 XP / 10 m
    /// run + 2 XP / gem), capped like the real grant. Style/combo/world bonuses settle at game over.
    private func liveRunXP(_ snap: GameSnapshot) -> Int {
        min(2_000, Int(snap.traveledDistance / 10) + snap.gems * 2)
    }

    // MARK: ghost chase — BEST appears only when it's actually a chase

    /// One-shot chase chip when within 10% of the best: "BEST 320 AHEAD" in the world accent.
    /// It vanishes on crossing — the NEW BEST celebration takes over. Floored at a 1,000 best
    /// (AUDIT D6-6): a tiny run-1 best would pop-and-vanish this in seconds during the exact
    /// window a new player is still learning the controls.
    @ViewBuilder private func ghostChaseChip(_ snap: GameSnapshot) -> some View {
        if snap.best >= 1_000, snap.score < snap.best,
           Double(snap.score) >= 0.9 * Double(snap.best) {
            let accent = Theme.color(Theme.evolvedPalette(ordinal: snap.worldOrdinal).accent2)
            Text("BEST \(snap.best - snap.score) AHEAD")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .monospacedDigit()
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.7), radius: 8)
                .transition(.opacity)
                .accessibilityLabel("Best score \(snap.best - snap.score) points ahead")
        }
    }

    // MARK: merged gem / multiplier pill — `◆ 23 ×4`

    private func gemMultPill(_ snap: GameSnapshot) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 1, green: 0.82, blue: 0.24))
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
                .shadow(color: Color(red: 1, green: 0.82, blue: 0.24), radius: 6)
            Text("\(snap.gems)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            if snap.mult > 1 {
                Text("×\(snap.mult)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 1, green: 0.82, blue: 0.24)))
                    .transition(.scale)
                    .id(snap.mult)
            }
        }
        .pillBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snap.gems) gems\(snap.mult > 1 ? ", times \(snap.mult) multiplier" : "")")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: power-up status — big, color-coded, readable countdowns (v1.6)

    /// One colour-coded chip per ACTIVE power-up, each with its own hue + a clear seconds countdown
    /// and a depletion bar (the owner's "I can't tell how long slow-mo lasts — it's a tiny grey
    /// circle" fix). Shield is held (no timer); the rest count down in their own colour.
    @ViewBuilder private func powerUpStack(_ snap: GameSnapshot) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if snap.shieldActive {
                powerUpChip("shield.lefthalf.filled", 0x00F5FF, "SHIELD", remaining: nil, duration: 0)
            }
            if snap.magnetRemaining > 0 {
                powerUpChip("dot.radiowaves.left.and.right", 0xFF2BD6, "MAGNET",
                            remaining: snap.magnetRemaining, duration: Tuning.magnetDuration)
            }
            if snap.doublerRemaining > 0 {
                powerUpChip("2.circle.fill", 0x00FF88, "×2 COINS",
                            remaining: snap.doublerRemaining, duration: Tuning.doublerDuration)
            }
            if snap.chronoRemaining > 0 {
                powerUpChip("hourglass", 0x9BF0FF, "SLOW-MO",
                            remaining: snap.chronoRemaining, duration: Tuning.chronoDuration)
            }
            if snap.sneakersRemaining > 0 {
                powerUpChip("arrow.up.circle.fill", 0xFF8A2B, "SNEAKERS",
                            remaining: snap.sneakersRemaining, duration: Tuning.superSneakersDuration)
            }
            if snap.boostRemaining > 0 {
                powerUpChip("bolt.fill", 0xFFD23D, "OVERDRIVE",
                            remaining: snap.boostRemaining, duration: Tuning.boostDuration)
            }
        }
        .animation(.spring(duration: 0.25), value: snap.shieldActive)
    }

    /// A power-up chip: coloured icon + name + a big seconds countdown, over a depletion bar in the
    /// power-up's own colour. Held power-ups (shield) show a breathing "READY" instead of a timer.
    /// Last 3 s pulses (reduceFlash dims rather than blinks). Reads at a glance, mid-rush.
    private func powerUpChip(_ symbol: String, _ hex: UInt32, _ name: String,
                             remaining: Double?, duration: Double) -> some View {
        let color = Theme.color(hex)
        let reduceFlash = ProfileStore.shared.profile.reduceFlash
        let warning = (remaining ?? .infinity) < 3
        let pulse = !warning || reduceFlash || Int((remaining ?? 0) * 4) % 2 == 0
        let progress = remaining != nil && duration > 0 ? max(0.03, min(1, remaining! / duration)) : 1
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                Text(name).font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.5)
                if let r = remaining {
                    Text("\(Int(r.rounded(.up)))s")
                        .font(.system(size: 14, weight: .black, design: .rounded)).monospacedDigit()
                } else {
                    Text("READY").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.5)
                }
            }
            .foregroundStyle(color)
            // Depletion bar in the power-up's own colour (held power-ups show a full bar).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(color).frame(width: max(3, geo.size.width * progress))
                }
            }
            .frame(width: 88, height: 4)
        }
        .opacity(pulse ? 1 : 0.45)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.55), lineWidth: 1))
        .shadow(color: color.opacity(0.45), radius: 7)
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining == nil ? "\(name) ready"
                            : "\(name), \(Int((remaining ?? 0).rounded(.up))) seconds left")
    }

    // MARK: flow pips — near-miss streak toward the next surge

    /// `flowPerSurge` dots fill as CLOSE/SLICKs chain; the surge itself resets them (Core-fed).
    @ViewBuilder private func flowPips(_ snap: GameSnapshot) -> some View {
        let filled = snap.flowStreak % Tuning.flowPerSurge
        if snap.flowStreak > 0, filled > 0 {
            HStack(spacing: 5) {
                ForEach(0..<Tuning.flowPerSurge, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? Theme.Role.interactive : Color.white.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .shadow(color: i < filled ? Theme.Role.interactive.opacity(0.8) : .clear, radius: 4)
                }
            }
            .pillBackground()
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Flow streak \(filled) of \(Tuning.flowPerSurge)")
        }
    }
}

/// Glassy pill chrome shared by HUD chips.
private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.14)))
    }
}

extension View {
    func pillBackground() -> some View { modifier(PillBackground()) }
}
