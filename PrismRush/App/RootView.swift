import SwiftUI

/// Phase 1 scaffold root. Proves the app launches and RealityView renders a neon primitive.
/// Phase 3 replaces this with the real menu → game → game-over stack.
struct RootView: View {
    var body: some View {
        ZStack {
            Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255)
                .ignoresSafeArea()

            PlaceholderRealityView()
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("PRISM RUSH")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0, green: 0.96, blue: 1),
                                Color(red: 1, green: 0.17, blue: 0.84),
                                Color(red: 1, green: 0.69, blue: 0.24),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .shadow(color: Color(red: 1, green: 0.17, blue: 0.84).opacity(0.6), radius: 18)

                Text("SCAFFOLD · PHASE 1")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 72)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

#Preview {
    RootView()
}
