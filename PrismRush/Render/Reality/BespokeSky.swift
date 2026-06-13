import RealityKit

/// A v1.5 bespoke world sky family: a self-contained set of far-background set pieces (its own
/// entities + build/restyle/animate) that `WorldSky` enables and drives. Each lives in its own file
/// mirroring `OrbitalSky` — build geometry once, recycle by `restyle` at a world boundary, write
/// only transforms + `isEnabled` per frame, deterministic from a LOCAL SplitMix64 (never the run
/// RNG), Reduce-Motion-gated. Conformance is retroactive: every family already matches this shape,
/// so `WorldSky` can hold them in one `[any BespokeSky]` indexed by `world ordinal − 3`.
@MainActor protocol BespokeSky: AnyObject {
    var root: Entity { get }
    func restyle(palette pal: WorldPalette, world: Int)
    func animate(elapsed: Double, reduceMotion: Bool)
}

extension OrbitalSky: BespokeSky {}
extension TidalSky: BespokeSky {}
extension AshfallSky: BespokeSky {}
extension BorealisSky: BespokeSky {}
extension DatastreamSky: BespokeSky {}
extension BloomfallSky: BespokeSky {}
extension EventideSky: BespokeSky {}
extension TempestSky: BespokeSky {}
extension SingularitySky: BespokeSky {}
