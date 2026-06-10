import SwiftUI

/// Menu retention bar: claim the streak-tiered daily reward, and open the free timed chest (every
/// 30 minutes). Reads `ProfileStore` live; the chest countdown ticks via a `TimelineView`.
struct RewardsBar: View {
    let model: GameModel

    var body: some View {
        let store = ProfileStore.shared
        HStack(spacing: 10) {
            if store.dailyRewardAvailable() {
                dailyButton(store: store)
            }
            chestButton(store: store)
        }
    }

    private func dailyButton(store: ProfileStore) -> some View {
        let streak = store.pendingDailyStreak()
        let amount = store.dailyReward(forStreak: streak)
        return Button { model.claimDailyReward() } label: {
            VStack(spacing: 2) {
                Text("DAILY · DAY \(streak)").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                HStack(spacing: 4) {
                    Text("CLAIM +\(amount)").font(.system(size: 13, weight: .heavy, design: .rounded))
                    CoinGlyph(size: 13)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(LinearGradient(colors: [Theme.color(0xFFD23D), Theme.color(0xFF9F1C)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: Theme.color(0xFFD23D).opacity(0.4), radius: 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dailyRewardButton")
    }

    private func chestButton(store: ProfileStore) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let ready = store.chestReady(now: context.date)
            let secs = Int(store.secondsUntilChest(now: context.date))
            Button { if ready { model.openChest() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: ready ? "gift.fill" : "gift")
                    Text(ready ? "FREE CHEST" : timeString(secs))
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(ready ? .black : .white.opacity(0.85))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(ready
                            ? AnyShapeStyle(LinearGradient(colors: [Theme.color(0x00F5FF), Theme.color(0x7B61FF)],
                                                           startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(.ultraThinMaterial),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(ready ? 0 : 0.14)))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityIdentifier("chestButton")
        }
    }

    private func timeString(_ secs: Int) -> String {
        String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
