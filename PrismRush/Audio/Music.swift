import AVFoundation

/// 132 BPM synthwave sequencer. Feeds back-to-back one-8th-note step buffers into a player node, so
/// timing is sample-accurate (buffers are contiguous — no wall-clock drift). `pump(_:)` is called
/// from the game loop each frame to keep a few steps queued ahead and to ramp the fade.
@MainActor
final class Music {
    private let player: AVAudioPlayerNode
    private let mixer: AVAudioMixerNode
    private let format: AVAudioFormat

    private var beat = 0
    private var scheduledFrames: Int64 = 0
    private var playing = false
    private var vol: Float = 0
    private var targetVol: Float = 0
    private var fadeRate: Float = 1
    private var duckLevel: Float = 1
    private let lookaheadFrames: Int64
    /// The world the queued buffers were rendered for — drives the crisp bed switch (v1.6).
    private var lastScheduledWorld = 0

    var world = 0
    /// Settings slider (0...1), multiplied into every fade/duck. Owned by `SynthEngine`.
    var userVolume: Float = 1

    init(player: AVAudioPlayerNode, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        self.player = player
        self.mixer = mixer
        self.format = format
        lookaheadFrames = Int64(Synth.stepFrames * 4)
    }

    /// `targetVolume` lets the hub/splash run the same sequencer as a calmer bed (≈0.4) so the menu
    /// has music that "makes you want to play" without competing with the UI, while a run starts the
    /// full-intensity bed (0.85). The fade-in time scales with the target so a calm start is gentle.
    func start(targetVolume: Float = 0.85) {
        player.stop()
        beat = 0
        scheduledFrames = 0
        lastScheduledWorld = world   // a fresh start is already in sync — never a spurious flush
        playing = true
        vol = min(0.08, targetVolume)  // start just audible so the run-start beat lands
        targetVol = targetVolume
        fadeRate = targetVolume / 0.5  // fade in over ~0.5 s
        duckLevel = 1
        mixer.outputVolume = vol * userVolume
        player.play()
    }

    func stop() {
        playing = false
        targetVol = 0
        fadeRate = max(vol, 0.0001) / 0.8   // fade out over ~0.8 s
    }

    /// Big SFX push the bed down to `level`; `pump` recovers it to 1 over ~0.25 s.
    func duck(to level: Float) { duckLevel = min(duckLevel, level) }

    /// After an engine stop (interruption / route change) the player's sample timeline and queued
    /// buffers are gone, so `scheduledFrames` no longer matches `playedFrames()` and pump wedges.
    /// Restart the player and reset the anchor; the next pump refills from the current beat.
    /// Only call with the engine running — `play()` on a stopped engine raises.
    func reanchor() {
        guard playing else { return }
        player.stop()
        scheduledFrames = 0
        player.play()
    }

    func pump(_ dt: Double) {
        if vol != targetVol {
            let step = fadeRate * Float(dt)
            vol = vol < targetVol ? min(targetVol, vol + step) : max(targetVol, vol - step)
        }
        duckLevel = min(1, duckLevel + Float(dt) * 2)   // recover from a 0.5 duck in ~0.25 s
        mixer.outputVolume = vol * duckLevel * userVolume
        guard playing else { return }

        // Crisp per-world bed switch (v1.6): without this, the lookahead queue (up to 4 steps) keeps
        // playing the OLD world's bed for ~0.45 s past the boundary. On a world change, schedule the
        // next step for the NEW world with `.interrupts` — the player discards the queued old-world
        // buffers and plays this one immediately, so the bed flips within one step of the crossfade
        // (the worldSweep whoosh covers the seam). Re-anchor `scheduledFrames` to (played + this
        // buffer): the discarded buffers were counted but won't play, so this keeps the pump's
        // lookahead math honest and can never wedge (worst case it tops up one extra buffer). `beat`
        // is preserved, so the synthwave phrase stays in time across the switch.
        if world != lastScheduledWorld {
            lastScheduledWorld = world
            if scheduledFrames > 0, let buf = makeBuffer(Synth.step(beat: beat, world: world)) {
                player.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
                scheduledFrames = playedFrames() + Int64(buf.frameLength)
                beat += 1
            }
        }

        let played = playedFrames()
        var safety = 0
        while scheduledFrames - played < lookaheadFrames, safety < 8 {
            let samples = Synth.step(beat: beat, world: world)
            guard let buf = makeBuffer(samples) else { break }
            player.scheduleBuffer(buf, completionHandler: nil)
            scheduledFrames += Int64(buf.frameLength)
            beat += 1
            safety += 1
        }
    }

    private func playedFrames() -> Int64 {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        return max(0, playerTime.sampleTime)
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let ch = buf.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { if let base = $0.baseAddress { ch.update(from: base, count: samples.count) } }
        return buf
    }
}
