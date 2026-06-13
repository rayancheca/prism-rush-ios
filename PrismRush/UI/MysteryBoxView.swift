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

    private var boxView: some View {
        Image(systemName: "gift.fill")
            .font(.system(size: 112, weight: .bold))
            .foregroundStyle(Theme.Role.reward)
            .shadow(color: Theme.Role.reward.opacity(glow), radius: 34)
            .rotationEffect(.degrees(wobble))
            .scaleEffect(boxScale)
    }

    // MARK: idle — odds + OPEN

    private var idleContent: some View {
        let afford = ProfileStore.shared.profile.coins >= cost
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
                .opacity(afford ? 1 : 0.5)
            }
            .buttonStyle(.neon)
            .disabled(!afford)
            .accessibilityIdentifier("mysteryBoxOpenButton")
            Button("CLOSE") { dismiss() }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Role.textSecondary)
        }
    }

    // MARK: reveal

    private func revealContent(_ reward: ConsumableGrant) -> some View {
        VStack(spacing: Theme.Space.m) {
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
            // No shake / scale / confetti burst — a calm beat then the reward, statically.
            phase = .opening
            revealTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                model.synth.play(.newBestFanfare)
                phase = .revealed(reward); rewardIn = true; glow = 1
            }
            return
        }
        withAnimation(.easeIn(duration: 1.0)) { phase = .opening; glow = 1; boxScale = 1.18 }
        withAnimation(.easeInOut(duration: 0.07).repeatCount(14, autoreverses: true)) { wobble = 14 }
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1050))
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
