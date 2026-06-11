import SwiftUI

/// Menu retention bar: claim the streak-tiered daily reward, open the free timed chest (every
/// 30 minutes), and jump to the missions board (with an unclaimed-count badge). Reads
/// `ProfileStore` live; the chest countdown ticks via a `TimelineView`.
struct RewardsBar: View {
    let model: GameModel
    /// Opens MissionsView — the owner routes it (`model.open(.missions)` once the sheet case
    /// exists; see reports/AGENT_meta.md).
    var onMissions: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let store = ProfileStore.shared
        HStack(spacing: 10) {
            if store.dailyRewardAvailable() {
                dailyButton(store: store)
            }
            chestButton(store: store)
            missionsButton(store: store)
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
            .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: Theme.color(0xFFD23D).opacity(0.4), radius: 12)
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("dailyRewardButton")
        .accessibilityLabel("Claim daily reward, day \(streak), \(amount) coins")
    }

    private func chestButton(store: ProfileStore) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let ready = store.chestReady(now: context.date)
            let secs = Int(store.secondsUntilChest(now: context.date))
            Button { if ready { model.openChest() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: ready ? "gift.fill" : "gift")
                        .symbolEffect(.pulse, options: .repeating, isActive: ready && !reduceMotion)
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
            .buttonStyle(.neon)
            .disabled(!ready)
            .accessibilityIdentifier("chestButton")
            .accessibilityLabel(ready
                                ? "Free chest ready to open"
                                : "Free chest in \(secs / 60) minutes \(secs % 60) seconds")
        }
    }

    private func missionsButton(store: ProfileStore) -> some View {
        let unclaimed = store.unclaimedCount()
        return Button(action: onMissions) {
            HStack(spacing: 5) {
                Image(systemName: "target")
                Text("MISSIONS")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(unclaimed > 0 ? Theme.color(0xFFD23D).opacity(0.6) : .white.opacity(0.14)))
            .overlay(alignment: .topTrailing) {
                if unclaimed > 0 {
                    Text("\(unclaimed)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(minWidth: 17)
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(Theme.goldGradient, in: Capsule())
                        .shadow(color: Theme.color(0xFFD23D).opacity(0.6), radius: 6)
                        .offset(x: 6, y: -7)
                }
            }
        }
        .buttonStyle(.neon)
        .accessibilityIdentifier("missionsButton")
        .accessibilityLabel(unclaimed > 0
                            ? "Missions — \(unclaimed) rewards ready to claim"
                            : "Missions")
    }

    private func timeString(_ secs: Int) -> String {
        String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
