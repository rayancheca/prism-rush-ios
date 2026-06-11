import SwiftUI

/// A small gold coin glyph + amount, reused across the HUD, menu, game-over and shop.
/// The amount rolls with a numeric content transition (premium feel) and reads as
/// "N coins" to VoiceOver. v1.3: optionally tappable (`action` → Shop everywhere, uiux §5);
/// the default keeps every existing call site compiling as a display-only badge (R13).
struct CoinBadge: View {
    let amount: Int
    var prefix: String = ""
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.neon)
                .accessibilityLabel(a11yLabel)
                .accessibilityHint("Opens the shop")
        } else {
            label
                .accessibilityLabel(a11yLabel)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            CoinGlyph(size: 16)
            Text("\(prefix)\(amount)")
                .monospacedDigit()
                .fontWeight(.bold)
                .contentTransition(.numericText(value: Double(amount)))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: amount)
        .accessibilityElement(children: .ignore)
    }

    private var a11yLabel: String {
        "\(prefix.isEmpty ? "" : prefix + " ")\(amount) coins"
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
