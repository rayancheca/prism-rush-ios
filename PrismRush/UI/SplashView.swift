import SwiftUI

/// Launch splash — the first beat of the game, so it gets a real entrance (owner: "the startup needs
/// to be the best part"). The wordmark drops in, the equipped character flip-spins up to full size out
/// of a burst of shards in its own hue, then settles into a free idle bob over its glow with a calm
/// "TAP TO START" shimmer. The hub's music bed is already playing (now on a `.playback` session, so it
/// sounds even on silent). Tapping anywhere fades into the menu. Reduce Motion shows the same scene as
/// a clean fade-in (no spin/burst). Shown once per launch; the menu lives behind it.
struct SplashView: View {
    let onStart: () -> Void

    /// The hero figure's size. Named because the stage ring derives its own frame from it — the two
    /// must not be able to drift apart.
    private static let figureSize: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var entered = false      // master intro spring (scale/opacity)
    @State private var spin: Double = 0     // character flip-spin (degrees, Y axis)
    @State private var burst: CGFloat = 0   // 0→1 shard-burst expansion

    var body: some View {
        // The skin the run actually plays (resolver, never raw selection) — previews never lie.
        let skin = SkinCatalog.skin(ProfileStore.shared.equippedSkinID)
        let tint = Theme.color(skin.bodyHex)
        ZStack {
            Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255).ignoresSafeArea()
            RadialGradient(colors: [tint.opacity(0.22), .clear],
                           center: .center, startRadius: 20, endRadius: 460)
                .opacity(entered ? 1 : 0.25)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer()
                LogoMark(size: 40)
                    .scaleEffect(entered ? 1 : 0.6)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : -24)
                // The character bursts in out of a ring of shards, flip-spinning up to size, and
                // lands on the SAME lit ring it stands on everywhere else in the app.
                //
                // It used to sit on the raw `AnimatedCharacterSwatch` halo instead (S-009, owner:
                // *"same ring under the character. not the diffused color"*). That halo is drawn
                // 1.6 × `size` wide, so a default-width canvas cut it square and it read as a faint
                // teal rectangle with visible vertical edges behind the figure — the same "box"
                // PR-0453 fixed for the hub hero and never fixed here, because the splash was
                // never using the hero stage. `haloScale: 0` removes the blur; `CharacterStageRing`
                // replaces it with the platform, which is the one the owner signed off in S-007.
                //
                // The ring deliberately does NOT ride the flip-spin: it is the floor, and a floor
                // that rotates with the thing standing on it stops reading as a floor.
                ZStack {
                    shardBurst(tint: tint)
                    // 0.82 is derived, not eyeballed, and it reproduces the hub hero's geometry:
                    // in a 1.85× canvas anchored at 0.62 the figure's feet land 0.722 × size below
                    // centre, and `CharacterHeroStage` sits its ring a further ~0.10 × size under
                    // the feet so the NEAR arc clears the body. An ellipse tucked up behind a
                    // sphere shows only its side tips and reads as two stray whiskers.
                    CharacterStageRing(skin: skin, size: Self.figureSize)
                        .frame(width: Self.figureSize * 1.6, height: Self.figureSize * 0.5)
                        .offset(y: Self.figureSize * 0.82)
                        .scaleEffect(entered ? 1 : 0.4)
                        .opacity(entered ? 1 : 0)
                    AnimatedCharacterSwatch(skin: skin, size: Self.figureSize,
                                            heightScale: 1.85, widthScale: 1.6,
                                            verticalAnchor: 0.62, haloScale: 0)
                        .scaleEffect(entered ? 1 : 0.15)
                        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                        .opacity(entered ? 1 : 0)
                }
                namePill(for: skin)
                    .opacity(entered ? 1 : 0)
                Spacer()
                tapPrompt
                    .opacity(entered ? 1 : 0)
                Spacer().frame(height: 44)
            }
            .padding(.horizontal, Theme.Space.l)
        }
        .contentShape(Rectangle())
        .onTapGesture { onStart() }
        .onAppear { animateIn() }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("splashStart")
        .accessibilityLabel("Prism Rush. Tap to start.")
        .accessibilityAddTraits(.isButton)
    }

    /// The arrival flourish: scale/opacity spring, one settling flip-spin, and the shard burst —
    /// all skipped under Reduce Motion (which shows the final composed scene, statically).
    private func animateIn() {
        guard !reduceMotion else { entered = true; pulse = true; return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { entered = true }
        withAnimation(.easeOut(duration: 0.85)) { spin = 360 }   // one full flip into view
        withAnimation(.easeOut(duration: 0.8)) { burst = 1 }
        pulse = true                                              // gated by the prompt's own opacity
    }

    /// A ring of diamond shards that flares outward from the character on entry, then fades — the
    /// "shard" arrival the owner asked for, in the character's own hue (zero assets, pure shapes).
    @ViewBuilder private func shardBurst(tint: Color) -> some View {
        if !reduceMotion {
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) / 12 * 2 * .pi
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(0.85 * Double(1 - burst)))
                        .frame(width: 10, height: 16)
                        .scaleEffect(1 - burst * 0.6)
                        .rotationEffect(.radians(angle))
                        .offset(x: CGFloat(cos(angle)) * 150 * burst,
                                y: CGFloat(sin(angle)) * 150 * burst)
                }
            }
            .allowsHitTesting(false)
        }
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

    /// Calm breathing prompt — the one sanctioned looping motion here. Reduce Motion holds it steady.
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
