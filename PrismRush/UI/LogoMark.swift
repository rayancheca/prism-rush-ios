import SwiftUI

/// Procedural "PRISM RUSH" wordmark — the game's logo, built entirely in code (no binary assets).
/// Three stacked letter rows make the lockup: a cyan and a magenta ghost copy offset a hair to
/// either side (chromatic fringe), then the real row filled with the shared action gradient and
/// wrapped in a soft two-tone neon glow. Letters ride a subtle baseline wave (per-letter rhythm,
/// not tracked-out type) and the whole lockup leans forward for speed. Static under Reduce
/// Motion; otherwise a faint highlight sweeps the letterforms every few seconds via a ≤20 fps
/// TimelineView — no repeatForever animations (the menu's pulse ban stands).
struct LogoMark: View {
    /// Letter point size; every other measurement in the lockup is derived from it.
    var size: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One shimmer sweep every `shimmerPeriod` s; the band crosses in `shimmerSweep` s.
    private static let shimmerPeriod = 7.0
    private static let shimmerSweep = 1.4

    var body: some View {
        Group {
            if reduceMotion {
                lockup(shimmer: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    lockup(shimmer: Self.shimmerPhase(at: context.date))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prism Rush")
    }

    // MARK: layers

    /// How far the cyan/magenta ghosts peek out from behind the gradient fill.
    private var fringe: CGFloat { max(1, size * 0.05) }

    private func lockup(shimmer: CGFloat?) -> some View {
        ZStack {
            // Chromatic fringe: pure-hue ghosts a hair to either side of the fill.
            letterRow().foregroundStyle(Theme.color(0x00F5FF)).offset(x: -fringe)
            letterRow().foregroundStyle(Theme.color(0xFF2BD6)).offset(x: fringe)
            letterRow()
                .foregroundStyle(Theme.actionGradient)
                .overlay { if let shimmer { shimmerBand(phase: shimmer) } }
        }
        .modifier(Slant(amount: 0.10))
        .shadow(color: Theme.color(0x00F5FF).opacity(0.35), radius: size * 0.45)
        .shadow(color: Theme.color(0xFF2BD6).opacity(0.30), radius: size * 0.85)
    }

    /// The letters, one `Text` each so every glyph can ride the baseline wave.
    private func letterRow() -> some View {
        HStack(spacing: size * 0.10) {
            ForEach(Array("PRISM RUSH".enumerated()), id: \.offset) { index, letter in
                if letter == " " {
                    Color.clear.frame(width: size * 0.16, height: 1)
                } else {
                    Text(String(letter))
                        .font(.system(size: size, weight: .black, design: .rounded))
                        .offset(y: wave(index))
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// ±4% baseline wave so the lockup reads hand-set rather than typed.
    private func wave(_ index: Int) -> CGFloat {
        size * 0.04 * CGFloat(sin(Double(index) * 0.8 + 0.6))
    }

    /// A soft white band sweeping left→right, masked to the letterforms only.
    private func shimmerBand(phase: CGFloat) -> some View {
        GeometryReader { geo in
            let band = geo.size.width * 0.28
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: band, height: geo.size.height * 2)
                .rotationEffect(.degrees(14))
                .offset(x: (geo.size.width + band) * phase - band, y: -geo.size.height / 2)
        }
        .mask(letterRow())
        .allowsHitTesting(false)
    }

    /// `nil` between sweeps; 0…1 while the band crosses. Derived from the wall clock so every
    /// LogoMark on screen shimmers in sync without storing animation state.
    private static func shimmerPhase(at date: Date) -> CGFloat? {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: shimmerPeriod)
        return t < shimmerSweep ? CGFloat(t / shimmerSweep) : nil
    }
}

/// Forward lean for the wordmark: a horizontal skew anchored at the vertical midline so the
/// lockup doesn't drift when applied (same `GeometryEffect` approach as `ShakeEffect`).
private struct Slant: GeometryEffect {
    var amount: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: -amount, d: 1,
                                              tx: amount * size.height / 2, ty: 0))
    }
}
