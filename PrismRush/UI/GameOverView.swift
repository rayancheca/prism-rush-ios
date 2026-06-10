import SwiftUI

/// Death panel: final score, a NEW BEST flourish, run stats, and a restart button.
struct GameOverView: View {
    let snapshot: GameSnapshot
    let coinsEarned: Int
    let canRestart: Bool
    let canRevive: Bool
    let reviveCost: Int
    let onRevive: () -> Void
    let onRestart: () -> Void
    let onHome: () -> Void

    private var isNewBest: Bool { snapshot.score >= snapshot.best && snapshot.score > 0 }
    private var worldReached: String {
        let ordinal = max(0, Int((snapshot.distance / Tuning.worldLength).rounded(.down)))
        return "World \(ordinal + 1) · \(Theme.worlds[ordinal % 3].name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SHATTERED")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.37))
                .shadow(color: Color(red: 1, green: 0.37, blue: 0.37).opacity(0.5), radius: 18)

            Text("\(snapshot.score)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .monospacedDigit()
                .padding(.top, 8)

            if isNewBest {
                Text("★ NEW BEST ★")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.24))
                    .shadow(color: Color(red: 1, green: 0.82, blue: 0.24), radius: 10)
                    .padding(.top, 2)
            }

            CoinBadge(amount: coinsEarned, prefix: "+")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.24))
                .padding(.top, 10)

            VStack(spacing: 0) {
                statRow("Gems", "\(snapshot.gems)")
                statRow("Reached", worldReached)
                statRow("Coins", "\(ProfileStore.shared.profile.coins)")
                statRow("Best", "\(snapshot.best)")
            }
            .padding(.top, 14)

            if canRevive {
                Button(action: onRevive) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.heart.fill")
                        Text("CONTINUE").tracking(2)
                        Spacer()
                        Text("\(reviveCost)")
                        CoinGlyph(size: 16)
                    }
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Theme.color(0xFFD23D), Theme.color(0xFF9F1C)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(color: Theme.color(0xFFD23D).opacity(0.4), radius: 18)
                }
                .accessibilityIdentifier("continueButton")
                .padding(.top, 18)
            }

            Button(action: onRestart) {
                Text(canRestart ? "RUN AGAIN" : "READY…")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .shadow(color: Theme.color(0x00F5FF).opacity(0.35), radius: 20)
            }
            .disabled(!canRestart)
            .opacity(canRestart ? 1 : 0.55)
            .accessibilityIdentifier("runAgainButton")
            .padding(.top, 22)

            Button(action: onHome) {
                Text("BACK TO MENU")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
            }
            .accessibilityIdentifier("backToMenuButton")
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(30)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45).ignoresSafeArea())
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.system(size: 13, design: .rounded))
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.12)), alignment: .top)
    }
}
