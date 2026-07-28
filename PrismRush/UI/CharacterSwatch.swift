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
    /// Vertical room for the figure as a multiple of `size`. The default 1.5 holds every existing
    /// call site (the 24-card grids, shop, select) byte-identical; the menu hero and the splash
    /// pass a taller value so the tallest antennas (Blossom) and the full up-bob never crop — the
    /// owner's "characters sit in a square smaller than them" fix.
    var heightScale: CGFloat = 1.5
    /// Horizontal room, same idea as `heightScale`. The body glow is drawn `bodyR * 3.2` wide — i.e.
    /// 1.6 × `size` at unit skin scale — so at `1.0` it is HARD-CLIPPED by the canvas bounds and
    /// leaves a faint vertical band with visible edges either side of the figure. On a small dark
    /// grid card that is invisible; on the hub, where the stage is large and the live 3D scene shows
    /// through, it reads as a box behind the character (PR-0453). The default 1.0 keeps every
    /// existing call site byte-identical; the hub hero passes 1.6 so the glow lands inside the
    /// canvas and falls off to nothing on its own.
    var widthScale: CGFloat = 1.0
    /// Where the figure's center sits in the canvas (0 = top, 1 = bottom). 0.5 keeps the grids
    /// centered; the hero/splash bias it down so the added headroom lands above the antenna while
    /// the feet stay near the disc.
    var verticalAnchor: CGFloat = 0.5

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
        // Antenna headroom + bob never clip vertically; `widthScale` gives the body glow room to
        // fall off instead of being cut square at the canvas edge.
        .frame(width: size * widthScale, height: size * heightScale)
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
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height * verticalAnchor + yOff)

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

        // Legendary aura (v1.6): an orbiting glow ring behind the figure — the unmistakable
        // "this one is special" tell. Drawn before the body so it reads as a halo around it.
        if skin.hasAura {
            drawAura(&ctx, t: t, center: center, bodyR: bodyR)
        }

        // Trail wisp behind everything but the glow: the same color the in-run wake, slide
        // ribbon, jump/land puffs, flow aura, and death shatter burn (Prism's rides the live
        // shimmer hue, exactly like its in-run trail). Drawn before the body so the puffs
        // emerge from behind the lower flank and sink toward the ground.
        if showsTrail {
            drawTrailWisp(&ctx, t: t, center: center, bodyR: bodyR)
        }

        // Antenna behind the body: stem + tip rotate around the stem base (per-skin sway).
        drawAntenna(&ctx, t: t, center: center, bodyR: bodyR, scale: scale)

        // Crest (v1.6) behind the body so it roots into the head and the tips poke out the top —
        // the visible rarity ladder (rare creature feature → epic bold crest → legendary signature).
        if skin.crest != .none {
            drawCrest(&ctx, center: center, bodyR: bodyR)
        }

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

    /// The rarity-ladder crest (v1.6) — drawn in the authored `antennaHex` so it reads as part of
    /// the character, with the SAME taxonomy the RealityKit rig builds (decree 2: previews never
    /// lie). All geometry derives from `bodyR`; `headY` is the crown anchor per body shape.
    private func drawCrest(_ ctx: inout GraphicsContext, center: CGPoint, bodyR: CGFloat) {
        let tint = Theme.color(skin.crestHex)   // antenna hue, or body hue if the antenna is too dark
        let headY = skin.bodyShape == .crystal ? center.y - bodyR * 1.02 : center.y - bodyR * 0.86

        func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ color: Color) {
            var p = Path()
            p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }

        switch skin.crest {
        case .none:
            break
        case .ears:   // upright cat ears flanking the antenna, with a darker inner ear
            for side in [CGFloat(-1), 1] {
                let bx = center.x + side * bodyR * 0.5
                triangle(CGPoint(x: bx - bodyR * 0.22, y: headY + bodyR * 0.12),
                         CGPoint(x: bx + bodyR * 0.22, y: headY + bodyR * 0.12),
                         CGPoint(x: bx + side * bodyR * 0.12, y: headY - bodyR * 0.80), tint)
                triangle(CGPoint(x: bx - bodyR * 0.10, y: headY + bodyR * 0.02),
                         CGPoint(x: bx + bodyR * 0.10, y: headY + bodyR * 0.02),
                         CGPoint(x: bx + side * bodyR * 0.08, y: headY - bodyR * 0.50),
                         .black.opacity(0.28))
            }
        case .floppy: // rounded drooping dog/bunny ears hanging beside the head
            for side in [CGFloat(-1), 1] {
                let cx = center.x + side * bodyR * 0.84
                let rect = CGRect(x: cx - bodyR * 0.26, y: center.y - bodyR * 0.52,
                                  width: bodyR * 0.52, height: bodyR * 1.02)
                ctx.fill(Path(ellipseIn: rect), with: .color(tint))
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: bodyR * 0.14, dy: bodyR * 0.22)),
                         with: .color(.black.opacity(0.22)))
            }
        case .fin:    // a sawtooth dorsal mohawk across the crown, tallest in the middle
            let heights: [CGFloat] = [0.50, 0.95, 0.62]
            let n = heights.count
            for i in 0..<n {
                let fx = center.x + (CGFloat(i) - CGFloat(n - 1) / 2) * bodyR * 0.32
                triangle(CGPoint(x: fx - bodyR * 0.17, y: headY + bodyR * 0.10),
                         CGPoint(x: fx + bodyR * 0.17, y: headY + bodyR * 0.10),
                         CGPoint(x: fx, y: headY - bodyR * heights[i]), tint)
            }
        case .horns:  // two horns sweeping up and out
            for side in [CGFloat(-1), 1] {
                let bx = center.x + side * bodyR * 0.42
                triangle(CGPoint(x: bx - side * bodyR * 0.02, y: headY + bodyR * 0.10),
                         CGPoint(x: bx + side * bodyR * 0.24, y: headY + bodyR * 0.10),
                         CGPoint(x: bx + side * bodyR * 0.95, y: headY - bodyR * 0.85), tint)
            }
        case .crown:  // a ring of points with a connecting band — royalty
            let span = bodyR * 1.2
            let n = 5
            ctx.fill(Path(roundedRect: CGRect(x: center.x - span / 2, y: headY - bodyR * 0.02,
                                              width: span, height: bodyR * 0.16),
                          cornerRadius: bodyR * 0.05), with: .color(tint))
            for i in 0..<n {
                let fx = center.x - span / 2 + span * CGFloat(i) / CGFloat(n - 1)
                let h = (i == n / 2) ? bodyR * 0.62 : bodyR * 0.42
                triangle(CGPoint(x: fx - bodyR * 0.10, y: headY),
                         CGPoint(x: fx + bodyR * 0.10, y: headY),
                         CGPoint(x: fx, y: headY - h), tint)
            }
        case .halo:   // a glowing ring floating above the head
            let cy = headY - bodyR * 0.58
            let rect = CGRect(x: center.x - bodyR * 0.70, y: cy - bodyR * 0.18,
                              width: bodyR * 1.40, height: bodyR * 0.36)
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -bodyR * 0.06, dy: -bodyR * 0.06)),
                       with: .color(tint.opacity(0.30)),
                       style: StrokeStyle(lineWidth: max(2, bodyR * 0.18)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(tint),
                       style: StrokeStyle(lineWidth: max(1.5, bodyR * 0.10)))
        }
    }

    /// The legendary aura (v1.6): a tilted orbit ring in the trail hue with two nodes circling it,
    /// brighter on the near (lower) pass. Pure of state — at `t == 0` the nodes freeze in place
    /// (Reduce Motion / static grids show the ring, never a missing one). Mirrors the rig's torus.
    private func drawAura(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint, bodyR: CGFloat) {
        let tint = skin.trailHex.map { Theme.color($0) } ?? prismaticTint(at: t)
        let a = bodyR * 1.5, b = bodyR * 0.55
        let cy = center.y + bodyR * 0.22
        let ringRect = CGRect(x: center.x - a, y: cy - b, width: a * 2, height: b * 2)
        ctx.stroke(Path(ellipseIn: ringRect), with: .color(tint.opacity(0.18)),
                   style: StrokeStyle(lineWidth: max(3, bodyR * 0.22)))   // soft underglow
        ctx.stroke(Path(ellipseIn: ringRect), with: .color(tint.opacity(0.5)),
                   style: StrokeStyle(lineWidth: max(2, bodyR * 0.10)))
        for k in 0..<2 {
            let theta = t * 1.1 + Double(k) * .pi
            let x = center.x + CGFloat(cos(theta)) * a
            let y = cy + CGFloat(sin(theta)) * b
            let depth = (CGFloat(sin(theta)) + 1) / 2        // 0 far (top) … 1 near (bottom)
            let r = bodyR * (0.11 + 0.07 * depth)
            // node glow then core — a bright comet circling the body
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2, y: y - r * 2, width: r * 4, height: r * 4)),
                     with: .color(tint.opacity(0.18 * (0.4 + depth))))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(tint.opacity(0.6 + 0.4 * depth)))
        }
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
    /// The splash sets this false: against its flat dark backdrop the mirrored floor reflection's
    /// glow reads as a faint rectangle behind the figure (the owner's "box"); on the menu the busy
    /// 3D scene washes it out, so the hub keeps it.
    var showsReflection = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero-stage tease opacity (grid cards use the swatch default 0.45).
    private static let stageTeaseOpacity = 0.6

    /// The body glow is drawn 1.6 × `size` wide, so the stage's canvases are widened to match and
    /// the halo falls off to nothing instead of being cut square (PR-0453). Kept just under the
    /// pedestal disc's 1.7 so the ZStack's width — and therefore the stage's clip — is unchanged.
    private static let glowWidthScale: CGFloat = 1.6

    // 0.42 (was 0.5): the figure now renders in a 1.85× canvas with real antenna headroom, so it
    // sizes down a touch to keep the taller, never-cropped stage inside the menu's height budget.
    private var swatchSize: CGFloat { height * 0.42 }
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
                if !reduceMotion && showsReflection {
                    AnimatedCharacterSwatch(skin: skin, size: swatchSize, widthScale: Self.glowWidthScale)
                        .scaleEffect(x: 1, y: -1)
                        .opacity(locked ? 0.11 : 0.18)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                        .offset(y: swatchSize)
                }
                AnimatedCharacterSwatch(skin: skin, size: swatchSize,
                                        silhouette: locked, teaseOpacity: Self.stageTeaseOpacity,
                                        heightScale: 1.85, widthScale: Self.glowWidthScale,
                                        verticalAnchor: 0.66)
            }
            // Clip matches the figure's own 1.85× canvas, so the antenna + up-bob are never cropped
            // (anchor 0.66 lands the headroom above the tip); only the mirrored reflection's spill
            // below the stage is trimmed.
            .frame(height: swatchSize * 1.85)
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
