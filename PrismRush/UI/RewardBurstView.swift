import SwiftUI

/// What a reward moment is showing. A value type, so the view is a pure function of it and the
/// same overlay serves the daily bonus, the free chest, and anything later that pays out coins.
struct RewardBurst: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The login ladder. `streak` is the day just claimed (1-based).
        case daily(streak: Int)
        /// The 30-minute free chest.
        case chest
    }

    var kind: Kind
    var coins: Int
    /// The login ladder, copied in at construction. Carried on the value rather than read from
    /// `ProfileStore` so this stays `Sendable` and the view needs no actor hop to draw it.
    var ladder: [Int] = []

    var title: String {
        switch kind {
        case .daily: return "DAILY BONUS"
        case .chest: return "FREE CHEST"
        }
    }

    /// The line under the title. Names what the player did, not what the system did.
    var subtitle: String {
        switch kind {
        case let .daily(streak):
            return streak >= ladder.count
                ? "DAY \(streak) · TOP TIER"
                : "DAY \(streak) · COME BACK TOMORROW FOR MORE"
        case .chest:
            return "ANOTHER IN 30 MINUTES"
        }
    }
}

/// The celebration. Previously both reward paths showed a 2.4 s text capsule and played one chime;
/// this is the beat that replaces it — scrim, rays, a lid that pops, confetti, a rolling count, and
/// (for the daily) the ladder you are climbing, so the reward reads as progress rather than a number.
///
/// Motion is driven by one `phase` value so every element stays on the same clock, and the whole
/// sequence collapses to a static frame under Reduce Motion.
struct RewardBurstView: View {
    let burst: RewardBurst
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Double = 0        // 0 → 1 across the entrance
    @State private var lid: Double = 0          // 0 closed → 1 popped
    @State private var spin: Double = 0         // ray rotation, degrees
    @State private var shownCoins: Int = 0
    @State private var dismissable = false

    private static let shards: [Shard] = Shard.fan(count: 34)

    var body: some View {
        ZStack {
            // This is a modal moment, so the scrim is near-opaque. At 0.78 the gold Claim card and
            // the PLAY gradient punched through and collided with this overlay's own type; at 0.94
            // PLAY still read through "TAP TO CONTINUE". Clarity beats keeping a sense of place.
            Color.black.opacity(0.975 * phase)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    rays
                    confetti
                    chest
                }
                .frame(width: 240, height: 240)

                Text(burst.title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(3.4)
                    .foregroundStyle(Theme.Role.textSecondary)
                    .padding(.top, 14)

                coinLine
                    .padding(.top, 6)

                if case let .daily(streak) = burst.kind, !burst.ladder.isEmpty {
                    ladder(streak: streak).padding(.top, 20)
                }

                Text(burst.subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)

                Text("TAP TO CONTINUE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .padding(.top, 30)
                    .opacity(dismissable ? 1 : 0)
            }
            .opacity(phase)
            .scaleEffect(0.88 + 0.12 * phase)
        }
        .contentShape(Rectangle())
        .onTapGesture { if dismissable { onDismiss() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(burst.title). \(burst.coins) coins. \(burst.subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if dismissable { onDismiss() } }
        .task { await run() }
    }

    // MARK: - Pieces

    /// A slow fan of light behind the chest. Kept very low contrast so the chest stays the subject.
    private var rays: some View {
        AngularGradient(
            gradient: Gradient(stops: (0..<12).map { i in
                .init(color: i.isMultiple(of: 2)
                        ? Theme.Role.reward.opacity(0.20) : .clear,
                      location: Double(i) / 12)
            }),
            center: .center
        )
        .mask(Circle().fill(RadialGradient(colors: [.white, .white.opacity(0.5), .clear],
                                           center: .center, startRadius: 6, endRadius: 118)))
        .rotationEffect(.degrees(spin))
        .opacity(phase)
    }

    private var confetti: some View {
        Canvas { ctx, size in
            guard lid > 0 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2 + 8)
            for s in Self.shards {
                let t = min(1, lid / s.life)
                guard t > 0 else { continue }
                let dist = s.speed * 132 * easeOut(t)
                let x = c.x + cos(s.angle) * dist
                let y = c.y + sin(s.angle) * dist + 96 * t * t   // gravity
                let side = s.size * (1 - 0.35 * t)
                var r = Path()
                r.addRect(CGRect(x: -side / 2, y: -side / 2, width: side, height: side * 1.7))
                let placed = r.applying(
                    CGAffineTransform(rotationAngle: s.spin * t * 7)
                        .concatenating(CGAffineTransform(translationX: x, y: y)))
                ctx.fill(placed, with: .color(s.color.opacity(1 - t * t)))
            }
        }
        .allowsHitTesting(false)
    }

    /// A real chest: body, banded lid that hinges open, keyhole, and the light that escapes it.
    private var chest: some View {
        ZStack {
            // The glow that leaks out once the lid is up.
            Circle()
                .fill(RadialGradient(colors: [Theme.Role.reward.opacity(0.55 * lid), .clear],
                                     center: .center, startRadius: 2, endRadius: 92))
                .frame(width: 184, height: 184)
                .offset(y: -6)

            VStack(spacing: 0) {
                // Lid
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 2,
                                       bottomTrailingRadius: 2, topTrailingRadius: 12)
                    .fill(LinearGradient(colors: [Theme.color(0xFFE27A), Theme.color(0xE0912A)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .center) {
                        Rectangle().fill(Theme.color(0x7A4A12).opacity(0.55))
                            .frame(width: 18)
                    }
                    .frame(width: 128, height: 40)
                    // Hinged at the joint with the body, so it swings back off the chest instead
                    // of floating detached above it.
                    .rotation3DEffect(.degrees(-118 * lid), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.55)

                // Body
                UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 10,
                                       bottomTrailingRadius: 10, topTrailingRadius: 2)
                    .fill(LinearGradient(colors: [Theme.color(0xD98A26), Theme.color(0x8A4F13)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .center) {
                        Rectangle().fill(Theme.color(0x7A4A12).opacity(0.55))
                            .frame(width: 18)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.color(0xFFF0B8))
                            .frame(width: 22, height: 16)
                            .offset(y: -4)
                            .opacity(1 - lid)          // the clasp, hidden once open
                    }
                    .frame(width: 128, height: 56)
            }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .scaleEffect(0.72 + 0.28 * phase)
        }
    }

    private var coinLine: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.goldGradient)
                .overlay(Circle().stroke(Theme.color(0xFFF0B8).opacity(0.9), lineWidth: 1.5))
                .frame(width: 26, height: 26)
            Text("+\(shownCoins)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.goldGradient)
        }
        .shadow(color: Theme.Role.reward.opacity(0.45), radius: 18)
    }

    /// The login ladder — seven rungs, so a player can see what tomorrow is worth.
    private func ladder(streak: Int) -> some View {
        let tiers = burst.ladder
        return HStack(spacing: 7) {
            ForEach(Array(tiers.enumerated()), id: \.offset) { i, amount in
                let claimed = i < streak
                let isToday = i == streak - 1
                VStack(spacing: 5) {
                    Circle()
                        .fill(claimed ? AnyShapeStyle(Theme.goldGradient)
                                      : AnyShapeStyle(Theme.Role.surfaceHi))
                        .frame(width: isToday ? 13 : 9, height: isToday ? 13 : 9)
                        .overlay(
                            Circle().stroke(Theme.Role.reward, lineWidth: isToday ? 2 : 0)
                                .scaleEffect(1.7).opacity(isToday ? 0.55 : 0)
                        )
                    Text("\(amount)")
                        .font(.system(size: 8, weight: isToday ? .black : .semibold,
                                      design: .rounded))
                        .foregroundStyle(claimed ? Theme.Role.reward : Theme.Role.textTertiary)
                }
            }
        }
    }

    // MARK: - Timeline

    private func run() async {
        guard !reduceMotion else {
            phase = 1; lid = 1; shownCoins = burst.coins; dismissable = true
            return
        }

        withAnimation(.easeOut(duration: 0.26)) { phase = 1 }
        withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = 360 }

        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.52)) { lid = 1 }

        // Roll the count so the number is earned rather than announced.
        try? await Task.sleep(for: .milliseconds(140))
        let steps = 26
        for i in 1...steps {
            let t = easeOut(Double(i) / Double(steps))
            shownCoins = Int((Double(burst.coins) * t).rounded())
            try? await Task.sleep(for: .milliseconds(26))
        }
        shownCoins = burst.coins

        withAnimation(.easeIn(duration: 0.25)) { dismissable = true }
    }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
}

// MARK: - Confetti shards

/// One piece of confetti. Precomputed from a fixed sequence so a reward looks organic but is
/// identical every time — no `Double.random` reaching for a global generator mid-render.
private struct Shard {
    var angle: Double
    var speed: Double
    var size: Double
    var spin: Double
    var life: Double
    var color: Color

    static func fan(count: Int) -> [Shard] {
        let palette = [0xFFD23D, 0x00F5FF, 0xFF2BD6, 0xFFF0B8, 0x38E8A0].map { Theme.color(UInt32($0)) }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func unit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        return (0..<count).map { i in
            // Bias upward: a chest throws its contents up, not sideways.
            let spread = (unit() - 0.5) * 2.5
            return Shard(angle: -.pi / 2 + spread,
                         speed: 0.45 + unit() * 0.75,
                         size: 5 + unit() * 5,
                         spin: (unit() - 0.5) * 2,
                         life: 0.55 + unit() * 0.45,
                         color: palette[i % palette.count])
        }
    }
}
