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

    /// Filtered noise burst (one-pole low/high pass) with a linear decay, summed into `buf`.
    static func noise(_ buf: inout [Float], dur: Float, vol: Float, cutoff: Float, highpass: Bool = false, offset: Int = 0, seed: UInt32 = 0x1234_5678) {
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

    static func gem(streak: Int) -> [Float] {
        let f = 560 * pow(1.045, Float(streak % 26))
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

    // MARK: Music — one 8th-note step (kick / hat / saw bass / sparkle arp), per the prototype.

    static let bpm: Float = 132
    static var stepDuration: Float { 60 / bpm / 2 }          // 8th note
    static var stepFrames: Int { Int(stepDuration * sampleRate) }

    private static let rootShift = [0, 2, -2]
    private static let scales = [[0, 3, 7, 10], [0, 3, 7, 12], [0, 5, 7, 12]]
    private static let bassPattern = [0, 0, 2, 1, 0, 0, 3, 2]

    static func step(beat: Int, world: Int) -> [Float] {
        let w = ((world % 3) + 3) % 3
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
        return b
    }
}
