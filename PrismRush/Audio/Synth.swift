import Foundation

/// Pure DSP: synthesizes raw `[Float]` sample buffers for every SFX and music voice. No AVAudio
/// dependency, so it's unit-testable and renderable to WAV offline. All synthesis is additive into
/// a buffer; `SynthEngine` wraps the results into `AVAudioPCMBuffer`s.
enum Synth {
    static let sampleRate: Float = 44_100

    enum Wave { case sine, square, saw, triangle }

    /// An oscillator with an exponential frequency ramp (`f0`→`f1`) and exponential amplitude decay,
    /// summed into `buf` starting at sample `offset`.
    static func tone(_ buf: inout [Float], _ f0: Float, _ f1: Float, dur: Float, _ type: Wave, vol: Float, offset: Int = 0) {
        let n = Int(dur * sampleRate)
        let a = max(f0, 1), b = max(f1, 1)
        var phase: Float = 0
        for i in 0..<n {
            let idx = offset + i
            if idx >= buf.count { break }
            let frac = Float(i) / Float(n)
            let f = a * pow(b / a, frac)
            phase += f / sampleRate
            if phase >= 1 { phase -= 1 }
            let s: Float
            switch type {
            case .sine: s = sin(2 * .pi * phase)
            case .square: s = phase < 0.5 ? 1 : -1
            case .saw: s = 2 * phase - 1
            case .triangle: s = 4 * abs(phase - 0.5) - 1
            }
            buf[idx] += s * vol * expf(-4 * frac)
        }
    }

    /// Filtered noise burst (one-pole low/high pass) with a linear decay — or a linear swell when
    /// `swell` is set (whooshes that build instead of die) — summed into `buf`.
    static func noise(_ buf: inout [Float], dur: Float, vol: Float, cutoff: Float, highpass: Bool = false, swell: Bool = false, offset: Int = 0, seed: UInt32 = 0x1234_5678) {
        let n = Int(dur * sampleRate)
        var rng = seed
        var lp: Float = 0
        let coeff = min(0.99, cutoff / (cutoff + sampleRate / (2 * .pi)))
        for i in 0..<n {
            let idx = offset + i
            if idx >= buf.count { break }
            rng = rng &* 1_664_525 &+ 1_013_904_223
            let white = Float(rng >> 8) / Float(0xFF_FFFF) * 2 - 1
            lp += coeff * (white - lp)
            let sample = highpass ? (white - lp) : lp
            let frac = Float(i) / Float(n)
            buf[idx] += sample * vol * (1 - frac)
        }
    }

    static func blank(_ dur: Float) -> [Float] { [Float](repeating: 0, count: Int(dur * sampleRate)) }

    /// MIDI note → frequency.
    static func freq(_ midi: Int) -> Float { 440 * pow(2, Float(midi - 69) / 12) }

    // MARK: SFX (route through sfxGain)

    /// Per-streak pitch ratio. 1.08 ≈ a bit over a semitone, so each gem in a chain is an audible
    /// step up the ladder (the prototype's 1.045 was barely perceptible).
    static let gemPitchStep: Float = 1.08

    static func gem(streak: Int) -> [Float] {
        let f = 560 * pow(gemPitchStep, Float(streak % 26))
        var b = blank(0.10)
        tone(&b, f, f * 1.5, dur: 0.09, .square, vol: 0.16)
        return b
    }

    static func jump() -> [Float] {
        var b = blank(0.18); tone(&b, 260, 560, dur: 0.16, .sine, vol: 0.22); return b
    }

    static func slide() -> [Float] {
        var b = blank(0.16)
        noise(&b, dur: 0.13, vol: 0.20, cutoff: 600)        // louder, deeper whoosh
        tone(&b, 180, 120, dur: 0.12, .sine, vol: 0.10)     // percussive low "thud" anchor
        return b
    }

    static func crash() -> [Float] {
        var b = blank(0.46)
        noise(&b, dur: 0.4, vol: 0.5, cutoff: 900)
        tone(&b, 320, 60, dur: 0.45, .saw, vol: 0.3)
        return b
    }

    static func chime() -> [Float] {
        var b = blank(0.28)
        tone(&b, 700, 1200, dur: 0.2, .triangle, vol: 0.25)
        tone(&b, 900, 1500, dur: 0.25, .sine, vol: 0.18)
        return b
    }

    static func shieldChime() -> [Float] {            // rising triad — protective, uplifting
        var b = blank(0.42)
        tone(&b, 660, 680, dur: 0.12, .sine, vol: 0.17)
        tone(&b, 880, 900, dur: 0.12, .sine, vol: 0.17, offset: Int(0.09 * sampleRate))
        tone(&b, 1320, 1340, dur: 0.20, .triangle, vol: 0.16, offset: Int(0.18 * sampleRate))
        return b
    }

    static func magnetChime() -> [Float] {            // descending arpeggio — a magnetic pull
        var b = blank(0.42)
        tone(&b, 1180, 1160, dur: 0.10, .triangle, vol: 0.16)
        tone(&b, 920, 900, dur: 0.10, .triangle, vol: 0.16, offset: Int(0.09 * sampleRate))
        tone(&b, 700, 680, dur: 0.18, .sine, vol: 0.16, offset: Int(0.18 * sampleRate))
        return b
    }

    static func worldSweep() -> [Float] {
        var b = blank(0.72)
        tone(&b, 220, 880, dur: 0.7, .saw, vol: 0.12)
        tone(&b, 330, 1320, dur: 0.7, .sine, vol: 0.08)
        return b
    }

    static func close() -> [Float] {
        var b = blank(0.08); tone(&b, 880, 1400, dur: 0.07, .sine, vol: 0.12); return b
    }

    static func startChime() -> [Float] {
        var b = blank(0.27); tone(&b, 440, 880, dur: 0.25, .triangle, vol: 0.2); return b
    }

    static func laneTick() -> [Float] {               // tiny blip so lane changes register
        var b = blank(0.04); tone(&b, 300, 360, dur: 0.04, .sine, vol: 0.08); return b
    }

    static func landThud() -> [Float] {               // hard-landing thump: pitch-drop + dust tick
        var b = blank(0.14)
        tone(&b, 150, 46, dur: 0.13, .sine, vol: 0.30)
        noise(&b, dur: 0.05, vol: 0.10, cutoff: 800)
        return b
    }

    static func purchaseChime() -> [Float] {          // rising major triad — money well spent
        var b = blank(0.50)
        tone(&b, 523, 525, dur: 0.16, .triangle, vol: 0.16)
        tone(&b, 659, 661, dur: 0.16, .triangle, vol: 0.16, offset: Int(0.10 * sampleRate))
        tone(&b, 784, 788, dur: 0.26, .triangle, vol: 0.17, offset: Int(0.20 * sampleRate))
        tone(&b, 1046, 1050, dur: 0.22, .sine, vol: 0.10, offset: Int(0.26 * sampleRate))
        return b
    }

    static func equipClick() -> [Float] {             // snappy mechanical click for equipping a skin
        var b = blank(0.06)
        tone(&b, 1800, 900, dur: 0.03, .square, vol: 0.07)
        noise(&b, dur: 0.025, vol: 0.06, cutoff: 3000, highpass: true)
        return b
    }

    static func uiTick() -> [Float] {                 // soft blip for sheet open/close
        var b = blank(0.05); tone(&b, 660, 880, dur: 0.045, .triangle, vol: 0.07); return b
    }

    static func newBestFanfare() -> [Float] {         // quick triumphant arp + held top note
        var b = blank(0.75)
        let arp: [Float] = [523, 659, 784, 1046]
        for (i, f) in arp.enumerated() {
            tone(&b, f, f * 1.01, dur: 0.14, .square, vol: 0.10, offset: Int(Float(i) * 0.11 * sampleRate))
        }
        tone(&b, 1046, 1052, dur: 0.30, .triangle, vol: 0.14, offset: Int(0.44 * sampleRate))
        return b
    }

    static func deathSweep() -> [Float] {             // long fall: saw dive + noise swelling under it
        var b = blank(0.92)
        tone(&b, 660, 55, dur: 0.90, .saw, vol: 0.18)
        noise(&b, dur: 0.88, vol: 0.24, cutoff: 900, swell: true)
        return b
    }

    static func doublerPickup() -> [Float] {          // coin-y double chime — ×2 means two
        var b = blank(0.30)
        tone(&b, 988, 992, dur: 0.10, .square, vol: 0.13)
        tone(&b, 1319, 1325, dur: 0.18, .square, vol: 0.13, offset: Int(0.10 * sampleRate))
        return b
    }

    static func frenzyStart() -> [Float] {            // rising whoosh into the power-up
        var b = blank(0.42)
        tone(&b, 200, 980, dur: 0.38, .saw, vol: 0.10)
        noise(&b, dur: 0.36, vol: 0.12, cutoff: 2400, highpass: true, swell: true)
        return b
    }

    static func frenzyEnd() -> [Float] {              // falling whoosh out of it
        var b = blank(0.42)
        tone(&b, 980, 200, dur: 0.38, .saw, vol: 0.10)
        noise(&b, dur: 0.36, vol: 0.12, cutoff: 2400, highpass: true)
        return b
    }

    // MARK: v1.3 mechanic SFX (R17) — rings, overdrive pads, flow surges, level-ups

    static func ringPass() -> [Float] {               // airy pass-through: quick up-chirp + hiss
        var b = blank(0.12)
        tone(&b, 740, 1180, dur: 0.09, .triangle, vol: 0.14)
        noise(&b, dur: 0.05, vol: 0.05, cutoff: 4200, highpass: true)
        return b
    }

    static func ringPerfect() -> [Float] {            // dead-centre: bright two-tone gold sparkle
        var b = blank(0.26)
        tone(&b, 1046, 1052, dur: 0.10, .triangle, vol: 0.15)
        tone(&b, 1568, 1576, dur: 0.16, .sine, vol: 0.13, offset: Int(0.07 * sampleRate))
        tone(&b, 2093, 2093, dur: 0.10, .sine, vol: 0.07, offset: Int(0.13 * sampleRate))
        return b
    }

    static func boostStart() -> [Float] {             // overdrive ignition: punchy double-octave rise
        var b = blank(0.36)
        tone(&b, 320, 1280, dur: 0.30, .square, vol: 0.08)
        tone(&b, 160, 640, dur: 0.30, .sine, vol: 0.12)
        noise(&b, dur: 0.30, vol: 0.10, cutoff: 3600, highpass: true, swell: true)
        return b
    }

    static func boostEnd() -> [Float] {               // overdrive tail-off: the ignition, mirrored
        var b = blank(0.34)
        tone(&b, 1280, 320, dur: 0.28, .square, vol: 0.07)
        tone(&b, 640, 160, dur: 0.28, .sine, vol: 0.10)
        noise(&b, dur: 0.26, vol: 0.08, cutoff: 3600, highpass: true)
        return b
    }

    static func flowSurgeChime() -> [Float] {         // rising three-note shimmer into the fountain
        var b = blank(0.52)
        let arp: [Float] = [659, 784, 988]
        for (i, f) in arp.enumerated() {
            tone(&b, f, f * 1.02, dur: 0.12, .triangle, vol: 0.13, offset: Int(Float(i) * 0.08 * sampleRate))
        }
        tone(&b, 1318, 1330, dur: 0.22, .sine, vol: 0.10, offset: Int(0.24 * sampleRate))
        noise(&b, dur: 0.30, vol: 0.06, cutoff: 5200, highpass: true, swell: true, offset: Int(0.10 * sampleRate))
        return b
    }

    static func levelUpFanfare() -> [Float] {         // D-major arp + held top — distinct from newBest's C
        var b = blank(0.85)
        let arp: [Float] = [587, 740, 880, 1175]
        for (i, f) in arp.enumerated() {
            tone(&b, f, f * 1.01, dur: 0.16, .triangle, vol: 0.12, offset: Int(Float(i) * 0.12 * sampleRate))
        }
        tone(&b, 1175, 1180, dur: 0.34, .triangle, vol: 0.13, offset: Int(0.48 * sampleRate))
        tone(&b, 2350, 2360, dur: 0.26, .sine, vol: 0.05, offset: Int(0.52 * sampleRate))
        return b
    }

    // MARK: Music — one 8th-note step (kick / hat / saw bass / sparkle arp), per the prototype.

    static let bpm: Float = 132
    static var stepDuration: Float { 60 / bpm / 2 }          // 8th note
    static var stepFrames: Int { Int(stepDuration * sampleRate) }

    private static let rootShift = [0, 2, -2]
    private static let scales = [[0, 3, 7, 10], [0, 3, 7, 12], [0, 5, 7, 12]]
    private static let bassPattern = [0, 0, 2, 1, 0, 0, 3, 2]
    /// Cap on the music cycle-layering (v1.4.3): deeper evolution cycles add voices up to here,
    /// then hold — so the bed thickens with the worlds without ever clipping.
    static let musicLayerCap = 3

    /// One 8th-note step. `world` is the ABSOLUTE ordinal (v1.4.3): the family (`% 3`) sets the
    /// root/scale/character as before, and the cycle (`/ 3`) layers extra voices so deep worlds
    /// sound progressively richer rather than looping. Cycle 0 (worlds 0/1/2) is byte-identical to
    /// the original three-world bed.
    static func step(beat: Int, world: Int) -> [Float] {
        let w = ((world % 3) + 3) % 3
        let cycle = max(0, world) / 3
        var b = [Float](repeating: 0, count: stepFrames)
        let root = 45 + rootShift[w]
        let scale = scales[w]

        if beat % 4 == 0 {                                   // kick on quarters
            tone(&b, 140, 42, dur: 0.16, .sine, vol: 0.5)
        }
        if beat % 2 == 1 {                                   // hat on offbeats
            noise(&b, dur: 0.03, vol: 0.06 + Float(w) * 0.02, cutoff: 6000, highpass: true)
        }
        let bassMidi = root + scale[bassPattern[beat % 8]]   // sawtooth bass every 8th
        tone(&b, freq(bassMidi), freq(bassMidi), dur: 0.16, .saw, vol: 0.12)

        if w >= 1, beat % 2 == 0 {                           // sparkle arp from World 2
            let arpMidi = root + 24 + scale[(beat >> 1) % 4]
            tone(&b, freq(arpMidi), freq(arpMidi), dur: 0.2, .triangle, vol: 0.05)
        }

        // Cycle layering — each evolution cycle thickens the bed (capped at `musicLayerCap`).
        let layer = min(cycle, musicLayerCap)
        if layer >= 1 {                                      // octave-up saw shimmer doubling bass
            let shimMidi = bassMidi + 12
            tone(&b, freq(shimMidi), freq(shimMidi), dur: 0.14, .saw, vol: 0.03 + 0.01 * Float(layer))
        }
        if layer >= 2, beat % 2 == 1 {                       // syncopated counter-arp on offbeats
            let cMidi = root + 19 + scale[(beat >> 1) % 4]
            tone(&b, freq(cMidi), freq(cMidi), dur: 0.16, .triangle, vol: 0.035)
        }
        if layer >= 3, beat % 8 == 0 {                       // held sub-octave swell anchoring the bar
            tone(&b, freq(root - 12), freq(root - 12), dur: 0.40, .sine, vol: 0.06)
        }
        return b
    }
}

extension Synth {
    /// Stable identity for every one-shot effect. All SFX are deterministic, so `SynthEngine`
    /// renders each case once and caches the PCM buffer instead of re-synthesizing per play.
    /// Pure (no AVAudio), so the full catalog stays unit-testable on Linux.
    enum SFX: Hashable, Sendable {
        case gem(streak: Int)
        case jump, slide, crash, chime, shieldPickup, magnetPickup, doublerPickup
        case worldSweep, close, startChime
        case laneTick, landThud, purchaseChime, equipClick, uiTick, newBestFanfare, deathSweep
        case frenzyStart, frenzyEnd
        // v1.3 (R17): exactly six new cases — NEW-CHARACTER toasts reuse `purchaseChime`.
        case ringPass, ringPerfect, boostStart, boostEnd, flowSurge, levelUp

        /// Gem repeats its pitch ladder every 26 streaks — collapse so the cache stays bounded.
        var normalized: SFX {
            if case let .gem(streak) = self { return .gem(streak: ((streak % 26) + 26) % 26) }
            return self
        }

        /// Big moments push the music bed down (see `Music.duck(to:)`); ticks and blips don't.
        var ducksMusic: Bool {
            switch self {
            case .crash, .deathSweep, .worldSweep, .shieldPickup, .magnetPickup, .doublerPickup,
                 .frenzyStart, .frenzyEnd, .newBestFanfare,
                 .boostStart, .boostEnd, .flowSurge, .levelUp:   // rings are too frequent to duck
                return true
            default:
                return false
            }
        }

        var samples: [Float] {
            switch self {
            case let .gem(streak): return Synth.gem(streak: streak)
            case .jump: return Synth.jump()
            case .slide: return Synth.slide()
            case .crash: return Synth.crash()
            case .chime: return Synth.chime()
            case .shieldPickup: return Synth.shieldChime()
            case .magnetPickup: return Synth.magnetChime()
            case .doublerPickup: return Synth.doublerPickup()
            case .worldSweep: return Synth.worldSweep()
            case .close: return Synth.close()
            case .startChime: return Synth.startChime()
            case .laneTick: return Synth.laneTick()
            case .landThud: return Synth.landThud()
            case .purchaseChime: return Synth.purchaseChime()
            case .equipClick: return Synth.equipClick()
            case .uiTick: return Synth.uiTick()
            case .newBestFanfare: return Synth.newBestFanfare()
            case .deathSweep: return Synth.deathSweep()
            case .frenzyStart: return Synth.frenzyStart()
            case .frenzyEnd: return Synth.frenzyEnd()
            case .ringPass: return Synth.ringPass()
            case .ringPerfect: return Synth.ringPerfect()
            case .boostStart: return Synth.boostStart()
            case .boostEnd: return Synth.boostEnd()
            case .flowSurge: return Synth.flowSurgeChime()
            case .levelUp: return Synth.levelUpFanfare()
            }
        }
    }
}
