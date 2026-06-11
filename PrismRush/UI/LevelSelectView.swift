import SwiftUI

/// Worlds tab, alive (uiux §3): a big preview header for the deepest startable world (PLAY FROM
/// HERE), a NEXT UNLOCK strip for the rung you're climbing, then the FULL 12-world ladder (v1.4):
/// reached worlds carry their best and start a checkpoint run, purchased-but-unreached worlds wear
/// OWNED, and locked worlds stay visible and enticing — dimmed vignette, lock chip, distance
/// requirement AND a price pill (reach it OR buy it). An ∞ AND BEYOND end-cap promises the run
/// never ends. All profile state is read from `ProfileStore.shared` at point of use (G3 — no
/// snapshot).
struct LevelSelectView: View {
    let model: GameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Locked card tapped → the unlock panel for this world index (nil = no panel open).
    @State private var unlockTarget: Int?

    var body: some View {
        // Deepest startable world (reach OR purchase), clamped to the display ladder; the ladder
        // itself always shows every rung — `worldDisplayCount` cards, status derived per render.
        let furthest = min(ProfileStore.shared.highestStartableWorld, ProfileStore.maxStartWorlds - 1)
        let nextLocked = (0..<ProfileStore.worldDisplayCount)
            .first { !ProfileStore.shared.isWorldStartable($0) }

        MetaScreenScaffold(title: "Worlds", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }, onCoins: { model.open(.shop) }) {
            VStack(spacing: Theme.Space.m) {
                previewHeader(furthest: furthest)

                // The next rung above the fold: the ladder's single most actionable CTA — both
                // keys (reach OR pay) in one line, routing to the same unlock panel as its card.
                if let next = nextLocked { nextUnlockStrip(world: next) }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Space.m)],
                          spacing: Theme.Space.m) {
                    ForEach(0..<ProfileStore.worldDisplayCount, id: \.self) { world in
                        // Status reads happen here, per render, straight off the live store (G3) —
                        // a successful purchase flips the card to startable on the same beat.
                        if ProfileStore.shared.isWorldStartable(world) {
                            WorldCard(world: world,
                                      isFurthest: world == furthest,
                                      isPurchase: world > ProfileStore.shared.profile.maxWorldReached,
                                      best: ProfileStore.shared.profile.bestDistanceByWorld[world] ?? 0) {
                                model.startRun(fromWorld: world)
                            }
                        } else {
                            LockedWorldCard(world: world) { unlockTarget = world }
                        }
                    }
                    BeyondCard()
                }
            }
        }
        .overlay {
            if let world = unlockTarget {
                UnlockPanel(model: model, world: world) { unlockTarget = nil }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: unlockTarget)
    }

    /// Full-width 200 pt header: the deepest startable world's hero vignette + PLAY FROM HERE.
    /// The whole header is one tap target → `startRun(fromWorld: furthest)`.
    private func previewHeader(furthest: Int) -> some View {
        let palette = Theme.worlds[furthest % 3]
        let best = ProfileStore.shared.profile.bestDistanceByWorld[furthest] ?? 0
        return Button {
            model.startRun(fromWorld: furthest)
        } label: {
            ZStack(alignment: .bottomLeading) {
                WorldPreviewCanvas(palette: palette, worldIndex: furthest, size: .hero)
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("FURTHEST CHECKPOINT")
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.title)
                        .foregroundStyle(Theme.Role.textPrimary)
                    HStack {
                        Text(best > 0 ? "BEST HERE \(Int(best))m" : "UNTOUCHED")
                            .typeScale(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Role.textSecondary)
                        Spacer()
                        // Interactive-border pill, NOT a gradient — the PLAY gradient budget
                        // belongs to the menu (uiux §3.1).
                        Text("PLAY FROM HERE")
                            .typeScale(.caption)
                            .foregroundStyle(Theme.Role.interactive)
                            .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                            .overlay(Capsule().strokeBorder(Theme.Role.interactive, lineWidth: 1.5))
                    }
                }
                .padding(Theme.Space.m)
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).strokeBorder(Theme.Role.hairline))
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldHeader")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Furthest checkpoint: world \(furthest + 1), \(palette.name)."
                            + (best > 0 ? " Your best here: \(Int(best)) meters." : " Untouched."))
        .accessibilityHint("Starts a run from your furthest checkpoint.")
    }

    /// One-line "next rung" strip: chip vignette, name, both keys (REACH n m / UNLOCK · price) —
    /// pinned above the fold so the climb is always visible. Tap → the same unlock panel.
    private func nextUnlockStrip(world: Int) -> some View {
        let palette = Theme.worlds[world % 3]
        let price = XPCurve.worldPrice(world)
        let reachM = Int(Double(world) * Tuning.worldLength)
        return Button { unlockTarget = world } label: {
            HStack(spacing: Theme.Space.s + 4) {
                WorldPreviewCanvas(palette: palette, worldIndex: world, size: .chip)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .strokeBorder(Theme.Role.hairline))
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT UNLOCK")
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("REACH \(reachM.formatted())m")
                        .typeScale(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.lock)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: Theme.Space.s)
                UnlockPricePill(price: price, compact: true)
            }
            .padding(Theme.Space.m - 4)
            .neonCard(radius: Theme.Radius.l)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("nextUnlockStrip")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next unlock: world \(world + 1), \(palette.name)."
                            + " Unlock for \(price) coins, or reach \(reachM) meters.")
        .accessibilityHint("Shows unlock options.")
    }
}

/// One startable world: live vignette on top, facts below (uiux §3.2). The furthest card wears
/// the only world-colored stroke allowed in meta; purchased-but-unreached worlds wear an OWNED
/// badge (gold = money, mirroring the characters NEW badge treatment).
private struct WorldCard: View {
    let world: Int
    let isFurthest: Bool
    let isPurchase: Bool
    let best: Double
    let action: () -> Void

    private var palette: WorldPalette { Theme.worlds[world % 3] }
    private var checkpointM: Int { Int(Double(world) * Tuning.worldLength) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                WorldPreviewCanvas(palette: palette, worldIndex: world, size: .card)
                    .frame(height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "WORLD %02d", world + 1))
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(best > 0 ? "BEST \(Int(best))m" : "UNTOUCHED")
                        .typeScale(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.textSecondary)
                    Text(world == 0 ? "▸ START" : "▸ \(checkpointM.formatted())m IN")
                        .typeScale(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(palette.accent2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m - 4)
            }
            .background(Theme.Role.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .strokeBorder(isFurthest ? Theme.color(palette.accent2) : Theme.Role.hairline,
                                  lineWidth: isFurthest ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isPurchase {
                    Text("OWNED")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.goldGradient, in: Capsule())
                        .padding(6)
                }
            }
            .shadow(color: isFurthest ? Theme.color(palette.accent2).opacity(0.35) : .clear, radius: 12)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldCard_\(world + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World \(world + 1), \(palette.name)."
                            + (isPurchase ? " Owned." : "")
                            + (best > 0 ? " Your best here: \(Int(best)) meters." : " Untouched.")
                            + (world == 0 ? " The start." : " Checkpoint \(checkpointM) meters in."))
        .accessibilityHint("Starts a run from this checkpoint.")
    }
}

/// A locked rung of the ladder, visible and enticing (v1.4): the live vignette dimmed — never
/// blacked out — under a lock chip, with the distance requirement and the gold price pill. Tap →
/// the unlock panel (reach it OR buy it; the old dead-end shake is gone — nothing on screen is
/// dead, uiux §5).
private struct LockedWorldCard: View {
    let world: Int
    let action: () -> Void

    private var palette: WorldPalette { Theme.worlds[world % 3] }
    private var requiredM: Int { Int(Double(world) * Tuning.worldLength) }
    private var price: Int { XPCurve.worldPrice(world) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                WorldPreviewCanvas(palette: palette, worldIndex: world, size: .card)
                    .frame(height: 96)
                    .saturation(0.55)
                    .opacity(0.75)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("LOCKED")
                                .typeScale(.micro)
                        }
                        .foregroundStyle(Theme.Role.textSecondary)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(Theme.Space.s)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "WORLD %02d", world + 1))
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("REACH \(requiredM.formatted())m")
                        .typeScale(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.lock)
                    UnlockPricePill(price: price, compact: true)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m - 4)
            }
            .background(Theme.Role.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(Theme.Role.hairline))
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldCard_\(world + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World \(world + 1), \(palette.name), locked,"
                            + " unlock for \(price) coins, or reach \(requiredM) meters.")
        .accessibilityHint("Shows unlock options.")
    }
}

/// The ladder's end-cap, non-interactive: after world 12 the run NEVER ends — worlds keep
/// cycling, so the deepest card is a promise, not a wall. Dashed hairline = horizon, not surface.
private struct BeyondCard: View {
    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Text("∞")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Role.interactive)
                .shadow(color: Theme.Role.interactive.opacity(0.5), radius: 10)
            Text("AND BEYOND")
                .typeScale(.heading)
                .foregroundStyle(Theme.Role.textPrimary)
            Text("WORLDS CYCLE FOREVER")
                .typeScale(.micro)
                .foregroundStyle(Theme.Role.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(Theme.Role.surface.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
            .strokeBorder(Theme.Role.hairline, style: StrokeStyle(lineWidth: 1, dash: [6, 6])))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("beyondCard")
        .accessibilityLabel("And beyond: after world twelve the run never ends — worlds cycle forever.")
    }
}

/// The gold spend pill shared by the strip / locked cards / unlock panel: coin glyph +
/// "UNLOCK · price" (gold = money ONLY, uiux §2 — this is a spend, so it wears the goldGradient
/// like every BUY).
private struct UnlockPricePill: View {
    let price: Int
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            CoinGlyph(size: compact ? 12 : 14)
            Text("UNLOCK · \(price.formatted())")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()        // the price never wraps — neighbors shrink instead
        }
        .typeScale(.caption)
        .fontWeight(.heavy)
        .foregroundStyle(.black)
        .padding(.horizontal, compact ? Theme.Space.s + 4 : Theme.Space.l)
        .padding(.vertical, compact ? 8 : 12)
        .background(Theme.goldGradient, in: Capsule())
    }
}

/// The buy flow (v1.4): scrim + centered detail card for ONE locked world — bigger hero vignette
/// and the two keys: UNLOCK · price (→ `ProfileStore.unlockWorld`) and the REACH IT explainer.
/// Success = celebratory gold ring pulse + purchaseChime, then the panel dismisses itself and the
/// flipped (startable) card is revealed underneath. Insufficient = denied shake (Reduce Motion
/// swaps it for the border flash, CharacterSelect's denial language) + NEED n MORE + GET COINS →
/// Shop. Lives inside the Worlds sheet as an overlay — no nested SwiftUI sheet.
private struct UnlockPanel: View {
    let model: GameModel
    let world: Int
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deniedShakes: CGFloat = 0
    /// Armed by a failed buy: red border on the pill + the NEED/GET COINS row (stays up — the
    /// player should read the shortfall, not chase a flash).
    @State private var denied = false
    @State private var celebrating = false
    @State private var ringExpand = false
    /// Tracked auto-dismiss after the celebration beat — cancelled if the view dies first, so a
    /// dismissed sheet can never close its successor (CharacterSelect.closeTask pattern).
    @State private var dismissTask: Task<Void, Never>?

    private var palette: WorldPalette { Theme.worlds[world % 3] }
    private var price: Int { XPCurve.worldPrice(world) }
    private var reachM: Int { Int(Double(world) * Tuning.worldLength) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { if !celebrating { onClose() } }
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.m) {
                WorldPreviewCanvas(palette: palette, worldIndex: world, size: .hero)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .strokeBorder(Theme.Role.hairline))
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.xs) {
                    Text(String(format: "WORLD %02d", world + 1))
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.title)
                        .foregroundStyle(Theme.Role.textPrimary)
                }

                if celebrating {
                    Text("UNLOCKED")
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.reward)
                        .accessibilityLabel("World \(world + 1) unlocked")
                } else {
                    // Key 1 — pay: the gold pill commits the purchase.
                    Button { attemptUnlock() } label: {
                        UnlockPricePill(price: price)
                            .overlay(Capsule().strokeBorder(denied ? Theme.Role.danger : .clear,
                                                            lineWidth: 2))
                    }
                    .buttonStyle(.neon)
                    .modifier(ShakeEffect(trigger: deniedShakes))
                    .accessibilityIdentifier("unlockButton_\(world + 1)")
                    .accessibilityLabel("Unlock world \(world + 1) for \(price) coins")

                    if denied {
                        // Live shortfall (G3 — coins read straight off the store per render).
                        let need = max(0, price - ProfileStore.shared.profile.coins)
                        HStack(spacing: Theme.Space.s) {
                            Text("NEED \(need.formatted()) MORE")
                                .typeScale(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Role.danger)
                            Button { model.open(.shop) } label: {
                                Text("GET COINS")
                                    .typeScale(.caption)
                                    .foregroundStyle(Theme.Role.reward)
                                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 8)
                                    .overlay(Capsule().strokeBorder(Theme.Role.reward.opacity(0.6)))
                            }
                            .buttonStyle(.neon)
                            .accessibilityIdentifier("unlockGetCoins")
                            .accessibilityLabel("Get coins. Opens the shop")
                        }
                    }

                    // Key 2 — reach: the free path, spelled out (distance was always a key).
                    Button { onClose() } label: {
                        VStack(spacing: 2) {
                            Text("REACH IT · \(reachM.formatted())m")
                                .typeScale(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Role.interactive)
                            Text("RUNS THAT DEEP UNLOCK IT FREE")
                                .typeScale(.micro)
                                .foregroundStyle(Theme.Role.textTertiary)
                        }
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
                        .background(Theme.Role.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Role.hairline))
                    }
                    .buttonStyle(.neon)
                    .accessibilityIdentifier("unlockReach_\(world + 1)")
                    .accessibilityLabel("Or reach it free: run \(reachM) meters from any earlier world")
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: 340)
            .background(Theme.Role.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(celebrating ? Theme.Role.reward : Theme.Role.hairline,
                              lineWidth: celebrating ? 2 : 1))
            .overlay {
                // Celebratory pulse: a gold ring blooming off the card edge (RM = none).
                if celebrating && !reduceMotion {
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .strokeBorder(Theme.Role.reward, lineWidth: 3)
                        .scaleEffect(ringExpand ? 1.12 : 1.0)
                        .opacity(ringExpand ? 0 : 1)
                        .onAppear { withAnimation(.easeOut(duration: 0.7)) { ringExpand = true } }
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(celebrating && !reduceMotion ? 1.03 : 1)
            .padding(Theme.Space.m)
            .accessibilityAddTraits(.isModal)
        }
        .onDisappear { dismissTask?.cancel() }
    }

    /// Commit the purchase. `unlockWorld` is the single gate (range / already-startable / spend);
    /// the panel only ever opens on locked in-range worlds, so false means "can't afford".
    private func attemptUnlock() {
        guard !celebrating else { return }
        if ProfileStore.shared.unlockWorld(world) {
            model.synth.play(.purchaseChime)
            if reduceMotion {
                celebrating = true
            } else {
                withAnimation(.spring(duration: 0.45, bounce: 0.4)) { celebrating = true }
            }
            dismissTask = Task {
                try? await Task.sleep(for: .milliseconds(1_100))
                guard !Task.isCancelled else { return }
                onClose()
            }
        } else {
            denied = true
            if !reduceMotion {
                withAnimation(.linear(duration: 0.4)) { deniedShakes += 1 }
            }
        }
    }
}
