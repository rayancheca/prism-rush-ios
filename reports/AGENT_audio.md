# AGENT_audio — handoff notes

Files touched: `PrismRush/Audio/Synth.swift`, `PrismRush/Audio/SynthEngine.swift`,
`PrismRush/Audio/Music.swift`, `Tests/CoreTests/SynthTests.swift`.
Verified: `swift test -c release` — **0 failures** (44 tests at last run: 38 baseline + 4 new
SynthTests + 2 added concurrently by another agent).
SynthEngine/Music use AVFoundation and cannot compile on Linux — changes there follow the existing
API/isolation patterns exactly; needs one simulator build to confirm.

## What changed

### P0 — AVAudioSession resilience (SynthEngine)
- Observes `AVAudioSession.interruptionNotification` (recovers on `.ended`),
  `AVAudioSession.routeChangeNotification`, and `.AVAudioEngineConfigurationChange` (both recover
  if `engine.isRunning` is false). Observers are block-based on `.main` +
  `MainActor.assumeIsolated`, tokens retained for the engine's app lifetime.
- `recoverEngine()`: re-activates the session, restarts the engine, re-`play()`s the SFX player
  pool, clears the SFX busy estimates, and calls `Music.reanchor()`.
- `Music.reanchor()`: stops/restarts the music player and resets `scheduledFrames` to 0 so `pump`
  refills from the current beat (fixes the playedFrames-vs-scheduledFrames wedge). The integration
  layer never calls this — it is internal to recovery.
- `musicStart()` self-heals: if the engine stalled before a new run starts, it attempts recovery
  first and bails (silently, alive) if the engine still won't run.

### P1 — mute fixes
- `musicStart()` no longer gates on `muted` — mute is mixer-level only, scheduling never depends
  on it. A run started while muted now has music as soon as you unmute.
- Mute is no longer a hard cut: `muted` sets a target, and `musicPump` ramps
  `mainMixerNode.outputVolume` to it over ~0.15 s.

### E2 — music ducking
- `Music.duck(to:)` multiplies a duck level into the music mixer; `pump` recovers it to 1 at 2/s
  (0.5 → 1 in ~0.25 s).
- Ducking is **automatic**: `Synth.SFX.ducksMusic` marks the big moments (crash, deathSweep,
  worldSweep, shieldPickup, magnetPickup, doublerPickup, frenzyStart/End, newBestFanfare) and
  `SynthEngine.play(_:)` ducks to 0.5 when playing them. No integrator wiring needed.

### E4 — gem streak ladder
- `Synth.gemPitchStep = 1.08` (was inline 1.045); test asserts ≥ 1.07 and adjacent-streak
  distinctness.

### E3 — new SFX (all pure DSP in Synth.swift, all unit-tested)
`laneTick` (0.04 s sine 300→360, vol 0.08) · `landThud` (150→46 Hz thump + dust) ·
`purchaseChime` (rising C–E–G major triad + octave sparkle) · `equipClick` (snappy click) ·
`uiTick` (soft sheet blip) · `newBestFanfare` (C–E–G–C arp + held top, 0.75 s) ·
`deathSweep` (saw 660→55 over 0.9 s + swelling filtered noise, vol 0.18) ·
`doublerPickup` (coin-y double chime) · `frenzyStart` / `frenzyEnd` (rising/falling whoosh).
Shield vs magnet were **already distinct** (`shieldChime` rising triad / `magnetChime` descending
arp) — left as-is, now also covered by a distinctness test.
`Synth.noise` gained a `swell: Bool = false` parameter (rising instead of decaying envelope).

### PERF — cached SFX buffers + idle-player selection
- New `Synth.SFX` enum (Hashable, Sendable, pure — lives in Synth.swift so it tests on Linux):
  one case per effect, `gem(streak:)` carries its variant. `normalized` collapses gem keys modulo
  the 26-step ladder so the cache stays bounded (~26 gem + 19 other sub-second mono buffers).
- `SynthEngine.play(_ sfx: Synth.SFX)` renders each case **once**, caches the `AVAudioPCMBuffer`,
  and reuses it forever — no per-play synthesis or allocation.
- Player selection prefers the first player whose scheduled audio has finished (tracked via
  per-player busy-until estimates — `isPlaying` is useless here since pooled players stay
  "playing" forever) and falls back to round-robin; queued-buffer delays are gone.
- `playSFX(_ samples: [Float])` is kept as the uncached escape hatch so GameView compiles
  unchanged; delete it once all call sites migrate to `play(_:)` (see wiring below).

### E5 — no force-unwrap
- `format`/`music` are now optional; if `AVAudioFormat` can't be created the engine logs and
  degrades to silent-but-alive (every entry point guards on `started`, which stays false).

## New API surface

```swift
// SynthEngine (@MainActor)
func play(_ sfx: Synth.SFX)          // cached one-shot; auto-ducks music for big SFX
var musicVolume: Float               // 0...1, multiplies into Music's fade/duck envelope
var sfxVolume: Float                 // 0...1, drives sfxMixer.outputVolume
// muted, start(), musicStart(), musicStop(), musicPump(dt:world:), playSFX([Float]) unchanged.

// Synth
Synth.SFX                            // .gem(streak:), .jump, …, .frenzyEnd; .normalized, .ducksMusic, .samples
Synth.gemPitchStep                   // 1.08
// New sample functions: laneTick(), landThud(), purchaseChime(), equipClick(), uiTick(),
// newBestFanfare(), deathSweep(), doublerPickup(), frenzyStart(), frenzyEnd()

// Music (internal to the audio layer)
func duck(to: Float); func reanchor(); var userVolume: Float
```

## Wiring for the integration agent (all in `PrismRush/UI/GameView.swift` unless noted)

Replace every `synth.playSFX(Synth.x(...))` with the cached call:

| Location | Current | Replace with |
|---|---|---|
| `startRun()` | `synth.playSFX(Synth.startChime())` | `synth.play(.startChime)` |
| `reviveForCoins()` | `synth.playSFX(Synth.shieldChime())` | `synth.play(.shieldPickup)` |
| `claimDailyReward()` | `synth.playSFX(Synth.chime())` | `synth.play(.chime)` |
| `openChest()` | `synth.playSFX(Synth.shieldChime())` | `synth.play(.purchaseChime)` |
| `handleFX` `.gemCollected` | `synth.playSFX(Synth.gem(streak: streak))` | `synth.play(.gem(streak: streak))` |
| `handleFX` `.nearMiss` | `synth.playSFX(Synth.close())` | `synth.play(.close)` |
| `handleFX` `.pickup` | shield/magnet chime | `synth.play(kind == .shield ? .shieldPickup : .magnetPickup)` (doubler kind, when added → `.doublerPickup`) |
| `handleFX` `.shieldAbsorbed` | `synth.playSFX(Synth.chime())` | `synth.play(.chime)` |
| `handleFX` `.died` | `synth.playSFX(Synth.crash())` | `synth.play(.crash); synth.play(.deathSweep)` (impact + fall; both duck/stop under `musicStop()` which stays as-is) |
| `handleFX` `.worldChanged` | `synth.playSFX(Synth.worldSweep())` | `synth.play(.worldSweep)` |
| `handleFX` `.jumped` | `synth.playSFX(Synth.jump())` | `synth.play(.jump)` |
| `handleFX` `.slid` | `synth.playSFX(Synth.slide())` | `synth.play(.slide)` |

New hookups (currently silent moments):

- `handleFX` `case .laneChanged:` → `synth.play(.laneTick)`
- `handleFX` `case .landed:` → `synth.play(.landThud)` (intended for hard landings; if the core
  later distinguishes slam-landings, gate on that)
- New-best: in `recordRunResults()` (or wherever `core.score > previous best` is detected) →
  `synth.play(.newBestFanfare)`
- Shop purchase success (IAP or coin skin buy) → `synth.play(.purchaseChime)`
- Equipping an owned skin (`equipOrBuy`-style path) → `synth.play(.equipClick)`
- `open(_:)` / `closeSheet()` → `synth.play(.uiTick)`
- Future frenzy power-up: start → `synth.play(.frenzyStart)`, expiry → `synth.play(.frenzyEnd)`

Ducking: nothing to wire — `play(_:)` ducks automatically per `Synth.SFX.ducksMusic`.

Settings screen: set `synth.musicVolume` / `synth.sfxVolume` (0...1) directly from the sliders;
persist them in `Profile` (like `muted`) and re-apply both in `GameModel.install` next to
`synth.muted = profile.muted`. Values are live-only in the engine; clamping is handled in the
setters.

Cleanup once migrated: remove `SynthEngine.playSFX(_ samples:)`.

## Notes / risks
- `MainActor.assumeIsolated` in the notification blocks relies on `queue: .main` delivery; this is
  the same pattern as GameView's `SceneEvents.Update` handler. SynthEngine is `@MainActor` (hence
  implicitly Sendable) so the weak self capture is strict-concurrency clean.
- Interruption recovery restarts music scheduling from the current beat, not the exact sample —
  a deliberate simplification; the bed is a loop, nobody will notice.
- On a failed recovery we keep `started == true` and log: the next route/config notification
  retries, so audio can come back later instead of being dead for the session.
