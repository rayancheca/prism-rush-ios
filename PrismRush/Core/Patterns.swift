import Foundation

/// A single thing a pattern asks the spawner to place, at an absolute world distance `d`.
enum SpawnCmd: Sendable, Equatable {
    case low(d: Double, lane: Int)
    case tall(d: Double, lane: Int)
    case movingTall(d: Double, phase: Double)
    case bar(d: Double)
    case gem(d: Double, lane: Int, y: Double)
    case shield(d: Double, lane: Int)
    case magnet(d: Double, lane: Int)
}

/// The 11-pattern catalogue, ported verbatim from the shipped Three.js prototype.
/// Every pattern is provably solvable (see `SolvabilityBotTests`). Each function appends its
/// spawns to `out` and returns its length (used by the spawner to advance the cursor).
enum Patterns {
    static let count = 11

    // MARK: helpers (mirror the prototype's gemLine / gemArc / otherLanes)

    private static func gemLine(_ d: Double, _ lane: Int, _ n: Int, _ out: inout [SpawnCmd]) {
        for i in 0..<n { out.append(.gem(d: d + Double(i) * 1.7, lane: lane, y: 0.8)) }
    }

    private static func gemArc(_ d: Double, _ lane: Int, _ out: inout [SpawnCmd]) {
        for i in 0..<7 {
            let t = Double(i) / 6
            let y = 0.8 + sin(t * .pi) * 1.5
            out.append(.gem(d: d + Double(i) * 1.25, lane: lane, y: y))
        }
    }

    private static func otherLanes(_ l: Int) -> [Int] { [0, 1, 2].filter { $0 != l } }

    // MARK: dispatch

    /// Run pattern `idx` (0-based) at `base`, returning its length.
    static func run(_ idx: Int, base b: Double, rng: inout SplitMix64, out: inout [SpawnCmd]) -> Double {
        switch idx {
        case 0:  // gem line, random lane
            gemLine(b, rng.int(0, 2), 6, &out); return 14

        case 1:  // one low + gem arc over it
            let l = rng.int(0, 2)
            out.append(.low(d: b + 6, lane: l)); gemArc(b + 2.2, l, &out); return 16

        case 2:  // triple low across all lanes, arc over center → forces jump
            out.append(.low(d: b + 6, lane: 0)); out.append(.low(d: b + 6, lane: 1)); out.append(.low(d: b + 6, lane: 2))
            gemArc(b + 2.2, 1, &out); return 18

        case 3:  // twin talls, gems in the free lane → forces weave
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 7, lane: o[0])); out.append(.tall(d: b + 7, lane: o[1]))
            gemLine(b + 1, free, 5, &out); return 18

        case 4:  // bar + low gem line after → forces slide
            out.append(.bar(d: b + 7)); gemLine(b + 10, rng.int(0, 2), 5, &out); return 20

        case 5:  // tall zigzag x3, alternating lanes, weaving gem trails
            let l1 = rng.int(0, 2)
            let l2 = rng.pick(otherLanes(l1))
            let l3 = rng.pick(otherLanes(l2))
            out.append(.tall(d: b + 5, lane: l1)); out.append(.tall(d: b + 14, lane: l2)); out.append(.tall(d: b + 23, lane: l3))
            gemLine(b + 8, l2 == 0 ? 1 : l2 - 1, 3, &out)
            gemLine(b + 17, l3 == 0 ? 1 : l3 - 1, 3, &out); return 30

        case 6:  // tall + low + low mixed row, arc over the free low
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.low(d: b + 6, lane: o[1])); out.append(.low(d: b + 6, lane: free))
            gemArc(b + 2, free, &out); return 18

        case 7:  // twin talls, then shield OR magnet (50/50) in the free lane
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.tall(d: b + 6, lane: o[1]))
            if rng.chance(0.5) { out.append(.shield(d: b + 13, lane: free)) } else { out.append(.magnet(d: b + 13, lane: free)) }
            return 18

        case 8:  // double bar 9 apart
            out.append(.bar(d: b + 6)); out.append(.bar(d: b + 15)); gemLine(b + 18, 1, 4, &out); return 24

        case 9:  // gauntlet: twin talls → bar → triple low, arc + line rewards
            let free = rng.int(0, 2); let o = otherLanes(free)
            out.append(.tall(d: b + 6, lane: o[0])); out.append(.tall(d: b + 6, lane: o[1]))
            out.append(.bar(d: b + 15))
            out.append(.low(d: b + 24, lane: 0)); out.append(.low(d: b + 24, lane: 1)); out.append(.low(d: b + 24, lane: 2))
            gemArc(b + 20, free, &out); gemLine(b + 27, free, 4, &out); return 34

        case 10: // moving walls x2, gem lines between
            out.append(.movingTall(d: b + 9, phase: rng.range(0, 6.28))); gemLine(b + 1, 0, 3, &out)
            out.append(.movingTall(d: b + 22, phase: rng.range(0, 6.28))); gemLine(b + 14, 2, 3, &out); return 32

        default:
            return 14
        }
    }
}
