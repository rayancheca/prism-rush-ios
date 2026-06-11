import SwiftUI

/// In-run heads-up display, on a diet (uiux §6.8): score top-left (BEST hidden during play — it
/// returns only as the ghost-chase chip when you're within 10% of it), the merged gem/multiplier
/// pill top-right, icon timer rings for the power-ups, flow pips and the boost ring. Reads the
/// observed `core.snapshot`, refreshes per frame, and stays strictly non-interactive.
struct HUDView: View {
    let core: GameCore

    var body: some View {
        let snap = core.snapshot
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(snap.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .shadow(color: .white.opacity(0.35), radius: 12)
                        .accessibilityLabel("Score \(snap.score)")
                        .accessibilityAddTraits(.updatesFrequently)
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
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .animation(.spring(duration: 0.25), value: snap.mult)
        .opacity(snap.mode == .play ? 1 : 0)
        .allowsHitTesting(false)   // the run is the UI — pause is the only in-play button
    }

    // MARK: ghost chase — BEST appears only when it's actually a chase

    /// One-shot chase chip when within 10% of the best (and a best exists): "BEST 320 AHEAD" in
    /// the world accent. It vanishes on crossing — the NEW BEST celebration takes over.
    @ViewBuilder private func ghostChaseChip(_ snap: GameSnapshot) -> some View {
        if snap.best > 0, snap.score < snap.best,
           Double(snap.score) >= 0.9 * Double(snap.best) {
            let accent = Theme.color(Theme.worlds[snap.worldTo % 3].accent2)
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

    @ViewBuilder private func timerRings(_ snap: GameSnapshot) -> some View {
        let anyActive = snap.magnetRemaining > 0 || snap.doublerRemaining > 0
            || snap.chronoRemaining > 0 || snap.boostRemaining > 0
        if anyActive {
            HStack(spacing: 8) {
                if snap.boostRemaining > 0 {
                    timerRing("bolt.fill", remaining: snap.boostRemaining,
                              duration: Tuning.boostDuration, name: "Overdrive")
                }
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
