import Foundation

/// Every place in the app that reserves space for a character preview, as data.
///
/// **Why this is in `Meta/` and not next to the views that use it.** PR-0312 — 23 of 24
/// characters cropped — survived sixteen sessions because the numbers that caused it were
/// literals scattered across `UI/`, which `Package.swift` does not compile, so no `swift test`
/// could ever see them. A rule that lives only in a view is a rule CI cannot check. These do.
///
/// Since v2.4 the canvas is derived from `CharacterGeometry.rosterExtentInSizeUnits`, so a slot
/// can no longer *clip* a character — it can only be smaller than the drawing, and the drawing
/// then **bleeds** past it. Bleed is usually free and often looks deliberate (a crown crossing a
/// grid gap). It is a problem only where a neighbour sits inside the bleed, so each slot declares
/// what it can afford and `CharacterParityTests` holds it to that.
enum CharacterSwatchSlot: String, CaseIterable, Sendable {
    case selectGrid          // CharacterSelectView — the 24-card shelf
    case selectNextUnlock    // CharacterSelectView — the NEXT UNLOCK spotlight row
    case selectHero          // CharacterSelectView / MenuView — CharacterHeroStage
    case shopRail            // ShopView — the 96x128 mini cards
    case shopFeatured        // ShopView — the featured-offer hero
    case splash              // SplashView

    /// The figure size the site asks for, in points.
    var size: Double {
        switch self {
        case .selectGrid:       return 56
        case .selectNextUnlock: return 36
        case .selectHero:       return 73.92    // height 176 * 0.42
        case .shopRail:         return 42
        case .shopFeatured:     return 52
        case .splash:           return 150
        }
    }

    /// The slot the layout reserves, as multiples of `size` — what the view passes as
    /// `widthScale` / `heightScale`.
    var slot: (width: Double, height: Double) {
        switch self {
        case .selectGrid:       return (1.0, 1.5)
        case .selectNextUnlock: return (Self.tight.width, Self.tight.height)
        case .selectHero:       return (1.6, 1.85)
        case .shopRail:         return (1.0, 1.5)
        case .shopFeatured:     return (Self.tight.width, Self.tight.height)
        case .splash:           return (1.6, 1.85)
        }
    }

    /// How far the drawing may spill past the slot before it lands on a neighbour, in points per
    /// side. Derived from what is actually beside each swatch on screen — not a wish.
    var bleedAllowance: (horizontal: Double, vertical: Double) {
        switch self {
        // Grid cards are >= 104 pt wide around a 56 pt swatch, in a 12 pt-gutter grid, and the
        // card pads 12 pt above the swatch. Spill lands in the gutter, never on another card.
        case .selectGrid:       return (28, 14)
        // Its neighbour is the NEXT UNLOCK text column, ~8 pt away. It gets a tight slot instead.
        case .selectNextUnlock: return (2, 2)
        // The stage is `maxWidth: .infinity` with the name pill below on a Theme.Space.s gap.
        case .selectHero:       return (60, 10)
        // 96 pt cards around a 42 pt swatch, 8 pt apart.
        case .shopRail:         return (26, 12)
        // Its neighbour is the offer's copy column. Tight slot.
        case .shopFeatured:     return (2, 2)
        // Screen-width VStack with Theme.Space.l padding either side.
        case .splash:           return (80, 20)
        }
    }

    /// Slot scales that exactly contain the roster envelope — zero bleed by construction.
    static var tight: (width: Double, height: Double, anchor: Double) {
        let e = CharacterGeometry.rosterExtentInSizeUnits
        return (Double(e.side) * 2, Double(e.up + e.down), Double(e.up / (e.up + e.down)))
    }

    /// How far the drawing actually spills past this slot, per side, in points.
    var bleed: (horizontal: Double, vertical: Double) {
        let e = CharacterGeometry.rosterExtentInSizeUnits
        let canvasW = size * Double(e.side) * 2
        let canvasH = size * Double(e.up + e.down)
        return (max(0, (canvasW - size * slot.width) / 2),
                max(0, (canvasH - size * slot.height) / 2))
    }
}
