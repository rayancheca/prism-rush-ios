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

    /// Filtered noise burst summed into `buf`.
    ///
    /// - `swell`  — rise into the tail instead of decaying out of the attack (whooshes that build).
    ///              **This was declared and never applied until v1.8 (PR-0320): the body always
    ///              used `(1 - frac)`, so all four callers that asked for a swelling whoosh got a
    ///              dying one.** The parameter existed, read correctly at every call site, and did
    ///              nothing — which is why the defect survived so long.
    /// - `attack` — fraction of the burst spent ramping IN, 0…1. At 0 the burst is at full
    ///              amplitude on its very first sample, and broadband noise starting instantly is
    ///              a click: it is the single biggest cause of a "harsh" one-shot.
    /// - `poles`  — filter order. One pole is 6 dB/oct, which leaves a lot of energy an octave or
    ///              two above `cutoff` (audible as hiss). Two poles (12 dB/oct) turns the same
    ///              burst into air.
    static func noise(_ buf: inout [Float], dur: Float, vol: Float, cutoff: Float, highpass: Bool = false, swell: Bool = false, attack: Float = 0, poles: Int = 1, offset: Int = 0, seed: UInt32 = 0x1234_5678) {
        let n = Int(dur * sampleRate)
        var rng = seed
        var lp: Float = 0, lp2: Float = 0
        let coeff = min(0.99, cutoff / (cutoff + sampleRate / (2 * .pi)))
        for i in 0..<n {
            let idx = offset + i
            if idx >= buf.count { break }
            rng = rng &* 1_664_525 &+ 1_013_904_223
            let white = Float(rng >> 8) / Float(0xFF_FFFF) * 2 - 1
            lp += coeff * (white - lp)
            var filtered = lp
            if poles >= 2 {
                lp2 += coeff * (lp - lp2)
                filtered = lp2
            }
            let sample = highpass ? (white - filtered) : filtered
            let frac = Float(i) / Float(n)
            let shape = swell ? frac : (1 - frac)
            let ramp = attack > 0 ? min(1, frac / attack) : 1
            buf[idx] += sample * vol * shape * ramp
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

    /// Slide (retuned v1.8 — owner: *"so harsh and horrible"*).
    ///
    /// The old sound was a one-pole 600 Hz noise burst at `vol` 0.20 that reached FULL amplitude on
    /// its very first sample. Two things made that harsh, and both are structural rather than a
    /// matter of taste:
    ///   1. **No attack.** An instantaneous broadband onset is a click. Every other percussive cue
    ///      in this game gets away with it because they are tones; noise does not.
    ///   2. **A 6 dB/oct filter at 600 Hz** still passes plenty of 2–5 kHz, the band the ear is most
    ///      sensitive to. That is hiss, not air.
    /// So: a 35% attack ramp, a second filter pole, cutoff down 600 → 320, and level down 0.20 →
    /// 0.14. It now reads as the player ducking under something rather than as a burst of static.
    /// Slightly longer (0.16 → 0.20 s) because a ramped whoosh needs room to be a whoosh; still far
    /// inside `slideDuration` 0.55, so a held slide never overlaps its own cue.
    static func slide() -> [Float] {
        var b = blank(0.20)
        noise(&b, dur: 0.18, vol: 0.14, cutoff: 320, attack: 0.35, poles: 2)
        tone(&b, 150, 96, dur: 0.15, .sine, vol: 0.075)     // soft low anchor under the air
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

    static func shieldBreak() -> [Float] {            // glass shatter — a sharp white crack + falling shards
        var b = blank(0.5)
        noise(&b, dur: 0.13, vol: 0.32, cutoff: 9000, highpass: true)                            // the crack
        tone(&b, 2300, 1500, dur: 0.08, .triangle, vol: 0.14)                                    // bright shard
        tone(&b, 1700, 850,  dur: 0.11, .triangle, vol: 0.12, offset: Int(0.07 * sampleRate))
        tone(&b, 1100, 520,  dur: 0.16, .sine,     vol: 0.10, offset: Int(0.16 * sampleRate))    // falling resonance
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

    // MARK: Warden telegraphs (S-009) — the sound tells you WHICH VERB, not merely "something"
    //
    // v1.9 played `laneTick` for every wind-up: a 40 ms blip at volume 0.08 that is *the same sound
    // as the player's own lane change*, and one of the few SFX excluded from `ducksMusic`. The one
    // moment in the fight the player must act on was the quietest, most ambiguous cue in the game.
    //
    // The three cues carry the same information the geometry does, in the same grammar, so a player
    // can begin the answer before their eyes have finished parsing the shape. Pitch direction maps
    // to the shape's motion, which maps to the verb:
    //   FLOOR   — rising: the slab climbs out of the deck.  You go up.
    //   CURTAIN — falling: the wall comes down from the sky. You go down.
    //   LANCE   — flat, doubled: neither. Move sideways.
    // Louder and longer than a lane tick, and all three duck the music.

    static func wardenFloorCue() -> [Float] {         // rising two-tone — jump
        var b = blank(0.34)
        tone(&b, 240, 300, dur: 0.14, .triangle, vol: 0.17)
        tone(&b, 420, 560, dur: 0.20, .triangle, vol: 0.19, offset: Int(0.13 * sampleRate))
        return b
    }

    static func wardenCurtainCue() -> [Float] {       // descending two-tone — slide
        var b = blank(0.34)
        tone(&b, 620, 520, dur: 0.14, .triangle, vol: 0.17)
        tone(&b, 330, 210, dur: 0.20, .triangle, vol: 0.19, offset: Int(0.13 * sampleRate))
        return b
    }

    static func wardenLanceCue() -> [Float] {         // flat doubled tick — change lane
        var b = blank(0.24)
        tone(&b, 330, 330, dur: 0.06, .square, vol: 0.13)
        tone(&b, 330, 330, dur: 0.06, .square, vol: 0.13, offset: Int(0.09 * sampleRate))
        return b
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

    static func sneakersChime() -> [Float] {          // spring-loaded leap: a coil release + a lighter rebound
        var b = blank(0.34)
        tone(&b, 240, 960, dur: 0.13, .triangle, vol: 0.14)                                  // main spring release (up)
        tone(&b, 360, 1440, dur: 0.10, .sine, vol: 0.09, offset: Int(0.03 * sampleRate))     // bright overtone
        tone(&b, 700, 1050, dur: 0.10, .triangle, vol: 0.10, offset: Int(0.17 * sampleRate)) // the rebound bounce
        noise(&b, dur: 0.05, vol: 0.06, cutoff: 5000, highpass: true)                        // a soft spring twang
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

    private static let bassPattern = [0, 0, 2, 1, 0, 0, 3, 2]
    /// Cap on the music cycle-layering (v1.4.3): deeper evolution cycles add voices up to here,
    /// then hold — so the bed thickens with the worlds without ever clipping.
    static let musicLayerCap = 3

    /// One themed bed per distinct world (v1.5). `rootShift` transposes the key, `scale` (4 degrees)
    /// sets the mood, `arp` toggles the sparkle voice, `hatVol` the offbeat hat. Beds 0/1/2 reproduce
    /// the shipped three-world bed EXACTLY (rootShift 0/2/−2, the original scales, arp off/on/on,
    /// hat 0.06/0.08/0.10 = the old `0.06 + w·0.02`), so worlds 0/1/2 stay byte-identical; 3…11 are
    /// new, each matched to its world's palette/sky character (Orbital floaty … Singularity radiant).
    struct Bed: Sendable { let rootShift: Int; let scale: [Int]; let arp: Bool; let hatVol: Float }
    static let beds: [Bed] = [
        Bed(rootShift:  0, scale: [0, 3, 7, 10], arp: false, hatVol: 0.06),  // 0 Pulse City (shipped)
        Bed(rootShift:  2, scale: [0, 3, 7, 12], arp: true,  hatVol: 0.08),  // 1 Geode Deep (shipped)
        Bed(rootShift: -2, scale: [0, 5, 7, 12], arp: true,  hatVol: 0.10),  // 2 Solar Sands (shipped)
        Bed(rootShift:  5, scale: [0, 3, 7, 10], arp: true,  hatVol: 0.07),  // 3 Orbital Drift (floaty)
        Bed(rootShift: -4, scale: [0, 5, 7, 12], arp: true,  hatVol: 0.08),  // 4 Tidal Glow (flowing)
        Bed(rootShift: -7, scale: [0, 3, 6, 10], arp: false, hatVol: 0.10),  // 5 Ashfall (heavy/dark)
        Bed(rootShift:  7, scale: [0, 4, 7, 11], arp: true,  hatVol: 0.07),  // 6 Borealis (bright maj7)
        Bed(rootShift:  0, scale: [0, 2, 7, 9],  arp: true,  hatVol: 0.12),  // 7 Datastream (driving)
        Bed(rootShift:  3, scale: [0, 5, 7, 12], arp: true,  hatVol: 0.06),  // 8 Bloomfall (gentle sus)
        Bed(rootShift: -5, scale: [0, 3, 8, 10], arp: true,  hatVol: 0.08),  // 9 Eventide (dusky b6)
        Bed(rootShift:  2, scale: [0, 3, 7, 10], arp: false, hatVol: 0.13),  // 10 Tempest (turbulent)
        Bed(rootShift:  9, scale: [0, 4, 7, 12], arp: true,  hatVol: 0.10),  // 11 Singularity (radiant)
    ]

    /// One 8th-note step. `world` is the ABSOLUTE ordinal: `world % 12` picks the themed bed (12
    /// distinct worlds, v1.5), and the cycle (`/ 12`) layers extra voices so deep loops sound
    /// progressively richer rather than identical. Cycle 0 (worlds 0…11) is the base bed; worlds
    /// 0/1/2 stay byte-identical to the original three-world bed (see `beds`).
    static func step(beat: Int, world: Int) -> [Float] {
        let n = Synth.beds.count
        let w = ((world % n) + n) % n
        let cycle = max(0, world) / n
        var b = [Float](repeating: 0, count: stepFrames)
        let bed = Synth.beds[w]
        let root = 45 + bed.rootShift
        let scale = bed.scale

        if beat % 4 == 0 {                                   // kick on quarters
            tone(&b, 140, 42, dur: 0.16, .sine, vol: 0.5)
        }
        if beat % 2 == 1 {                                   // hat on offbeats
            noise(&b, dur: 0.03, vol: bed.hatVol, cutoff: 6000, highpass: true)
        }
        let bassMidi = root + scale[bassPattern[beat % 8]]   // sawtooth bass every 8th
        tone(&b, freq(bassMidi), freq(bassMidi), dur: 0.16, .saw, vol: 0.12)

        if bed.arp, beat % 2 == 0 {                          // sparkle arp (per-bed)
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
        case jump, slide, crash, chime, shieldPickup, shieldBreak, magnetPickup, doublerPickup
        case worldSweep, close, startChime
        case laneTick, landThud, purchaseChime, equipClick, uiTick, newBestFanfare, deathSweep
        case frenzyStart, frenzyEnd
        // v1.3 (R17): exactly six new cases — NEW-CHARACTER toasts reuse `purchaseChime`.
        case ringPass, ringPerfect, boostStart, boostEnd, flowSurge, levelUp
        // v1.6: Super Sneakers gets its own spring-loaded leap (was reusing `boostStart`).
        case sneakersPickup
        // v1.9/S-009: one telegraph cue per Warden shape — the sound names the verb.
        case wardenFloorCue, wardenCurtainCue, wardenLanceCue

        /// Gem repeats its pitch ladder every 26 streaks — collapse so the cache stays bounded.
        var normalized: SFX {
            if case let .gem(streak) = self { return .gem(streak: ((streak % 26) + 26) % 26) }
            return self
        }

        /// Big moments push the music bed down (see `Music.duck(to:)`); ticks and blips don't.
        var ducksMusic: Bool {
            switch self {
            case .crash, .deathSweep, .worldSweep, .shieldPickup, .shieldBreak, .magnetPickup, .doublerPickup,
                 .frenzyStart, .frenzyEnd, .newBestFanfare,
                 .boostStart, .boostEnd, .flowSurge, .levelUp, .sneakersPickup,   // rings too frequent to duck
                 // A Warden telegraph is the most time-critical cue in the game; it must not be
                 // competing with the music bed, which is exactly what the old `laneTick` did.
                 .wardenFloorCue, .wardenCurtainCue, .wardenLanceCue:
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
            case .shieldBreak: return Synth.shieldBreak()
            case .magnetPickup: return Synth.magnetChime()
            case .doublerPickup: return Synth.doublerPickup()
            case .worldSweep: return Synth.worldSweep()
            case .close: return Synth.close()
            case .startChime: return Synth.startChime()
            case .laneTick: return Synth.laneTick()
            case .wardenFloorCue: return Synth.wardenFloorCue()
            case .wardenCurtainCue: return Synth.wardenCurtainCue()
            case .wardenLanceCue: return Synth.wardenLanceCue()
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
            case .sneakersPickup: return Synth.sneakersChime()
            }
        }
    }
}
