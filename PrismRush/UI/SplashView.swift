import SwiftUI

/// Launch splash. The equipped character idles full-size and *uncropped* on its glow stage beneath
/// the wordmark, the hub's calm ambient bed already playing, and a gentle "TAP TO START" shimmer
/// inviting the run. Tapping anywhere fades into the menu. Addresses two owner asks directly: the
/// loading screen now has music, and the character bobs freely in a 1.85× canvas (no more being
/// "cut off in a square smaller than them"). Shown once per launch; the menu lives behind it.
struct SplashView: View {
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        // The skin the run actually plays (resolver, never raw selection) — previews never lie.
        let skin = SkinCatalog.skin(ProfileStore.shared.equippedSkinID)
        ZStack {
            Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255).ignoresSafeArea()
            // A single soft bloom in the character's own body hue — atmosphere, not chrome.
            RadialGradient(colors: [Theme.color(skin.bodyHex).opacity(0.20), .clear],
                           center: .center, startRadius: 20, endRadius: 460)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer()
                LogoMark(size: 40)
                // Frameless float — just the figure and its own radial glow on the flat backdrop,
                // so there's no stage rectangle to read as a "box." 1.85× canvas + low anchor keeps
                // the antenna and up-bob fully in frame.
                AnimatedCharacterSwatch(skin: skin, size: 150, heightScale: 1.85, verticalAnchor: 0.62)
                namePill(for: skin)
                Spacer()
                tapPrompt
                Spacer().frame(height: 44)
            }
            .padding(.horizontal, Theme.Space.l)
        }
        .contentShape(Rectangle())
        .onTapGesture { onStart() }
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("splashStart")
        .accessibilityLabel("Prism Rush. Tap to start.")
        .accessibilityAddTraits(.isButton)
    }

    /// The equipped character's name, same pill treatment as the hub hero.
    private func namePill(for skin: Skin) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(skin.bodyHex)).frame(width: 6, height: 6)
            Text(skin.name.uppercased())
                .typeScale(.caption).fontWeight(.bold)
                .foregroundStyle(Theme.Role.textPrimary)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Role.hairline))
        .accessibilityHidden(true)
    }

    /// Calm breathing prompt — the one sanctioned motion here (a splash invites; gameplay stays
    /// calm per decree 6). Reduce Motion holds it steady at full legibility.
    private var tapPrompt: some View {
        Text("TAP TO START")
            .font(.system(size: 15, weight: .bold, design: .rounded)).tracking(4)
            .foregroundStyle(Theme.Role.textSecondary)
            .opacity(reduceMotion ? 0.9 : (pulse ? 0.9 : 0.3))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                       value: pulse)
            .accessibilityHidden(true)
    }
}
