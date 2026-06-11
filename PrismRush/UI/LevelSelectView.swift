import SwiftUI

/// Worlds tab, alive (uiux §3): a big preview header for the furthest checkpoint (PLAY FROM HERE),
/// a card grid of live `WorldPreviewCanvas` vignettes with per-world bests, and the next LOCKED
/// world made visible with its distance requirement (the ladder you're climbing). All profile
/// state is read from `ProfileStore.shared` at point of use (G3 — no snapshot).
struct LevelSelectView: View {
    let model: GameModel

    var body: some View {
        // One source of truth for "how deep can you start": ProfileStore.unlockedWorldCount
        // (maxWorldReached + 1, capped at ProfileStore.maxStartWorlds).
        let count = ProfileStore.shared.unlockedWorldCount
        let furthest = count - 1

        MetaScreenScaffold(title: "Worlds", coins: ProfileStore.shared.profile.coins,
                           onClose: { model.closeSheet() }, onCoins: { model.open(.shop) }) {
            VStack(spacing: Theme.Space.m) {
                previewHeader(furthest: furthest)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Space.m)],
                          spacing: Theme.Space.m) {
                    ForEach(0..<count, id: \.self) { world in
                        WorldCard(world: world,
                                  isFurthest: world == furthest,
                                  best: ProfileStore.shared.profile.bestDistanceByWorld[world] ?? 0) {
                            model.startRun(fromWorld: world)
                        }
                    }
                    // The next rung of the ladder stays visible — locked, with its requirement
                    // (distance is the only key; no purchase path).
                    if count < ProfileStore.maxStartWorlds {
                        LockedWorldCard(world: count)
                    }
                }
            }
        }
    }

    /// Full-width 200 pt header: the furthest world's hero vignette + PLAY FROM HERE. The whole
    /// header is one tap target → `startRun(fromWorld: furthest)`.
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
}

/// One unlocked world: live vignette on top, facts below (uiux §3.2). The furthest card wears the
/// only world-colored stroke allowed in meta — the preview already speaks that palette.
private struct WorldCard: View {
    let world: Int
    let isFurthest: Bool
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
            .shadow(color: isFurthest ? Theme.color(palette.accent2).opacity(0.35) : .clear, radius: 12)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldCard_\(world + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World \(world + 1), \(palette.name)."
                            + (best > 0 ? " Your best here: \(Int(best)) meters." : " Untouched.")
                            + (world == 0 ? " The start." : " Checkpoint \(checkpointM) meters in."))
        .accessibilityHint("Starts a run from this checkpoint.")
    }
}

/// The next locked world: desaturated vignette under a scrim, lock glyph, requirement line.
/// Tap = shake (no purchase path — distance is the only key, uiux §3.2). Reduce Motion swaps
/// the shake for a brief lock-tinted border flash (same denial language as CharacterSelect).
private struct LockedWorldCard: View {
    let world: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deniedShakes: CGFloat = 0
    @State private var deniedFlash = false

    private var palette: WorldPalette { Theme.worlds[world % 3] }
    private var requiredM: Int { Int(Double(world) * Tuning.worldLength) }

    var body: some View {
        Button {
            if reduceMotion {
                deniedFlash = true            // hold, then clear (CharacterSelect.deny() pattern)
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    deniedFlash = false
                }
            } else {
                withAnimation(.linear(duration: 0.3)) { deniedShakes += 1 }
            }
        } label: {
            VStack(spacing: 0) {
                WorldPreviewCanvas(palette: palette, worldIndex: world, size: .card)
                    .frame(height: 96)
                    .saturation(0.15)
                    .overlay(Color.black.opacity(0.45))
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.Role.lock)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "WORLD %02d", world + 1))
                        .typeScale(.micro)
                        .foregroundStyle(Theme.Role.textTertiary)
                    Text(palette.name)
                        .typeScale(.heading)
                        .foregroundStyle(Theme.Role.lock)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("REACH \(requiredM.formatted())m TO UNLOCK")
                        .typeScale(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Role.lock)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m - 4)
            }
            .background(Theme.Role.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(deniedFlash ? Theme.Role.lock : Theme.Role.hairline,
                              lineWidth: deniedFlash ? 2 : 1))
            .modifier(ShakeEffect(trigger: deniedShakes))
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("worldCardLocked_\(world + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World \(world + 1), \(palette.name). Locked.")
        .accessibilityHint("Reach \(requiredM) meters to unlock.")
    }
}
