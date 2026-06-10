import Foundation

/// Deterministic SplitMix64 PRNG. Seed fully determines every run — this is what makes the
/// spawner reproducible and the test suite (solvability bot, run hashing) possible.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in [0, 1) using the top 53 bits (full mantissa).
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform Double in [a, b).
    mutating func range(_ a: Double, _ b: Double) -> Double { a + unit() * (b - a) }

    /// Uniform Int in [a, b] inclusive (matches the prototype's `ri`).
    mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(unit() * Double(b - a + 1)) }

    /// Uniform element (matches the prototype's `pick`).
    mutating func pick<T>(_ arr: [T]) -> T { arr[Int(unit() * Double(arr.count))] }

    /// True with probability `p`.
    mutating func chance(_ p: Double) -> Bool { unit() < p }
}
