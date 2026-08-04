import SwiftUI

/// **The one chest in this app.**
///
/// A container the player opens is a recurring moment here — the 30-minute free chest and the daily
/// bonus both use it (`RewardBurstView`), and so does the Mystery Box (`MysteryBoxView`). Until
/// v2.5 the reward overlay drew a real chest — body, banded lid on a hinge, clasp, and the light
/// that escapes as it swings back — while the Mystery Box showed a stock `Image(systemName:
/// "gift.fill")` that wobbled and scaled. Same gesture, same promise, two unrelated objects and two
/// unrelated opening motions, which is what the owner reported: *"the mystery box opening from the
/// loading screen and the one from the store have different animations."*
///
/// The chest is the better of the two — it is drawn rather than borrowed, it *opens* rather than
/// merely shaking, and it carries the app's reward palette — so the Mystery Box adopts it and the
/// SF Symbol is gone. Decree 6: one visual family per idea.
///
/// Purely a function of its inputs. It owns no state and runs no animation of its own; the caller
/// animates `lid` and `scale` on whatever timeline its own beats need, which is what lets one shape
/// serve a 2.0 s reward ceremony and a 1.05 s gacha reveal without either one bending to the other.
struct TreasureChest: View {
    /// 0 = shut, 1 = lid fully hinged back. Drives the escaping glow and hides the clasp.
    var lid: Double
    /// Overall scale. The callers' entrance curves differ, so this stays theirs.
    var scale: Double = 1

    /// Body width. Everything else is proportional to it, so one number resizes the whole chest.
    private let w: CGFloat = 128

    var body: some View {
        ZStack {
            // The glow that leaks out once the lid is up.
            Circle()
                .fill(RadialGradient(colors: [Theme.Role.reward.opacity(0.55 * lid), .clear],
                                     center: .center, startRadius: 2, endRadius: 92))
                .frame(width: w * 1.4375, height: w * 1.4375)
                .offset(y: -6)

            VStack(spacing: 0) {
                // Lid
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 2,
                                       bottomTrailingRadius: 2, topTrailingRadius: 12)
                    .fill(LinearGradient(colors: [Theme.color(0xFFE27A), Theme.color(0xE0912A)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .center) {
                        Rectangle().fill(Theme.color(0x7A4A12).opacity(0.55))
                            .frame(width: 18)
                    }
                    .frame(width: w, height: w * 0.3125)
                    // Hinged at the joint with the body, so it swings back off the chest instead
                    // of floating detached above it.
                    .rotation3DEffect(.degrees(-118 * lid), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.55)

                // Body
                UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 10,
                                       bottomTrailingRadius: 10, topTrailingRadius: 2)
                    .fill(LinearGradient(colors: [Theme.color(0xD98A26), Theme.color(0x8A4F13)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .center) {
                        Rectangle().fill(Theme.color(0x7A4A12).opacity(0.55))
                            .frame(width: 18)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.color(0xFFF0B8))
                            .frame(width: 22, height: 16)
                            .offset(y: -4)
                            .opacity(1 - lid)          // the clasp, hidden once open
                    }
                    .frame(width: w, height: w * 0.4375)
            }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .scaleEffect(scale)
        }
    }
}
