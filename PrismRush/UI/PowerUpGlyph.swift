import SwiftUI

/// Bespoke procedural power-up glyphs (owner P3 — "custom procedural icons matching the in-world
/// meshes, NOT generic SF Symbols"). One Canvas-drawn vector per power-up, in the power-up's own
/// neon hue, shared by the HUD chips, the deploy buttons, the shop packs, and the PowerUps catalog
/// so every surface shows the SAME identity. Zero binary assets — pure SwiftUI paths.
enum PowerUpKind: String, CaseIterable, Identifiable {
    case shield, magnet, doubler, slowMo, speedUp, sneakers, headStart, coinSurge, overdrive, ring

    var id: String { rawValue }

    /// The power-up's identity hue (matches the in-world mesh + the HUD chip colours).
    var hex: UInt32 {
        switch self {
        case .shield:    0x00F5FF
        case .magnet:    0xFF2BD6
        case .doubler:   0x00FF88
        case .slowMo:    0x9BF0FF
        case .speedUp:   0xFFD23D
        case .sneakers:  0xFF8A2B
        case .headStart: 0xFF9F1C
        case .coinSurge: 0xFFD23D
        case .overdrive: 0xFFD23D
        case .ring:      0x7DF9FF
        }
    }
}

/// Draws one `PowerUp` glyph at `size`, centred, in its hue (override with `tint`). All geometry is
/// normalised to the size so it scales cleanly from a 14 pt HUD chip to a 40 pt catalog tile.
struct PowerUpGlyph: View {
    let kind: PowerUpKind
    var size: CGFloat = 24
    var tint: Color? = nil

    var body: some View {
        Canvas { ctx, cs in
            draw(&ctx, in: cs)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, in cs: CGSize) {
        let color = tint ?? Theme.color(kind.hex)
        let c = CGPoint(x: cs.width / 2, y: cs.height / 2)
        let s = min(cs.width, cs.height)

        func fillTri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint, _ col: Color) {
            var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: d); p.closeSubpath()
            ctx.fill(p, with: .color(col))
        }
        func text(_ str: String, weight: Font.Weight, frac: CGFloat, _ col: Color) {
            let t = Text(str).font(.system(size: s * frac, weight: weight, design: .rounded))
                .foregroundColor(col)
            ctx.draw(ctx.resolve(t), at: c)
        }

        switch kind {
        case .shield:
            var p = Path()
            let w = s * 0.62, h = s * 0.78
            p.move(to: CGPoint(x: c.x - w / 2, y: c.y - h / 2))
            p.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - h / 2))
            p.addLine(to: CGPoint(x: c.x + w / 2, y: c.y + h * 0.08))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h / 2),
                           control: CGPoint(x: c.x + w / 2, y: c.y + h * 0.42))
            p.addQuadCurve(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.08),
                           control: CGPoint(x: c.x - w / 2, y: c.y + h * 0.42))
            p.closeSubpath()
            ctx.fill(p, with: .color(color.opacity(0.28)))
            ctx.stroke(p, with: .color(color), lineWidth: max(1.5, s * 0.07))

        case .magnet:   // horseshoe: thick U opening up, with two banded tips
            var u = Path()
            let w = s * 0.5, top = c.y - s * 0.34, bot = c.y + s * 0.26
            u.move(to: CGPoint(x: c.x - w / 2, y: top))
            u.addLine(to: CGPoint(x: c.x - w / 2, y: bot - w / 2))
            u.addArc(center: CGPoint(x: c.x, y: bot - w / 2), radius: w / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            u.addLine(to: CGPoint(x: c.x + w / 2, y: top))
            ctx.stroke(u, with: .color(color), style: StrokeStyle(lineWidth: s * 0.18, lineCap: .butt))
            for dx in [-w / 2, w / 2] {   // tip bands
                let r = CGRect(x: c.x + dx - s * 0.09, y: top - s * 0.01, width: s * 0.18, height: s * 0.1)
                ctx.fill(Path(r), with: .color(.white.opacity(0.9)))
            }

        case .doubler:
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.36, y: c.y - s * 0.36,
                                              width: s * 0.72, height: s * 0.72)),
                       with: .color(color), lineWidth: max(1.5, s * 0.07))
            text("2×", weight: .black, frac: 0.42, color)

        case .slowMo:   // hourglass
            let w = s * 0.46, h = s * 0.6
            let tl = CGPoint(x: c.x - w / 2, y: c.y - h / 2), tr = CGPoint(x: c.x + w / 2, y: c.y - h / 2)
            let bl = CGPoint(x: c.x - w / 2, y: c.y + h / 2), br = CGPoint(x: c.x + w / 2, y: c.y + h / 2)
            fillTri(tl, tr, c, color)
            fillTri(bl, br, c, color)
            for y in [c.y - h / 2, c.y + h / 2] {   // cap bars
                ctx.fill(Path(CGRect(x: c.x - w / 2 - s * 0.04, y: y - s * 0.04,
                                     width: w + s * 0.08, height: s * 0.08)), with: .color(color))
            }

        case .speedUp:  // fast-forward — two right triangles
            for off in [-s * 0.22, s * 0.06] {
                fillTri(CGPoint(x: c.x + off, y: c.y - s * 0.26),
                        CGPoint(x: c.x + off, y: c.y + s * 0.26),
                        CGPoint(x: c.x + off + s * 0.26, y: c.y), color)
            }

        case .sneakers: // double up-chevron
            for (i, yb) in [c.y + s * 0.12, c.y + s * 0.32].enumerated() {
                _ = i
                var p = Path()
                p.move(to: CGPoint(x: c.x - s * 0.28, y: yb))
                p.addLine(to: CGPoint(x: c.x, y: yb - s * 0.3))
                p.addLine(to: CGPoint(x: c.x + s * 0.28, y: yb))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round, lineJoin: .round))
            }

        case .headStart: // forward burst — bold chevron + speed lines
            var p = Path()
            p.move(to: CGPoint(x: c.x - s * 0.02, y: c.y - s * 0.28))
            p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y))
            p.addLine(to: CGPoint(x: c.x - s * 0.02, y: c.y + s * 0.28))
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round, lineJoin: .round))
            for (i, y) in [c.y - s * 0.16, c.y, c.y + s * 0.16].enumerated() {
                let len = s * (0.18 - CGFloat(i % 2) * 0.06)
                var line = Path()
                line.move(to: CGPoint(x: c.x - s * 0.34, y: y))
                line.addLine(to: CGPoint(x: c.x - s * 0.34 + len, y: y))
                ctx.stroke(line, with: .color(color.opacity(0.7)),
                           style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            }

        case .coinSurge: // coin with an up-arrow
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.36, y: c.y - s * 0.36,
                                              width: s * 0.72, height: s * 0.72)),
                       with: .color(color), lineWidth: max(1.5, s * 0.07))
            var arrow = Path()
            arrow.move(to: CGPoint(x: c.x, y: c.y - s * 0.22))
            arrow.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.2))
            arrow.move(to: CGPoint(x: c.x - s * 0.14, y: c.y - s * 0.06))
            arrow.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.22))
            arrow.addLine(to: CGPoint(x: c.x + s * 0.14, y: c.y - s * 0.06))
            ctx.stroke(arrow, with: .color(color),
                       style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round, lineJoin: .round))

        case .overdrive: // lightning bolt
            var p = Path()
            p.move(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.34))
            p.addLine(to: CGPoint(x: c.x - s * 0.22, y: c.y + s * 0.06))
            p.addLine(to: CGPoint(x: c.x - s * 0.02, y: c.y + s * 0.06))
            p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y + s * 0.34))
            p.addLine(to: CGPoint(x: c.x + s * 0.22, y: c.y - s * 0.08))
            p.addLine(to: CGPoint(x: c.x + s * 0.02, y: c.y - s * 0.08))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))

        case .ring:     // prism-ring torus — concentric ring
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.34, y: c.y - s * 0.34,
                                              width: s * 0.68, height: s * 0.68)),
                       with: .color(color), lineWidth: max(2, s * 0.1))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.16, y: c.y - s * 0.16,
                                              width: s * 0.32, height: s * 0.32)),
                       with: .color(color.opacity(0.5)), lineWidth: max(1, s * 0.05))
        }
    }
}
