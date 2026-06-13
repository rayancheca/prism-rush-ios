import SwiftUI

/// The reveal that fires when a coin-spend power-up pack is bought (owner S1 — "a real open/pay/
/// reveal workflow + animations", today it was only a sound). A brief celebratory burst: an
/// expanding ring + radiating sparks in the pack's tint, the icon springing in, and the grant line
/// ("+3 SLOW-MO CHARGES") — then it auto-dismisses. Lighter than the full Mystery Box sequence
/// (that one is the gacha centrepiece); this is the satisfying "got it" beat for a known purchase.
/// Reduce Motion shows the same reveal as a static frame (no expansion), never a missing one.
struct PackRewardBurst: View {
    let item: CoinSpendItem
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0       // 0→1 ring/spark expansion
    @State private var pop: CGFloat = 0         // 0→1 icon spring-in
    @State private var dismissTask: Task<Void, Never>?

    private var tint: Color { Theme.color(item.hex) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { finish() }

            ZStack {
                // Expanding ring + soft halo (static at phase 0 under Reduce Motion).
                Circle()
                    .stroke(tint.opacity(0.9 * Double(1 - phase)), lineWidth: 4)
                    .frame(width: 120, height: 120)
                    .scaleEffect(0.4 + phase * 1.9)
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.35 * Double(1 - phase * 0.8)), .clear],
                                         center: .center, startRadius: 4, endRadius: 110))
                    .frame(width: 220, height: 220)

                // Radiating sparks.
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) / 12 * 2 * .pi
                    Capsule()
                        .fill(tint.opacity(0.9 * Double(1 - phase)))
                        .frame(width: 4, height: 16 + 18 * phase)
                        .offset(y: -(54 + phase * 54))
                        .rotationEffect(.radians(angle))
                }

                // The icon medallion, springing in.
                ZStack {
                    Circle()
                        .fill(Theme.Role.surfaceHi)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
                        .frame(width: 92, height: 92)
                        .shadow(color: tint.opacity(0.6), radius: 18)
                    Image(systemName: item.icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(tint)
                }
                .scaleEffect(0.3 + pop * 0.7)
                .opacity(Double(pop))
            }
            .frame(width: 240, height: 240)

            // Grant copy below the burst.
            VStack(spacing: 6) {
                Spacer()
                Text(item.title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(tint)
                Text(item.blurb)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Role.textPrimary)
                Text("ADDED TO YOUR LOADOUT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.Role.textTertiary)
                    .padding(.top, 2)
                Spacer().frame(height: 120)
            }
            .opacity(Double(pop))
            .padding(.horizontal, Theme.Space.xl)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title) purchased. \(item.blurb). Added to your loadout.")
        .accessibilityAddTraits(.isModal)
        .onAppear { animate() }
        .onDisappear { dismissTask?.cancel() }
    }

    private func animate() {
        if reduceMotion {
            phase = 0; pop = 1                          // static reveal — icon + copy, no expansion
        } else {
            withAnimation(.easeOut(duration: 0.65)) { phase = 1 }
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { pop = 1 }
        }
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        dismissTask?.cancel()
        onDone()
    }
}
