import SwiftUI

/// Menu card for the shared daily challenge: one seeded track per UTC day, same for everyone.
/// Shows a countdown to the next track (UTC midnight), today's best, and a 7-day played calendar.
/// Reads `ProfileStore.shared` live in `body` (G3 — never snapshot an @Observable singleton).
struct DailyChallengeCard: View {
    /// Starts a challenge run. The owner must seed it with `ProfileStore.shared.todaysChallengeSeed()`
    /// and disable revive + checkpoint for the run — see reports/AGENT_meta.md.
    var onPlay: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 10
    @State private var glow = false

    var body: some View {
        let store = ProfileStore.shared
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let best = store.todaysChallengeBest(now: now)
            let playedToday = store.playedChallenge(daysAgo: 0, now: now)
            Button(action: onPlay) {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12, weight: .bold))
                            Text("TODAY'S RUSH")
                                .font(.system(size: captionSize + 1, weight: .heavy, design: .rounded))
                                .tracking(2)
                        }
                        .foregroundStyle(Theme.color(0xFFB13D))
                        Spacer()
                        Text("NEW TRACK \(countdown(now: now))")
                            .font(.system(size: captionSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(best > 0 ? "\(best)" : "—")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(best > 0 ? "TODAY'S BEST" : "NOT PLAYED YET")
                                .font(.system(size: captionSize - 1, weight: .semibold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        weekDots(store: store, now: now)
                    }

                    Text(playedToday ? "RUN IT AGAIN" : "PLAY THE DAILY")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [Theme.color(0xFFB13D), Theme.color(0xFF5E3A)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.color(0xFFB13D).opacity(glow ? 0.55 : 0.3), lineWidth: 1.5)
                )
                .shadow(color: Theme.color(0xFFB13D).opacity(glow ? 0.25 : 0.12), radius: 14)
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier("dailyChallengeCard")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel(best: best, now: now))
            .accessibilityHint("Plays today's shared challenge track")
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    /// 7-day dot calendar — oldest on the left, today (highlighted ring) on the right.
    private func weekDots(store: ProfileStore, now: Date) -> some View {
        HStack(spacing: 5) {
            ForEach((0..<7).reversed(), id: \.self) { daysAgo in
                let played = store.playedChallenge(daysAgo: daysAgo, now: now)
                Circle()
                    .fill(played ? Theme.color(0xFFB13D) : Color.white.opacity(0.16))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(daysAgo == 0 ? 0.8 : 0), lineWidth: 1)
                    )
                    .shadow(color: played ? Theme.color(0xFFB13D).opacity(0.6) : .clear, radius: 3)
            }
        }
        .accessibilityHidden(true)   // folded into the card's combined label
    }

    private func countdown(now: Date) -> String {
        let secs = Int(ProfileStore.secondsUntilUTCMidnight(now: now))
        return String(format: "%d:%02d:%02d", secs / 3600, (secs / 60) % 60, secs % 60)
    }

    private func a11yLabel(best: Int, now: Date) -> String {
        let played = (0..<7).filter { ProfileStore.shared.playedChallenge(daysAgo: $0, now: now) }.count
        let bestPart = best > 0 ? "Today's best \(best)." : "Not played yet today."
        let mins = Int(ProfileStore.secondsUntilUTCMidnight(now: now)) / 60
        return "Today's Rush daily challenge. \(bestPart) Played \(played) of the last 7 days. New track in \(mins / 60) hours \(mins % 60) minutes."
    }
}
