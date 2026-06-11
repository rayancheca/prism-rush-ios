import SwiftUI

/// Live procedural character preview — Canvas + TimelineView at 30 Hz (no per-card RealityViews;
/// 16 RealityKit instances in a grid is a memory/stutter trap). Draws the same `Skin` recipe the
/// renderer rebuilds in 3D: body shape/scale, eye tint + pupil style, antenna height/tip, and the
/// idle personality (bob, deterministic per-skin blink, antenna sway). Zero binary assets.
struct AnimatedCharacterSwatch: View {
    let skin: Skin
    var size: CGFloat = 62
    var silhouette = false          // locked state — shapes only, eyes closed, no glow
    var animated = true             // hero/grid: true; Reduce Motion forces a static frame

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Locked silhouettes are a flat fill so only the shape reads (DESIGN_characters §3.4).
    private static let silhouetteColor = Theme.color(0x202036)

    var body: some View {
        Group {
            if animated && !reduceMotion && !silhouette {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    swatchCanvas(t: tl.date.timeIntervalSinceReferenceDate)
                }
            } else {
                swatchCanvas(t: 0)   // single static frame (Reduce Motion / silhouette / grids off-screen)
            }
        }
        .frame(width: size, height: size * 1.5)   // antenna headroom + bob never clips
        .accessibilityHidden(true)                 // containers carry the meaning (name/state labels)
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

        let bodyColor: Color = silhouette ? Self.silhouetteColor : Theme.color(skin.bodyHex)

        // Glow (dropped entirely in silhouette mode).
        if !silhouette {
            let glowColor = skin.followsWorld ? Theme.color(0x00F5FF) : bodyColor
            let glowRect = CGRect(x: center.x - bodyR * 1.6, y: center.y - bodyR * 1.6,
                                  width: bodyR * 3.2, height: bodyR * 3.2)
            ctx.fill(Path(ellipseIn: glowRect),
                     with: .radialGradient(Gradient(colors: [glowColor.opacity(0.45), .clear]),
                                           center: center, startRadius: bodyR * 0.4, endRadius: bodyR * 1.6))
        }

        // Antenna behind the body: stem + tip rotate around the stem base (per-skin sway).
        drawAntenna(&ctx, t: t, center: center, bodyR: bodyR, scale: scale)

        // Body shape: sphere → circle, cube → rounded rect, crystal → vertical diamond.
        let bodyPath = bodyPath(center: center, bodyR: bodyR)
        if silhouette {
            ctx.fill(bodyPath, with: .color(Self.silhouetteColor))
        } else if skin.followsWorld {
            // Prism keeps the rainbow — the chameleon IS its identity.
            ctx.fill(bodyPath, with: .conicGradient(
                Gradient(colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6),
                                  Theme.color(0xFFB13D), Theme.color(0x00F5FF)]),
                center: center))
        } else {
            ctx.fill(bodyPath, with: .color(bodyColor))
        }

        drawEyes(&ctx, t: t, center: center, scale: scale)
    }

    private func bodyPath(center: CGPoint, bodyR: CGFloat) -> Path {
        switch skin.bodyShape {
        case .sphere:
            return Path(ellipseIn: CGRect(x: center.x - bodyR, y: center.y - bodyR,
                                          width: bodyR * 2, height: bodyR * 2))
        case .cube:
            return Path(roundedRect: CGRect(x: center.x - bodyR, y: center.y - bodyR,
                                            width: bodyR * 2, height: bodyR * 2),
                        cornerRadius: size * 0.22 * CGFloat(skin.scale))
        case .crystal:
            // Square rotated 45°, slightly elongated vertically (DESIGN_characters §4.1).
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - bodyR * 1.15))
            p.addLine(to: CGPoint(x: center.x + bodyR * 0.95, y: center.y))
            p.addLine(to: CGPoint(x: center.x, y: center.y + bodyR * 1.15))
            p.addLine(to: CGPoint(x: center.x - bodyR * 0.95, y: center.y))
            p.closeSubpath()
            return p
        }
    }

    private func drawEyes(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint, scale: CGFloat) {
        let eyeY = center.y - size * 0.05 * scale
        let eyeDX = size * 0.19 * scale
        let eyeD = size * 0.2 * CGFloat(skin.eyeRadius / 0.13) * scale

        if silhouette {
            // Eyes drawn closed: two short dark arcs, no sclera.
            for dx in [-eyeDX, eyeDX] {
                var arc = Path()
                arc.addArc(center: CGPoint(x: center.x + dx, y: eyeY),
                           radius: eyeD * 0.4, startAngle: .degrees(20), endAngle: .degrees(160),
                           clockwise: false)
                ctx.stroke(arc, with: .color(Theme.color(0x0A0A14)),
                           style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round))
            }
            return
        }

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

    private func drawAntenna(_ ctx: inout GraphicsContext, t: TimeInterval, center: CGPoint,
                             bodyR: CGFloat, scale: CGFloat) {
        let antennaColor: Color = silhouette
            ? Self.silhouetteColor
            : (skin.followsWorld ? Theme.color(0xFF2BD6) : Theme.color(skin.antennaHex))
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var swatchSize: CGFloat { height * 0.5 }   // menu ≈240 → 120; select 192 → 96 (R5)
    private var discTint: Color {
        skin.followsWorld ? Theme.color(0x00F5FF) : Theme.color(skin.bodyHex)
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ZStack(alignment: .bottom) {
                glowDisc
                    .frame(width: swatchSize * 1.7, height: swatchSize * 0.42)
                    .offset(y: swatchSize * 0.12)
                // Floor reflection at 18% (skipped under Reduce Motion: one Canvas, not two).
                // Offset so the mirrored feet meet the real feet; the stage frame clips the rest.
                if !reduceMotion {
                    AnimatedCharacterSwatch(skin: skin, size: swatchSize)
                        .scaleEffect(x: 1, y: -1)
                        .opacity(0.18)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                        .offset(y: swatchSize)
                }
                AnimatedCharacterSwatch(skin: skin, size: swatchSize)
            }
            .frame(height: swatchSize * 1.5)
            .clipped()
            if showsNamePill { namePill }
        }
        .frame(height: height)
        .accessibilityHidden(true)   // the wrapping button / sibling texts carry the label
    }

    /// Elliptical glow disc tinted by the skin body (slow hue drift for `followsWorld` — the
    /// Prism stage cycles like its body; static under Reduce Motion, per uiux §1.8).
    @ViewBuilder private var glowDisc: some View {
        if skin.followsWorld && !reduceMotion {
            TimelineView(.animation(minimumInterval: 0.2)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8)
                disc.hueRotation(.degrees(t / 8 * 360))
            }
        } else {
            disc
        }
    }

    private var disc: some View {
        Ellipse().fill(
            RadialGradient(colors: [discTint.opacity(0.5), discTint.opacity(0.12), .clear],
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

/// Legacy static swatch (pre-v1.3), moved out of MetaScreenScaffold. Still referenced by
/// ShopView's characters row; the shop reframe replaces it with `AnimatedCharacterSwatch`,
/// after which this shim is deleted (R13 parking lot).
struct CharacterSwatch: View {
    let bodyHex: UInt32
    let antennaHex: UInt32
    let followsWorld: Bool
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            // antenna tip
            Circle()
                .fill(followsWorld ? Color(red: 1, green: 0.17, blue: 0.84) : Theme.color(antennaHex))
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(y: -size * 0.58)
            // body
            ZStack {
                Circle().fill(bodyFill)
                // eyes
                HStack(spacing: size * 0.18) {
                    eye; eye
                }
                .offset(y: -size * 0.05)
            }
            .frame(width: size, height: size)
            .shadow(color: (followsWorld ? Color(red: 0, green: 0.96, blue: 1) : Theme.color(bodyHex)).opacity(0.55), radius: size * 0.18)
        }
        .frame(width: size, height: size * 1.5)
    }

    private var bodyFill: AnyShapeStyle {
        if followsWorld {
            return AnyShapeStyle(AngularGradient(colors: [Theme.color(0x00F5FF), Theme.color(0xFF2BD6), Theme.color(0xFFB13D), Theme.color(0x00F5FF)], center: .center))
        }
        return AnyShapeStyle(Theme.color(bodyHex))
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.2, height: size * 0.2)
            Circle().fill(.black).frame(width: size * 0.09, height: size * 0.09)
        }
    }
}
