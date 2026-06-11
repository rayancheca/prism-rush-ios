import SwiftUI

/// Full-screen pause veil shown mid-run: RESUME (also tap the veil) and QUIT TO MENU.
struct PauseOverlay: View {
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onResume() }

            VStack(spacing: 16) {
                Text("PAUSED")
                    .font(.system(size: 34, weight: .black, design: .rounded)).tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: Theme.color(0x00F5FF).opacity(0.5), radius: 18)

                Button(action: onResume) {
                    Text("RESUME")
                        .font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(2)
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
                        .font(.system(size: 15, weight: .bold, design: .rounded)).tracking(1)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quitButton")

                Text("tap anywhere to resume")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 40)
        }
    }
}
