import SwiftUI
import UIKit

/// Screen-space juice driven by the engine's `FXEvent`s: rising score popups (with v1.3 styles
/// for RING / PERFECT / OVERDRIVE / FLOW SURGE / LEVEL UP / NEW CHARACTER), the world banner,
/// and white flash frames. Purely cosmetic and non-interactive.
struct EffectsOverlay: View {
    let model: GameModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(model.popups) { popup in
                    PopupText(popup: popup, size: geo.size)
                }
                BannerView(id: model.bannerID, name: model.bannerName, ordinal: model.bannerOrdinal)
                // Read live in body (G3): the Settings toggle takes effect on the very next flash.
                FlashView(id: model.flashID, strength: model.flashStrength,
                          reduceFlash: ProfileStore.shared.profile.reduceFlash)
                CrackView(id: model.shieldBreakID,
                          reduceFlash: ProfileStore.shared.profile.reduceFlash)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Per-popup presentation, keyed off the popup text so the model stays a plain (text, color)
/// pair: milestone popups (LEVEL UP, NEW CHARACTER) hold longer and announce to VoiceOver;
/// mechanic popups (PERFECT, OVERDRIVE, FLOW SURGE) punch bigger than the +score ticks.
private struct PopupStyle {
    var fontSize: CGFloat = 19
    var tracking: CGFloat = 0
    var rise: CGFloat = 72
    var duration: Double = 0.85
    var glow: CGFloat = 9
    var popScale: CGFloat = 1        // >1 = scale-in entrance
    var announce = false             // VO announcement — milestone class only (chatter discipline)

    static func style(for text: String) -> PopupStyle {
        if text.hasPrefix("LEVEL UP") || text.hasPrefix("NEW CHARACTER") {
            return PopupStyle(fontSize: 24, tracking: 1.5, rise: 48, duration: 1.6, glow: 16,
                              popScale: 1.25, announce: true)
        }
        if text.hasPrefix("FLOW SURGE") || text.hasPrefix("OVERDRIVE") {
            return PopupStyle(fontSize: 22, tracking: 1, rise: 84, duration: 1.1, glow: 13, popScale: 1.15)
        }
        if text.hasPrefix("PERFECT") {
            return PopupStyle(fontSize: 22, tracking: 1, rise: 80, duration: 0.95, glow: 14, popScale: 1.2)
        }
        if text.hasPrefix("RING") {
            return PopupStyle(fontSize: 17, tracking: 0.5, rise: 64, duration: 0.75, glow: 8)
        }
        return PopupStyle()
    }
}

/// A score / bonus popup that rises and fades once, then is pruned by the model.
/// Reduce Motion: no rise, no scale-in — opacity fade only.
private struct PopupText: View {
    let popup: GameModel.Popup
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let style = PopupStyle.style(for: popup.text)
        let x = size.width * (0.5 + popup.worldX / 2.2 * 0.2)
        let y = size.height * 0.52
        Text(popup.text)
            .font(.system(size: style.fontSize, weight: .heavy, design: .rounded))
            .tracking(style.tracking)
            .foregroundStyle(popup.color)
            .shadow(color: popup.color.opacity(0.8), radius: style.glow)
            .scaleEffect(appeared || reduceMotion ? 1 : 1 / style.popScale)
            .position(x: x, y: y - (appeared && !reduceMotion ? style.rise : 0))
            .opacity(appeared ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: style.duration)) { appeared = true }
                if style.announce {
                    UIAccessibility.post(notification: .announcement, argument: popup.text)
                }
            }
    }
}

/// "WORLD N · NAME" banner that pops in, holds, and fades out on each world change.
private struct BannerView: View {
    let id: Int
    let name: String
    let ordinal: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text("WORLD \(ordinal + 1)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.85))
            Text(name)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.5), radius: 22)
        }
        .scaleEffect(shown || reduceMotion ? 1 : 0.82)   // no scale-in pop under Reduce Motion
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("World \(ordinal + 1), \(name)")
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: id) {
            guard id > 0 else { return }
            if reduceMotion { shown = true }   // plain cross-fade, no spring scale
            else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shown = true } }
            try? await Task.sleep(for: .seconds(1.8))
            // A new world change restarts this task mid-sleep; the cancelled instance must not
            // race the fresh one and hide the banner it just showed.
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { shown = false }
        }
    }
}

/// A radial glass-crack overlay that flashes on a shield break, then fades. The crack geometry is
/// deterministic per `id` (a seeded SplitMix64), so it stays stable across the fade's redraws
/// instead of flickering. `reduceFlash` dims it for photosensitivity.
private struct CrackView: View {
    let id: Int
    let reduceFlash: Bool
    @State private var opacity: Double = 0

    var body: some View {
        Canvas { ctx, size in
            guard id > 0 else { return }
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(id)) &* 0x9E37_79B9 ^ 0xC2A6_F00D)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
            let reach = min(size.width, size.height)
            let rays = 12
            for i in 0..<rays {
                let base = Double(i) / Double(rays) * 2 * .pi
                var ang = base + (rng.unit() - 0.5) * 0.4
                let len = reach * (0.45 + rng.unit() * 0.5)
                var pt = center
                var path = Path()
                path.move(to: pt)
                let segs = 4
                for _ in 0..<segs {
                    ang += (rng.unit() - 0.5) * 0.5
                    let step = len / Double(segs)
                    pt = CGPoint(x: pt.x + cos(ang) * step, y: pt.y + sin(ang) * step)
                    path.addLine(to: pt)
                }
                ctx.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1.6)
                ctx.stroke(path, with: .color(Color(red: 0.61, green: 0.94, blue: 1).opacity(0.5)), lineWidth: 0.7)
            }
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .onChange(of: id) {
            opacity = reduceFlash ? 0.2 : 0.95
            withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
        }
    }
}

/// White flash frames on death / shield events. `reduceFlash` (Settings → "Reduce flashing")
/// scales every flash to 0.15× — photosensitivity accommodation, not a binary off.
private struct FlashView: View {
    let id: Int
    let strength: Double
    let reduceFlash: Bool
    @State private var opacity: Double = 0

    var body: some View {
        Color.white
            .opacity(opacity)
            .ignoresSafeArea()
            .onChange(of: id) {
                opacity = strength * (reduceFlash ? 0.15 : 1)
                withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
            }
    }
}
