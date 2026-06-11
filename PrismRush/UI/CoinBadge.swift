import SwiftUI

/// A small gold coin glyph + amount, reused across the HUD, menu, game-over and shop.
/// The amount rolls with a numeric content transition (premium feel) and reads as
/// "N coins" to VoiceOver.
struct CoinBadge: View {
    let amount: Int
    var prefix: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            CoinGlyph(size: 16)
            Text("\(prefix)\(amount)")
                .monospacedDigit()
                .fontWeight(.bold)
                .contentTransition(.numericText(value: Double(amount)))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prefix.isEmpty ? "" : prefix + " ")\(amount) coins")
    }
}

struct CoinGlyph: View {
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.34), Color(red: 0.95, green: 0.62, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(.white.opacity(0.45), lineWidth: max(1, size * 0.06))
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5), radius: size * 0.3)
        .accessibilityHidden(true)
    }
}
