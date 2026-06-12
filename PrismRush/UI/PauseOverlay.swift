import SwiftUI

/// Full-screen pause veil shown mid-run: RESUME (also tap the veil) and QUIT TO MENU, plus a
/// small live session line (`2,140m · ◆ 23`) so quitting is an informed choice (uiux §6.9).
struct PauseOverlay: View {
    let onResume: () -> Void
    let onQuit: () -> Void
    /// The paused run's snapshot for the session line. Defaulted so the v1.2 GameView call site
    /// compiles (R13); the line is hidden until wave 5 passes it.
    var snapshot: GameSnapshot? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onResume() }

            VStack(spacing: 16) {
                Text("PAUSED")
                    .scaledFont(34, weight: .black).tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: Theme.color(0x00F5FF).opacity(0.5), radius: 18)

                if let snapshot {
                    HStack(spacing: 6) {
                        Text("\(Int(snapshot.distance))m")
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 1, green: 0.82, blue: 0.24))
                            .frame(width: 8, height: 8)
                            .rotationEffect(.degrees(45))
                        Text("\(snapshot.gems)")
                    }
                    .scaledFont(13, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, -8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("This run so far: \(Int(snapshot.distance)) meters, \(snapshot.gems) gems.")
                }

                Button(action: onResume) {
                    Text("RESUME")
                        .scaledFont(17, weight: .heavy).tracking(2)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(LinearGradient(colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("resumeButton")

                Button(action: onQuit) {
                    Text("QUIT TO MENU")
                        .scaledFont(15, weight: .bold).tracking(1)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quitButton")

                Text("tap anywhere to resume")
                    .scaledFont(11, weight: .semibold)
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 40)
        }
    }
}
