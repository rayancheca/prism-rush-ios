import SwiftUI

/// Four swipeable tutorial cards (controls / scoring / rings & flow / power-ups), built entirely
/// from shapes and SF Symbols — no assets. Shown from Settings, and before the first PLAY when
/// `profile.totalRuns == 0`. The RINGS & FLOW card teaches the three v1.3 mechanics.
struct HowToPlayView: View {
    let onClose: () -> Void
    /// Label on the final card's dismiss button ("GOT IT" from Settings, "LET'S GO" pre-first-run).
    var doneLabel: String = "GOT IT"

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header: the wordmark centred (its gradient is the same family as the NEXT button),
            // close button trailing.
            ZStack {
                LogoMark(size: 15)
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                    }
                    .buttonStyle(.neon)
                    .accessibilityIdentifier("howToPlayClose")
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            TabView(selection: $page) {
                controlsCard.tag(0)
                scoringCard.tag(1)
                flowCard.tag(2)
                powerUpsCard.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 { withAnimation { page += 1 } } else { onClose() }
            } label: {
                Text(page < 3 ? "NEXT" : doneLabel)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.color(0x00F5FF).opacity(0.35), radius: 18)
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("howToPlayNext")
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255)
                RadialGradient(colors: [Theme.color(0x00F5FF).opacity(0.12), .clear],
                               center: .top, startRadius: 10, endRadius: 520)
            }.ignoresSafeArea()
        )
    }

    // MARK: card 1 — controls

    private var controlsCard: some View {
        card(title: "CONTROLS", accent: 0x00F5FF) {
            // Three lanes with the runner in the middle.
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { lane in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.color(0xFF2BD6).opacity(lane == 1 ? 0.35 : 0.14))
                        .frame(width: 44, height: 110)
                        .overlay {
                            if lane == 1 {
                                Circle().fill(Theme.color(0x00F5FF))
                                    .frame(width: 22, height: 22)
                                    .shadow(color: Theme.color(0x00F5FF), radius: 8)
                            }
                        }
                }
            }
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            instructionRow("arrow.left.and.right", "SWIPE LEFT / RIGHT", "switch lanes")
            instructionRow("arrow.up", "SWIPE UP — OR TAP", "jump the low walls")
            instructionRow("arrow.down", "SWIPE DOWN", "slide under the bars")
        }
    }

    // MARK: card 2 — scoring

    private var scoringCard: some View {
        card(title: "SCORING", accent: 0xFFD23D) {
            // A gem: rotated square with a glow.
            Rectangle()
                .fill(LinearGradient(colors: [Theme.color(0xFFD23D), Theme.color(0xFF9F1C)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(45))
                .shadow(color: Theme.color(0xFFD23D).opacity(0.7), radius: 12)
                .padding(.bottom, 14)
                .accessibilityHidden(true)

            Text("Chain gems without missing to climb the streak ladder.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { mult in
                    Text("×\(mult)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(mult == 5 ? .black : .white.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            mult == 5
                                ? AnyShapeStyle(Theme.goldGradient)
                                : AnyShapeStyle(.white.opacity(0.06 + Double(mult) * 0.04)),
                            in: Capsule()
                        )
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Streak multiplier ladder, times 1 up to times 5")

            instructionRow("scope", "CLOSE", "shave past an obstacle for bonus points")
            instructionRow("water.waves", "SLICK", "slide under a bar at the last instant")
        }
    }

    // MARK: card 3 — rings, pads & flow (the v1.3 mechanics)

    private var flowCard: some View {
        card(title: "RINGS & FLOW", accent: 0xB26BFF) {
            // A prism ring: a glowing torus seen edge-on.
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [Theme.color(0x00F5FF), Theme.color(0xB26BFF),
                                             Theme.color(0x00F5FF)], center: .center),
                    lineWidth: 7)
                .frame(width: 56, height: 56)
                .shadow(color: Theme.color(0xB26BFF).opacity(0.7), radius: 12)
                .padding(.bottom, 14)
                .accessibilityHidden(true)

            instructionRow("circle.dashed", "PRISM RINGS", "dive through for bonus coins — dead-centre pays PERFECT")
            instructionRow("bolt.fill", "OVERDRIVE PADS", "hit the glowing pad for a one-second speed surge")
            instructionRow("wind", "FLOW SURGE", "chain 3 near-misses to detonate a gem fountain")
        }
    }

    // MARK: card 4 — power-ups

    private var powerUpsCard: some View {
        card(title: "POWER-UPS", accent: 0x00FF88) {
            powerRow(0x00F5FF, "shield.fill", "SHIELD", "absorbs one hit")
            powerRow(0xFF2BD6, "dot.radiowaves.left.and.right", "MAGNET", "pulls gems to you")
            powerRow(0x00FF88, "2.circle.fill", "DOUBLER", "gems pay double coins")
            powerRow(0x9BF0FF, "hourglass", "CHRONO", "slows time — wider dodge windows")

            Divider().overlay(.white.opacity(0.15)).padding(.vertical, 8)

            instructionRow("bolt.heart.fill", "CONTINUE", "shattered? spend coins to revive mid-run")
        }
    }

    // MARK: shared chrome

    private func card(title: String, accent: UInt32, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.color(accent))
                .shadow(color: Theme.color(accent).opacity(0.5), radius: 12)
                .padding(.bottom, 6)
            content()
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)))
        .padding(24)
    }

    private func instructionRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func powerRow(_ hex: UInt32, _ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.color(hex))
                .frame(width: 34, height: 34)
                .background(Theme.color(hex).opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(Theme.color(hex).opacity(0.5)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.color(hex))
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
