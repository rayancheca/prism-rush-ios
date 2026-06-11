import SwiftUI

/// Shared chrome for the full-screen meta surfaces (Characters, Shop, Levels, Stats): a back button,
/// a title, a coin balance, and a scrolling content area over the neutral `Role.bg` (uiux §2 — the
/// per-screen magenta radials are gone; world color lives only in previews). The coin balance is a
/// tap target wherever the caller routes it (`onCoins` → Shop, uiux §5).
struct MetaScreenScaffold<Content: View>: View {
    let title: String
    let coins: Int
    let onClose: () -> Void
    /// Destination for tapping the coin balance (Shop). Defaulted so existing call sites compile
    /// (R13); nil keeps the badge display-only.
    var onCoins: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.Role.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Role.hairline))
                }
                .accessibilityIdentifier("closeSheetButton")
                Spacer()
                Text(title)
                    .typeScale(.title)
                    .foregroundStyle(Theme.Role.textPrimary)
                Spacer()
                CoinBadge(amount: coins, action: onCoins)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Role.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Role.hairline))
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, 12)
            .padding(.bottom, Theme.Space.s)

            ScrollView {
                content()
                    .padding(Theme.Space.m)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Theme.Role.bg
                // A whisper of the tap accent up top — alive, below the "rainbow" threshold.
                RadialGradient(colors: [Theme.Role.interactive.opacity(0.06), .clear],
                               center: .top, startRadius: 10, endRadius: 520)
            }.ignoresSafeArea()
        )
    }
}
