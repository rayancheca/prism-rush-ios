#!/usr/bin/env swift
//
// gen_icon.swift — programmatic 1024×1024 App Store icon for PRISM RUSH.
//
// Standalone macOS script. No Xcode project, no UIKit, no binary assets, no text.
// Renders everything in CoreGraphics and writes a fully-opaque PNG via ImageIO.
//
//   Usage:  swift Tools/gen_icon.swift [outputPath]
//   Default output: Store/icon_1024.png
//
// Design: a glowing "prism-slime" character — a cute rounded blob/orb fused with
// an octahedral gem facet motif — floating in a deep void-purple field with a
// soft magenta glow. Neon cyan→magenta→amber gradient body, additive halo,
// and a little antenna with a glowing tip. Bold and readable at small sizes.
//
import Foundation
import CoreGraphics
import ImageIO

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Constants

let kSize: CGFloat = 1024                 // App Store icon edge length (px)
let kCenter = CGPoint(x: kSize / 2, y: kSize / 2)

/// Build an sRGB color from a hex string. Always fully opaque unless `alpha` given.
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Context

// Opaque XRGB bitmap in sRGB — the alpha component is skipped entirely so the
// finished PNG carries NO alpha channel (App Store icons must be fully opaque).
guard let ctx = CGContext(
    data: nil,
    width: Int(kSize), height: Int(kSize),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
) else {
    FileHandle.standardError.write(Data("gen_icon: failed to create bitmap context\n".utf8))
    exit(1)
}
ctx.interpolationQuality = .high

// MARK: - 1. Void-purple background (vertical gradient, fully opaque)

func drawVerticalBackground() {
    let grad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x0A0420), rgb(0x07021A), rgb(0x040010)] as CFArray,
        locations: [0.0, 0.6, 1.0]
    )!
    // Top of image is y = kSize in CG's bottom-left origin.
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: kSize),
        end: CGPoint(x: 0, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

// MARK: - 2. Soft radial magenta glow, centered slightly above middle

func drawBackgroundGlow() {
    ctx.saveGState()
    let glowCenter = CGPoint(x: kCenter.x, y: kCenter.y + kSize * 0.06)
    let grad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0xFF2BD6, 0.55), rgb(0x9A1E8C, 0.22), rgb(0x07021A, 0.0)] as CFArray,
        locations: [0.0, 0.45, 1.0]
    )!
    ctx.drawRadialGradient(
        grad,
        startCenter: glowCenter, startRadius: 0,
        endCenter: glowCenter, endRadius: kSize * 0.62,
        options: []
    )
    ctx.restoreGState()
}

// MARK: - Geometry helpers

/// Octahedral gem facet diamond (pointed top & bottom, wide middle) as a path.
func octahedronPath(center c: CGPoint, halfWidth w: CGFloat, halfHeight h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + h))            // top point
    p.addLine(to: CGPoint(x: c.x + w, y: c.y + h * 0.18)) // right shoulder
    p.addLine(to: CGPoint(x: c.x, y: c.y - h))         // bottom point
    p.addLine(to: CGPoint(x: c.x - w, y: c.y + h * 0.18)) // left shoulder
    p.closeSubpath()
    return p
}

/// Rounded blob/orb body — a slightly squashed orb (the slime).
func blobPath(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let rect = CGRect(x: c.x - r, y: c.y - r * 0.92, width: r * 2, height: r * 1.9)
    return CGPath(roundedRect: rect, cornerWidth: r * 0.78, cornerHeight: r * 0.72, transform: nil)
}

// MARK: - 3. Character: prism-slime silhouette with neon gradient + glow

func neonBodyGradient() -> CGGradient {
    // cyan → magenta → amber, the PRISM RUSH signature ramp.
    CGGradient(
        colorsSpace: space,
        colors: [rgb(0x00F5FF), rgb(0xFF2BD6), rgb(0xFFB13D)] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
}

/// Fill an arbitrary path with the diagonal neon gradient, clipped to that path.
func fillWithNeon(_ path: CGPath, in box: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        neonBodyGradient(),
        start: CGPoint(x: box.minX, y: box.maxY),   // top-left
        end: CGPoint(x: box.maxX, y: box.minY),     // bottom-right
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

func drawCharacter() {
    // ~12% safe margin → character lives within the central ~76%.
    let bodyR = kSize * 0.30
    let bodyCenter = CGPoint(x: kCenter.x, y: kCenter.y - kSize * 0.02)

    // --- Additive outer glow halo (drawn first, behind the body) ---
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    let haloGrad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x00F5FF, 0.5), rgb(0xFF2BD6, 0.35), rgb(0xFF2BD6, 0.0)] as CFArray,
        locations: [0.0, 0.4, 1.0]
    )!
    ctx.drawRadialGradient(
        haloGrad,
        startCenter: bodyCenter, startRadius: bodyR * 0.5,
        endCenter: bodyCenter, endRadius: bodyR * 1.55,
        options: []
    )
    ctx.restoreGState()

    // --- Antenna stalk + glowing tip (behind body so it reads as emerging) ---
    let tip = CGPoint(x: bodyCenter.x + bodyR * 0.04, y: bodyCenter.y + bodyR * 1.32)
    ctx.saveGState()
    ctx.setLineWidth(kSize * 0.016)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0x00F5FF, 0.95))
    ctx.move(to: CGPoint(x: bodyCenter.x, y: bodyCenter.y + bodyR * 0.78))
    ctx.addLine(to: tip)
    ctx.strokePath()
    // Glowing tip dot (additive).
    ctx.setBlendMode(.plusLighter)
    let tipGrad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0xFFFFFF, 0.95), rgb(0x00F5FF, 0.6), rgb(0x00F5FF, 0.0)] as CFArray,
        locations: [0.0, 0.4, 1.0]
    )!
    ctx.drawRadialGradient(
        tipGrad,
        startCenter: tip, startRadius: 0,
        endCenter: tip, endRadius: kSize * 0.05,
        options: []
    )
    ctx.restoreGState()

    // --- Blob body filled with neon gradient ---
    let body = blobPath(center: bodyCenter, radius: bodyR)
    let bodyBox = body.boundingBox
    fillWithNeon(body, in: bodyBox)

    // --- Octahedral gem facet fused into the body core (brighter, additive) ---
    let gem = octahedronPath(
        center: CGPoint(x: bodyCenter.x, y: bodyCenter.y + bodyR * 0.04),
        halfWidth: bodyR * 0.46, halfHeight: bodyR * 0.62
    )
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.addPath(gem)
    ctx.clip()
    let gemGrad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0xFFFFFF, 0.85), rgb(0x00F5FF, 0.55), rgb(0xFF2BD6, 0.35)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    let gemBox = gem.boundingBox
    ctx.drawLinearGradient(
        gemGrad,
        start: CGPoint(x: gemBox.minX, y: gemBox.maxY),
        end: CGPoint(x: gemBox.maxX, y: gemBox.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // --- Facet ridge line down the gem for a crystalline read ---
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.setLineWidth(kSize * 0.006)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.7))
    ctx.move(to: CGPoint(x: bodyCenter.x, y: bodyCenter.y + bodyR * 0.66))
    ctx.addLine(to: CGPoint(x: bodyCenter.x, y: bodyCenter.y - bodyR * 0.58))
    ctx.strokePath()
    ctx.restoreGState()

    // --- Two cute eyes (dark voids) for character ---
    func eye(at p: CGPoint, r: CGFloat) {
        ctx.saveGState()
        ctx.setFillColor(rgb(0x0A0420, 0.92))
        ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fillPath()
        // tiny highlight
        ctx.setBlendMode(.plusLighter)
        ctx.setFillColor(rgb(0xFFFFFF, 0.9))
        let hr = r * 0.32
        ctx.addEllipse(in: CGRect(x: p.x - hr + r * 0.25, y: p.y - hr + r * 0.3, width: hr * 2, height: hr * 2))
        ctx.fillPath()
        ctx.restoreGState()
    }
    let eyeY = bodyCenter.y + bodyR * 0.18
    let eyeR = bodyR * 0.13
    eye(at: CGPoint(x: bodyCenter.x - bodyR * 0.26, y: eyeY), r: eyeR)
    eye(at: CGPoint(x: bodyCenter.x + bodyR * 0.26, y: eyeY), r: eyeR)

    // --- Glossy top-light highlight on the orb (additive) ---
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    let hi = CGPoint(x: bodyCenter.x - bodyR * 0.3, y: bodyCenter.y + bodyR * 0.5)
    let hiGrad = CGGradient(
        colorsSpace: space,
        colors: [rgb(0xFFFFFF, 0.6), rgb(0xFFFFFF, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.addPath(body)
    ctx.clip()
    ctx.drawRadialGradient(
        hiGrad,
        startCenter: hi, startRadius: 0,
        endCenter: hi, endRadius: bodyR * 0.6,
        options: []
    )
    ctx.restoreGState()
}

// MARK: - Compose

drawVerticalBackground()
drawBackgroundGlow()
drawCharacter()

// MARK: - Write PNG via ImageIO

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Store/icon_1024.png"
let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true
)

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("gen_icon: failed to make image\n".utf8))
    exit(1)
}

#if canImport(UniformTypeIdentifiers)
let pngType = UTType.png.identifier as CFString
#else
let pngType = "public.png" as CFString
#endif

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, pngType, 1, nil) else {
    FileHandle.standardError.write(Data("gen_icon: failed to create image destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("gen_icon: failed to finalize PNG\n".utf8))
    exit(1)
}

print("gen_icon: wrote \(outURL.path)")
print("gen_icon: \(image.width)×\(image.height) px, opaque sRGB PNG")

// The shipped springboard icon is a COPY of this output inside the asset catalog. Keep them
// in lockstep: a regeneration that only updated Store/ would silently diverge from the app.
let catalogPath = "PrismRush/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if outPath == "Store/icon_1024.png", FileManager.default.fileExists(atPath: catalogPath) {
    try? FileManager.default.removeItem(atPath: catalogPath)
    do {
        try FileManager.default.copyItem(atPath: outPath, toPath: catalogPath)
        print("gen_icon: synced catalog copy \(catalogPath)")
    } catch {
        FileHandle.standardError.write(Data("gen_icon: FAILED to sync \(catalogPath) — do it manually: \(error)\n".utf8))
        exit(1)
    }
}
