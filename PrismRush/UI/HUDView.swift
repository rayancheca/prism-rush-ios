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
                    timerRings(snap)
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

    // MARK: power-up timer rings (uiux §6.8 — icons in circular depletion strokes, no rainbow)

    /// Overdrive deliberately has NO ring (AUDIT D6-7): `boostDuration` is ~1 s, so its ring was
    /// unreadable churn next to the OVERDRIVE popup + SFX + speed FX that already announce it.
    @ViewBuilder private func timerRings(_ snap: GameSnapshot) -> some View {
        let anyActive = snap.magnetRemaining > 0 || snap.doublerRemaining > 0
            || snap.chronoRemaining > 0
        if anyActive {
            HStack(spacing: 8) {
                if snap.magnetRemaining > 0 {
                    timerRing("dot.radiowaves.left.and.right", remaining: snap.magnetRemaining,
                              duration: Tuning.magnetDuration, name: "Magnet")
                }
                if snap.doublerRemaining > 0 {
                    timerRing("2.circle.fill", remaining: snap.doublerRemaining,
                              duration: Tuning.doublerDuration, name: "Doubler")
                }
                if snap.chronoRemaining > 0 {
                    timerRing("hourglass", remaining: snap.chronoRemaining,
                              duration: Tuning.chronoDuration, name: "Slow motion")
                }
            }
            .transition(.scale)
        }
    }

    /// 20 pt depletion ring, `Role.interactive` for all power-ups. Last-4-seconds warning blinks
    /// the ring twice a second; with Reduce Flashing on, the ring thins instead of blinking.
    private func timerRing(_ symbol: String, remaining: Double, duration: Double, name: String) -> some View {
        // Read live in body (G3): the Settings toggle applies to the very next warning.
        let reduceFlash = ProfileStore.shared.profile.reduceFlash
        let warning = remaining < 4 && duration > 4
        let blinkOn = !warning || reduceFlash || Int(remaining * 4) % 2 == 0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: warning && reduceFlash ? 1.2 : 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, remaining / duration))
                .stroke(Theme.Role.interactive,
                        style: StrokeStyle(lineWidth: warning && reduceFlash ? 1.2 : 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(blinkOn ? 1 : 0.25)
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 20, height: 20)
        .pillBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(Int(remaining.rounded(.up))) seconds left")
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
