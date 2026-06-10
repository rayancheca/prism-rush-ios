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
    private let lookaheadFrames: Int64

    var world = 0

    init(player: AVAudioPlayerNode, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        self.player = player
        self.mixer = mixer
        self.format = format
        lookaheadFrames = Int64(Synth.stepFrames * 4)
    }

    func start() {
        player.stop()
        beat = 0
        scheduledFrames = 0
        playing = true
        vol = 0.0001
        targetVol = 0.85
        fadeRate = 0.85 / 1.2          // fade in over 1.2 s
        mixer.outputVolume = 0
        player.play()
    }

    func stop() {
        playing = false
        targetVol = 0
        fadeRate = max(vol, 0.0001) / 0.8   // fade out over ~0.8 s
    }

    func pump(_ dt: Double) {
        if vol != targetVol {
            let step = fadeRate * Float(dt)
            vol = vol < targetVol ? min(targetVol, vol + step) : max(targetVol, vol - step)
            mixer.outputVolume = vol
        }
        guard playing else { return }

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
