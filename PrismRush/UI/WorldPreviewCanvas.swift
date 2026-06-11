import SwiftUI

/// A live procedural vignette of a world — a true slice of the renderer's recipe (same palette
/// struct, same decor archetypes) drawn in a SwiftUI Canvas, so the preview is honest: what you
/// tap is what you run (uiux §3.3). Zero binary assets; TimelineView 30 Hz; decor layout comes
/// from a UI-local SplitMix64 seeded by the world index — deterministic per world and never
/// touching run RNG (rule 2 safe). Reduce Motion renders a single static frame.
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
            switch worldIndex % 3 {
            case 0:  drawTowers(&ctx, rng: &rng, w: w, h: h, horizonY: horizonY)
            case 1:  drawCrystals(&ctx, rng: &rng, w: w, h: h, horizonY: horizonY)
            default: drawDunes(&ctx, rng: &rng, w: w, h: h, horizonY: horizonY)
            }
        }

        // 4. Three-lane perspective grid scrolling toward the viewer.
        drawGrid(&ctx, t: t, w: w, h: h, horizonY: horizonY)

        // 5. Hero size only: the player slime silhouette in the centre lane.
        if size == .hero { drawSlime(&ctx, w: w, h: h) }
    }

    /// Metropolis: rounded-rect tower clusters with 2×3 lit-window dots, far + near depth bands.
    private func drawTowers(_ ctx: inout GraphicsContext, rng: inout SplitMix64,
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
                // 2×3 lit windows on the near towers.
                for row in 0..<3 {
                    for col in 0..<2 {
                        let d = tw * 0.14
                        let wx = rect.minX + tw * (0.28 + Double(col) * 0.44) - d / 2
                        let wy = rect.minY + th * (0.2 + Double(row) * 0.26) - d / 2
                        ctx.fill(Path(ellipseIn: CGRect(x: wx, y: wy, width: d, height: d)),
                                 with: .color(accent2.opacity(0.7)))
                    }
                }
            }
        }
    }

    /// Caverns: triangle crystal clusters — paired spikes, ~8° tilt, two depth bands.
    private func drawCrystals(_ ctx: inout GraphicsContext, rng: inout SplitMix64,
                              w: CGFloat, h: CGFloat, horizonY: CGFloat) {
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

    /// Sands: overlapping quadratic-curve dunes + one ring-planet circle in the sky.
    private func drawDunes(_ ctx: inout GraphicsContext, rng: inout SplitMix64,
                           w: CGFloat, h: CGFloat, horizonY: CGFloat) {
        // Ring planet up in the lifted sky band.
        let pr = w * rng.range(0.05, 0.08)
        let pc = CGPoint(x: w * rng.range(0.6, 0.85), y: horizonY * rng.range(0.3, 0.55))
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                 with: .color(accent.opacity(0.3)))
        ctx.stroke(Path(ellipseIn: CGRect(x: pc.x - pr * 1.7, y: pc.y - pr * 0.5,
                                          width: pr * 3.4, height: pr)),
                   with: .color(accent2.opacity(0.4)), lineWidth: max(1, pr * 0.12))
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
