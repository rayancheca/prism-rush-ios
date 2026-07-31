import SwiftUI

/// In-run heads-up display, on a diet (uiux §6.8): score top-left (BEST hidden during play — it
/// returns only as the ghost-chase chip when you're within 10% of it), the merged gem/multiplier
/// pill top-right, icon timer rings for the power-ups, and flow pips. Reads the observed
/// `core.snapshot`, refreshes per frame, and stays strictly non-interactive.
struct HUDView: View {
    let core: GameCore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // The multiplier lives HERE, on the thing it multiplies (v2.1, S-011). It used
                    // to occupy the LABEL slot of the gem chip, so for ~90% of a run that chip read
                    // `◆ ×5 24,523` with no noun anywhere — a SCORE multiplier printed against a
                    // CURRENCY figure it has never touched. The owner, looking at exactly that:
                    // *"what does x5 mean in the [HUD] and why am i getting so many coins."*
                    HStack(spacing: 6) {
                        Text("SCORE \(snap.score)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.68))
                        if snap.mult > 1 {
                            Text("×\(snap.mult)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.color(0x00F5FF))
                                .shadow(color: Theme.color(0x00F5FF).opacity(0.8), radius: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(snap.mult > 1
                                        ? "Score \(snap.score), times \(snap.mult) multiplier"
                                        : "Score \(snap.score)")
                    ghostChaseChip(snap)
                }

                Spacer()

                // Starts below the mute/pause cluster anchored in the top-trailing corner.
                VStack(alignment: .trailing, spacing: 8) {
                    gemPill(snap)
                    chargeMeter(snap)
                    powerUpStack(snap)
                    flowPips(snap)
                }
                // Sits clear BELOW the mute/pause cluster (those are 38pt buttons at top padding 14);
                // the owner found the old 38 crowded them. Starts the chips ~22pt under the buttons.
                .padding(.top, 64)
            }
            Spacer()
            // The Warden readout sits LOW, just above the XP bar — not under the score row.
            //
            // Centred at the top it landed on the craft's exact screen coordinates: "CORE EXPOSED"
            // was drawn straight through the hull, and at rank 3 the six hit pips were a 471 px row
            // — 1.6× wider than the entire ship — painted across it in full-saturation red against
            // the hull's desaturated grey. The player was reading the label instead of the boss.
            // Down here it is still centred and still unmissable, but the sky it describes is clear.
            wardenPanel(snap)
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

    // MARK: Wardens (v1.9)

    private static let hazard = Theme.color(0xFF3355)
    private static let shieldHue = Theme.color(0x66E0FF)
    /// The calm tint for a state that is normal but not yet actionable — a reloading blast bank.
    /// Deliberately NOT `hazard`: having no ammo is an expected situation, and decree 3 says an
    /// expected situation never gets a red.
    private static let dim = Theme.color(0x8C93B8)

    /// The charge bank — **ammunition for THE BLAST** (v2.2).
    ///
    /// It used to read `CHARGE · 37%`, and a percentage was the wrong unit twice over. It appears
    /// 1.5 s into the first run anybody ever plays, and until v2.2 the thing it fed (a Warden's fire
    /// rate) did not exist for another 104 seconds — so a new player watched a bar fill for nearly
    /// two minutes with no way to learn what it was for. And even during a fight, "37%" is not a
    /// decision: nobody can act on a fraction of a gun.
    ///
    /// Charge is now ammo and this reads as ammo. The unit is ROUNDS — `⚡︎ ×2` — because rounds are
    /// what the player spends, and the fractional remainder rides the chip's own progress rule so
    /// the next round still visibly fills. Below one round it says `RELOADING`, which is the honest
    /// word for a bar that cannot yet be spent, and it says it in the calm tint rather than the
    /// hazard one: having no ammo is a normal state, not a failure (decree 3).
    @ViewBuilder
    private func chargeMeter(_ snap: GameSnapshot) -> some View {
        if snap.wardenCharge > 0.001 {
            let rounds = Int((snap.wardenCharge / Tuning.blastCost).rounded(.down))
            // Progress toward the NEXT round, so the bar always measures the thing it is filling.
            // At the cap it pins full rather than snapping back to zero.
            let toNext = min(1, (snap.wardenCharge / Tuning.blastCost) - Double(rounds))
            let armed = rounds > 0
            StatusChip(tint: armed ? Self.shieldHue : Self.dim,
                       label: armed ? "BLAST" : "RELOADING",
                       progress: snap.wardenCharge >= 0.999 ? 1 : toNext) {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .black))
            } value: {
                Text(armed ? "×\(rounds)" : "\(Int(toNext * 100))%")
                    .font(.system(size: 13, weight: .black, design: .rounded)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(armed
                ? "Blast charges: \(rounds). Double tap to fire."
                : "Blast reloading, \(Int(toNext * 100)) percent to the next charge.")
        }
    }

    /// The encounter readout: what is left of the shield, and how much of the core is gone.
    ///
    /// Centre-top, below the score row, because during a fight this is the only thing that matters
    /// and it must not be hunted for. Absent entirely on open track — nothing here is decorative.
    @ViewBuilder
    private func wardenPanel(_ snap: GameSnapshot) -> some View {
        if let w = snap.warden, w.phase != .leaving {
            let broken = w.shieldFraction <= 0
            VStack(spacing: 5) {
                Text(broken ? "CORE EXPOSED" : "WARDEN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(broken ? Self.hazard : Self.shieldHue)
                if broken {
                    // Three pips, not a bar: the kill is a fixed count of clean dodges, so the
                    // readout should be countable at a glance rather than estimated off a length.
                    // Count comes from the ENCOUNTER, never from a constant: a rank-3 Warden needs
                    // six clean answers where a rank-1 needs four, and a HUD that pinned the old
                    // flat value would quietly under-report the fight the player is actually in.
                    HStack(spacing: 5) {
                        ForEach(0..<w.coreHitsNeeded, id: \.self) { i in
                            Capsule()
                                .fill(i < w.coreHits ? Self.hazard : .white.opacity(0.22))
                                .frame(width: 22, height: 5)
                        }
                    }
                } else {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 132, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Self.shieldHue)
                                .frame(width: 132 * w.shieldFraction, height: 6)
                        }
                }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(broken
                ? "Warden core exposed, \(w.coreHits) of \(w.coreHitsNeeded) hits landed"
                : "Warden shielded, \(Int(w.shieldFraction * 100)) percent")
            .transition(.opacity)
        }
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

    // MARK: the gem pill — `◆ GEMS 23`

    /// **It always says GEMS** (v2.1, S-011).
    ///
    /// The multiplier used to take the LABEL slot, on the reasoning that it read as *what this chip
    /// is*. The flaw was arithmetic rather than typographic: `mult` reaches its ×5 cap at 124 m /
    /// 7.16 s and holds it for **90.3% of a clean run**, so the label was almost never "GEMS" — the
    /// chip spent nearly every run showing a bare `×5` beside a five-digit number with nothing
    /// naming either. And the two have never been related: `mult` multiplies SCORE, and every
    /// currency line in `GameCore` deliberately omits it.
    ///
    /// The multiplier now sits beside the score readout, on the quantity it actually multiplies.
    /// The label slot is fixed text, so the width still never reflows — which was the original
    /// concern, and it is preserved without paying for it in meaning.
    private func gemPill(_ snap: GameSnapshot) -> some View {
        let gold = Color(red: 1, green: 0.82, blue: 0.24)
        return StatusChip(tint: gold, label: "GEMS") {
            RoundedRectangle(cornerRadius: 2)
                .fill(gold)
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
                .shadow(color: gold, radius: 5)
        } value: {
            Text("\(snap.gems)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snap.gems) gems")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: power-up status — big, color-coded, readable countdowns (v1.6)

    /// One colour-coded chip per ACTIVE power-up, each with its own hue + a clear seconds countdown
    /// and a depletion bar (the owner's "I can't tell how long slow-mo lasts — it's a tiny grey
    /// circle" fix). Shield is held (no timer); the rest count down in their own colour.
    @ViewBuilder private func powerUpStack(_ snap: GameSnapshot) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if snap.shieldActive {
                powerUpChip(.shield, "SHIELD", remaining: nil, duration: 0)
            }
            if snap.magnetRemaining > 0 {
                powerUpChip(.magnet, "MAGNET",
                            remaining: snap.magnetRemaining, duration: Tuning.magnetDuration)
            }
            if snap.doublerRemaining > 0 {
                powerUpChip(.doubler, "×2 COINS",
                            remaining: snap.doublerRemaining, duration: Tuning.doublerDuration)
            }
            if snap.chronoRemaining > 0 {
                powerUpChip(.slowMo, "SLOW-MO",
                            remaining: snap.chronoRemaining, duration: Tuning.chronoDuration)
            }
            if snap.sneakersRemaining > 0 {
                powerUpChip(.sneakers, "SNEAKERS",
                            remaining: snap.sneakersRemaining, duration: Tuning.superSneakersDuration)
            }
            if snap.boostRemaining > 0 {
                powerUpChip(.overdrive, "OVERDRIVE",
                            remaining: snap.boostRemaining, duration: Tuning.boostDuration)
            }
        }
        .animation(.spring(duration: 0.25), value: snap.shieldActive)
    }

    /// A power-up chip: coloured icon + name + a big seconds countdown, over a depletion bar in the
    /// power-up's own colour. Held power-ups (shield) show a breathing "READY" instead of a timer.
    /// Last 3 s pulses (reduceFlash dims rather than blinks). Reads at a glance, mid-rush.
    private func powerUpChip(_ kind: PowerUpKind, _ name: String,
                             remaining: Double?, duration: Double) -> some View {
        let color = Theme.color(kind.hex)
        // System Reduce Motion suppresses the last-3s blink too, not just the custom Reduce Flash.
        let reduceFlash = ProfileStore.shared.profile.reduceFlash || reduceMotion
        let warning = (remaining ?? .infinity) < 3
        let blinkOff = warning && !reduceFlash && Int((remaining ?? 0) * 4) % 2 != 0
        // A held power-up (shield) has no duration, so it draws no bar at all rather than a
        // permanently-full one — a full bar that never moves reads as a timer that is stuck.
        let progress = remaining.flatMap { duration > 0 ? max(0.03, min(1, $0 / duration)) : nil }
        return StatusChip(tint: color, label: name, progress: progress, dimmed: blinkOff) {
            PowerUpGlyph(kind: kind, size: 15, tint: color)
        } value: {
            if let r = remaining {
                Text("\(Int(r.rounded(.up)))s")
                    .font(.system(size: 14, weight: .black, design: .rounded)).monospacedDigit()
            } else {
                Text("HELD").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.5)
            }
        }
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining == nil ? "\(name) held"
                            : "\(name), \(Int((remaining ?? 0).rounded(.up))) seconds left")
    }

    // MARK: flow pips — near-miss streak toward the next surge

    /// `flowPerSurge` dots fill as CLOSE/SLICKs chain; the surge itself resets them (Core-fed).
    @ViewBuilder private func flowPips(_ snap: GameSnapshot) -> some View {
        let filled = snap.flowStreak % Tuning.flowPerSurge
        if snap.flowStreak > 0, filled > 0 {
            // Labelled so the dots aren't a mystery (owner: "what the fuck is that?"): a FLOW meter
            // that fills as you chain near-misses (CLOSE/SLICK) — completing it pops a gem fountain.
            StatusChip(tint: Theme.Role.interactive, label: "FLOW") {
                Image(systemName: "wind").font(.system(size: 11, weight: .black))
            } value: {
                HStack(spacing: 5) {
                    ForEach(0..<Tuning.flowPerSurge, id: \.self) { i in
                        Circle()
                            .fill(i < filled ? Theme.Role.interactive : Color.white.opacity(0.18))
                            .frame(width: 6, height: 6)
                            .shadow(color: i < filled ? Theme.Role.interactive.opacity(0.8) : .clear, radius: 4)
                    }
                }
            }
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Flow meter, \(filled) of \(Tuning.flowPerSurge) near-misses to a gem fountain")
        }
    }
}

/// The in-run status stack's one and only chip (S-009).
///
/// **What this replaces, and why.** The top-right column had grown four unrelated geometries: the
/// gem pill hugged its content (so it visibly *changed width* as the count went 23 → 798), the
/// charge meter was a bare label with no container at all, power-up chips hugged their own name
/// length and carried an extra colour glow, and the flow pips were a third chrome. Five things
/// stacked in a right-aligned column, no two the same size — the owner's *"i really dont like this
/// being different sizes"*.
///
/// Ragged is the visible symptom; the real cost is that SIZE was accidentally carrying meaning.
/// `SHIELD ACTIVE` was the widest and most heavily glowing element on screen, so it read as the
/// most urgent thing in the run merely because its label was long. Decree 6 says clarity beats
/// spectacle and the UI stays calm with role-based colour — so size and chrome are now constant
/// across every chip, and **colour is the only channel that varies**. What a chip means comes from
/// its hue and its glyph, never from how big it is.
///
/// The layout is a fixed three-slot row — `[glyph] [label] [value]` — with the value trailing and
/// monospaced, so digits never shift the chip's internals either. A chip with a duration draws a
/// depletion hairline; one without simply centres its row in the same fixed height, so the column
/// stays on a single rhythm whether one power-up is live or all six are.
private struct StatusChip<Glyph: View, Value: View>: View {
    let tint: Color
    let label: String
    /// 0…1 depletion, or `nil` for a chip that is held or has no duration.
    var progress: Double? = nil
    /// Dims the whole chip without blinking — the last-3s warning under Reduce Flash.
    var dimmed = false
    @ViewBuilder var glyph: () -> Glyph
    @ViewBuilder var value: () -> Value

    /// One width for the whole column, sized so that NO chip is ever the exception — the widest
    /// combination in the set is `CHARGE` beside a three-character `100%`, which truncated at 146.
    /// Verified on the simulator rather than estimated; `OVERDRIVE 12s` and `SHIELD HELD` both clear
    /// it with room. A chip that has to truncate is a chip that will be redesigned separately, which
    /// is how the column became four different sizes in the first place.
    static var width: CGFloat { 162 }
    static var height: CGFloat { 38 }
    private static var radius: CGFloat { 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                glyph().frame(width: 15, height: 15)
                Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
                Spacer(minLength: 4)
                value()
            }
            .foregroundStyle(tint)
            if let progress {
                Capsule().fill(.white.opacity(0.14))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(tint)
                                .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
                        }
                    }
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: Self.width, height: Self.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.radius))
        .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(tint.opacity(0.45)))
        // One shadow budget for every chip. The power-up chips used to carry a bigger bloom than
        // their neighbours, which is the same mistake as the width: emphasis by accident.
        .shadow(color: tint.opacity(0.28), radius: 5)
        .opacity(dimmed ? 0.45 : 1)
    }
}
