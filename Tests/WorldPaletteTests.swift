import XCTest
@testable import PrismRush

/// v1.5 world-palette guards. Lives directly under `Tests/` (NOT `Tests/CoreTests/`) so only the
/// Mac app test target compiles it — it references `Theme` (UI), which the Linux SPM Core package
/// does not build. Pins the two invariants the 12-world expansion must hold.
final class WorldPaletteTests: XCTestCase {

    /// C2 regression guard: worlds 0–11 are cycle 0 — strict identity to their authored palettes,
    /// no roman-numeral suffix and no hue rotation. (If the cycle divisor ever drifts back to /3,
    /// world 3 would render as "Orbital Drift II" with a shifted hue on first sight.)
    func testWorlds0to11AreCycleZeroIdentity() {
        for o in 0..<Theme.worlds.count {
            let evolved = Theme.evolvedPalette(ordinal: o)
            let base = Theme.worlds[o]
            XCTAssertEqual(evolved.name, base.name,
                           "world \(o) must keep its authored name at cycle 0 (got '\(evolved.name)')")
            XCTAssertEqual(evolved.bg, base.bg, "world \(o) bg must equal the authored palette at cycle 0")
            XCTAssertEqual(evolved.grid, base.grid, "world \(o) grid must equal the authored palette at cycle 0")
            XCTAssertEqual(evolved.accent, base.accent, "world \(o) accent must equal the authored palette at cycle 0")
            XCTAssertEqual(evolved.accent2, base.accent2, "world \(o) accent2 must equal the authored palette at cycle 0")
        }
    }

    /// Evolution only begins past the authored set (ordinal ≥ worlds.count = cycle 1).
    func testEvolutionBeginsAfterTheAuthoredSet() {
        let firstEvolved = Theme.evolvedPalette(ordinal: Theme.worlds.count)   // "Pulse City II"
        XCTAssertTrue(firstEvolved.name.hasSuffix(" II"),
                      "ordinal worlds.count must be cycle 1 with a roman suffix (got '\(firstEvolved.name)')")
        XCTAssertEqual(firstEvolved.name.replacingOccurrences(of: " II", with: ""), Theme.worlds[0].name)
    }

    /// `Core/` mirrors the world count as `Tuning.worldFamilyCount` (it can't import the UI `Theme`).
    /// Pin them equal so a future 13th world can't silently desync the world-family modulus.
    func testCoreFamilyCountMatchesPaletteCount() {
        XCTAssertEqual(Tuning.worldFamilyCount, Theme.worlds.count,
                       "Tuning.worldFamilyCount must equal Theme.worlds.count")
    }

    /// The owner's loop-break: every authored world is a distinct identity (no two share a name
    /// or a background).
    func testAllTwelveWorldsAreDistinct() {
        XCTAssertEqual(Theme.worlds.count, 12)
        XCTAssertEqual(Set(Theme.worlds.map(\.name)).count, 12, "world names must be unique")
        XCTAssertEqual(Set(Theme.worlds.map { "\($0.bg)" }).count, 12, "world backgrounds must be unique")
    }
}
