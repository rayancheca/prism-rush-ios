import SwiftUI

/// In-run heads-up display: score + best on the left, gems + streak multiplier on the right.
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
                }
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
