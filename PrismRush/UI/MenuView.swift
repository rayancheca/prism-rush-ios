import SwiftUI

/// The menu hub: title, a big PLAY button, and entries into Characters / Shop / Worlds.
struct MenuView: View {
    let best: Int
    let coins: Int
    let onPlay: () -> Void
    let onCharacters: () -> Void
    let onShop: () -> Void
    let onLevels: () -> Void
    let onProfile: () -> Void

    @State private var pulse = false

    private let titleGradient = LinearGradient(
        colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6), Theme.color(0xFFB13D)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onProfile) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Spacer()
                CoinBadge(amount: coins)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            }

            Spacer()

            Text("A THREE-WORLD HYPERSPEED RUNNER")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(4).foregroundStyle(.white.opacity(0.7))
            Text("PRISM\nRUSH")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .multilineTextAlignment(.center).lineSpacing(-8)
                .foregroundStyle(titleGradient)
                .shadow(color: Theme.color(0xFF2BD6).opacity(0.5), radius: 26)
                .padding(.top, 8)
            Text("Outrun the void. Keep the streak alive.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85)).padding(.top, 12)

            HStack(spacing: 8) {
                worldChip("01", "Metropolis", 0xFF2BD6)
                worldChip("02", "Caverns", 0x00FFC8)
                worldChip("03", "Sands", 0xFFB13D)
            }
            .padding(.top, 22)

            Spacer()

            Button(action: onPlay) {
                Text("PLAY")
                    .font(.system(size: 24, weight: .black, design: .rounded)).tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(titleGradient, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Theme.color(0xFF2BD6).opacity(0.45), radius: 24)
                    .scaleEffect(pulse ? 1 : 0.98)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            HStack(spacing: 12) {
                hubButton("person.fill", "Characters", action: onCharacters)
                hubButton("cart.fill", "Shop", action: onShop)
                hubButton("map.fill", "Worlds", action: onLevels)
            }
            .padding(.top, 14)

            Text("BEST \(best)")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).tracking(2)
                .foregroundStyle(.white.opacity(0.75)).padding(.top, 18)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Theme.color(0xFF2BD6).opacity(0.16), .clear],
                           center: .bottom, startRadius: 10, endRadius: 520).ignoresSafeArea()
        )
        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private func worldChip(_ n: String, _ name: String, _ hex: UInt32) -> some View {
        HStack(spacing: 6) {
            Text(n).foregroundStyle(Theme.color(hex)).fontWeight(.heavy)
            Text(name).foregroundStyle(.white.opacity(0.9))
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
    }

    private func hubButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
