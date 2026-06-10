import SwiftUI

/// Title / attract screen. Tapping anywhere starts a run (handled by the GameView gesture catcher).
struct MenuView: View {
    let best: Int

    private let titleGradient = LinearGradient(
        colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6), Theme.color(0xFFB13D)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 0) {
            Text("A THREE-WORLD HYPERSPEED RUNNER")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(5)
                .foregroundStyle(.white.opacity(0.7))

            Text("PRISM\nRUSH")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(-8)
                .foregroundStyle(titleGradient)
                .shadow(color: Theme.color(0xFF2BD6).opacity(0.5), radius: 26)
                .padding(.top, 8)

            Text("Outrun the void. Keep the streak alive.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 12)

            HStack(spacing: 8) {
                worldChip("01", "Metropolis", 0xFF2BD6)
                worldChip("02", "Caverns", 0x00FFC8)
                worldChip("03", "Sands", 0xFFB13D)
            }
            .padding(.top, 26)

            Text("TAP TO RUN")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.top, 34)
                .opacity(pulse ? 0.55 : 1)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)

            HStack(spacing: 18) {
                hint("⇠⇢", "lanes"); hint("⇡", "jump"); hint("⇣", "slide"); hint("◆", "power-ups")
            }
            .padding(.top, 24)

            HStack(spacing: 18) {
                CoinBadge(amount: ProfileStore.shared.profile.coins)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("BEST \(best)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(.top, 26)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Theme.color(0xFF2BD6).opacity(0.18), .clear],
                           center: .bottom, startRadius: 10, endRadius: 480)
            .ignoresSafeArea()
        )
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }

    @State private var pulse = false

    private func worldChip(_ n: String, _ name: String, _ hex: UInt32) -> some View {
        HStack(spacing: 6) {
            Text(n).foregroundStyle(Theme.color(hex)).fontWeight(.heavy)
            Text(name).foregroundStyle(.white.opacity(0.9))
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .tracking(1)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(symbol).font(.system(size: 14, weight: .bold))
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.75))
    }
}
