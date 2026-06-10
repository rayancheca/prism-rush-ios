import Foundation

/// Tiny numeric helpers shared across the deterministic core. Foundation only.
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
@inline(__always) func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
