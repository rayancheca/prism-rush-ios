import SwiftUI

/// Shared chrome for the full-screen meta surfaces (Characters, Shop, Levels, Stats): a back button,
/// a title, a coin balance, and a scrolling content area over a dark gradient.
struct MetaScreenScaffold<Content: View>: View {
    let title: String
    let coins: Int
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                }
                Spacer()
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                CoinBadge(amount: coins)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                content()
                    .padding(16)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255)
                RadialGradient(colors: [Theme.color(0xFF2BD6).opacity(0.16), .clear],
                               center: .top, startRadius: 10, endRadius: 520)
            }.ignoresSafeArea()
        )
    }
}

/// A tiny stylized character preview (body + eyes + antenna tip) used in cards.
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
