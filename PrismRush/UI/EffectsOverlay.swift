import SwiftUI

/// Screen-space juice driven by the engine's `FXEvent`s: rising score popups, the world banner,
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
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A score / bonus popup that rises and fades once, then is pruned by the model.
private struct PopupText: View {
    let popup: GameModel.Popup
    let size: CGSize
    @State private var appeared = false

    var body: some View {
        let x = size.width * (0.5 + popup.worldX / 2.2 * 0.2)
        let y = size.height * 0.52
        Text(popup.text)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundStyle(popup.color)
            .shadow(color: popup.color.opacity(0.8), radius: 9)
            .position(x: x, y: y - (appeared ? 72 : 0))
            .opacity(appeared ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.85)) { appeared = true } }
    }
}

/// "WORLD N · NAME" banner that pops in, holds, and fades out on each world change.
private struct BannerView: View {
    let id: Int
    let name: String
    let ordinal: Int
    @State private var shown = false

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
        .scaleEffect(shown ? 1 : 0.82)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 150)
        .task(id: id) {
            guard id > 0 else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { shown = true }
            try? await Task.sleep(for: .seconds(1.8))
            // A new world change restarts this task mid-sleep; the cancelled instance must not
            // race the fresh one and hide the banner it just showed.
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { shown = false }
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
