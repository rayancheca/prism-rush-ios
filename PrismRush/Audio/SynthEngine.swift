import AVFoundation
import os

/// AVAudioEngine graph for fully-synthesized audio (no asset files). A pool of player nodes plays
/// one-shot SFX buffers through `sfxMixer`; `Music` streams step buffers through `musicMixer`
/// (kept below the SFX so it sits under them). Each `Synth.SFX` is rendered once and cached as a
/// PCM buffer. Master mute ramps the main mixer (in `musicPump`) so toggling never clicks, and
/// AVAudioSession interruptions / route changes are observed so the engine recovers instead of
/// silently no-oping for the rest of the session.
@MainActor
final class SynthEngine {
    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var sfxPlayers: [AVAudioPlayerNode] = []
    private var sfxBusyUntil: [TimeInterval] = []
    private var sfxCursor = 0
    private let musicPlayer = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private let music: Music?
    private var sfxCache: [Synth.SFX: AVAudioPCMBuffer] = [:]
    private var started = false
    private var masterTarget: Float = 1
    private var observers: [NSObjectProtocol] = []   // session/engine notification tokens, app-lifetime
    private let log = Logger(subsystem: "com.rayancheca.prismrush", category: "audio")

    var muted = false { didSet { masterTarget = muted ? 0 : 1 } }

    /// Settings sliders (0...1). SFX applies to the SFX submix; music multiplies into Music's own
    /// fade/duck envelope. Persistence is the caller's job — these are live values only.
    var sfxVolume: Float = 1 { didSet { sfxMixer.outputVolume = min(1, max(0, sfxVolume)) } }
    /// Music has TWO independent user levels: the in-run bed (`musicVolume`) and the hub/splash bed
    /// (`menuMusicVolume`). Only the level for the currently-playing context feeds Music's
    /// `userVolume`; `musicStart(calm:)` flips the context. Both setters re-apply live so dragging a
    /// slider while that bed plays updates immediately.
    var musicVolume: Float = 1 { didSet { applyMusicUserVolume() } }
    var menuMusicVolume: Float = 1 { didSet { applyMusicUserVolume() } }
    /// true while the calm hub/splash bed is the active context; false during a run.
    private var musicIsCalm = false

    private func applyMusicUserVolume() {
        music?.userVolume = min(1, max(0, musicIsCalm ? menuMusicVolume : musicVolume))
    }

    init() {
        // No mono float format would mean no audio at all — degrade to a silent-but-alive engine
        // rather than crash (every entry point guards on `started`, which stays false).
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(Synth.sampleRate), channels: 1) else {
            format = nil
            music = nil
            log.error("No usable AVAudioFormat; audio disabled")
            return
        }
        format = fmt

        engine.attach(sfxMixer)
        engine.attach(musicMixer)
        engine.attach(musicPlayer)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            sfxPlayers.append(p)
        }
        sfxBusyUntil = [TimeInterval](repeating: 0, count: sfxPlayers.count)

        engine.connect(sfxMixer, to: engine.mainMixerNode, format: fmt)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: fmt)
        for p in sfxPlayers { engine.connect(p, to: sfxMixer, format: fmt) }
        engine.connect(musicPlayer, to: musicMixer, format: fmt)

        sfxMixer.outputVolume = 1.0
        musicMixer.outputVolume = 0.0   // Music ramps this in

        music = Music(player: musicPlayer, mixer: musicMixer, format: fmt)
        observeSessionNotifications()
    }

    func start() {
        guard !started, format != nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // `.playback` (not `.ambient`): the synthwave + SFX are core to the game, so they play even
            // when the ringer/mute switch is off — the owner's "there's no music" was the silent switch
            // killing an `.ambient` session. The in-app mute toggle + volume sliders stay in control,
            // and interruption/route-change recovery is wired below.
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            engine.mainMixerNode.outputVolume = masterTarget   // apply initial mute without a ramp
            engine.prepare()
            try engine.start()
            for p in sfxPlayers { p.play() }
            started = true
        } catch {
            started = false
            log.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Play a one-shot from the cache; the first play of a case renders + caches its buffer.
    func play(_ sfx: Synth.SFX) {
        guard started, !muted, engine.isRunning else { return }
        let key = sfx.normalized
        let buf: AVAudioPCMBuffer
        if let cached = sfxCache[key] {
            buf = cached
        } else {
            guard let made = makeBuffer(key.samples) else { return }
            sfxCache[key] = made
            buf = made
        }
        if sfx.ducksMusic { music?.duck(to: 0.5) }
        schedule(buf)
    }

    /// `calm` starts the bed at a quieter target (the hub/splash ambience); the default full
    /// intensity is the in-run bed. Either way mute is mixer-level — never gate scheduling on it.
    func musicStart(calm: Bool = false) {
        guard started else { return }
        if !engine.isRunning { recoverEngine() }   // self-heal if an interruption beat us here
        guard engine.isRunning else { return }
        musicIsCalm = calm
        applyMusicUserVolume()                     // feed the right bed's user level before fading in
        music?.start(targetVolume: calm ? 0.4 : 0.85)
    }
    func musicStop() { music?.stop() }
    func musicPump(dt: Double, world: Int) {
        rampMaster(dt)
        // Owner decree (v1.6): NO per-world music. The bed stays one consistent track for the whole
        // run — the key/scale/arp changing every 800 m read as disruptive ("destroys the game"). The
        // per-world `beds` table + `Synth.step(world:)` stay intact (reversible), just not fed varying
        // worlds. `world` is kept in the signature so callers don't change.
        _ = world
        music?.world = 0
        music?.pump(dt)
    }

    /// ~0.15 s linear ramp toward the mute target so toggling doesn't hard-cut.
    private func rampMaster(_ dt: Double) {
        let cur = engine.mainMixerNode.outputVolume
        guard cur != masterTarget else { return }
        let step = Float(dt) / 0.15
        engine.mainMixerNode.outputVolume = cur < masterTarget
            ? min(masterTarget, cur + step)
            : max(masterTarget, cur - step)
    }

    /// Pick an idle player when one exists — queued buffers on a busy player delay, not overlap —
    /// falling back to round-robin when all are mid-buffer.
    private func schedule(_ buf: AVAudioPCMBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let idx = sfxBusyUntil.firstIndex { $0 <= now } ?? sfxCursor
        sfxCursor = (idx + 1) % sfxPlayers.count
        sfxBusyUntil[idx] = max(sfxBusyUntil[idx], now) + Double(buf.frameLength) / Double(Synth.sampleRate)
        let p = sfxPlayers[idx]
        p.scheduleBuffer(buf, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    // A phone call / Siri / alarm / headphone unplug stops the engine out from under us; without
    // these observers `started` stays true and all later audio silently no-ops forever.
    private func observeSessionNotifications() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
                self?.recoverEngine()
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverIfStalled() }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverIfStalled() }
        })
    }

    private func recoverIfStalled() {
        guard started, !engine.isRunning else { return }
        recoverEngine()
    }

    private func recoverEngine() {
        guard started else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            for p in sfxPlayers where !p.isPlaying { p.play() }
            music?.reanchor()
            for i in sfxBusyUntil.indices { sfxBusyUntil[i] = 0 }   // queued SFX died with the engine
        } catch {
            // Leave `started` true: route/config notifications retry on the next opportunity.
            log.error("Audio engine recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format, !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let ch = buf.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { if let base = $0.baseAddress { ch.update(from: base, count: samples.count) } }
        return buf
    }
}
