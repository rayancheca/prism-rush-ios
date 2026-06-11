import SwiftUI

/// SwiftUI bridge for the shared Prism shimmer — `SkinCatalog.prismaticColor` is pure
/// Foundation; both this preview layer and the RealityKit body material feed it the same
/// reference-date wall clock, so the menu hero and the in-run body match at any instant.
private func prismaticTint(at t: TimeInterval) -> Color {
    let c = SkinCatalog.prismaticColor(at: t)
    return Color(red: c.r, green: c.g, blue: c.b)
}

/// Live procedural character preview — Canvas + TimelineView at 30 Hz (no per-card RealityViews;
/// 24 RealityKit instances in a grid is a memory/stutter trap). Draws the same `Skin` recipe the
/// renderer rebuilds in 3D: body shape/scale, eye tint + pupil style, antenna height/tip, and the
/// idle personality (bob, deterministic per-skin blink, antenna sway). Zero binary assets.
struct AnimatedCharacterSwatch: View {
    let skin: Skin
    var size: CGFloat = 62
    /// Locked state — v1.4 TEASE: the full-color character at reduced opacity with a lock chip,
    /// still gently animated. The old dark cutout hid what players were missing; the tease sells
    /// it ("see them, want them"). The parameter keeps its v1.3 spelling so every call site
    /// compiles unchanged (R13 — `silhouette` now reads as "locked tease").
    var silhouette = false
    var animated = true             // hero/grid: true; Reduce Motion forces a static frame
    /// Tease fade for locked renders: grid cards 0.45; the hero stage lifts to 0.6 so the
    /// buy/requirement button below it feels within reach.
    var teaseOpacity: Double = 0.45
    /// Trail wisp (AUDIT D2-4): a short stream of fading puffs in the skin's `trailHex` behind
    /// the body — the paid-for trail identity (Aurora's two-tone money look) visible at every
    /// buy moment (shop cards, select stage/grid, menu hero). Static frames freeze the wisp
    /// in place (Reduce Motion = static wisp, never a missing one).
    var showsTrail = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    swatchCanvas(t: tl.date.timeIntervalSinceReferenceDate)
                }
            } else {
                swatchCanvas(t: 0)   // single static frame (Reduce Motion / grids off-screen)
            }
        }
        .opacity(silhouette ? teaseOpacity : 1)    // the tease fade — the lock chip stays solid
        .overlay(alignment: .bottom) {
            if silhouette { lockChip }
        }
        .frame(width: size, height: size * 1.5)   // antenna headroom + bob never clips
        .accessibilityHidden(true)                 // containers carry the meaning (name/state labels)
    }

    /// Solid lock chip riding the teased render's feet — the one element that does NOT fade.
    private var lockChip: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: max(8, size * 0.16), weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(max(4, size * 0.1))
            .background(Color.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22)))
    }

    private func swatchCanvas(t: TimeInterval) -> some View {
        Canvas { ctx, canvasSize in
            draw(&ctx, t: t, in: canvasSize)
        }
    }

    // MARK: drawing (all geometry derived from `size`, scaled by `skin.scale`)

    private func draw(_ ctx: inout GraphicsContext, t: TimeInterval, in canvasSize: CGSize) {
        let scale = CGFloat(skin.scale)
        let bodyR = size * 0.5 * scale
        // Bob: whole figure rides a per-skin sine; 0 at the static frame.
        let yOff = sin(t * skin.idle.bobSpeed * 2 * .pi) * skin.idle.bobAmp * size
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + yOff)

        // Prism: the SAME 8 s shimmer the in-run body runs — one shared clock→color function
        // (`SkinCatalog.prismaticColor`), so this preview and the RealityKit rig show the same
        // hue at the same instant (decree 2). Static frames (t == 0: Reduce Motion, off-screen
        // grids) hold phase 0 = the authored cyan body, matching the in-run Reduce Motion look.
        let bodyColor = skin.isPrismatic ? prismaticTint(at: t) : Theme.color(skin.bodyHex)

        // Glow — teased renders keep it: the whole canvas fades as one, so the glow reads as a
        // dimmed version of the owned look rather than a different art style.
        let glowRect = CGRect(x: center.x - bodyR * 1.6, y: center.y - bodyR * 1.6,
                              width: bodyR * 3.2, height: bodyR * 3.2)
        ctx.fill(Path(ellipseIn: glowRect),
                 with: .radialGradient(Gradient(colors: [bodyColor.opacity(0.45), .clear]),
                                       center: center, startRadius: bodyR * 0.4, endRadius: bodyR * 1.6))

        // Trail wisp behind everything but the glow: the same color the in-run wake, slide
        // ribbon, jump/land puffs, flow aura, and death shatter burn (Prism's rides the live
        // shimmer hue, exactly like its in-run trail). Drawn before the body so the puffs
        // emerge from behind the lower flank and sink toward the ground.
        if showsTrail {
            drawTrailWisp(&ctx, t: t, center: center, bodyR: bodyR)
        }

        // Antenna behind the body: stem + tip rotate around the stem base (per-skin sway).
        drawAntenna(&ctx, t: t, center: center, bodyR: bodyR, scale: scale)

        // Body shape: sphere → circle, cube → rounded rect, crystal → vertical diamond.
        ctx.fill(bodyPath(center: center, bodyR: bodyR), with: .color(bodyColor))

        drawEyes(&ctx, t: t, center: center, scale: scale)
    }

    /// Body silhouette — every proportion derives from `CharacterProportions`, the SAME
    /// constants `RealityRenderer.buildCharacter` sizes its meshes from, so the preview and
    /// the in-run rig agree by construction (AUDIT D2-5: the cube used to span 100% of the
    /// footprint here while rendering at ~85% in 3D; relative sizes flipped across the seam).
    private func bodyPath(center: CGPoint, bodyR: CGFloat) -> Path {
        switch skin.bodyShape {
        case .sphere:
            return Path(ellipseIn: CGRect(x: center.x - bodyR, y: center.y - bodyR,
                                          width: bodyR * 2, height: bodyR * 2))
        case .cube:
            let half = bodyR * CGFloat(CharacterProportions.cubeEdgeRatio)
            return Path(roundedRect: CGRect(x: center.x - half, y: center.y - half,
                                            width: half * 2, height: half * 2),
                        cornerRadius: half * 2 * CGFloat(CharacterProportions.cubeCornerRatio))
        case .crystal:
            // Square rotated 45°, elongated vertically (DESIGN_characters §4.1) — the rig's
            // octahedron now carries the same half-extents in 3D.
            let hw = bodyR * CGFloat(CharacterProportions.crystalHalfWidthRatio)
            let hh = bodyR * CGFloat(CharacterProportions.crystalHalfHeightRatio)
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - hh))
            p.addLine(to: CGPoint(x: center.x + hw, y: center.y))
            p.addLine(to: CGPoint(x: center.x, y: center.y + hh))
            p.addLine(to: CGPoint(x: center.x - hw, y: center.y))
            p.closeSubpath()
            return p
        }
    }

    private func drawEyes(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint, scale: CGFloat) {
        let eyeY = center.y - size * 0.05 * scale
        let eyeDX = size * 0.19 * scale
        let eyeD = size * 0.2 * CGFloat(skin.eyeRadius / 0.13) * scale

        // Blink: deterministic, no state — per-skin period means Tempo visibly blinks on its 3 s
        // beat next to Fang's long stare. Static frames (t == 0) always render eyes open.
        let period = (skin.idle.blinkMin + skin.idle.blinkMax) / 2
        let blinking = t > 0 && t.truncatingRemainder(dividingBy: period) < 0.12
        let eyeH = blinking ? eyeD * 0.1 : eyeD

        for dx in [-eyeDX, eyeDX] {
            let eyeRect = CGRect(x: center.x + dx - eyeD / 2, y: eyeY - eyeH / 2, width: eyeD, height: eyeH)
            ctx.fill(Path(ellipseIn: eyeRect), with: .color(Theme.color(skin.eyeTintHex)))
            guard !blinking else { continue }
            drawPupil(&ctx, at: CGPoint(x: center.x + dx, y: eyeY), scale: scale)
        }
    }

    private func drawPupil(_ ctx: inout GraphicsContext, at p: CGPoint, scale: CGFloat) {
        let ink = Color.black
        switch skin.pupilStyle {
        case .dot:
            let d = size * 0.09 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                     with: .color(ink))
        case .wide:
            let d = size * 0.13 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                     with: .color(ink))
        case .slit:
            let w = size * 0.05 * scale, h = size * 0.14 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)),
                     with: .color(ink))
        case .glint:
            let d = size * 0.09 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                     with: .color(ink))
            let g = size * 0.035 * scale
            let off = CGPoint(x: p.x + size * 0.02 * scale, y: p.y - size * 0.02 * scale)
            ctx.fill(Path(ellipseIn: CGRect(x: off.x - g / 2, y: off.y - g / 2, width: g, height: g)),
                     with: .color(.white))
        }
    }

    /// The trail wisp (AUDIT D2-4): five puffs looping from behind the body's lower flank down
    /// toward the ground, shrinking and fading — a miniature of the in-run wake. Color comes
    /// from the same rule the renderer applies: `trailHex`, or the live shimmer hue when nil
    /// (Prism), so the promise IS the in-run trail (decree 2). At `t == 0` (Reduce Motion,
    /// static grids) the loop freezes into a staggered static streak — present, just still.
    private func drawTrailWisp(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint,
                               bodyR: CGFloat) {
        let tint = skin.trailHex.map { Theme.color($0) } ?? prismaticTint(at: t)
        let head = CGPoint(x: center.x - bodyR * 0.52, y: center.y + bodyR * 0.72)
        let tail = CGPoint(x: size * 0.07, y: center.y + bodyR * 1.18)
        let puffs = 5
        for i in 0..<puffs {
            // Each puff travels head→tail over ~1.5 s, offset a fifth of a loop apart.
            let phase = (t * 0.66 + Double(i) / Double(puffs)).truncatingRemainder(dividingBy: 1)
            let x = head.x + (tail.x - head.x) * CGFloat(phase)
                + sin(t * 2.6 + phase * 6) * size * 0.018   // gentle swim along the way
            let y = head.y + (tail.y - head.y) * CGFloat(phase)
            let r = bodyR * (0.13 - 0.085 * CGFloat(phase))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(tint.opacity(0.55 * (1 - phase))))
        }
    }

    private func drawAntenna(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint,
                             bodyR: CGFloat, scale: CGFloat) {
        let antennaColor = Theme.color(skin.antennaHex)   // constant authored hex — never shimmers
        let baseY = skin.bodyShape == .crystal ? center.y - bodyR * 1.1 : center.y - bodyR * 0.92
        let base = CGPoint(x: center.x, y: baseY)
        let stemLen = size * 0.28 * CGFloat(skin.antennaHeightScale) * scale
        // Sway: rotate stem + tip around the stem base (0 at the static frame).
        let a = t > 0 ? sin(t * skin.idle.bobSpeed * 2 * .pi * 0.8) * skin.idle.sway : 0
        let tipCenter = CGPoint(x: base.x + sin(a) * stemLen, y: base.y - cos(a) * stemLen)

        var stem = Path()
        stem.move(to: base)
        stem.addLine(to: tipCenter)
        ctx.stroke(stem, with: .color(antennaColor),
                   style: StrokeStyle(lineWidth: max(1, size * 0.035 * scale), lineCap: .round))

        let tipR = size * 0.08 * CGFloat(skin.antennaTipScale) * scale
        ctx.fill(Path(ellipseIn: CGRect(x: tipCenter.x - tipR, y: tipCenter.y - tipR,
                                        width: tipR * 2, height: tipR * 2)),
                 with: .color(antennaColor))
    }
}

/// The hero presentation of a character: idle swatch standing on a tinted glow disc, with a
/// subtle floor reflection and the skin-name pill. One visual unit — callers wrap it in a Button
/// when it must be a tap target (menu hero stage), or show it inert (CharacterSelect stage).
/// Realizes uiux §1.3's "CharacterIdleStage" as a thin Canvas-only wrapper (R5).
struct CharacterHeroStage: View {
    let skin: Skin
    let height: CGFloat
    /// The select screen prints the name as its own title row — it hides the pill.
    var showsNamePill = true
    /// v1.4: a focused LOCKED skin stages as a 0.6-opacity tease (full color + lock chip) —
    /// bright enough to want, dim enough that the buy/requirement button reads as the way in.
    var locked = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero-stage tease opacity (grid cards use the swatch default 0.45).
    private static let stageTeaseOpacity = 0.6

    private var swatchSize: CGFloat { height * 0.5 }   // menu ≈240 → 120; select 192 → 96 (R5)
    private var discTint: Color { Theme.color(skin.bodyHex) }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ZStack(alignment: .bottom) {
                glowDisc
                    .frame(width: swatchSize * 1.7, height: swatchSize * 0.42)
                    .offset(y: swatchSize * 0.12)
                    .opacity(locked ? 0.55 : 1)   // dimmed pedestal under a teased skin
                // Floor reflection at 18% (skipped under Reduce Motion: one Canvas, not two).
                // Offset so the mirrored feet meet the real feet; the stage frame clips the rest.
                // Locked: plain render faded harder (0.18 × 0.6) — a mirrored lock chip is noise.
                if !reduceMotion {
                    AnimatedCharacterSwatch(skin: skin, size: swatchSize)
                        .scaleEffect(x: 1, y: -1)
                        .opacity(locked ? 0.11 : 0.18)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                        .offset(y: swatchSize)
                }
                AnimatedCharacterSwatch(skin: skin, size: swatchSize,
                                        silhouette: locked, teaseOpacity: Self.stageTeaseOpacity)
            }
            .frame(height: swatchSize * 1.5)
            .clipped()
            if showsNamePill { namePill }
        }
        .frame(height: height)
        .accessibilityHidden(true)   // the wrapping button / sibling texts carry the label
    }

    /// Elliptical glow disc tinted by the skin's fixed authored body hex. Prism's disc rides
    /// the SAME shared 8 s shimmer as its body (no skin ever tracks the world palette);
    /// static at phase 0 under Reduce Motion, per uiux §1.8.
    @ViewBuilder private var glowDisc: some View {
        if skin.isPrismatic && !reduceMotion {
            TimelineView(.animation(minimumInterval: 0.2)) { tl in
                disc(tint: prismaticTint(at: tl.date.timeIntervalSinceReferenceDate))
            }
        } else {
            disc(tint: discTint)
        }
    }

    private func disc(tint: Color) -> some View {
        Ellipse().fill(
            RadialGradient(colors: [tint.opacity(0.5), tint.opacity(0.12), .clear],
                           center: .center, startRadius: 1, endRadius: swatchSize * 0.85))
    }

    private var namePill: some View {
        HStack(spacing: 6) {
            Circle().fill(discTint).frame(width: 6, height: 6)
            Text(skin.name.uppercased())
                .typeScale(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Role.textPrimary)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Role.hairline))
    }
}
