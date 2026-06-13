import SwiftUI

/// A discoverable, standalone reference of every in-run power-up — what it does, how long it lasts,
/// and how you get it. The owner's gap: power-up info used to be buried as the 5th card of How to
/// Play, three taps deep ("nobody is ever gonna find that"). This surfaces it as its own screen,
/// reached from the hub's (now prominent) Settings gear. Presented as a full-screen overlay, mirror
/// of the How-to-Play sub-sheet. Zero binary assets — SF Symbols + role color.
struct PowerUpsView: View {
    var onClose: () -> Void

    private struct PowerUp: Identifiable {
        let id = UUID()
        let hex: UInt32
        let icon: String
        let name: String
        let desc: String
        let timing: String
    }

    /// Durations come from `Tuning`, so the screen can never drift from the actual effect lengths.
    private let powerUps: [PowerUp] = [
        PowerUp(hex: 0x00F5FF, icon: "shield.lefthalf.filled", name: "SHIELD",
                desc: "Absorbs one crash and keeps you running. A badge shows when it's armed.",
                timing: "Held until used"),
        PowerUp(hex: 0xFF2BD6, icon: "dot.radiowaves.left.and.right", name: "MAGNET",
                desc: "Pulls nearby gems straight to you — sweep lanes without weaving.",
                timing: "\(Int(Tuning.magnetDuration))s"),
        PowerUp(hex: 0x00FF88, icon: "2.circle.fill", name: "DOUBLER",
                desc: "Every gem you grab pays double coins. Stack it with a gem run.",
                timing: "\(Int(Tuning.doublerDuration))s"),
        PowerUp(hex: 0x9BF0FF, icon: "hourglass", name: "CHRONO",
                desc: "Slows the world down — wider dodge windows when it gets fast.",
                timing: "\(Int(Tuning.chronoDuration))s"),
        PowerUp(hex: 0xFF8A2B, icon: "arrow.up.circle.fill", name: "SUPER SNEAKERS",
                desc: "Spring-loaded jumps — leap noticeably higher to clear lows and bars with ease.",
                timing: "\(Int(Tuning.superSneakersDuration))s"),
        PowerUp(hex: 0xFFD23D, icon: "bolt.fill", name: "OVERDRIVE",
                desc: "A boost pad rockets you forward through a clear gem river.",
                timing: "Burst"),
    ]

    var body: some View {
        MetaScreenScaffold(title: "Power-Ups", coins: ProfileStore.shared.profile.coins, onClose: onClose) {
            VStack(spacing: Theme.Space.m) {
                Text("Collect these on the track mid-run — they activate the instant you grab them. Here's what each one does.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Role.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                ForEach(powerUps) { pu in row(pu) }

                // The revive is not a track pickup — call it out separately so it's not mistaken for one.
                reviveRow
            }
        }
        .accessibilityIdentifier("powerUpsView")
    }

    private func row(_ pu: PowerUp) -> some View {
        let tint = Theme.color(pu.hex)
        return HStack(spacing: 14) {
            Image(systemName: pu.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.s))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pu.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.Role.textPrimary)
                    Spacer()
                    Text(pu.timing)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tint.opacity(0.14), in: Capsule())
                }
                Text(pu.desc)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Role.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pu.name). \(pu.desc). \(pu.timing).")
    }

    private var reviveRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Role.reward)
                .frame(width: 46, height: 46)
                .background(Theme.Role.reward.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.s))
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTINUE")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.Role.textPrimary)
                Text("Crashed? Spend coins to revive and keep your run going (not on Daily Rush).")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Role.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Role.reward.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue. Crashed? Spend coins to revive mid-run.")
    }
}
