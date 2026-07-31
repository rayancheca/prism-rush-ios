import SwiftUI

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
    /// Horizontal room, same idea as `heightScale`. Now that the body halo is gone (see `draw`) the
    /// widest thing drawn is the aura ring at `bodyR * 1.5`, so `1.0` no longer clips anything on a
    /// grid card. The hero surfaces keep passing `1.6` because their crests, auras and trail wisps
    /// are drawn at hero scale and the extra room costs nothing.
    ///
    /// The claim this comment used to carry — "on a small dark grid card that is invisible" — was
    /// simply wrong, and it is why the clipped halo survived four sessions: it was an assumption
    /// about a screen nobody had looked at. It was plainly visible as a coloured rectangle behind
    /// every card in the 24-skin grid.
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
        // authored `bodyHex`, so this preview and the RealityKit rig show the same
        // hue at the same instant (decree 2). Static frames (t == 0: Reduce Motion, off-screen
        // grids) hold phase 0 = the authored cyan body, matching the in-run Reduce Motion look.
        let bodyColor = Theme.color(skin.bodyHex)

        // **There is no body halo, and there must not be one** (owner, S-011 — the third time he has
        // named this artifact: "background light behind the character" on the hub (S-007), "the box"
        // on the splash (PR-0453), and now "the characters in the character selection still have the
        // faded color background").
        //
        // The halo was a radial gradient of radius `bodyR * 1.6` — i.e. `0.8 × size` from centre —
        // drawn into a canvas only `size × widthScale` wide. Every surface that still drew it passed
        // the default `widthScale: 1.0`, so it was clipped at `0.5 × size` on all four sides: not a
        // glow, a COLOURED RECTANGLE with hard edges, one per character, in its own hue. The three
        // large surfaces (hub hero, select stage, splash) had already opted out one at a time via a
        // `haloScale: 0` parameter, which left the halo drawn *only* where it was guaranteed to clip.
        // A parameter whose every remaining use is a bug is not a parameter; it is dead code with a
        // switch on it, so it is gone rather than defaulted off.
        //
        // Lift now comes from the one thing in this game that has an edge: `CharacterStageRing`, the
        // lit platform the figure stands on. Diffuse light has no edge and the visual language here
        // is edges (decree 6 — clarity beats spectacle).

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
        let body = bodyPath(center: center, bodyR: bodyR)
        if let spectrum = skin.spectrum, skin.bodyShape == .sphere {
            drawSpectrumBody(&ctx, body: body, center: center, bodyR: bodyR, spectrum: spectrum)
        } else {
            ctx.fill(body, with: .color(bodyColor))
        }

        drawEyes(&ctx, t: t, center: center, scale: scale)
    }

    /// Prism's static spectrum (v1.8 / D-011): equal-HEIGHT bands, top to bottom, clipped to the
    /// silhouette. That is deliberately the same rule `ProceduralMesh.bandedSphere` slices the 3-D
    /// body by, so this preview and the in-run rig cannot drift apart — decree 2 holds because both
    /// layers derive from one list and one rule, not because two sets of numbers were kept in sync.
    ///
    /// The bands are drawn a hair wider than the body and clipped, so the seams meet the silhouette
    /// edge cleanly instead of leaving a half-pixel of background between band and outline.
    private func drawSpectrumBody(_ ctx: inout GraphicsContext, body: Path,
                                  center: CGPoint, bodyR: CGFloat, spectrum: [UInt32]) {
        ctx.drawLayer { layer in
            layer.clip(to: body)
            let top = center.y - bodyR
            let bandH = bodyR * 2 / CGFloat(spectrum.count)
            for (i, hex) in spectrum.enumerated() {
                let rect = CGRect(x: center.x - bodyR - 1, y: top + bandH * CGFloat(i),
                                  width: bodyR * 2 + 2, height: bandH + 0.5)
                layer.fill(Path(rect), with: .color(Theme.color(hex)))
            }
        }
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
        let tint = skin.trailHex.map { Theme.color($0) } ?? Theme.color(skin.bodyHex)
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
        let tint = skin.trailHex.map { Theme.color($0) } ?? Theme.color(skin.bodyHex)
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
                // Wider than the figure and dropped below its base, so the near arc clears the body
                // and the ring reads as ONE platform in perspective rather than two stray slivers
                // either side of it.
                glowDisc
                    .frame(width: swatchSize * 1.6, height: swatchSize * 0.5)
                    .offset(y: swatchSize * 0.22)
                    .opacity(locked ? 0.55 : 1)   // dimmed pedestal under a teased skin
                // Floor reflection at 18% (skipped under Reduce Motion: one Canvas, not two).
                // Offset so the mirrored feet meet the real feet.
                // Locked: plain render faded harder (0.18 × 0.6) — a mirrored lock chip is noise.
                //
                // **The clip lives HERE, on the one child that needs it** (S-011). It used to sit on
                // the whole ZStack, which meant the stage ring's pool blur and its rim shadow — both
                // of which deliberately spill past the ring's own frame, because that spill IS the
                // glow — were cut off square at the stack's bounds. The result was a faint bright
                // RECTANGLE around the character's feet with hard vertical edges: the same "box" the
                // owner has now named three times, arriving by a second route after the body halo
                // was deleted. Clipping only the reflection trims the spill the comment always
                // claimed to be trimming, and lets the glow fall off to nothing on its own.
                if !reduceMotion && showsReflection {
                    AnimatedCharacterSwatch(skin: skin, size: swatchSize,
                                            widthScale: Self.glowWidthScale)
                        .scaleEffect(x: 1, y: -1)
                        // Halved: with the halo gone there is nothing to soften the mirrored body,
                        // and at 18% it read as a dark blob sitting on the platform.
                        .opacity(locked ? 0.06 : 0.09)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                        .offset(y: swatchSize)
                        .frame(height: swatchSize * 1.85, alignment: .top)
                        .clipped()
                }
                AnimatedCharacterSwatch(skin: skin, size: swatchSize,
                                        silhouette: locked, teaseOpacity: Self.stageTeaseOpacity,
                                        heightScale: 1.85, widthScale: Self.glowWidthScale,
                                        verticalAnchor: 0.66)
            }
            // Height matches the figure's own 1.85× canvas, so the antenna + up-bob are never
            // cropped (anchor 0.66 lands the headroom above the tip). Layout only — nothing clips.
            .frame(height: swatchSize * 1.85)
            if showsNamePill { namePill }
        }
        .frame(height: height)
        .accessibilityHidden(true)   // the wrapping button / sibling texts carry the label
    }

    /// The lit platform the figure stands on. One implementation, shared with the splash — see
    /// `CharacterStageRing`.
    @ViewBuilder private var glowDisc: some View {
        CharacterStageRing(skin: skin, size: swatchSize)
    }

    /// Spectral skins light their own pad with their own bands; everyone else gets their identity
    /// hue. The first colour repeats last so the sweep closes without a seam. Fixed hues, no clock
    /// in the path — this is surface, not a changing identity (decree 1 / D-011).
    private func poolStyle(tint: Color) -> AnyShapeStyle {
        guard let spectrum = skin.spectrum, let first = spectrum.first, spectrum.count > 1 else {
            return AnyShapeStyle(tint.opacity(0.55))
        }
        return AnyShapeStyle(AngularGradient(colors: (spectrum + [first]).map { Theme.color($0).opacity(0.8) },
                                             center: .center))
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

/// The stage floor a character stands on: a lit ring with a pool of light in it.
///
/// **The ring is the point** (owner's call, S-007, reaffirmed S-009). The original pedestal was a
/// wide diffuse radial glow and the figure carried a second soft halo `3.2 × bodyR` across. Two
/// problems, both of which the owner named:
///
/// 1. On the hub — where the live 3D city and its perspective grid show through — the two stacked
///    into a murky teal smear that dirtied the grid lines instead of lighting anything ("background
///    light behind the character"). Diffuse light has no edge, and the visual language of this game
///    is edges.
/// 2. The soft halo is drawn `1.6 × size` wide, so any canvas narrower than that HARD-CLIPS it into
///    a faint rectangle with visible vertical edges either side of the figure (PR-0453 — the
///    owner's "box"). That is a blur cut square, and it reads as one.
///
/// Splitting this out of `CharacterHeroStage` is the fix for S-009's report that the splash still
/// showed the box: the splash was never using the stage, so it inherited the raw halo and none of
/// the ring. Decree 2 says previews never lie, and the cheapest way to keep two surfaces honest is
/// to give them one implementation rather than two that agree today.
///
/// Tinted per character, which is also the only honest option for a SPECTRAL skin: the old glow
/// took its colour from `bodyHex`, so after D-011 gave Prism a six-band rainbow surface the light
/// under it stayed cyan — light that did not match the thing casting it. The rim sweeps the real
/// spectrum, so Prism stands on its own colours. Fixed hues, no clock in the resolution path —
/// this is surface, never a changing identity (decree 1 / D-011).
struct CharacterStageRing: View {
    let skin: Skin
    /// The figure's size, not the ring's — the ring derives its own proportions so every caller
    /// gets the same platform under the same-sized character.
    let size: CGFloat

    var body: some View {
        ZStack {
            // Pool: bright at the contact point, gone by the edge.
            Ellipse()
                .fill(style)
                .mask(Ellipse().fill(
                    RadialGradient(colors: [.white, .white.opacity(0.4), .clear],
                                   center: .center, startRadius: 1, endRadius: size * 0.52)))
                .blur(radius: size * 0.04)
            // The rim — the edge that makes it a platform rather than a blob.
            Ellipse()
                .strokeBorder(style, lineWidth: 2.4)
                .shadow(color: Theme.color(skin.bodyHex).opacity(0.55), radius: 10)
        }
    }

    /// Spectral skins light their own pad with their own bands; everyone else gets their identity
    /// hue. The first colour repeats last so the sweep closes without a seam.
    private var style: AnyShapeStyle {
        guard let spectrum = skin.spectrum, let first = spectrum.first, spectrum.count > 1 else {
            return AnyShapeStyle(Theme.color(skin.bodyHex).opacity(0.55))
        }
        return AnyShapeStyle(AngularGradient(
            colors: (spectrum + [first]).map { Theme.color($0).opacity(0.8) }, center: .center))
    }
}
