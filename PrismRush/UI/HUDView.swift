import SwiftUI

/// In-run heads-up display: score + best on the left; gems, streak multiplier and live power-up
/// timers (magnet / coin doubler / chrono slow-mo) on the right.
/// Reads the observed `core.snapshot`, so it refreshes as the run progresses.
struct HUDView: View {
    let core: GameCore

    var body: some View {
        let snap = core.snapshot
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snap.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .shadow(color: .white.opacity(0.35), radius: 12)
                    Text("BEST \(snap.best)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Starts below the mute/pause cluster anchored in the top-trailing corner.
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 1, green: 0.82, blue: 0.24))
                            .frame(width: 11, height: 11)
                            .rotationEffect(.degrees(45))
                            .shadow(color: Color(red: 1, green: 0.82, blue: 0.24), radius: 6)
                        Text("\(snap.gems)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .pillBackground()

                    if snap.mult > 1 {
                        Text("×\(snap.mult)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(red: 1, green: 0.82, blue: 0.24))
                                    .shadow(color: Color(red: 1, green: 0.82, blue: 0.24).opacity(0.6), radius: 10)
                            )
                            .transition(.scale)
                            .id(snap.mult)
                    }

                    if snap.magnetRemaining > 0 {
                        powerChip("MAG", snap.magnetRemaining, Theme.color(0x00F5FF))
                    }
                    if snap.doublerRemaining > 0 {
                        powerChip("×2", snap.doublerRemaining, Theme.color(0x00FF88))
                    }
                    if snap.chronoRemaining > 0 {
                        powerChip("SLOW", snap.chronoRemaining, Theme.color(0x9BF0FF))
                    }
                }
                .padding(.top, 38)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .animation(.spring(duration: 0.25), value: snap.mult)
        .opacity(snap.mode == .play ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Power-up countdown chip — same glassy pill chrome as the gems counter.
    private func powerChip(_ label: String, _ remaining: Double, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color, radius: 5)
            Text("\(label) \(Int(remaining.rounded(.up)))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .pillBackground()
        .transition(.scale)
    }
}

/// Glassy pill chrome shared by HUD chips.
private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.14)))
    }
}

extension View {
    func pillBackground() -> some View { modifier(PillBackground()) }
}
