import AVFoundation

/// AVAudioEngine graph for fully-synthesized audio (no asset files). A pool of player nodes plays
/// one-shot SFX buffers through `sfxMixer`; `Music` streams step buffers through `musicMixer`
/// (kept below the SFX so it sits under them). Master mute via the main mixer.
@MainActor
final class SynthEngine {
    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var sfxPlayers: [AVAudioPlayerNode] = []
    private var sfxCursor = 0
    private let musicPlayer = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let music: Music
    private var started = false

    var muted = false { didSet { engine.mainMixerNode.outputVolume = muted ? 0 : 1 } }

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: Double(Synth.sampleRate), channels: 1)!

        engine.attach(sfxMixer)
        engine.attach(musicMixer)
        engine.attach(musicPlayer)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            sfxPlayers.append(p)
        }

        engine.connect(sfxMixer, to: engine.mainMixerNode, format: format)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: format)
        for p in sfxPlayers { engine.connect(p, to: sfxMixer, format: format) }
        engine.connect(musicPlayer, to: musicMixer, format: format)

        sfxMixer.outputVolume = 1.0
        musicMixer.outputVolume = 0.0   // Music ramps this in

        music = Music(player: musicPlayer, mixer: musicMixer, format: format)
    }

    func start() {
        guard !started else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            for p in sfxPlayers { p.play() }
            started = true
        } catch {
            started = false
        }
    }

    func playSFX(_ samples: [Float]) {
        guard started, !muted, !samples.isEmpty, let buf = makeBuffer(samples) else { return }
        let p = sfxPlayers[sfxCursor]
        sfxCursor = (sfxCursor + 1) % sfxPlayers.count
        p.scheduleBuffer(buf, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func musicStart() { guard started, !muted else { return }; music.start() }
    func musicStop() { music.stop() }
    func musicPump(dt: Double, world: Int) { music.world = world; music.pump(dt) }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let ch = buf.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { if let base = $0.baseAddress { ch.update(from: base, count: samples.count) } }
        return buf
    }
}
