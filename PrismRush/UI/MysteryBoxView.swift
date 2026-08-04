import SwiftUI

/// The Mystery Box gacha as a full reveal SEQUENCE (v1.6): the player sees the honest odds, taps
/// OPEN, the box shakes + swivels with building anticipation, then bursts open in a shower of colour
/// and the reward flies out big. Subway-Surfers crate energy — entirely procedural (zero binary
/// assets). Honest odds shown up front + the real reward delivered (decree 5).
struct MysteryBoxView: View {
    let model: GameModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .idle
    @State private var wobble: Double = 0        // box shake/swivel angle (degrees)
    @State private var boxScale: CGFloat = 1
    @State private var lid: Double = 0           // 0 shut → 1 hinged fully back
    @State private var glow: Double = 0.4
    @State private var burstT: CGFloat = 0       // 0→1 reveal burst progress
    @State private var rewardIn = false
    @State private var revealTask: Task<Void, Never>?

    private enum Phase: Equatable { case idle, opening, revealed(ConsumableGrant) }
    private var cost: Int { ShopConsumables.mysteryBoxCost }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
                .onTapGesture { if case .revealed = phase { dismiss() } }

            if burstT > 0 { burstLayer }

            Group {
                switch phase {
                case .idle: idleContent
                case .opening: boxView
                case let .revealed(reward): revealContent(reward)
                }
            }
            .padding(Theme.Space.l)
        }
        .accessibilityIdentifier("mysteryBoxView")
        .accessibilityAddTraits(.isModal)
        .onDisappear { revealTask?.cancel() }   // the reveal beat must never outlive the sheet
    }

    // MARK: the box

    /// v2.5: the SAME `TreasureChest` the free chest and the daily bonus open, on the same hinge.
    ///
    /// This was `Image(systemName: "gift.fill")` — a stock SF Symbol that wobbled and scaled but
    /// never actually opened. The reward overlay next door has always drawn a real chest whose lid
    /// swings back, so the app had two different objects and two different opening motions for the
    /// identical player gesture, which is what the owner reported. The chest wins: it is drawn
    /// rather than borrowed, and a container that opens is the whole point of a gacha reveal.
    private var boxView: some View {
        TreasureChest(lid: lid, scale: boxScale)
            .shadow(color: Theme.Role.reward.opacity(glow), radius: 34)
            .rotationEffect(.degrees(wobble))
    }

    // MARK: idle — odds + OPEN

    private var idleContent: some View {
        // G3: coins read live off the store during `body`'s evaluation — never snapshotted.
        let shortfall = ShopConsumables.mysteryBoxShortfall(coins: ProfileStore.shared.profile.coins)
        return VStack(spacing: Theme.Space.m) {
            Text("MYSTERY BOX").font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(3)
                .foregroundStyle(Theme.Role.textSecondary)
            boxView.onAppear {
                guard !reduceMotion else { return }   // no perpetual idle wobble under Reduce Motion
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { wobble = 4 }
            }
            VStack(spacing: 6) {
                Text("ODDS").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(Theme.Role.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(ShopConsumables.mysteryOdds.indices, id: \.self) { i in
                    let o = ShopConsumables.mysteryOdds[i]
                    HStack {
                        Text(o.label).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.color(o.hex))
                        Spacer()
                        Text("\(o.pct)%").font(.system(size: 12.5, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Theme.Role.textSecondary)
                    }
                }
            }
            .padding(Theme.Space.m)
            .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .frame(maxWidth: 300)

            Button { open() } label: {
                HStack(spacing: 7) {
                    Text("OPEN").font(.system(size: 17, weight: .black, design: .rounded)).tracking(1)
                    CoinGlyph(size: 15)
                    Text("\(cost)").font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 30).frame(height: 54)
                .background(Theme.actionGradient, in: Capsule())
                .opacity(shortfall == 0 ? 1 : 0.5)
            }
            .buttonStyle(.neon)
            .disabled(shortfall > 0)
            .accessibilityIdentifier("mysteryBoxOpenButton")
            // The button carried NO label at all before, so VoiceOver read the price digits and
            // nothing else — strictly worse than the dimmed-row anti-pattern this sweep exists
            // to kill.
            .accessibilityLabel(shortfall == 0
                                ? "Open the Mystery Box for \(cost) coins"
                                : "Open costs \(cost) coins — you need \(shortfall) more")

            if shortfall > 0 {
                // GET COINS dismisses rather than routing to the Shop: `ShopView` is this
                // overlay's ONLY presenter, so `model.open(.shop)` would be a no-op that left the
                // box sitting on top of the coin packs it just sent the player to.
                ShortfallRow(shortfall: shortfall, routeTitle: "GET COINS", route: { dismiss() },
                             identifier: "mysteryBoxGetCoins",
                             shortfallIdentifier: "mysteryBoxShortfall",
                             routeHint: "Closes the box and returns to the coin packs")
            }

            // Real chrome: this was bare text, the only control in the app without any.
            Button { dismiss() } label: {
                Text("CLOSE")
                    .typeScale(.caption)
                    .foregroundStyle(Theme.Role.textSecondary)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
                    .background(Theme.Role.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("mysteryBoxClose")
        }
        // PR-0303: the odds table is this app's honesty surface and was the least legible thing on
        // screen. The 0.85 scrim at `:25` is already the strongest in the app and was never the
        // problem — `Role.surface` is 6% white, so the panel transmitted the Shop straight through
        // it. Every other modal sits on an opaque card (`UnlockPanel`, LevelSelectView:549); this
        // was the only one that did not.
        .padding(Theme.Space.m)
        .frame(maxWidth: 340)
        .background(Theme.Role.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
            .strokeBorder(Theme.Role.hairline))
    }

    // MARK: reveal

    private func revealContent(_ reward: ConsumableGrant) -> some View {
        VStack(spacing: Theme.Space.m) {
            // The OPEN chest stays on screen under the prize, exactly as `RewardBurstView` keeps
            // its chest above the coin line. Two reasons, and the second is the important one:
            //
            // 1. It is what makes the two surfaces actually match. The free chest ends its
            //    ceremony as an open chest with the reward beside it; ending this one on a bare
            //    number would still have been a different moment even with the same object.
            // 2. It makes the opening impossible to MISS. The hinge itself runs in the 320 ms
            //    before this view appears, which is a window the player can blink through — and,
            //    as this session found the hard way, a window that is very easy to convince
            //    yourself is working when it is not. A chest that is still open while the player
            //    reads the prize does not depend on catching a frame.
            TreasureChest(lid: 1, scale: 0.62)
                .frame(height: 96)
            Text("YOU WON").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(3)
                .foregroundStyle(Theme.Role.textSecondary)
            Text(grantText(reward))
                .font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.Role.reward)
                .shadow(color: Theme.Role.reward.opacity(0.7), radius: 18)
                .scaleEffect(rewardIn ? 1 : 0.4).opacity(rewardIn ? 1 : 0)
            Text("TAP TO CONTINUE").font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Role.textSecondary).padding(.top, Theme.Space.m)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    // MARK: the colour-shower burst (procedural, deterministic geometry)

    private var burstLayer: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
            var rng = SplitMix64(seed: 0xB0F0_0D5E)
            let maxR = max(size.width, size.height) * 0.75
            let palette: [Color] = [Theme.color(0xFFD23D), Theme.color(0xFF8A2B), Theme.color(0x00F5FF),
                                    Theme.color(0xFF2BD6), Theme.color(0x00FF88), .white]
            // Radial rays.
            for i in 0..<20 {
                let a = Double(i) / 20 * 2 * .pi + rng.unit() * 0.15
                let r = maxR * Double(burstT)
                var p = Path(); p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(p, with: .color(palette[i % palette.count].opacity(0.5)), lineWidth: 2)
            }
            // Confetti dots flying outward.
            for i in 0..<60 {
                let a = rng.unit() * 2 * .pi
                let r = maxR * Double(burstT) * (0.3 + rng.unit() * 0.7)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r + Double(burstT) * 40)
                let d = 4 + rng.unit() * 6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                         with: .color(palette[i % palette.count]))
            }
        }
        .opacity(1 - Double(burstT) * 0.7)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: flow

    private func open() {
        guard ProfileStore.shared.profile.coins >= cost,
              let reward = ProfileStore.shared.openMysteryBox() else { return }
        model.synth.play(.boostStart)   // tension whoosh on open (sound kept in both paths)
        if reduceMotion {
            // No shake / scale / confetti burst — a calm beat then the reward, statically. The lid
            // is shown ALREADY open rather than never opening: Reduce Motion removes the motion,
            // not the fact that the chest opened (`RewardBurstView.run` does exactly this).
            phase = .opening; lid = 1
            revealTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                model.synth.play(.newBestFanfare)
                phase = .revealed(reward); rewardIn = true; glow = 1
            }
            return
        }
        // Swap to the chest on a SHORT transition, and animate the grow/glow separately.
        //
        // These used to share one `.easeIn(duration: 1.0)`. Because `phase` selects which branch of
        // the `Group`'s `switch` is on screen, animating it stretched the `idleContent -> boxView`
        // cross-fade across the entire 1.05 s sequence — so at 730 ms, when the lid hinges, what
        // was mostly on screen was the OUTGOING snapshot of the odds panel's chest, which does not
        // re-render. The hinge was running and could not be seen. Keep the view swap brief and let
        // the slow easeIn do what it was actually for: the anticipation grow.
        withAnimation(.easeOut(duration: 0.2)) { phase = .opening }
        withAnimation(.easeIn(duration: 1.0)) { glow = 1; boxScale = 1.18 }
        withAnimation(.easeInOut(duration: 0.07).repeatCount(14, autoreverses: true)) { wobble = 14 }
        revealTask = Task { @MainActor in
            // The lid has to swing BEFORE the reward replaces the chest on screen, or the opening
            // never gets seen: `.revealed` swaps `boxView` out for `revealContent`.
            //
            // The gap is 320 ms against a 0.42 s spring response, so the lid is most of the way
            // back when the prize arrives — at 170 ms it was still under halfway and the chest
            // vanished mid-swing, which reads as a cut rather than as an opening. The BEAT ITSELF
            // is unchanged: the reveal still lands at 1050 ms exactly as it shipped, because the
            // lid moved earlier rather than the prize moving later.
            try? await Task.sleep(for: .milliseconds(730))
            guard !Task.isCancelled else { return }
            // Settle the shake FIRST, in its own transaction. `wobble` is still carrying the
            // `.repeatCount(14)` animation started above (and a `.repeatForever` before that from
            // the idle beat); folding it into the same `withAnimation` as `lid` lets the repeating
            // curve win the transaction and the hinge never renders at all.
            withAnimation(.easeOut(duration: 0.12)) { wobble = 0 }
            // The SAME spring `RewardBurstView` opens the free chest with, so the two surfaces the
            // owner compared now share the object, the hinge AND the curve.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.52)) { lid = 1 }

            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            model.synth.play(.newBestFanfare)   // reveal fanfare
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { phase = .revealed(reward); rewardIn = true }
            withAnimation(.easeOut(duration: 0.9)) { burstT = 1 }
        }
    }

    private func dismiss() {
        revealTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { onClose() }
    }

    private func grantText(_ g: ConsumableGrant) -> String {
        switch g {
        case let .coins(n):     return "+\(n.formatted()) COINS"
        case let .slowMo(n):    return "+\(n) SLOW-MO"
        case let .speedUp(n):   return "+\(n) SPEED-UP"
        case let .shield(n):    return "+\(n) SHIELD"
        case let .headStart(n): return "+\(n) HEAD START"
        case let .coinSurge(n): return "+\(n) COIN SURGE"
        }
    }
}
