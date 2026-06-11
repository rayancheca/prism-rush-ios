import SwiftUI

/// Checkpoint / world select: start a run from any world you've reached. The world sets the
/// difficulty & palette; score and coins still count from zero.
struct LevelSelectView: View {
    let model: GameModel

    var body: some View {
        let store = ProfileStore.shared
        let profile = store.profile
        // One source of truth for "how deep can you start": ProfileStore.unlockedWorldCount
        // (maxWorldReached + 1, capped at ProfileStore.maxStartWorlds).
        let count = store.unlockedWorldCount

        MetaScreenScaffold(title: "Worlds", coins: profile.coins, onClose: { model.closeSheet() }) {
            VStack(spacing: 16) {
                Text("Start from any checkpoint you've reached. Deeper = faster & harder.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 8)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(0..<count, id: \.self) { world in
                        WorldCard(world: world, isFurthest: world == count - 1) {
                            model.startRun(fromWorld: world)
                        }
                    }
                }
            }
        }
    }
}

private struct WorldCard: View {
    let world: Int
    let isFurthest: Bool
    let action: () -> Void

    private var palette: WorldPalette { Theme.worlds[world % 3] }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("WORLD \(world + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(world + 1)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.color(palette.accent2))
                    .shadow(color: Theme.color(palette.accent2).opacity(0.6), radius: 14)
                Text(palette.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(world == 0 ? "START" : "\(Int(Double(world) * Tuning.worldLength))m in")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isFurthest ? Theme.color(palette.accent2) : .white.opacity(0.12),
                                  lineWidth: isFurthest ? 2.5 : 1)
            )
        }
        .buttonStyle(.neon)
        .accessibilityLabel("World \(world + 1), \(palette.name)\(world == 0 ? ", the start" : ", \(Int(Double(world) * Tuning.worldLength)) meters in")")
        .accessibilityHint("Starts a run from this checkpoint")
    }
}
