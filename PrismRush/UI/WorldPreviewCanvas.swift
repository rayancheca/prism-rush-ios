import SwiftUI

/// A live procedural vignette of a world — a true slice of the renderer's recipe (same palette
/// struct, same decor archetypes) drawn in a SwiftUI Canvas, so the preview is honest: what you
/// tap is what you run (uiux §3.3). v1.4 wave-2 echo: each family carries its in-game WorldSky
/// signature — blinking windows in Metropolis, a hanging crystal fringe in Caverns, twin ringed
/// planets in Sands. Zero binary assets; TimelineView 30 Hz; decor layout comes from a UI-local
/// SplitMix64 seeded by the world index — deterministic per world and never touching run RNG
/// (rule 2 safe). Reduce Motion renders a single static frame (t = 0 freezes the blinks too).
struct WorldPreviewCanvas: View {
    enum PreviewSize { case chip, card, hero }

    let palette: WorldPalette
    let worldIndex: Int
    let size: PreviewSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                vignette(t: 0)                 // static frame — same beauty, zero scroll
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    vignette(t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)             // the wrapping card carries the meaning (uiux §3.3)
    }

    private func vignette(t: TimeInterval) -> some View {
        Canvas { ctx, canvasSize in
            draw(&ctx, t: t, in: canvasSize)
        }
    }

    // MARK: palette helpers

    private var bgColor: Color { Theme.color(palette.bg) }
    private var bgLift: Color {                            // bg × 1.6 — the luminance ramp top
        Theme.color(SIMD3(min(1, palette.bg.x * 1.6), min(1, palette.bg.y * 1.6), min(1, palette.bg.z * 1.6)))
    }
    private var accent: Color { Theme.color(palette.accent) }
    private var accent2: Color { Theme.color(palette.accent2) }
    private var gridColor: Color { Theme.color(palette.grid) }

    // MARK: draw

    private func draw(_ ctx: inout GraphicsContext, t: TimeInterval, in s: CGSize) {
        let w = s.width, h = s.height
        let horizonY = h * 0.42

        // 1. Background + vertical luminance ramp (bg up top, brightest at the horizon line).
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .color(bgColor))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizonY)),
                 with: .linearGradient(Gradient(colors: [bgColor, bgLift]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))

        // 2. Horizon glow: accent ellipse, blurred.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            let glow = CGRect(x: w * 0.06, y: horizonY - h * 0.1, width: w * 0.88, height: h * 0.2)
            layer.fill(Path(ellipseIn: glow), with: .color(accent.opacity(0.25)))
        }

        // 3. Decor silhouettes (2 parallax depths) — archetype keyed by worldIndex % 3.
        if size != .chip {
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(worldIndex)))   // UI-local, cosmetic
            switch ((worldIndex % Theme.worlds.count) + Theme.worlds.count) % Theme.worlds.count {
            case 3:  drawOrbital(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 4:  drawTidal(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 5:  drawAshfall(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 6:  drawBorealis(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 7:  drawDatastream(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 8:  drawBloomfall(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 9:  drawEventide(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 10: drawTempest(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            case 11: drawSingularity(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
            default:
                // Legacy families 0–2 (Pulse City / Geode Deep / Solar Sands).
                switch worldIndex % 3 {
                case 0:  drawTowers(&ctx, rng: &rng, t: t, w: w, h: h, horizonY: horizonY)
                case 1:  drawCrystals(&ctx, rng: &rng, w: w, h: h, horizonY: horizonY)
                default: drawDunes(&ctx, rng: &rng, w: w, h: h, horizonY: horizonY)
                }
            }
        }

        // 4. Three-lane perspective grid scrolling toward the viewer.
        drawGrid(&ctx, t: t, w: w, h: h, horizonY: horizonY)

        // 5. Hero size only: the player slime silhouette in the centre lane.
        if size == .hero { drawSlime(&ctx, w: w, h: h) }
    }

    /// Metropolis: rounded-rect tower clusters with 2×3 window dots, far + near depth bands.
    /// v1.4 (wave-2 echo): the near-tower windows BLINK — each window carries its own phase and
    /// period from the UI-local rng (re-seeded every frame, so the layout never drifts), matching
    /// the in-game WorldSky's blinking facades. t = 0 (Reduce Motion) freezes a deterministic
    /// mixed on/off frame; dark windows stay faintly visible so the skyline never reads broken.
    private func drawTowers(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                            w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        for depth in 0..<2 {
            let far = depth == 0
            let count = far ? 4 : 3
            let alpha = far ? 0.16 : 0.26
            for _ in 0..<count {
                let tw = w * (far ? rng.range(0.06, 0.10) : rng.range(0.09, 0.14))
                let th = h * (far ? rng.range(0.10, 0.18) : rng.range(0.16, 0.28))
                let x = w * rng.range(0.02, 0.92)
                let rect = CGRect(x: x, y: horizonY - th, width: tw, height: th)
                ctx.fill(Path(roundedRect: rect, cornerRadius: tw * 0.18), with: .color(accent.opacity(alpha)))
                guard !far else { continue }
                // 2×3 blinking windows on the near towers (~⅔ lit at any instant).
                for row in 0..<3 {
                    for col in 0..<2 {
                        let phase = rng.range(0, 2 * .pi)
                        let speed = rng.range(0.5, 1.3)
                        let lit = sin(t * speed + phase) > -0.35
                        let d = tw * 0.14
                        let wx = rect.minX + tw * (0.28 + Double(col) * 0.44) - d / 2
                        let wy = rect.minY + th * (0.2 + Double(row) * 0.26) - d / 2
                        ctx.fill(Path(ellipseIn: CGRect(x: wx, y: wy, width: d, height: d)),
                                 with: .color(accent2.opacity(lit ? 0.75 : 0.12)))
                    }
                }
            }
        }
    }

    /// Caverns: triangle crystal clusters — paired floor spikes, ~8° tilt, two depth bands, plus
    /// a hanging crystal fringe along the top edge (wave-2's stalactite ceiling band, echoed) with
    /// accent2 tip glints so the cave reads closed-over like it does in-game.
    private func drawCrystals(_ ctx: inout GraphicsContext, rng: inout SplitMix64,
                              w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Ceiling fringe: 5 crystals hanging into the sky band.
        for _ in 0..<5 {
            let cx = w * rng.range(0.04, 0.96)
            let ch = h * rng.range(0.10, 0.22)
            let tilt = CGFloat(rng.range(-0.12, 0.12))
            var p = Path()
            p.move(to: CGPoint(x: cx - ch * 0.16, y: 0))
            p.addLine(to: CGPoint(x: cx + ch * tilt, y: ch))
            p.addLine(to: CGPoint(x: cx + ch * 0.16, y: 0))
            p.closeSubpath()
            ctx.fill(p, with: .color(accent.opacity(0.28)))
            let glintD = max(2, ch * 0.10)
            ctx.fill(Path(ellipseIn: CGRect(x: cx + ch * tilt - glintD / 2, y: ch - glintD / 2,
                                            width: glintD, height: glintD)),
                     with: .color(accent2.opacity(0.55)))
        }
        for depth in 0..<2 {
            let far = depth == 0
            let alpha = far ? 0.18 : 0.30
            for _ in 0..<(far ? 4 : 3) {
                let cx = w * rng.range(0.05, 0.95)
                let ch = h * (far ? rng.range(0.08, 0.14) : rng.range(0.14, 0.24))
                let tilt = CGFloat(rng.range(-0.14, 0.14))           // ±8°
                for pair in 0..<2 {                                  // paired spikes
                    let px = cx + CGFloat(pair) * ch * 0.34 - ch * 0.17
                    let ph = pair == 0 ? ch : ch * 0.62
                    var p = Path()
                    p.move(to: CGPoint(x: px - ph * 0.22, y: horizonY))
                    p.addLine(to: CGPoint(x: px + ph * tilt, y: horizonY - ph))
                    p.addLine(to: CGPoint(x: px + ph * 0.22, y: horizonY))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(accent.opacity(alpha)))
                }
            }
        }
    }

    /// Sands: overlapping quadratic-curve dunes + ringed planets in the sky (wave-2's WorldSky
    /// floats 2–3; the preview carries two — one big high, one small low — so a single frame
    /// names the world).
    private func drawDunes(_ ctx: inout GraphicsContext, rng: inout SplitMix64,
                           w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Ring planets up in the lifted sky band: sphere fill + flattened ring ellipse each.
        for big in [true, false] {
            let pr = w * (big ? rng.range(0.05, 0.08) : rng.range(0.025, 0.04))
            let pc = CGPoint(x: w * (big ? rng.range(0.6, 0.85) : rng.range(0.10, 0.35)),
                             y: horizonY * (big ? rng.range(0.3, 0.55) : rng.range(0.5, 0.8)))
            let dim = big ? 1.0 : 0.65
            ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                     with: .color(accent.opacity(0.3 * dim)))
            ctx.stroke(Path(ellipseIn: CGRect(x: pc.x - pr * 1.7, y: pc.y - pr * 0.5,
                                              width: pr * 3.4, height: pr)),
                       with: .color(accent2.opacity(0.4 * dim)), lineWidth: max(1, pr * 0.12))
        }
        // Two overlapping dunes hugging the horizon.
        for depth in 0..<2 {
            let far = depth == 0
            let crest = h * (far ? rng.range(0.06, 0.10) : rng.range(0.10, 0.16))
            let apexX = w * rng.range(0.2, 0.8)
            var p = Path()
            p.move(to: CGPoint(x: -w * 0.05, y: horizonY))
            p.addQuadCurve(to: CGPoint(x: w * 1.05, y: horizonY),
                           control: CGPoint(x: apexX, y: horizonY - crest * 2))
            p.closeSubpath()
            ctx.fill(p, with: .color(accent.opacity(far ? 0.16 : 0.24)))
        }
    }

    /// Orbital Drift: a planet limb curving across one horizon side, a small drifting astronaut
    /// (helmet + visor + box suit), and a twinkling starfield — the single-frame signature of the
    /// in-game WorldSky (planet + astronaut + stars), so the card never lies (decree 2).
    private func drawOrbital(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                             w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Stars scattered through the lifted sky band (gentle twinkle via per-star sine).
        for _ in 0..<16 {
            let sx = w * rng.range(0.02, 0.98)
            let sy = horizonY * rng.range(0.06, 0.95)
            let tw = 0.55 + 0.45 * sin(t * rng.range(0.5, 1.6) + rng.range(0, 6.28))
            let d = max(1.2, w * rng.range(0.004, 0.011)) * (t > 0 ? tw : 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - d / 2, y: sy - d / 2, width: d, height: d)),
                     with: .color(accent.opacity(0.85)))
        }
        // Planet limb: a big disc parked low-left, only its upper curve in frame, with a glow rim.
        let pr = w * rng.range(0.30, 0.40)
        let pc = CGPoint(x: w * rng.range(0.08, 0.22), y: horizonY + pr * 0.72)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 1.12, y: pc.y - pr * 1.12,
                                              width: pr * 2.24, height: pr * 2.24)),
                       with: .color(accent.opacity(0.22)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                 with: .color(Theme.color(palette.grid).opacity(0.45)))
        // Astronaut, upper-right: helmet circle + dark visor + box torso + stub limbs.
        let ax = w * rng.range(0.62, 0.82), ay = horizonY * rng.range(0.32, 0.55)
        let hr = w * 0.05
        let suit = accent2.opacity(0.92)
        // torso
        ctx.fill(Path(roundedRect: CGRect(x: ax - hr * 0.85, y: ay + hr * 0.5, width: hr * 1.7, height: hr * 1.9),
                      cornerRadius: hr * 0.4), with: .color(suit))
        // limbs
        for dx in [-hr * 1.05, hr * 1.05] {
            ctx.fill(Path(roundedRect: CGRect(x: ax + dx - hr * 0.28, y: ay + hr * 0.6, width: hr * 0.56, height: hr * 1.3),
                          cornerRadius: hr * 0.25), with: .color(suit))
        }
        // helmet + visor
        ctx.fill(Path(ellipseIn: CGRect(x: ax - hr, y: ay - hr, width: hr * 2, height: hr * 2)), with: .color(suit))
        let vr = hr * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: ax - vr * 0.6, y: ay - vr * 0.5, width: vr * 1.2, height: vr)),
                 with: .color(Theme.color(palette.bg).opacity(0.85)))
    }


    // ===== world 4 TidalSky =====
    /// Tidal Glow: 2–3 bioluminescent jellyfish (dome bell + rim arc + bright core + a swaying
    /// tentacle fan), a couple of very dim light shafts raking down, rising plankton glints, and a
    /// low seabed ridge — the single-frame signature of the in-game WorldSky (jellyfish + plankton +
    /// shafts), so the card never lies (decree 2).
    private func drawTidal(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                           w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Light shafts raking down from the surface (very dim, wide-bottomed wedges).
        for _ in 0..<2 {
            let sx = w * rng.range(0.15, 0.85)
            var p = Path()
            p.move(to: CGPoint(x: sx - w * 0.012, y: 0))
            p.addLine(to: CGPoint(x: sx + w * 0.012, y: 0))
            p.addLine(to: CGPoint(x: sx + w * 0.09, y: horizonY))
            p.addLine(to: CGPoint(x: sx - w * 0.09, y: horizonY))
            p.closeSubpath()
            ctx.fill(p, with: .color(accent.opacity(0.07)))
        }
        // Seabed ridge: a low wavy silhouette hugging the horizon.
        var bed = Path()
        bed.move(to: CGPoint(x: 0, y: horizonY))
        for i in 0...10 {
            let x = w * CGFloat(i) / 10
            let y = horizonY - h * (0.02 + 0.03 * (0.5 + 0.5 * sin(Double(i) * 1.4)))
            bed.addLine(to: CGPoint(x: x, y: y))
        }
        bed.addLine(to: CGPoint(x: w, y: horizonY)); bed.closeSubpath()
        ctx.fill(bed, with: .color(gridColor.opacity(0.22)))
        // Plankton glints rising through the column (gentle twinkle via per-mote sine).
        for _ in 0..<14 {
            let px = w * rng.range(0.02, 0.98)
            let py = horizonY * rng.range(0.1, 0.98)
            let tw = 0.55 + 0.45 * sin(t * rng.range(0.5, 1.2) + rng.range(0, 6.28))
            let d = max(1.2, w * rng.range(0.004, 0.010)) * (t > 0 ? tw : 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)),
                     with: .color(accent.opacity(0.85)))
        }
        // Jellyfish: dome bell + rim arc + bright core + a fan of swaying tentacles.
        for big in [true, false] {
            let br = w * (big ? rng.range(0.10, 0.14) : rng.range(0.06, 0.09))
            let cx = w * (big ? rng.range(0.55, 0.78) : rng.range(0.14, 0.40))
            let cy = horizonY * (big ? rng.range(0.30, 0.5) : rng.range(0.42, 0.68))
            let dim = big ? 1.0 : 0.7
            let bell = accent2.opacity(0.85 * dim)
            // Bell dome: a half-ellipse (flattened sphere) — fill the upper arc.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - br, y: cy - br * 0.7, width: br * 2, height: br * 1.4)),
                     with: .color(bell))
            // Rim arc along the bell's lower edge.
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - br, y: cy + br * 0.2, width: br * 2, height: br * 0.5)),
                       with: .color(accent2.opacity(0.6 * dim)), lineWidth: max(1, br * 0.10))
            // Bright core glow inside the bell.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - br * 0.4, y: cy - br * 0.2, width: br * 0.8, height: br * 0.7)),
                     with: .color(accent.opacity(0.9 * dim)))
            // Tentacle fan: 5 swaying strokes hung down from the rim.
            for k in 0..<5 {
                let fx = cx + br * (CGFloat(k) - 2) * 0.32
                let sway = CGFloat(sin(t * 0.9 + Double(k) + (big ? 0 : 1.7))) * br * 0.22
                var tp = Path()
                tp.move(to: CGPoint(x: fx, y: cy + br * 0.45))
                tp.addQuadCurve(to: CGPoint(x: fx + sway, y: cy + br * 2.1),
                                control: CGPoint(x: fx - sway, y: cy + br * 1.3))
                ctx.stroke(tp, with: .color(accent2.opacity(0.45 * dim)), lineWidth: max(1, br * 0.08))
            }
        }
    }

    // ===== world 5 AshfallSky =====
    /// Ashfall: a dark volcano cone low off-centre with a breathing lava pool at its base, two dim
    /// orange lava seams running flat across the lower sky, fast rising embers, and a jagged ash
    /// ridge banking the horizon — the single-frame signature of the in-game WorldSky (volcano +
    /// lava pool + embers + ridge), so the card never lies (decree 2).
    private func drawAshfall(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                             w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Jagged ash ridge banking the horizon (dim grid-tinted silhouette).
        let segs = 9
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: horizonY))
        for i in 0...segs {
            let u = CGFloat(i) / CGFloat(segs)
            let peak = horizonY * (0.18 + 0.12 * abs(sin(u * 11 + 0.5)))
            ridge.addLine(to: CGPoint(x: w * u, y: horizonY - peak))
        }
        ridge.addLine(to: CGPoint(x: w, y: horizonY)); ridge.closeSubpath()
        ctx.fill(ridge, with: .color(gridColor.opacity(0.22)))

        // Volcano cone: a dark triangle, base at the horizon, off to one side.
        let side = rng.range(0, 1) < 0.5 ? CGFloat(0.30) : CGFloat(0.66)
        let vx = w * side, vBaseY = horizonY, vTop = horizonY - h * 0.30
        let vHalf = w * 0.20
        var cone = Path()
        cone.move(to: CGPoint(x: vx - vHalf, y: vBaseY))
        cone.addLine(to: CGPoint(x: vx - vHalf * 0.32, y: vTop))   // truncated crater rim
        cone.addLine(to: CGPoint(x: vx + vHalf * 0.32, y: vTop))
        cone.addLine(to: CGPoint(x: vx + vHalf, y: vBaseY))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(gridColor.opacity(0.28)))

        // Lava pool at the crater: breathing glow halo + bright amber core.
        let pulse = t > 0 ? 1 + 0.16 * sin(t * 1.3) : 1.0
        let pr = vHalf * 0.30 * pulse
        let pc = CGPoint(x: vx, y: vTop + pr * 0.2)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 1.7, y: pc.y - pr * 1.7,
                                              width: pr * 3.4, height: pr * 3.4)),
                       with: .color(accent.opacity(0.45)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr * 0.7, width: pr * 2, height: pr * 1.4)),
                 with: .color(accent2.opacity(0.92)))

        // Two dim lava seams running flat across the lower sky band.
        for k in 0..<2 {
            let sy = horizonY * (0.70 + 0.14 * CGFloat(k))
            var seam = Path()
            seam.move(to: CGPoint(x: 0, y: sy))
            for i in 0...8 {
                let u = CGFloat(i) / 8
                seam.addLine(to: CGPoint(x: w * u, y: sy + sin(u * 6.5 + CGFloat(k) * 1.7) * h * 0.012))
            }
            ctx.stroke(seam, with: .color(accent.opacity(0.30)), lineWidth: max(1.5, h * 0.012))
        }

        // Rising embers off the cone: fast climb, flicker, fade near the top.
        for _ in 0..<14 {
            let phase = rng.range(0, 1)
            let frac = t > 0 ? (phase + t * rng.range(0.18, 0.32)).truncatingRemainder(dividingBy: 1) : phase
            let ex = vx + CGFloat(rng.range(-0.16, 0.16)) * w
            let ey = vTop - CGFloat(frac) * horizonY * 0.55
            let flick = t > 0 ? 0.55 + 0.45 * sin(t * rng.range(4, 9) + rng.range(0, 6.28)) : 0.8
            let d = max(1.2, w * rng.range(0.004, 0.010)) * flick * (1 - CGFloat(frac) * 0.7)
            ctx.fill(Path(ellipseIn: CGRect(x: ex - d / 2, y: ey - d / 2, width: d, height: d)),
                     with: .color(accent2.opacity(0.9)))
        }
    }

    // ===== world 6 BorealisSky =====
    /// Borealis: aurora curtains (wavy lavender/ice-blue bands high in the sky), a row of standing
    /// ice shards at the horizon (tall diamonds with a faint inner glow), a low snow-plain ridge, and
    /// fine snow drifting downward — the single-frame signature of the in-game WorldSky (decree 2).
    private func drawBorealis(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                              w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Aurora curtains: 3 wavy bands across the upper sky, each sliding + breathing slightly.
        for band in 0..<3 {
            let baseY = horizonY * CGFloat(rng.range(0.18, 0.5))
            let amp = horizonY * CGFloat(rng.range(0.05, 0.10))
            let waves = CGFloat(rng.range(1.3, 1.8))
            let phase = rng.range(0, 6.28)
            let slide = (t > 0 ? sin(t * 0.18 + Double(band)) * w * 0.04 : 0)
            let tint = band % 2 == 0 ? accent2 : accent
            let breathe = t > 0 ? 1 + 0.18 * sin(t * 0.4 + Double(band)) : 1
            var p = Path()
            let steps = 26
            for s in 0...steps {
                let u = CGFloat(s) / CGFloat(steps)
                let x = u * w + CGFloat(slide)
                let y = baseY + amp * breathe * CGFloat(sin(Double(u) * waves * 2 * .pi + phase))
                if s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(p, with: .color(tint.opacity(0.34)),
                       style: StrokeStyle(lineWidth: max(2, h * 0.022), lineCap: .round))
        }
        // Snow plain: a low ridge capping the ground just under the horizon.
        var plain = Path()
        plain.move(to: CGPoint(x: 0, y: horizonY))
        for s in 0...10 {
            let x = w * CGFloat(s) / 10
            plain.addLine(to: CGPoint(x: x, y: horizonY - h * 0.018 - h * 0.012 * CGFloat(sin(Double(s) * 1.3))))
        }
        plain.addLine(to: CGPoint(x: w, y: horizonY)); plain.closeSubpath()
        ctx.fill(plain, with: .color(gridColor.opacity(0.16)))
        // Ice shards: a few tall standing diamonds at the horizon, each with an inner glow dot.
        for _ in 0..<5 {
            let sx = w * rng.range(0.06, 0.94)
            let sh = horizonY * CGFloat(rng.range(0.22, 0.42))
            let sw = sh * 0.18
            var d = Path()
            d.move(to: CGPoint(x: sx, y: horizonY - sh))
            d.addLine(to: CGPoint(x: sx + sw, y: horizonY - sh * 0.5))
            d.addLine(to: CGPoint(x: sx, y: horizonY))
            d.addLine(to: CGPoint(x: sx - sw, y: horizonY - sh * 0.5))
            d.closeSubpath()
            ctx.fill(d, with: .color(accent.opacity(0.32)))
            let gd = max(2, sw * 0.7)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - gd / 2, y: horizonY - sh * 0.5 - gd / 2, width: gd, height: gd)),
                     with: .color(Theme.color(palette.grid).opacity(0.55)))
        }
        // Snowfall: flakes drifting downward through the sky band.
        for _ in 0..<18 {
            let fx = w * rng.range(0.02, 0.98)
            let span = horizonY * 0.9
            let fall = t > 0 ? CGFloat((t * rng.range(8, 18)).truncatingRemainder(dividingBy: Double(span))) : CGFloat(rng.range(0, Double(span)))
            let fy = horizonY * CGFloat(rng.range(0.05, 0.2)) + fall
            let d = max(1.4, w * rng.range(0.004, 0.009))
            ctx.fill(Path(ellipseIn: CGRect(x: fx - d / 2, y: fy.truncatingRemainder(dividingBy: horizonY) - d / 2, width: d, height: d)),
                     with: .color(accent.opacity(0.85)))
        }
    }

    // ===== world 7 DatastreamSky =====
    /// Datastream: a Tron grid wall receding to a glowing vanishing point, a few flickering vertical
    /// pylons, and data motes rising in orderly columns — the single-frame signature of the in-game
    /// WorldSky (grid + vanishing glow + pylons + rising motes), so the card never lies (decree 2).
    private func drawDatastream(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                                w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        let vp = CGPoint(x: w / 2, y: horizonY * 0.18)          // vanishing point, high in the sky band

        // Vanishing-point glow: a dim teal disc that breathes (frozen at t = 0 under Reduce Motion).
        let gp = 1 + 0.12 * sin(t * 0.9)
        let gr = w * 0.16 * (t > 0 ? gp : 1)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.fill(Path(ellipseIn: CGRect(x: vp.x - gr, y: vp.y - gr, width: gr * 2, height: gr * 2)),
                       with: .color(accent.opacity(0.30)))
        }

        // Receding grid wall: verticals fanning from the vanishing point + rungs packing toward it.
        let line = gridColor.opacity(0.34), lw = max(1, w * 0.0035)
        for k in -4...4 {
            var p = Path()
            p.move(to: vp)
            p.addLine(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.16, y: horizonY))
            ctx.stroke(p, with: .color(line), style: StrokeStyle(lineWidth: lw))
        }
        for i in 1...6 {
            let u = CGFloat(i) / 6
            let y = vp.y + (horizonY - vp.y) * (u * u)           // u² → dense near the vanishing point
            let half = w * 0.5 * (0.04 + 0.96 * (u * u))
            var p = Path()
            p.move(to: CGPoint(x: w / 2 - half, y: y))
            p.addLine(to: CGPoint(x: w / 2 + half, y: y))
            ctx.stroke(p, with: .color(line.opacity(0.3 + 0.7 * u)), style: StrokeStyle(lineWidth: lw))
        }

        // Flickering vertical pylons: a sine past a per-pylon threshold (t = 0 → all lit, static).
        for _ in 0..<3 {
            let px = w * rng.range(0.14, 0.86)
            let on = t > 0 ? sin(t * rng.range(1.6, 3.4) + rng.range(0, 6.28)) > rng.range(0, 0.35) : true
            guard on else { continue }
            var p = Path()
            p.move(to: CGPoint(x: px, y: horizonY))
            p.addLine(to: CGPoint(x: px, y: horizonY * rng.range(0.25, 0.5)))
            ctx.stroke(p, with: .color(accent.opacity(0.55)), style: StrokeStyle(lineWidth: max(1.5, w * 0.006), lineCap: .round))
        }

        // Data motes: rise straight up in orderly columns (no sway), looping over a fixed span.
        for col in 0..<6 {
            let cx = w * (0.08 + 0.84 * (Double(col) + 0.5) / 6) + w * rng.range(-0.01, 0.01)
            let span = horizonY * rng.range(0.55, 0.8)
            for row in 0..<3 {
                let off = (Double(row) / 3 + t * rng.range(0.04, 0.09)).truncatingRemainder(dividingBy: 1)
                let my = horizonY - off * span                  // base near horizon, rising toward vp
                let d = max(1.5, w * 0.008)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - d / 2, y: my - d / 2, width: d, height: d)),
                         with: .color(accent2.opacity(0.85)))
            }
        }
    }

    // ===== world 8 BloomfallSky =====
    /// Bloomfall: a cherry-blossom grove at night — ONE pale moon high in the sky behind a faint
    /// halo, soft-pink tree canopies on flattened crowns at the sides, hanging lanterns that softly
    /// glow, a low hill crest, and pink petals drifting downward with a wide sway. The single-frame
    /// signature of the in-game WorldSky (moon + blossom trees + falling petals), so the card never
    /// lies (decree 2). The caller adds the lane grid; this only paints the sky band y∈[0, horizonY].
    private func drawBloomfall(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                               w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        let pink = gridColor                                       // soft-pink grid = blossom hue
        // Moon: one large pale disc high on one side, behind a faint blurred halo (static).
        let mr = w * rng.range(0.10, 0.14)
        let mc = CGPoint(x: w * rng.range(0.62, 0.82), y: horizonY * rng.range(0.22, 0.4))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.fill(Path(ellipseIn: CGRect(x: mc.x - mr * 1.7, y: mc.y - mr * 1.7,
                                              width: mr * 3.4, height: mr * 3.4)),
                       with: .color(accent2.opacity(0.22)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2)),
                 with: .color(accent2.opacity(0.85)))
        // Low hill crest hugging the horizon.
        var hill = Path()
        hill.move(to: CGPoint(x: -w * 0.05, y: horizonY))
        hill.addQuadCurve(to: CGPoint(x: w * 1.05, y: horizonY),
                          control: CGPoint(x: w * rng.range(0.3, 0.7), y: horizonY - h * 0.06))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(pink.opacity(0.14)))
        // Blossom trees at the edges: thin trunk + a flattened soft-pink canopy crown.
        for side in [0.16, 0.84] {
            let tx = w * (side + rng.range(-0.04, 0.04))
            let th = h * rng.range(0.18, 0.26)
            ctx.fill(Path(CGRect(x: tx - w * 0.006, y: horizonY - th, width: w * 0.012, height: th)),
                     with: .color(gridColor.opacity(0.30)))
            let cr = w * rng.range(0.07, 0.10)
            ctx.fill(Path(ellipseIn: CGRect(x: tx - cr, y: horizonY - th - cr * 0.7,
                                            width: cr * 2, height: cr * 1.4)),
                     with: .color(accent.opacity(0.45)))
        }
        // Lanterns: 2 soft warm-gold discs flickering gently between the trees.
        for _ in 0..<2 {
            let lr = w * rng.range(0.018, 0.03)
            let lx = w * rng.range(0.3, 0.7), ly = horizonY * rng.range(0.4, 0.8)
            let f = t > 0 ? 0.85 + 0.15 * sin(t * rng.range(1.4, 2.6) + rng.range(0, 6.28)) : 0.9
            ctx.fill(Path(ellipseIn: CGRect(x: lx - lr, y: ly - lr, width: lr * 2, height: lr * 2)),
                     with: .color(accent2.opacity(0.8 * f)))
        }
        // Falling petals: pink flattened discs drifting down the sky band with a wide sway.
        for _ in 0..<18 {
            let baseX = w * rng.range(0.04, 0.96)
            let speed = rng.range(0.03, 0.07), phase = rng.range(0, 6.28)
            let prog = ((t * speed + phase / 6.28).truncatingRemainder(dividingBy: 1))
            let py = horizonY * (0.05 + 0.9 * prog)
            let px = baseX + CGFloat(sin(t * rng.range(0.6, 1.2) + phase)) * w * 0.04   // wide sway
            let pd = max(1.5, w * rng.range(0.008, 0.014))
            ctx.fill(Path(ellipseIn: CGRect(x: px - pd / 2, y: py - pd * 0.3, width: pd, height: pd * 0.6)),
                     with: .color(pink.opacity(0.7)))
        }
    }

    // ===== world 9 EventideSky =====
    /// Eventide: the edge of a black hole — a near-black disc high + centred, framed by two
    /// flattened accretion rings (magenta + amber) spinning slowly in opposite directions, a thin
    /// scale-pulsing horizon ring, twin vertical polar jets, dim nebula washes, and a twinkling
    /// starfield. The single-frame signature of the in-game WorldSky so the card never lies (decree 2).
    private func drawEventide(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                              w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        let cx = w * 0.5, cy = horizonY * 0.5
        let R = w * 0.16                                   // accretion radius
        // Nebula washes: a few big dim blurred discs behind everything.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            for _ in 0..<3 {
                let nr = w * rng.range(0.18, 0.30)
                let nc = CGPoint(x: w * rng.range(0.1, 0.9), y: horizonY * rng.range(0.1, 0.95))
                layer.fill(Path(ellipseIn: CGRect(x: nc.x - nr, y: nc.y - nr, width: nr * 2, height: nr * 2)),
                           with: .color(accent.opacity(0.10)))
            }
        }
        // Starfield: gentle per-star twinkle.
        for _ in 0..<24 {
            let sx = w * rng.range(0.02, 0.98), sy = horizonY * rng.range(0.04, 0.96)
            let tw = 0.55 + 0.45 * sin(t * rng.range(0.5, 1.6) + rng.range(0, 6.28))
            let d = max(1.2, w * rng.range(0.004, 0.010)) * (t > 0 ? tw : 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - d / 2, y: sy - d / 2, width: d, height: d)),
                     with: .color(accent.opacity(0.85)))
        }
        // Polar jets: two thin vertical beams through the hole centre.
        let jh = R * 2.6, jw = R * 0.28
        ctx.fill(Path(CGRect(x: cx - jw / 2, y: cy - jh, width: jw, height: jh * 2)),
                 with: .color(accent2.opacity(0.35)))
        // Horizon ring (scale-pulsing) + two accretion rings (slowly spinning, flattened ellipses).
        let pulse = 1 + 0.06 * sin(t * 0.7)
        let hRx = R * 1.55 * pulse, hRy = hRx * 0.30
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - hRx, y: cy - hRy, width: hRx * 2, height: hRy * 2)),
                   with: .color(accent.opacity(0.45)), lineWidth: max(1, R * 0.05))
        for (i, ring) in [(R * 1.22, accent2), (R, accent)].enumerated() {
            let rad = ring.0, tilt = (i == 0 ? 1.0 : -1.0) * t * 0.1
            let rx = rad, ry = rad * 0.30
            ctx.translateBy(x: cx, y: cy); ctx.rotate(by: .radians(tilt))
            ctx.stroke(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)),
                       with: .color(ring.1.opacity(0.6)), lineWidth: max(1.5, R * 0.10))
            ctx.rotate(by: .radians(-tilt)); ctx.translateBy(x: -cx, y: -cy)
        }
        // Black hole core: near-black disc (grid-tinted) in front of the rings.
        ctx.fill(Path(ellipseIn: CGRect(x: cx - R * 0.7, y: cy - R * 0.7, width: R * 1.4, height: R * 1.4)),
                 with: .color(Theme.color(palette.grid).opacity(0.55)))
    }

    // ===== world 10 TempestSky =====
    /// Tempest: a dark cloud ridge hanging across the top of the sky, jagged lightning bolts that
    /// strobe on a deterministic (UI-local rng + t) cadence with synced ground-flash + haze pulse,
    /// and fast vertical rain streaks — the single-frame signature of the in-game storm (decree 2).
    /// t = 0 (Reduce Motion) freezes one bolt struck, matching TempestSky's static pose.
    private func drawTempest(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                             w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Haze: a dim accent wash high in the sky that brightens during a flash.
        let band = (t * 0.9).truncatingRemainder(dividingBy: 1)          // sweep 0..1 each ~1.1s
        let flashing = t == 0 || band < 0.06                              // brief strobe window
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizonY * 0.9)),
                       with: .color(accent.opacity(flashing ? 0.22 : 0.08)))
        }
        // Cloud ridges hanging from the top: two lumpy silhouettes (rear dim, near dark + sharp).
        for far in [true, false] {
            let drop = horizonY * (far ? 0.30 : 0.42)
            let lumps = far ? 7 : 6
            var p = Path()
            p.move(to: CGPoint(x: -w * 0.05, y: 0))
            for i in 0...lumps {
                let x = -w * 0.05 + w * 1.1 * CGFloat(i) / CGFloat(lumps)
                let y = drop * (0.55 + 0.45 * CGFloat(rng.range(0.2, 1.0)))
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: w * 1.05, y: 0)); p.closeSubpath()
            ctx.fill(p, with: .color(gridColor.opacity(far ? 0.30 : 0.55)))
        }
        // Lightning: 2-3 zig-zag bolts dropping from the cloud edge; flash together this frame.
        let bolts = 3
        for k in 0..<bolts {
            let bx = w * rng.range(0.15, 0.85)
            let lit = flashing && (t == 0 ? k == 0 : true)
            var seg = CGPoint(x: bx, y: horizonY * 0.34)
            var p = Path(); p.move(to: seg)
            for j in 0..<4 {
                seg = CGPoint(x: seg.x + (j % 2 == 0 ? 1 : -1) * w * 0.045,
                              y: seg.y + horizonY * 0.14)
                p.addLine(to: seg)
            }
            ctx.stroke(p, with: .color(accent2.opacity(lit ? 0.95 : 0.0)),
                       style: StrokeStyle(lineWidth: max(1.5, w * 0.008), lineJoin: .round))
            if lit {                                                     // synced ground-flash disc
                let gr = w * 0.06
                ctx.fill(Path(ellipseIn: CGRect(x: seg.x - gr, y: seg.y - gr * 0.4, width: gr * 2, height: gr * 0.8)),
                         with: .color(accent2.opacity(0.5)))
            }
        }
        // Rain: fast diagonal streaks falling across the storm.
        for _ in 0..<22 {
            let rx = w * rng.range(0.0, 1.0)
            let phase = (t * rng.range(1.4, 2.2) + rng.range(0, 1)).truncatingRemainder(dividingBy: 1)
            let ry = horizonY * CGFloat(t == 0 ? rng.range(0.1, 0.95) : phase)
            let len = h * rng.range(0.05, 0.09)
            var p = Path()
            p.move(to: CGPoint(x: rx, y: ry))
            p.addLine(to: CGPoint(x: rx - w * 0.01, y: ry + len))
            ctx.stroke(p, with: .color(accent.opacity(0.5)), style: StrokeStyle(lineWidth: max(1, w * 0.003)))
        }
    }

    // ===== world 11 SingularitySky =====
    /// Singularity: the white endgame — one radiant white-hot core hangs high and centred on the
    /// deep-violet field, ringed by six concentric spectrum rings (the same fixed rainbow ladder the
    /// 3D sky uses), an eight-spoke ray crown rotating behind it, and a couple of bright flares strung
    /// along one axis. Single-frame signature so the world-select card never lies (decree 2).
    private func drawSingularity(_ ctx: inout GraphicsContext, rng: inout SplitMix64, t: TimeInterval,
                                 w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Core high + centred, with a tiny per-world lateral nudge (cosmetic, UI-local rng).
        let cx = w * (0.5 + rng.range(-0.05, 0.05)), cy = horizonY * rng.range(0.42, 0.55)
        let coreR = w * 0.05
        // Dim wash disc farthest back.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            let wr = coreR * 5
            layer.fill(Path(ellipseIn: CGRect(x: cx - wr, y: cy - wr, width: wr * 2, height: wr * 2)),
                       with: .color(gridColor.opacity(0.16)))
        }
        // Ray crown: eight tapering spokes, the whole crown rotating slowly.
        let spin = t > 0 ? t * 0.06 : 0
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * 2 * .pi + spin
            var p = Path()
            let n = coreR * 0.5, f = coreR * 4.0
            p.move(to: CGPoint(x: cx + cos(a - 0.05) * n, y: cy + sin(a - 0.05) * n))
            p.addLine(to: CGPoint(x: cx + cos(a) * f, y: cy + sin(a) * f))
            p.addLine(to: CGPoint(x: cx + cos(a + 0.05) * n, y: cy + sin(a + 0.05) * n))
            p.closeSubpath()
            ctx.fill(p, with: .color(accent2.opacity(0.22)))
        }
        // Six concentric spectrum rings (fixed rainbow ladder), flattened to ellipses, breathing out.
        let spectrum: [Color] = [.init(red: 1, green: 0.27, blue: 0.45), .init(red: 1, green: 0.7, blue: 0.2),
                                 .init(red: 0.95, green: 0.96, blue: 0.3), .init(red: 0.3, green: 0.95, blue: 0.55),
                                 .init(red: 0.3, green: 0.78, blue: 1), .init(red: 0.7, green: 0.45, blue: 1)]
        for i in 0..<6 {
            let phase = (Double(i) / 6 + (t > 0 ? t * 0.045 : 0)).truncatingRemainder(dividingBy: 1)
            let rr = coreR * (1.2 + CGFloat(phase) * 3.6)
            let fade = 0.55 * (1 - phase)                              // dimmer as it expands out
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr * 0.5, width: rr * 2, height: rr)),
                       with: .color(spectrum[i].opacity(fade)), lineWidth: max(1, coreR * 0.13))
        }
        // Flares strung along one diagonal axis through the core (static).
        let ax = cos(CGFloat(rng.range(-1, 1))), ay = sin(CGFloat(rng.range(-1, 1))) * 0.4
        for i in 1...3 {
            let d = CGFloat(i) * coreR * rng.range(1.4, 2.0)
            let fd = max(2, coreR * (0.5 / CGFloat(i) + 0.18))
            ctx.fill(Path(ellipseIn: CGRect(x: cx + ax * d - fd, y: cy + ay * d - fd, width: fd * 2, height: fd * 2)),
                     with: .color(accent2.opacity(0.7)))
        }
        // Core: bright white-hot heart (accent lifted toward white) + soft halo, drawn last on top.
        let coreC = Color(red: 0.7, green: 0.85, blue: 1.0)           // accent lifted toward white
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            let hr = coreR * 2.2
            layer.fill(Path(ellipseIn: CGRect(x: cx - hr, y: cy - hr, width: hr * 2, height: hr * 2)),
                       with: .color(accent.opacity(0.5)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                 with: .color(coreC))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR * 0.55, y: cy - coreR * 0.55, width: coreR * 1.1, height: coreR * 1.1)),
                 with: .color(.white.opacity(0.95)))
    }

    /// 5 converging verticals + forward-scrolling rungs; centre lane dashed in accent2.
    private func drawGrid(_ ctx: inout GraphicsContext, t: TimeInterval,
                          w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        let vanish = CGPoint(x: w / 2, y: horizonY)
        let lineColor = gridColor.opacity(0.35)
        let lineWidth = max(1, w * 0.004)

        // Verticals: 5 lines fanning from the vanishing point to the bottom edge.
        for k in -2...2 {
            let bottomX = w / 2 + CGFloat(k) * w * 0.30
            var p = Path()
            p.move(to: vanish)
            p.addLine(to: CGPoint(x: bottomX, y: h))
            ctx.stroke(p, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth))
        }

        // Rungs: u² spacing reads as perspective; phase scrolls them slowly toward the viewer.
        let phase = (t / 6).truncatingRemainder(dividingBy: 1)
        let rungs = size == .chip ? 4 : 6
        for i in 0..<rungs {
            let u = ((Double(i) + phase) / Double(rungs))
            let v = CGFloat(u * u)
            let y = horizonY + (h - horizonY) * v
            let halfW = (w / 2) * (0.08 + 0.92 * v) * 1.32        // tracks the outer verticals
            var p = Path()
            p.move(to: CGPoint(x: max(0, w / 2 - halfW), y: y))
            p.addLine(to: CGPoint(x: min(w, w / 2 + halfW), y: y))
            ctx.stroke(p, with: .color(lineColor.opacity(0.25 + 0.75 * u)),
                       style: StrokeStyle(lineWidth: lineWidth))
        }

        // Centre-lane guide, dashed, accent2 at 50%.
        var center = Path()
        center.move(to: vanish)
        center.addLine(to: CGPoint(x: w / 2, y: h))
        ctx.stroke(center, with: .color(accent2.opacity(0.5)),
                   style: StrokeStyle(lineWidth: lineWidth, dash: [4, 5]))
    }

    /// Static player silhouette (rounded rect + eye dots) sitting in the centre lane (hero only).
    private func drawSlime(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let bodyW = h * 0.14
        let body = CGRect(x: w / 2 - bodyW / 2, y: h * 0.74 - bodyW, width: bodyW, height: bodyW)
        ctx.fill(Path(roundedRect: body, cornerRadius: bodyW * 0.3),
                 with: .color(Theme.color(0x0A0A14).opacity(0.85)))
        let eyeD = bodyW * 0.18
        for dx in [-bodyW * 0.2, bodyW * 0.2] {
            ctx.fill(Path(ellipseIn: CGRect(x: body.midX + dx - eyeD / 2,
                                            y: body.midY - bodyW * 0.1 - eyeD / 2,
                                            width: eyeD, height: eyeD)),
                     with: .color(.white.opacity(0.9)))
        }
    }
}
