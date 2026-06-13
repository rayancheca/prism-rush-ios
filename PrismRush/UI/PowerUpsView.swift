import SwiftUI

/// A discoverable, standalone reference of every power-up — what it does, how long it lasts, and how
/// you get it. The owner's gap: power-up info used to be buried as the 5th card of How to Play, three
/// taps deep ("nobody is ever gonna find that"), and the v1.6 deploys/loadout were nowhere. This
/// surfaces all of it as its own screen, reached from the hub's Settings gear. Full-screen overlay,
/// mirror of the How-to-Play sub-sheet. Icons are the bespoke `PowerUpGlyph`s (owner P3 — no SF
/// Symbols), so the catalog, the HUD, and the deploy buttons all show the same identity. Zero assets.
struct PowerUpsView: View {
    var onClose: () -> Void

    private struct Item: Identifiable {
        let id = UUID()
        let kind: PowerUpKind
        let name: String
        let desc: String
        let timing: String
    }

    /// Track pickups — collected mid-run, active the instant you grab them. Durations come from
    /// `Tuning` so the screen can never drift from the real effect lengths.
    private let pickups: [Item] = [
        Item(kind: .shield, name: "SHIELD",
             desc: "Absorbs one crash and keeps you running. A badge shows when it's armed.",
             timing: "Held until used"),
        Item(kind: .magnet, name: "MAGNET",
             desc: "Pulls nearby gems straight to you — sweep lanes without weaving.",
             timing: "\(Int(Tuning.magnetDuration))s"),
        Item(kind: .doubler, name: "DOUBLER",
             desc: "Every gem you grab pays double coins. Stack it with a gem run.",
             timing: "\(Int(Tuning.doublerDuration))s"),
        Item(kind: .slowMo, name: "CHRONO",
             desc: "Slows the world down — wider dodge windows when it gets fast.",
             timing: "\(Int(Tuning.chronoDuration))s"),
        Item(kind: .sneakers, name: "SUPER SNEAKERS",
             desc: "Spring-loaded jumps — leap higher and vault clean over tall walls.",
             timing: "\(Int(Tuning.superSneakersDuration))s"),
        Item(kind: .ring, name: "PRISM RING",
             desc: "Dive through for bonus coins — dead-centre pays a PERFECT.",
             timing: "Pickup"),
        Item(kind: .overdrive, name: "OVERDRIVE PAD",
             desc: "A boost pad rockets you forward through a clear gem river.",
             timing: "\(Tuning.boostDuration.formatted())s"),
    ]

    /// Deployables — banked charges you trigger on demand from the corner buttons (v1.6).
    private let deployables: [Item] = [
        Item(kind: .slowMo, name: "SLOW-MO",
             desc: "Bank charges and trigger slow-mo whenever YOU choose, not just on a pickup.",
             timing: "\(Int(Tuning.chronoDuration))s"),
        Item(kind: .speedUp, name: "SPEED UP",
             desc: "A manual overdrive burst on demand — punch through a tough stretch.",
             timing: "\(Int(Tuning.speedUpDeployDuration))s"),
        Item(kind: .shield, name: "SHIELD",
             desc: "Drop a shield mid-run from your banked charges, before the hit lands.",
             timing: "Held until used"),
    ]

    /// Pre-run loadout — armed on the hub before you start, not collected on the track.
    private let loadout: [Item] = [
        Item(kind: .headStart, name: "HEAD START",
             desc: "Launch the run already flying with an overdrive boost. Arm it on the hub.",
             timing: "\(Tuning.headStartBoostDuration.formatted())s"),
        Item(kind: .coinSurge, name: "COIN SURGE",
             desc: "Doubles every coin you earn for the whole run — always fair, never the leaderboard.",
             timing: "Whole run"),
    ]

    var body: some View {
        MetaScreenScaffold(title: "Power-Ups", coins: ProfileStore.shared.profile.coins, onClose: onClose) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                section("ON THE TRACK", "Grab these mid-run — they activate the instant you touch them.",
                        pickups)
                section("DEPLOY ON DEMAND", "Bank charges, then tap the corner buttons when you need them.",
                        deployables)
                section("PRE-RUN LOADOUT", "Arm these on the hub before you start a run.",
                        loadout)
                reviveRow
            }
        }
        .accessibilityIdentifier("powerUpsView")
    }

    private func section(_ title: String, _ subtitle: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Theme.Role.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Role.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items) { row($0) }
        }
    }

    private func row(_ item: Item) -> some View {
        let tint = Theme.color(item.kind.hex)
        return HStack(spacing: 14) {
            PowerUpGlyph(kind: item.kind, size: 30)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.s))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(1)
                        .foregroundStyle(Theme.Role.textPrimary)
                    Spacer()
                    Text(item.timing)
                        .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tint.opacity(0.14), in: Capsule())
                }
                Text(item.desc)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Role.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.Role.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name). \(item.desc). \(item.timing).")
    }

    /// The revive is not a power-up — called out separately so it's never mistaken for one.
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
