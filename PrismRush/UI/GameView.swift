import SwiftUI
import RealityKit

/// Owns the engine, the renderer, and the per-frame loop. The loop is driven by RealityKit's
/// `SceneEvents.Update` (per the directive): advance the fixed-timestep core by wall-clock dt,
/// then push the snapshot to the renderer. `PR_AUTOPLAY` / `PR_DEMO` reuse the proven Autopilot so
/// gameplay can be screenshotted deterministically on the simulator without manual gestures.
@MainActor
@Observable
final class GameModel {
    let core = GameCore()
    @ObservationIgnored let renderer = RealityRenderer()
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored let synth = SynthEngine()
    @ObservationIgnored private var sub: EventSubscription?
    private(set) var muted = false
    private(set) var paused = false
    private(set) var rewardToast: String?
    @ObservationIgnored private var toastClearAt: Double = 0

    /// Which meta screen is open over the menu (nil = the menu hub itself).
    enum MetaScreen { case characters, shop, levels, stats, settings, missions }
    var activeSheet: MetaScreen?
    /// Skin the next CharacterSelect opens focused on (shop rail / featured-card routing —
    /// uiux §4.1: "tap card → CharacterSelect focused to THAT skin"). nil = focus the equipped.
    private(set) var pendingCharacterFocus: String?
    @ObservationIgnored private var overTime: Double = 0
    @ObservationIgnored private var demoElapsed: Double = 0
    @ObservationIgnored private var demoDied = false
    @ObservationIgnored private var uiClock: Double = 0
    @ObservationIgnored private var popupCounter = 0
    // Milestone celebrations (LEVEL UP / NEW CHARACTER) all share the same screen anchor and are
    // often born in the SAME call (crossing L3/L6/L12/L25 grants a character in the same death;
    // launch catch-up can grant several). A queue releases them one per beat so the headline
    // strings never render on top of each other and each VO announcement gets its moment.
    @ObservationIgnored private var milestoneQueue: [(text: String, color: Color, sfx: Synth.SFX)] = []
    @ObservationIgnored private var nextMilestoneAt: Double = 0
    /// Gap between milestone releases — the previous popup has risen clear (EffectsOverlay holds
    /// the milestone style 1.6 s; 1.0 s in, it sits well above the anchor and is mostly faded).
    private static let milestoneSpacing = 1.0

    // Run-recording state (revive economy): a revived run dies more than once, so everything
    // cumulative is awarded as a delta over what this run has already paid out, and the lifetime
    // run counter is folded exactly once. All reset in `startRun`.
    @ObservationIgnored private var coinsAwardedThisRun = 0
    @ObservationIgnored private var distanceRecordedThisRun: Double = 0
    @ObservationIgnored private var gemsRecordedThisRun = 0
    @ObservationIgnored private var statsRecorded = false
    @ObservationIgnored private var newBestCelebrated = false
    @ObservationIgnored private var runStartWorld = 0
    /// `maxWorldReached` captured at `startRun` — the basis for `ProfileStore.reachCredit`, so a
    /// PURCHASED-world start (beyond reach) can never fold its head-start into the reach ladder.
    @ObservationIgnored private var reachAtRunStart = 0

    /// True while the current run is today's shared challenge (revive is disabled — fair, shared
    /// track; checkpoint starts are structurally impossible, the entry point always seeds world 0).
    private(set) var isChallengeRun = false
    /// Monotonic timestamp of the last play-surface tap, for the blast's double-tap chain (v2.2).
    /// `@ObservationIgnored` because it changes on every tap and drives no view — observing it would
    /// re-render the whole hierarchy on each jump. Seeded far in the past so the first tap of a
    /// session can never chain.
    @ObservationIgnored private var lastTapAt: Double = -.greatestFiniteMagnitude
    /// First-run tutorial gate (AUDIT D6-1): non-nil while the tutorial is interposed before a
    /// run. Holds the ORIGINAL deferred start (menu PLAY, the rail's DAILY RUSH cell, or Worlds'
    /// PLAY FROM HERE / world cards) so LET'S GO proceeds to the run the player actually chose;
    /// the ✕ just clears it (D6-2 — an info tap is never a gameplay commitment).
    private(set) var pendingFirstRunStart: (() -> Void)?
    /// Seconds actually spent in `.play` this run (accumulated in the frame loop; pause, the death
    /// panel and revive shopping don't count — feeds the game-over TIME tile + RunSummary.duration).
    @ObservationIgnored private var playTimeThisRun: Double = 0
    /// Run duration captured at death-time, so the panel's TIME tile doesn't keep ticking.
    private(set) var lastRunDuration: Double = 0
    /// Best on record BEFORE this run started (death folds the run into profile.bestScore, so the
    /// panel must compare against this, not the live profile).
    private(set) var previousBest = 0
    // Exact per-death coin-delta split (sums to `lastCoinsEarned` — each component is an Int
    // before the multiplier, so the split is exact, no rounding drift).
    private(set) var lastCoinsFromGems = 0
    private(set) var lastCoinsFromDistance = 0
    private(set) var lastCoinsFromWorlds = 0
    /// The 4th per-death delta (v1.3): CLOSE/SLICK style coins via `XPCurve.styleCoins` (rule 9).
    private(set) var lastCoinsFromStyle = 0
    /// Warden bounty coins, tracked separately from gems so a kill never inflates the gem stat.
    private(set) var lastCoinsFromBounty = 0
    @ObservationIgnored private var gemCoinsAwarded = 0
    @ObservationIgnored private var distCoinsAwarded = 0
    @ObservationIgnored private var worldCoinsAwarded = 0
    @ObservationIgnored private var styleCoinsAwarded = 0
    @ObservationIgnored private var bountyCoinsAwarded = 0
    /// XP/level outcome of this run, captured ONCE from `applyRunSummary` and held as model state
    /// (G3: the panel must animate the run's result, never a re-derived live-store snapshot).
    private(set) var lastLevelUp: LevelUpResult?
    /// Challenge-tier payout from `recordChallengeRun` (R16) — feeds the game-over tier line.
    private(set) var lastChallengePayout = 0
    // Per-run FX counters (missions feed + game-over stats), reset in `startRun`.
    @ObservationIgnored private var nearMissesThisRun = 0
    @ObservationIgnored private var closesThisRun = 0
    @ObservationIgnored private var wardensDefeatedThisRun = 0
    @ObservationIgnored private var slicksThisRun = 0
    @ObservationIgnored private var slidesThisRun = 0
    /// Blasts fired this run (v2.2) — mirrored from the core for the run summary.
    @ObservationIgnored private var blastsThisRun = 0
    /// Edge latch so a blast that shatters five walls plays ONE shatter voice, not five.
    @ObservationIgnored private var shatterVoicedThisBlast = false
    var nearMisses: Int { nearMissesThisRun }

    // Pre-run loadout (v1.5): transient arm-state toggled on the hub. Consumed at run start in
    // `beginRun` (normal runs only — never the competitive Daily). `coinSurgeActiveThisRun` is
    // captured at run start and held stable for the whole run (incl. post-revive deaths), so the
    // coin payout multiplier never drifts mid-run.
    var armedHeadStart = false
    var armedCoinSurge = false
    @ObservationIgnored private(set) var coinSurgeActiveThisRun = false

    @ObservationIgnored private let autoplay = ProcessInfo.processInfo.environment["PR_AUTOPLAY"] == "1"
    @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["PR_DEMO"] == "1"
    @ObservationIgnored private let stumbleDebug = ProcessInfo.processInfo.environment["PR_STUMBLE"] == "1"
    /// `PR_BLAST=1` (QA/screenshot capture): fire a blast every 1.6 s during autoplay.
    @ObservationIgnored private let blastDebug = ProcessInfo.processInfo.environment["PR_BLAST"] == "1"
    @ObservationIgnored private var blastDebugT: Double = 0

    // First-run contextual control hints (the just-in-time tutorial): the first time each obstacle
    // type approaches on a brand-new player's first run, a "SWIPE UP/DOWN/SIDE" prompt appears so
    // they learn the control in context (Subway-Surfers/Temple-Run style). Pure presentation off
    // the snapshot — never touches Core/RNG, so the solvability bot is unaffected.
    enum TutorialCue: Equatable { case jump, slide, lane }
    private(set) var tutorialHint: TutorialCue?
    @ObservationIgnored private var tutorialActive = false
    @ObservationIgnored private var hintsShown: Set<TutorialCue> = []
    @ObservationIgnored private var hintTimer: Double = 0

    // SwiftUI-facing effect state (observed).
    struct Popup: Identifiable {
        let id: Int
        let text: String
        let color: Color
        let worldX: Double
        let born: Double
    }
    private(set) var popups: [Popup] = []
    private(set) var flashID = 0
    private(set) var flashStrength: Double = 0
    private(set) var shieldBreakID = 0   // increments on a shield-absorb to fire the glass-crack overlay
    private(set) var bannerID = 0
    private(set) var bannerName = ""
    private(set) var bannerOrdinal = 0
    private(set) var lastCoinsEarned = 0

    /// Restart is allowed a beat after death (lets the death moment land; avoids accidental
    /// restart). Stored + observed — `overTime` is `@ObservationIgnored`, so a computed property
    /// reading it would never trigger a SwiftUI re-render when the gate opens.
    private(set) var canRestart = false
    /// Whole seconds until RUN AGAIN unlocks (0 once it has) — observed, for a "READY IN X" label.
    private(set) var restartCountdown = 0

    func install(_ content: RealityViewCameraContent) {
        renderer.install(into: content)
        haptics.prepare()
        synth.start()
        synth.musicStart(calm: true)   // hub/splash ambience from launch (silenced until a run before)
        IAPManager.shared.start()
        GameCenterService.shared.authenticate()
        if ProcessInfo.processInfo.environment["PR_DEMOPROFILE"] == "1" {
            // Auto-granted characters (level/achievement/challengeDays) must read as LOCKED here:
            // XP and metrics banked by earlier autoplay/CI cycles on this simulator would otherwise
            // re-grant Pebble & co. and break the locked-requirement UI test. Strip the grants AND
            // zero the metrics that would instantly re-earn them in checkSkinUnlocks() below.
            let autoGranted = Set(SkinCatalog.all.compactMap { skin -> String? in
                switch skin.unlock {
                case .level, .achievement, .challengeDays: return skin.id
                case .free, .coins, .iap: return nil
                }
            })
            ProfileStore.shared.mutate {
                // EXACT pins, not max-folds (v1.4): the worlds buy-flow test needs rung 8
                // affordable (5,800) then rung 9 denied (7,400 > the 2,200 left) — coins banked
                // or worlds purchased by a prior CI cycle must never flip those outcomes.
                $0.coins = 8000
                $0.maxWorldReached = 6
                $0.purchasedWorlds = []
                $0.ownedSkins.formUnion(["ember", "void", "bolt"])
                $0.ownedSkins.subtract(autoGranted)
                $0.selectedSkin = "default"   // deterministic start state for UI tests/screenshots
                $0.lastDailyClaim = nil       // daily + chest always claimable in the demo profile
                $0.lastChestOpen = nil
                $0.totalXP = 0                // pin level 1 — Pebble's stage button reads REACH LEVEL 3
                $0.xpLevelRewarded = 1
                $0.achievementTier["ach.dist"] = 0    // Drift stays locked
                $0.achievementTier["ach.close"] = 0   // Wisp stays locked
                $0.challengeDaysPlayed = []           // Tempo stays locked
                // Pin the WHOLE achievement ladder (progress banked by earlier autoplay/CI cycles
                // would otherwise leave stray claimables): the claim-flow UI test opens on exactly
                // these three, and after its CLAIM ALL sweep exactly ONE re-arms (ach.chests sits
                // past BOTH tier targets, 10 then 100 — the single-claim leg). ach.gems' skin
                // needs tier 2, so claiming tier 1 here can never auto-grant a character.
                $0.missionProgress["ach.chests"] = 110
                $0.missionProgress["ach.gems"] = 100
                $0.missionProgress["ach.slick"] = 50
                $0.missionProgress["ach.dist"] = 0
                $0.missionProgress["ach.close"] = 0
                $0.missionProgress["ach.runs"] = 0
                $0.missionProgress["ach.worlds"] = 0
                $0.achievementTier["ach.chests"] = 0
                $0.achievementTier["ach.gems"] = 0
                $0.achievementTier["ach.slick"] = 0
                $0.achievementTier["ach.runs"] = 0
                $0.achievementTier["ach.worlds"] = 0
            }
        }
        // PR_SKIN=<id>: force-equip a skin (owned) so an autoplay run renders that character's
        // rig — the in-run verification side of the crest/aura screenshot hooks (decree 2).
        if let s = ProcessInfo.processInfo.environment["PR_SKIN"], !s.isEmpty {
            ProfileStore.shared.mutate { $0.ownedSkins.insert(s); $0.selectedSkin = s }
        }
        // One-shot launch reads (not a body snapshot — G3 applies to SwiftUI body observation).
        let saved = ProfileStore.shared.profile
        synth.muted = saved.muted
        muted = saved.muted
        // Settings persistence: SettingsView applies changes live (model.synth / model.haptics);
        // these lines make them stick across launches (AGENT_meta.md §4).
        synth.musicVolume = Float(saved.musicVolume)
        synth.menuMusicVolume = Float(saved.menuMusicVolume)
        synth.sfxVolume = Float(saved.sfxVolume)
        haptics.enabled = saved.hapticsEnabled
        core.best = saved.bestScore
        applyCurrentSkin()
        checkSkinUnlocks()   // launch catch-up: cloud merges/level-ups earned while away grant here
        core.onFX = { [weak self] fx in self?.handleFX(fx) }
        if autoplay || demo { core.startRun(seed: 7) }
        // Debug: PR_WORLD=n starts the run already inside world n (sky/decor verification on the
        // simulator — mirrors PR_AUTOPLAY above and combines with it; seed 7 keeps it repeatable).
        if let w = ProcessInfo.processInfo.environment["PR_WORLD"].flatMap(Int.init), w > 0 {
            beginRun(fromWorld: w, seed: 7)   // debug path — bypasses the first-run tutorial gate
        }
        // Debug: drop a chasm dead ahead so the tier-six gap can be inspected head-on without
        // running 2,560 m to meet one. Combine with PR_WORLD / PR_AUTOPLAY (which start the run).
        // Placed at the spawn horizon so it fades in from the backdrop exactly as a real one does.
        if ProcessInfo.processInfo.environment["PR_CHASM"] == "1" {
            core.debugSpawn(.chasm(d: core.distance + Tuning.spawnHorizon))
        }
        // Debug: PR_WARDEN=1 starts the run at the mouth of the first Warden arena with a full
        // charge bank, so the encounter can be inspected without running 2,400 m and collecting
        // ~520 gems to earn one. Uses the same checkpoint path a real world-start would, so the
        // arena, the arm window and the suppression all behave exactly as they do in a live run.
        if ProcessInfo.processInfo.environment["PR_WARDEN"] == "1" {
            beginRun(fromWorld: Tuning.wardenEveryWorlds, seed: 7)
            core.debugFillWardenCharge()
        }
        // Debug: drop a shield just ahead AND deploy one now (so the HUD chip + in-world dome show).
        if ProcessInfo.processInfo.environment["PR_SHIELD"] == "1" {
            core.debugSpawn(.shield(d: core.distance + 5, lane: 1))
            core.deployShield()
        }
        // Debug: arm Super Sneakers (active HUD ring + amber rig sparks + higher jump) and drop one
        // on the track. Combine with PR_WORLD / PR_AUTOPLAY (which start the run) so it's in play.
        if ProcessInfo.processInfo.environment["PR_SNEAKERS"] == "1" {
            core.debugSpawn(.superSneakers(d: core.distance + 6, lane: 1))
            core.debugActivateSuperSneakers()
        }
        // Debug/screenshot: deep reach so the Worlds ladder shows the evolved cycles past 12.
        if ProcessInfo.processInfo.environment["PR_DEEPWORLDS"] == "1" {
            ProfileStore.shared.mutate { $0.maxWorldReached = max($0.maxWorldReached, 14) }
        }
        // Debug/screenshot: a LATE-GAME hub state — deep reach (evolved palette live), a real best,
        // a high level, money banked, and every claimable already taken so the hub renders its idle
        // rewards state. The hub reads differently at each end of the profile range and a layout
        // verified only at first launch is not verified (PR-0452); this pins the far end so the
        // capture is repeatable across sessions.
        if ProcessInfo.processInfo.environment["PR_HUBDEEP"] == "1" {
            ProfileStore.shared.mutate {
                $0.coins = 24_500
                $0.bestScore = 128_400
                $0.totalRuns = 214
                $0.totalXP = 42_000
                $0.xpLevelRewarded = XPCurve.level(for: 42_000)
                $0.maxWorldReached = 14
                $0.headStartCharges = 3
                $0.coinSurgeCharges = 2
                $0.lastDailyClaim = Date()   // idle rewards state: nothing to claim
                $0.lastChestOpen = Date()
            }
            core.best = ProfileStore.shared.profile.bestScore
        }
        // Debug/UITest: pin a true zero-run profile (first-run gate + FIRST RUN chip flows),
        // regardless of what earlier autoplay/CI cycles banked on this simulator.
        if ProcessInfo.processInfo.environment["PR_FIRSTRUN"] == "1" {
            ProfileStore.shared.mutate { $0.totalRuns = 0; $0.bestScore = 0 }
            core.best = 0
        }
        // Debug: jump straight to a meta screen for screenshots.
        switch ProcessInfo.processInfo.environment["PR_SCREEN"] {
        case "characters":
            // PR_FOCUS=<skinID> opens the character screen pre-focused on that skin (screenshot hook).
            if let f = ProcessInfo.processInfo.environment["PR_FOCUS"], !f.isEmpty {
                pendingCharacterFocus = f
            }
            activeSheet = .characters
        case "shop": activeSheet = .shop
        case "levels": activeSheet = .levels
        case "stats": activeSheet = .stats
        case "settings": activeSheet = .settings
        case "missions": activeSheet = .missions
        default: break
        }

        sub = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dt = event.deltaTime
                self.uiClock += dt
                self.haptics.tick(dt, playing: self.core.mode == .play && !self.paused)

                if self.paused {
                    self.synth.musicPump(dt: dt, world: self.core.snapshot.worldOrdinal)
                    return   // freeze the simulation while paused; keep music + UI alive
                }

                if self.core.mode == .play { self.playTimeThisRun += dt }

                if (self.autoplay || self.demo), self.core.mode == .play {
                    Autopilot.drive(self.core)
                }
                if self.demo, self.core.mode == .play {
                    self.demoElapsed += dt
                    if self.demoElapsed > 6, !self.demoDied { self.demoDied = true; self.core.debugForceDie() }
                }
                if self.autoplay, self.core.mode == .over {
                    self.startRun()
                }
                // PR_STUMBLE=1: hold the player permanently staggered so the vulnerability shell,
                // the EXPOSED chip and the impact FX can be captured. Re-armed as the window
                // expires rather than fired once, because `Tuning.stumbleRecover` is 0.9 s — far
                // shorter than a launch-to-screenshot round trip. The Autopilot plays perfectly and
                // never enters a graze band, so an autoplay capture can never produce one itself.
                if self.stumbleDebug, self.core.mode == .play, self.core.stumbleT <= 0 {
                    self.core.debugStumble()
                }
                // PR_BLAST=1: fire THE BLAST on a cadence so an autoplay capture can show it.
                // Deliberately driven from HERE and not from `Autopilot.decide` — the 200-seed
                // solvability proof means "every pattern is survivable by dodging", and a bot that
                // could delete a pattern instead would turn that into "survivable or destructible".
                // `BlastTests.testTheSolvabilityBotNeverBlasts` is the guard; this hook keeps the
                // verb capturable without touching it.
                if self.blastDebug, self.core.mode == .play {
                    self.blastDebugT += dt
                    if self.blastDebugT >= 1.6 {
                        self.blastDebugT = 0
                        self.core.debugFillWardenCharge()
                        self.core.blast()
                    }
                }

                self.core.advance(realDt: dt)
                self.updateTutorialHints(dt: dt)
                self.renderer.advanceVisuals(dt)
                self.renderer.sync(self.core.snapshot)
                self.synth.musicPump(dt: dt, world: self.core.snapshot.worldOrdinal)
                self.overTime = self.core.mode == .over ? self.overTime + dt : 0
                let ready = self.core.mode == .over && self.overTime > 1.0
                if self.canRestart != ready { self.canRestart = ready }
                let remain = (self.core.mode == .over && !ready) ? Int((1.0 - self.overTime).rounded(.up)) : 0
                if self.restartCountdown != remain { self.restartCountdown = remain }
                self.ageEffects()
            }
        }
    }

    /// Start a run. `fromWorld > 0` is a checkpoint start (not leaderboard-eligible); pass a
    /// `seed` for deterministic runs — e.g. the daily challenge
    /// (`DailyChallenge.seed(year:month:day:)`, date derived in UTC).
    /// AUDIT D6-1: routes through the first-run tutorial gate, so EVERY live entrance (menu
    /// PLAY, Worlds' PLAY FROM HERE and world cards) tutors a zero-run player — not just PLAY.
    func startRun(fromWorld: Int = 0, seed: UInt64? = nil) {
        routeRun { [weak self] in self?.beginRun(fromWorld: fromWorld, seed: seed) }
    }

    /// ONE first-run gate for every run entrance (AUDIT D6-1). A zero-run player gets the
    /// tutorial first; LET'S GO (`confirmFirstRunTutorial`) executes the SAME deferred start,
    /// ✕ (`cancelFirstRunTutorial`) returns to where they were (D6-2). Autoplay/demo drive the
    /// core directly and skip the gate (CI/screenshot determinism).
    private func routeRun(_ start: @escaping () -> Void) {
        if ProfileStore.shared.profile.totalRuns == 0, !autoplay, !demo {
            pendingFirstRunStart = start
        } else {
            start()
        }
    }

    /// LET'S GO on the gated tutorial: clear the gate FIRST (the deferred start re-enters
    /// `startRun` paths via `beginRun`, never re-gates), then run the chosen start.
    func confirmFirstRunTutorial() {
        let start = pendingFirstRunStart
        pendingFirstRunStart = nil
        start?()
    }

    /// ✕ on the gated tutorial: drop the deferred start — back to the menu, no run (D6-2).
    func cancelFirstRunTutorial() {
        pendingFirstRunStart = nil
        synth.play(.uiTick)
    }

    /// First-run control hints. Each frame: hold the current prompt for a beat, else show the next
    /// untaught control the moment an obstacle that needs it enters a readable window ahead. Each
    /// control teaches once; after all three, it goes quiet. Reads only the snapshot.
    private func updateTutorialHints(dt: Double) {
        guard tutorialActive, core.mode == .play else {
            if tutorialHint != nil { tutorialHint = nil }
            return
        }
        if tutorialHint != nil {
            hintTimer -= dt
            if hintTimer <= 0 { tutorialHint = nil }
            return                                  // one prompt at a time
        }
        if hintsShown.count >= 3 { tutorialActive = false; return }
        for cue in [TutorialCue.jump, .slide, .lane] where !hintsShown.contains(cue) {
            let kinds = Self.cueKinds(cue)
            // Readable window: far enough ahead to read + react (z is negative ahead of the player).
            if core.snapshot.entities.contains(where: { kinds.contains($0.kind) && $0.z > -34 && $0.z < -12 }) {
                tutorialHint = cue
                hintsShown.insert(cue)
                hintTimer = 2.2
                synth.play(.uiTick)
                return
            }
        }
    }

    private static func cueKinds(_ cue: TutorialCue) -> [EntityKind] {
        switch cue {
        case .jump:  return [.low]
        case .slide: return [.bar, .splitBar]
        case .lane:  return [.tall, .movingTall]
        }
    }

    /// The actual run start — everything below the first-run gate. `consumeLoadout` is false for the
    /// competitive Daily run (pre-run consumables would be pay-to-win on the shared board — decree 5).
    private func beginRun(fromWorld: Int, seed: UInt64?, consumeLoadout: Bool = true) {
        applyCurrentSkin()
        core.startRun(seed: seed, startDistance: Double(fromWorld) * Tuning.worldLength)
        // Pre-run loadout: consume armed + available consumables now that the run is in `.play`.
        // Each is RNG-free and leaderboard-safe; Coin Surge only multiplies COINS, never the score.
        coinSurgeActiveThisRun = false
        if consumeLoadout {
            let store = ProfileStore.shared
            if armedHeadStart, store.profile.headStartCharges > 0 {
                store.mutate { $0.headStartCharges = max(0, $0.headStartCharges - 1) }
                core.activateHeadStart()
                if store.profile.headStartCharges == 0 { armedHeadStart = false }
            }
            if armedCoinSurge, store.profile.coinSurgeCharges > 0 {
                store.mutate { $0.coinSurgeCharges = max(0, $0.coinSurgeCharges - 1) }
                coinSurgeActiveThisRun = true
                if store.profile.coinSurgeCharges == 0 { armedCoinSurge = false }
            }
        }
        renderer.resetEntities()
        // PLAY / RUN AGAIN must never inherit the challenge flag — `startDailyChallenge` re-sets
        // it AFTER this returns (AGENT_meta.md §3).
        isChallengeRun = false
        playTimeThisRun = 0
        previousBest = ProfileStore.shared.profile.bestScore
        reachAtRunStart = ProfileStore.shared.profile.maxWorldReached
        overTime = 0
        canRestart = false
        restartCountdown = 0
        coinsAwardedThisRun = 0
        distanceRecordedThisRun = 0
        gemsRecordedThisRun = 0
        gemCoinsAwarded = 0
        distCoinsAwarded = 0
        worldCoinsAwarded = 0
        styleCoinsAwarded = 0
        bountyCoinsAwarded = 0
        lastLevelUp = nil
        lastChallengePayout = 0
        nearMissesThisRun = 0
        closesThisRun = 0
        wardensDefeatedThisRun = 0
        slicksThisRun = 0
        slidesThisRun = 0
        blastsThisRun = 0
        shatterVoicedThisBlast = false
        statsRecorded = false
        newBestCelebrated = false
        // Teach controls in-context only on a genuine brand-new player's first run.
        // PR_TUTORIAL=1 forces it on (QA/screenshot — lets autoplay keep the run alive to verify).
        let forceTutorial = ProcessInfo.processInfo.environment["PR_TUTORIAL"] == "1"
        tutorialActive = forceTutorial || (ProfileStore.shared.profile.totalRuns == 0 && !autoplay && !demo)
        hintsShown.removeAll()
        tutorialHint = nil
        hintTimer = 0
        runStartWorld = fromWorld
        paused = false
        popups.removeAll()
        milestoneQueue.removeAll()
        nextMilestoneAt = 0
        activeSheet = nil
        synth.musicStart()
        synth.play(.startChime)
    }

    /// Start today's shared challenge run: seeded from the UTC date so the whole world plays the
    /// same track. Revive is disabled for fairness (see `canRevive`); a checkpoint start is
    /// structurally impossible (`fromWorld` stays 0). First-run gated like every entrance
    /// (AUDIT D6-1) — the deferred start keeps the challenge flag, so LET'S GO still lands in
    /// the no-revive ruleset the player tapped (`beginRun` resets the flag; set it after).
    func startDailyChallenge() {
        routeRun { [weak self] in
            guard let self else { return }
            beginRun(fromWorld: 0, seed: ProfileStore.shared.todaysChallengeSeed(), consumeLoadout: false)
            isChallengeRun = true
        }
    }

    /// Pause is only meaningful mid-run. The pause button toggles it; backgrounding forces it on.
    func togglePause() {
        guard core.mode == .play else { return }
        paused.toggle()
    }

    func pauseForBackground() {
        if core.mode == .play { paused = true }
    }

    func resume() { paused = false }

    // Continue-after-death, paid with coins (no ads). Escalating cost, capped at 2 continues per run.
    var reviveCost: Int { 150 * (core.revivesUsed + 1) }
    var canRevive: Bool {
        core.mode == .over && !isChallengeRun && core.revivesUsed < 2
            && ProfileStore.shared.profile.coins >= reviveCost
    }

    @discardableResult
    func reviveForCoins() -> Bool {
        guard canRevive, ProfileStore.shared.spendCoins(reviveCost) else { return false }
        core.revive()
        overTime = 0
        canRestart = false
        restartCountdown = 0
        synth.musicStart()
        // A deliberate CONTINUE beat so it reads as resuming the SAME run (you keep your score), not a
        // fresh start: a flash, a "CONTINUE" call-out, and the shield-grant chime.
        flash(0.4)
        addPopup("CONTINUE", color: Theme.color(0x00F5FF), worldX: core.snapshot.playerX)
        synth.play(.shieldPickup)
        return true
    }

    // Retention rewards (menu).
    func claimDailyReward() {
        guard let r = ProfileStore.shared.claimDailyReward() else { return }
        showToast("DAY \(r.streak)  ·  +\(r.coins)")
        synth.play(.chime)
    }

    func openChest() {
        guard let amount = ProfileStore.shared.openFreeChest() else { return }
        showToast("CHEST  ·  +\(amount)")
        synth.play(.purchaseChime)
    }

    private func showToast(_ text: String) {
        rewardToast = text
        toastClearAt = uiClock + 2.4
    }

    /// Abandon the current run/over state and return to the menu hub (the "BACK TO MENU" path).
    func returnToMenu() {
        paused = false
        core.reset(seed: nil)
        renderer.resetEntities()
        synth.musicStart(calm: true)   // back to the calm hub bed (was musicStop → dead-silent menu)
        activeSheet = nil
        overTime = 0
        canRestart = false
        restartCountdown = 0
    }

    // MARK: effects

    private func handleFX(_ fx: FXEvent) {
        renderer.fire(fx)
        haptics.handle(fx)
        switch fx {
        case let .gemCollected(x, _, streak):
            let mult = min(Tuning.multCap, 1 + streak / Tuning.streakPerMult)
            // SCORE points, not coins — cyan (the score/interactive hue) so it never reads as a coin
            // payout (gold is reserved for actual currency). A gem pays 1 coin; this is the point pop.
            addPopup("+\(Tuning.gemBaseScore * mult)", color: Theme.color(0x00F5FF), worldX: x)
            synth.play(.gem(streak: streak))
        case let .nearMiss(kind, x):
            nearMissesThisRun += 1
            switch kind {
            case .close:
                closesThisRun += 1
                addPopup("CLOSE", color: Theme.color(0x00F5FF), worldX: x)
            case .slick:
                slicksThisRun += 1
                addPopup("SLICK", color: Theme.color(0xFFD23D), worldX: x)
            }
            synth.play(.close)
        case let .pickup(kind, x, _):
            switch kind {
            case .shield:
                addPopup("SHIELD", color: .white, worldX: x)
                synth.play(.shieldPickup)
            case .magnet:
                addPopup("MAGNET", color: .white, worldX: x)
                synth.play(.magnetPickup)
            case .doubler:
                addPopup("COINS ×2", color: Theme.color(0x00FF88), worldX: x)
                synth.play(.doublerPickup)
            case .chrono:
                addPopup("SLOW-MO", color: Theme.color(0x9BF0FF), worldX: x)
                synth.play(.frenzyEnd)   // falling whoosh: time dips into slow-mo
            case .superSneakers:
                addPopup("SUPER SNEAKERS", color: Theme.color(0xFF8A2B), worldX: x)
                synth.play(.sneakersPickup)  // bespoke spring-loaded leap (v1.6, was reusing boostStart)
            }
            flash(0.28)
        // MARK: Wardens (v1.9)
        //
        // Every sound here is a REUSE of an existing one-shot, chosen for what it already means:
        // the shield really is a shield breaking, the defeat really is an achievement stinger.
        // Bespoke Warden synthesis belongs to the audio pass (PR-0456) — nothing in this program
        // can hear a sound, so inventing four new DSP voices unheard would be guesswork shipped.
        case .wardenArrived:
            addPopup("WARDEN", color: Theme.color(0xFF3355), worldX: 0)
            synth.play(.worldSweep)
            flash(0.4)
        case let .wardenThrew(band, _):
            // One cue per shape, and the pitch direction names the verb (Synth §Warden telegraphs).
            // The three voices survive the v2.2 rebuild unchanged and are now BETTER placed: they
            // fire when the hazard leaves the craft, so the sound and the object appear together
            // instead of the sound announcing a band that was about to be painted over the deck.
            switch band {
            case .floor:   synth.play(.wardenFloorCue)
            case .curtain: synth.play(.wardenCurtainCue)
            case .lance:   synth.play(.wardenLanceCue)
            }
        case .wardenCoreHit:
            // **No popup during the fight (v2.2).** `EffectsOverlay` draws popups at row 0.52 of the
            // frame, which the S-011 audit measured as sitting inside the exact band the player is
            // reading — and this one fired after every successful answer, in hazard red, 0.40 s
            // before the next throw. The craft sheds a spar for every hit; that is the readout, it
            // is where the player's eyes already are, and it does not cover the deck.
            synth.play(.ringPerfect)
        case .wardenShieldBroke:
            addPopup("SHIELD DOWN", color: Theme.color(0x66E0FF), worldX: 0)
            synth.play(.shieldBreak)
            flash(0.5)
        case let .wardenDefeated(_, bounty):
            wardensDefeatedThisRun += 1
            addPopup("WARDEN DOWN  +\(bounty)", color: Theme.color(0xFFD23D), worldX: 0)
            synth.play(.levelUp)
            flash(0.6)
        case .wardenBrokeOff:
            // It gave up. Decree 3: this is an expected outcome, not a failure — so it is stated
            // plainly and paid nothing, rather than dressed up as a loss.
            addPopup("WARDEN WITHDREW", color: Theme.color(0x9AA6C8), worldX: 0)
            synth.play(.boostEnd)

        case let .shieldAbsorbed(x):
            // A real glass-shatter moment so you KNOW the shield broke: cyan call-out, hard flash,
            // the screen-crack overlay, and the glass-break SFX (v1.6).
            addPopup("SHIELD BROKEN", color: Theme.color(0x9BF0FF), worldX: x)
            flash(0.55)
            shieldBreakID += 1
            synth.play(.shieldBreak)
        case .chronoEnded:
            synth.play(.frenzyStart)     // rising whoosh: time resumes
        case .sneakersEnded:
            break   // jump height + HUD ring restore are snapshot-driven; the depleting ring is the cue
        case let .stumbled(x, fromWarden):
            // The multiplier reset is the cost, so the call-out names it. "CLOSE ONE" would read as
            // praise — this is the same word the HUD chip uses, and it is a warning.
            addPopup(fromWarden ? "HIT — ONE MORE ENDS IT" : "STUMBLE  ×1",
                     color: Theme.color(0xFF3355), worldX: x)
            // Reuses the shatter, which is what a survivable hard knock already sounds like in this
            // game. A bespoke stagger voice belongs with the Warden audio pass (PR-0456) — nothing
            // in this program can hear a sound, so inventing one unheard is guesswork shipped.
            synth.play(.shieldBreak)
            flash(0.3)
        // MARK: THE BLAST (v2.2)
        case let .blastFired(x, _, chargeLeft):
            blastsThisRun += 1
            shatterVoicedThisBlast = false
            // **No popup for an ordinary blast.** The first build called out "BLAST · 2 LEFT" on
            // every shot and it was wrong twice over on the simulator: it duplicated the HUD chip,
            // which already reads `⚡ BLAST ×2` (decree 4 — nothing on screen should be decoration),
            // and it printed cyan text across the middle of the frame at the exact moment the player
            // is watching a cyan shockwave open a path through it (decree 6). The ring and the
            // shatters ARE the feedback; the chip is the readout.
            //
            // Running dry is the one state change worth a word, because it is the one the player
            // cannot infer from what just happened on screen.
            //
            // `.boostStart` is a rising whoosh, the closest existing voice to a shockwave leaving.
            // A bespoke one belongs with the standing audio pass (PR-0456): nothing in this program
            // can hear a sound, and inventing one unheard is guesswork shipped — the same call
            // S-010 made for the stumble.
            if chargeLeft < Tuning.blastCost {
                addPopup("BLAST EMPTY", color: Theme.color(0x8C93B8), worldX: x)
            }
            synth.play(.boostStart)
        case .obstacleShattered:
            // ONE shatter voice per blast, not one per obstacle: a full-range blast can destroy
            // five walls inside 0.31 s, and five overlapping glass breaks is noise, not feedback.
            // This is the same edge-triggering `.slid` needed (v1.8) for the same reason.
            if !shatterVoicedThisBlast {
                shatterVoicedThisBlast = true
                synth.play(.shieldBreak)
            }
        case .died:
            flash(0.5)
            synth.play(.crash)
            synth.play(.deathSweep)
            synth.musicStop()
            recordRunResults()
        case let .worldChanged(_, ordinal):
            // Evolved name carries the cycle tier ("Neon Metropolis II") so deep worlds read as
            // distinct, not looped (v1.4.3).
            bannerName = Theme.evolvedPalette(ordinal: ordinal).name
            bannerOrdinal = ordinal
            bannerID += 1
            synth.play(.worldSweep)
        case .jumped:
            synth.play(.jump)
        case .slid:
            slidesThisRun += 1
            synth.play(.slide)
        case .landed:
            synth.play(.landThud)
        case .laneChanged:
            synth.play(.laneTick)
        // v1.3 mechanics — popup styles keyed by prefix in EffectsOverlay (RING/PERFECT/
        // OVERDRIVE/FLOW SURGE); the score shown is exactly what the core just paid.
        case let .ringPassed(x, _, perfect):
            if perfect {
                addPopup("PERFECT +\(Tuning.ringScore * core.mult)", color: Theme.color(0xFFD23D), worldX: x)
                synth.play(.ringPerfect)
            } else {
                addPopup("RING +\(Tuning.ringScore * core.mult)", color: Theme.color(0x00F5FF), worldX: x)
                synth.play(.ringPass)
            }
        case let .boostStarted(x):
            addPopup("OVERDRIVE", color: Theme.color(0xFF9F1C), worldX: x)
            synth.play(.boostStart)
        case .boostEnded:
            synth.play(.boostEnd)
        case let .flowSurge(level, x):
            addPopup(level > 1 ? "FLOW SURGE ×\(level)" : "FLOW SURGE",
                     color: Theme.color(0x00F5FF), worldX: x)
            synth.play(.flowSurge)
        }
    }

    func toggleMute() { setMuted(!muted) }

    /// The single writer for mute: the model flag, the live engine and the saved profile move
    /// together. Both the in-run corner control and the Settings row route through here — before
    /// PR-0305 the corner control was the ONLY caller, so a player who muted mid-run and relaunched
    /// had a permanently silent game and no way to find the one control that could undo it.
    func setMuted(_ on: Bool) {
        guard on != muted else { return }
        muted = on
        synth.muted = on
        ProfileStore.shared.mutate { $0.muted = on }
    }

    /// Push the equipped skin's full rig recipe to the renderer (v1.3 `applySkin(Skin)` API).
    /// Reads the canonical `ProfileStore.equippedSkinID` resolver (AUDIT D3-1) — the SAME
    /// ownership guard the menu hero, select stage, and shop cards render from, so the run can
    /// never silently diverge from what those surfaces call "Equipped".
    func applyCurrentSkin() {
        renderer.applySkin(SkinCatalog.skin(ProfileStore.shared.equippedSkinID))
    }

    /// Auto-grant every newly earned character (XP level / achievement / challenge-days — R2) and
    /// celebrate each exactly once: `ownedSkins` insertion inside `refreshSkinUnlocks` is the
    /// dedupe, so a popup can never repeat. Called at install (launch catch-up), after run/
    /// challenge recording, and on sheet close (mission claims bump achievement tiers).
    private func checkSkinUnlocks() {
        let granted = ProfileStore.shared.refreshSkinUnlocks(level: ProfileStore.shared.playerLevel)
        for skin in granted {
            celebrateMilestone("NEW CHARACTER — \(skin.name.uppercased())",
                               color: Theme.color(skin.bodyHex),
                               sfx: .purchaseChime)
        }
    }

    /// Queue a milestone popup (LEVEL UP / NEW CHARACTER). `ageEffects` releases one per
    /// `milestoneSpacing` beat — never two headline strings on the same anchor at once.
    private func celebrateMilestone(_ text: String, color: Color, sfx: Synth.SFX) {
        milestoneQueue.append((text, color, sfx))
    }

    /// Open a meta screen. `focusSkin` pre-focuses Characters' stage on that skin; the default
    /// nil clears any stale focus, so plain opens land on the equipped skin as before.
    func open(_ screen: MetaScreen, focusSkin: String? = nil) {
        pendingCharacterFocus = screen == .characters ? focusSkin : nil
        activeSheet = screen
        synth.play(.uiTick)
    }

    func closeSheet() {
        activeSheet = nil
        synth.play(.uiTick)
        // MissionsView claims straight on ProfileStore (G3 store reads), so achievement-unlocked
        // characters (Drift/Wisp) are granted on the way back to the hub — popup lands on the menu.
        checkSkinUnlocks()
    }

    /// Equip an owned skin, or buy it with coins (premium skins require IAP — handled in the shop).
    /// Hard gate, independent of UI routing: only `.free`/`.coins` unlocks are purchasable here —
    /// level/achievement/challengeDays skins read as cost 0 via the back-compat computeds, so a
    /// stray call site must never turn `spendCoins(0)` into a free legendary (review fix).
    @discardableResult
    func buyOrEquipSkin(_ skin: Skin) -> Bool {
        let store = ProfileStore.shared
        if store.owns(skin: skin.id) {
            store.select(skin: skin.id); applyCurrentSkin()
            synth.play(.equipClick)
            return true
        }
        switch skin.unlock {
        case .free:
            break                                                  // structurally always owned
        case .coins(let price):
            guard store.spendCoins(price) else { return false }
        case .level, .achievement, .challengeDays, .iap:
            return false                                           // auto-grant / StoreKit only
        }
        store.unlock(skin: skin.id); store.select(skin: skin.id); applyCurrentSkin()
        synth.play(.purchaseChime)
        return true
    }

    /// Fold the run-so-far into the profile and award coins (gems + distance + worlds crossed).
    /// Called on EVERY death — a revived run dies more than once — so all cumulative payouts are
    /// awarded as `max(0, cumulative − alreadyAwarded)` deltas, and `totalRuns` counts once per run.
    private func recordRunResults() {
        let store = ProfileStore.shared
        lastRunDuration = playTimeThisRun

        // New best fanfare, once per run, against the best on record BEFORE this death is folded in.
        if core.score > store.profile.bestScore, !newBestCelebrated {
            newBestCelebrated = true
            synth.play(.newBestFanfare)
        }

        // Earn = gems + traveled distance/35 + a small bonus per world crossed THIS run (a
        // checkpoint start must not pay for the skipped worlds), then the Double-Coins multiplier.
        // Computed per component so the death panel's breakdown is the exact delta split — each
        // component is an Int before the multiplier, so the sum equals the old single-base figure.
        // Coin Surge (pre-run consumable) stacks atop the Double-Coins IAP for THIS run only.
        // Captured at run start (stable across revives), so the watermark deltas never drift.
        let mult = store.profile.coinMultiplier * (coinSurgeActiveThisRun ? 2 : 1)
        let worldsCrossed = max(0, core.maxWorld - runStartWorld)
        // A gem is no longer a coin (v2.1, S-011 — `Tuning.coinsPerGemDivisor`). Integer division is
        // monotone non-decreasing in `gemCount`, so the per-death watermark below still holds.
        lastCoinsFromGems = max(0, core.gemCount / Tuning.coinsPerGemDivisor * mult - gemCoinsAwarded)
        gemCoinsAwarded += lastCoinsFromGems
        lastCoinsFromDistance = max(0, Int(core.traveledDistance / Tuning.coinsPerMetreDivisor) * mult
                                      - distCoinsAwarded)
        distCoinsAwarded += lastCoinsFromDistance
        lastCoinsFromWorlds = max(0, worldsCrossed * Tuning.coinsPerWorld * mult - worldCoinsAwarded)
        worldCoinsAwarded += lastCoinsFromWorlds
        // 4th component: CLOSE/SLICK style coins, plus flow-surge streak coins — same watermark shape
        // as the other three (XPCurve.styleCoins is cumulative-this-run, so post-revive deaths pay
        // only the new part). This is the term the owner asked to become the upside; it is uncapped.
        lastCoinsFromStyle = max(0, XPCurve.styleCoins(closes: closesThisRun, slicks: slicksThisRun,
                                                       surges: core.flowSurges,
                                                       multiplier: mult) - styleCoinsAwarded)
        styleCoinsAwarded += lastCoinsFromStyle
        // 5th component (S-009): Warden bounties. Their own watermark, and deliberately NOT folded
        // into `lastCoinsFromGems` — the bounty is currency the player was paid, not gems they
        // collected, and `RunSummary.gems` below feeds gem missions, the gem achievement and 2 XP
        // per gem. It used to land in `core.gemCount`, so one kill silently completed 40% of the
        // "collect 60 gems" mission and leaked 300 XP.
        lastCoinsFromBounty = max(0, core.bountyCoins * mult - bountyCoinsAwarded)
        bountyCoinsAwarded += lastCoinsFromBounty
        let coinsDelta = lastCoinsFromGems + lastCoinsFromDistance + lastCoinsFromWorlds
                       + lastCoinsFromStyle + lastCoinsFromBounty
        coinsAwardedThisRun += coinsDelta
        lastCoinsEarned = coinsDelta

        let distanceDelta = max(0, core.traveledDistance - distanceRecordedThisRun)
        distanceRecordedThisRun += distanceDelta
        let gemsDelta = max(0, core.gemCount - gemsRecordedThisRun)
        gemsRecordedThisRun += gemsDelta

        // Reach stays EARNED-by-play: a purchased-world start (runStartWorld beyond the reach at
        // launch) must not fold `core.maxWorld` into `maxWorldReached` or the reach-based
        // `ach.worlds` feed below — one bought-deep death would otherwise unlock every cheaper
        // rung for free (see ProfileStore.reachCredit; rules 9/10). Legit starts are unchanged.
        let reachWorld = ProfileStore.reachCredit(maxWorldThisRun: core.maxWorld,
                                                  startWorld: runStartWorld,
                                                  reachAtStart: reachAtRunStart)

        if statsRecorded {
            // Post-revive death: pay only what's new; totalRuns was already counted for this run.
            store.mutate {
                $0.coins += coinsDelta
                $0.totalCoinsEarned += coinsDelta
                $0.bestScore = max($0.bestScore, core.score)
                $0.totalDistance += distanceDelta
                $0.totalGems += gemsDelta
                $0.bestStreak = max($0.bestStreak, core.bestStreak)
                $0.maxWorldReached = max($0.maxWorldReached, reachWorld)
            }
        } else {
            statsRecorded = true
            store.recordRun(score: core.score, distance: distanceDelta, gems: gemsDelta,
                            bestStreak: core.bestStreak, maxWorld: reachWorld, coinsEarned: coinsDelta)

            // Missions feed: exactly once per run (`runsFinished` counts 1 per call, so post-revive
            // deaths must NOT call again — AGENT_meta.md §8's recommended shape). The first death
            // carries the run's metrics; post-revive tail progress is deliberately not folded
            // (accepted trade-off; `revives` therefore stays 0 here — see reports/AGENT_wiring.md).
            var summary = RunSummary()
            summary.gems = gemsDelta                       // == run totals at first death
            summary.distance = distanceDelta
            summary.nearMissCloses = closesThisRun
            summary.wardensDefeated = wardensDefeatedThisRun
            summary.slicks = slicksThisRun
            summary.slides = slidesThisRun
            summary.bestStreak = core.bestStreak           // max-style: engine maxes
            summary.bestMult = min(Tuning.multCap, 1 + core.bestStreak / Tuning.streakPerMult)
            summary.worldsCrossed = reachWorld + 1         // 1-based reach CREDIT (gated above) —
                                                           // ach.worlds stays reach-based (rule 9/10)
            summary.startWorld = runStartWorld             // checkpoint start: zeroes skipped-world XP
            summary.revives = core.revivesUsed
            summary.duration = lastRunDuration
            // Captured as model state for the death panel (G3) — applyRunSummary stays
            // exactly-once-per-run behind this statsRecorded branch (rule 9).
            let result = store.applyRunSummary(summary)
            lastLevelUp = result
            if result.levelAfter > result.levelBefore {
                celebrateMilestone("LEVEL UP — \(result.levelAfter)",
                                   color: Theme.color(0x00F5FF), sfx: .levelUp)
                // Earn deploy charges by levelling up (honest replenishment — decree 5): slow-mo +
                // speed-up ×2/level, shield ×1/level (a free on-demand hit is the most potent).
                //
                // **Coin surges are granted HERE, and only here plus the Mystery Box** (v2.1,
                // S-011). They used to be buyable for 450 coins, which let a player spend coins to
                // multiply coins — see the note in `ShopValue.coinPacks`. Earning them by levelling
                // makes the surge a reward for playing rather than a lever for compounding, and it
                // is the one grant a player cannot farm, because XP comes from runs.
                let levels = result.levelAfter - result.levelBefore
                store.mutate {
                    $0.slowMoCharges += 2 * levels
                    $0.speedUpCharges += 2 * levels
                    $0.shieldCharges += levels
                    $0.coinSurgeCharges += levels
                }
            }
        }

        // Daily challenge: fold the score into the per-UTC-day best + played calendar, and rank it
        // on the recurring daily leaderboard (shared seed, revive disabled — fair worldwide board).
        if isChallengeRun {
            lastChallengePayout = store.recordChallengeRun(score: core.score)   // tier payout (R16)
            GameCenterService.shared.submitDailyChallenge(score: core.score,
                                                          day: ProfileStore.daysSinceEpoch(Date()))
        }

        // Character grants ride the fresh post-run state: new XP level, new achievement tiers,
        // and (challenge deaths) the just-extended challengeDaysPlayed calendar (Tempo).
        checkSkinUnlocks()

        // Checkpoint runs ramp to end-game speed from t = 0 — never leaderboard-eligible
        // (the local best still updates above; see AGENT_core.md §Game Center).
        GameCenterService.shared.submitRun(score: core.score, usedCheckpoint: core.usedCheckpoint)
    }

    private func addPopup(_ text: String, color: Color, worldX: Double) {
        popupCounter += 1
        popups.append(Popup(id: popupCounter, text: text, color: color, worldX: worldX, born: uiClock))
        if popups.count > 12 { popups.removeFirst(popups.count - 12) }
    }

    private func flash(_ strength: Double) { flashStrength = strength; flashID += 1 }

    private func ageEffects() {
        // Prune window must outlive the longest EffectsOverlay popup style (milestones hold 1.6 s);
        // shorter popups have already faded to opacity 0 by then — lingering is invisible.
        if !popups.isEmpty { popups.removeAll { uiClock - $0.born > 1.8 } }
        // Release the next queued milestone once the previous one has had its beat (the chime and
        // success haptic ride the popup, so stacked grants celebrate one at a time, in order).
        if !milestoneQueue.isEmpty, uiClock >= nextMilestoneAt {
            let m = milestoneQueue.removeFirst()
            addPopup(m.text, color: m.color, worldX: 0)
            synth.play(m.sfx)
            haptics.levelUp()
            nextMilestoneAt = uiClock + Self.milestoneSpacing
        }
        if rewardToast != nil, uiClock > toastClearAt { rewardToast = nil }
    }

    // MARK: pre-run loadout (hub chips) — arm a consumable to bring into the next run.

    func toggleHeadStart() {
        guard ProfileStore.shared.profile.headStartCharges > 0 else { return }
        armedHeadStart.toggle()
        synth.play(armedHeadStart ? .equipClick : .uiTick)   // affirmative "armed" vs neutral "disarm"
    }

    func toggleCoinSurge() {
        guard ProfileStore.shared.profile.coinSurgeCharges > 0 else { return }
        armedCoinSurge.toggle()
        synth.play(armedCoinSurge ? .equipClick : .uiTick)
    }

    /// Whether the slow-mo button is live: in play, a charge banked, none already running. NEVER on a
    /// Daily Rush — banked/bought consumables must not skew the shared competitive board (decree 5 +
    /// iron rule 10, the same fairness reason challenge runs can't revive/checkpoint; the loadout is
    /// likewise gated via consumeLoadout:false).
    var canDeploySlowMo: Bool {
        core.mode == .play && !paused && !isChallengeRun
            && ProfileStore.shared.profile.slowMoCharges > 0 && core.chronoT <= 0
    }

    /// Deploy one banked slow-mo on demand (the HUD button). Spending persists immediately; the
    /// chrono FX/SFX fire through the normal pickup event path. A soft tick when it can't fire.
    func deploySlowMo() {
        guard core.mode == .play, !paused, !isChallengeRun else { return }
        guard ProfileStore.shared.profile.slowMoCharges > 0, core.chronoT <= 0 else {
            synth.play(.uiTick)
            return
        }
        if core.activateSlowMo() {
            ProfileStore.shared.mutate { $0.slowMoCharges = max(0, $0.slowMoCharges - 1) }
        }
    }

    /// Whether the Speed Up button is live: in play, a charge banked, no overdrive already running.
    var canDeploySpeedUp: Bool {
        core.mode == .play && !paused && !isChallengeRun
            && ProfileStore.shared.profile.speedUpCharges > 0 && core.boostT <= 0
    }

    /// Deploy one banked Speed Up (manual overdrive burst). Spending persists only on a successful
    /// core deploy; the boost FX/SFX ride the normal boost-start path. Soft tick when it can't fire.
    func deploySpeedUp() {
        guard core.mode == .play, !paused, !isChallengeRun else { return }
        guard ProfileStore.shared.profile.speedUpCharges > 0, core.boostT <= 0 else {
            synth.play(.uiTick)
            return
        }
        if core.deployOverdrive() {
            ProfileStore.shared.mutate { $0.speedUpCharges = max(0, $0.speedUpCharges - 1) }
        }
    }

    /// Whether the Shield button is live: in play, a charge banked, no shield already held.
    var canDeployShield: Bool {
        core.mode == .play && !paused && !isChallengeRun
            && ProfileStore.shared.profile.shieldCharges > 0 && !core.shield
    }

    /// Deploy one banked shield (a one-hit shield on demand). Spends only on a successful core deploy;
    /// the shield FX/SFX ride the normal pickup path. Soft tick when it can't fire (empty / already held).
    func deployShield() {
        guard core.mode == .play, !paused, !isChallengeRun else { return }
        guard ProfileStore.shared.profile.shieldCharges > 0, !core.shield else {
            synth.play(.uiTick)
            return
        }
        if core.deployShield() {
            ProfileStore.shared.mutate { $0.shieldCharges = max(0, $0.shieldCharges - 1) }
        }
    }

    /// Translate a finished drag/tap into game input. 22pt threshold separates tap from swipe.
    ///
    /// **The tap is never delayed (v2.2).** A double-tap recogniser would have to hold the first tap
    /// for its window before deciding, which is pure added latency on the game's most-used input —
    /// 0.30 s against a readable lead of 1.97 s at the speed cap, i.e. 15% of the entire reaction
    /// budget, on every jump in the game. So tap 1 fires `jump()` on the frame it arrives exactly as
    /// it always has, and a second tap inside `blastTapWindow` fires THE BLAST instead of the jump
    /// it would otherwise have buffered.
    ///
    /// Nothing is lost by that. A buffered jump only survives to touchdown if it is tapped within
    /// `jumpBuffer` (0.25 s) of landing — later than 0.565 s into an 0.815 s arc — so the whole of
    /// [0, 0.30 s] after a tap is input the game already discards. And when the bank is short,
    /// `core.blast()` returns false and we fall through to the jump, so the verb can never eat a tap.
    ///
    /// The chain resets after each blast (tap → jump, tap → blast, tap → jump …) so a burst of taps
    /// can never drain the bank, and a tap is only ever chained to the immediately preceding one.
    func handleGesture(_ t: CGSize) {
        let adx = abs(t.width), ady = abs(t.height)
        if max(adx, ady) < 22 {
            switch core.mode {
            case .menu: break    // the menu PLAY button starts a run
            case .over: break    // game-over uses explicit CONTINUE / RUN AGAIN / MENU buttons
            case .play:
                let now = ProcessInfo.processInfo.systemUptime   // monotonic; a wall clock can jump
                if now - lastTapAt <= Tuning.blastTapWindow, core.blast() {
                    lastTapAt = -.greatestFiniteMagnitude   // break the chain: the next tap jumps
                } else {
                    lastTapAt = now
                    core.jump()
                }
            }
            return
        }
        // A swipe is a deliberate, different verb — it must not leave a live tap chain behind that a
        // following tap could complete into a blast the player never asked for.
        lastTapAt = -.greatestFiniteMagnitude
        guard core.mode == .play else { return }
        if adx > ady {
            core.changeLane(t.width > 0 ? 1 : -1)
        } else if t.height < 0 {
            core.jump()
        } else {
            core.slide()
        }
    }
}

struct GameView: View {
    @State private var model = GameModel()
    /// Info-mode tutorial (the FIRST RUN chip): browse-and-dismiss only — both ✕ and GOT IT
    /// return to the menu, never into a run (AUDIT D6-2). The pre-run tutorial is the model's
    /// `pendingFirstRunStart` gate, a separate flow.
    @State private var showHowToPlayInfo = false
    /// Launch splash, shown once over the booting scene; first tap fades into the hub.
    /// `PR_SKIP_SPLASH=1` (QA/screenshot capture only) boots straight to the hub.
    @State private var showSplash =
        ProcessInfo.processInfo.environment["PR_SKIP_SPLASH"] != "1"
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    private func metaSheet(_ sheet: GameModel.MetaScreen) -> some View {
        switch sheet {
        case .characters:
            CharacterSelectView(model: model, initialFocus: model.pendingCharacterFocus)
        case .levels:
            LevelSelectView(model: model)
        case .shop:
            ShopView(model: model)
        case .stats:
            ProfileView(model: model)
        case .settings:
            SettingsView(model: model)
        case .missions:
            MissionsView(model: model)
        }
    }

    /// Top-corner control glyph (mute / pause). 48 pt (was 38) with a bigger icon — easier to reach
    /// and hit on a large phone (owner), kept top-trailing where pause is conventionally expected.
    private func cornerControlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.16)))
            .contentShape(Circle())
    }

    /// The three banked deploy buttons (v1.6): SLOW-MO + SPEED UP stacked in the bottom-LEFT, and
    /// SHIELD in the bottom-RIGHT — big, labelled, colour-coded, thumb-reachable in the bottom
    /// corners (the owner's "that tiny button in a rush is impossible" fix). Reads the store live (G3).
    private var deployControls: some View {
        // A deploy button shows ONLY when you actually hold a charge (owner: no dimmed dead buttons —
        // zero clutter when there's nothing to deploy). Reads live at point of use (G3).
        let slowMo = ProfileStore.shared.profile.slowMoCharges
        let speedUp = ProfileStore.shared.profile.speedUpCharges
        let shield = ProfileStore.shared.profile.shieldCharges
        return HStack(alignment: .bottom) {
            VStack(spacing: 10) {
                if slowMo > 0 {
                    deployButton(kind: .slowMo, label: "SLOW-MO",
                                 charges: slowMo, live: model.canDeploySlowMo,
                                 id: "slowMoButton") { model.deploySlowMo() }
                }
                if speedUp > 0 {
                    deployButton(kind: .speedUp, label: "SPEED UP",
                                 charges: speedUp, live: model.canDeploySpeedUp,
                                 id: "speedUpButton") { model.deploySpeedUp() }
                }
            }
            Spacer()
            if shield > 0 {
                deployButton(kind: .shield, label: "SHIELD",
                             charges: shield, live: model.canDeployShield,
                             id: "shieldButton") { model.deployShield() }
            }
        }
    }

    /// A big circular deploy button + label + charge badge. Lit in the power-up's colour when ready,
    /// dimmed + disabled when empty (a soft tick if tapped while its effect is already running).
    private func deployButton(kind: PowerUpKind, label: String, charges: Int, live: Bool,
                              id: String, action: @escaping () -> Void) -> some View {
        let color = Theme.color(kind.hex)
        return Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    PowerUpGlyph(kind: kind, size: 28, tint: live ? color : .white.opacity(0.4))
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(live ? color.opacity(0.7) : .white.opacity(0.12), lineWidth: 1.5))
                        .shadow(color: live ? color.opacity(0.55) : .clear, radius: 10)
                    Text("\(charges)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.black)
                        .frame(minWidth: 21, minHeight: 21)
                        .background(charges > 0 ? color : Color.white.opacity(0.5), in: Circle())
                        .offset(x: 6, y: -4)
                }
                Text(label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5)
                    .foregroundStyle(live ? color : .white.opacity(0.4))
            }
            .opacity(charges == 0 ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(charges == 0)
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(label), \(charges) charges")
        .accessibilityHint(live ? "Deploys \(label)." : "No charge ready.")
    }

    /// The first-run control prompt — a calm capsule below the meters, never interactive.
    private func tutorialBanner(_ cue: GameModel.TutorialCue) -> some View {
        let icon: String
        let text: String
        switch cue {
        case .jump:  icon = "arrow.up"; text = "SWIPE UP TO JUMP"
        case .slide: icon = "arrow.down"; text = "SWIPE DOWN TO SLIDE"
        case .lane:  icon = "arrow.left.and.right"; text = "SWIPE TO CHANGE LANE"
        }
        return VStack {
            Spacer().frame(height: 128)   // clear of the meters readout up top
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 19, weight: .heavy))
                Text(text).font(.system(size: 16, weight: .heavy, design: .rounded)).tracking(1)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.actionGradient, in: Capsule())
            .shadow(color: Theme.color(0x00F5FF).opacity(0.5), radius: 16)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The near-black the 3D scene sits on. Shared by the root backdrop and the hub's lower-third
    /// scrim (PR-0445) so the fade resolves to exactly the same colour it started from.
    static let voidColor = Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255)

    var body: some View {
        ZStack {
            Self.voidColor.ignoresSafeArea()

            RealityView { content in
                model.install(content)
            }
            .ignoresSafeArea()

            // Full-surface gesture catcher (behind the overlays' own controls).
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { model.handleGesture($0.translation) })
                .ignoresSafeArea()

            HUDView(core: model.core)

            // Mute/pause cluster anchored to the top-trailing corner (the HUD's right-hand chips
            // start below it — see HUDView's top padding) instead of floating top-centre. Hidden in
            // `.menu` mode: it used to sit on top of the hub's coin badge (the owner's "hidden
            // circular button behind the coins"). On the hub, audio lives in Settings (top-right
            // gear); this cluster is for play/over only.
            if model.core.snapshot.mode != .menu {
                VStack {
                    HStack(spacing: 12) {
                        Spacer()
                        Button { model.toggleMute() } label: {
                            cornerControlIcon(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(model.muted ? "Unmute" : "Mute")
                        if model.core.snapshot.mode == .play {
                            Button { model.togglePause() } label: {
                                cornerControlIcon("pause.fill")
                            }
                            .accessibilityIdentifier("pauseButton")
                            .accessibilityLabel("Pause")
                        }
                    }
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.trailing, 14)
            }

            // PR-0445 / D-008 — the attract track used to cross the hub's glyphs: a solid magenta
            // band cut straight through "HEAD START ×1" and diagonals sliced the CHARACTERS / SHOP /
            // WORLDS row. That fails decree 6 (clarity beats spectacle). The hub's lower half is
            // where every tappable card lives, so the track fades into the void colour under it —
            // the neon look survives up top around the hero and the wordmark, which is the part
            // worth keeping, and nothing crosses a glyph below. Menu only; hit-testing untouched.
            //
            // S-005 adds the mirrored top band. The masthead's wordmark used to sit straight on the
            // city skyline (PR-0452's "the wordmark collides with the city backdrop"); the redesign
            // left-aligns it and rules a hairline under it, which only reads as deliberate chrome if
            // there is a plate behind it. The band is shallow — fully clear again by 16% — so the
            // skyline and the whole hero region are untouched.
            if model.core.snapshot.mode == .menu && model.activeSheet == nil {
                LinearGradient(stops: [
                    // Four stops, not two, and a long tail: a short fade met the untouched skyline
                    // as a visible horizontal seam across the buildings, right where the masthead
                    // rule sits — which read as a rendering artefact rather than as chrome.
                    .init(color: Self.voidColor.opacity(0.78), location: 0.00),
                    .init(color: Self.voidColor.opacity(0.46), location: 0.07),
                    .init(color: Self.voidColor.opacity(0.17), location: 0.14),
                    .init(color: .clear, location: 0.23),
                    .init(color: Self.voidColor.opacity(0.55), location: 0.50),
                    .init(color: Self.voidColor.opacity(0.93), location: 0.66),
                    .init(color: Self.voidColor.opacity(0.97), location: 1.00),
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            switch model.core.snapshot.mode {
            case .menu:
                if model.activeSheet == nil {
                    // Final v1.3 signature: settings ride inside Profile, Daily Rush inside the
                    // rewards rail — their legacy params are gone from this call site (R13).
                    MenuView(best: model.core.snapshot.best,
                             coins: ProfileStore.shared.profile.coins,
                             // First-ever PLAY tutors via the model-level gate (AUDIT D6-1) —
                             // the SAME gate Daily Rush and Worlds starts route through.
                             onPlay: { model.startRun() },
                             onCharacters: { model.open(.characters) },
                             onShop: { model.open(.shop) },
                             onLevels: { model.open(.levels) },
                             onProfile: { model.open(.stats) },
                             onSettings: { model.open(.settings) },
                             onMissions: { model.open(.missions) },
                             // The hub's own actions, passed as closures rather than an injected
                             // AnyView (PR-0134): an AnyView here is the exact shape that severed
                             // @Observable tracking and shipped the "Head Start does nothing" bug.
                             onDailyRush: { model.startDailyChallenge() },
                             onClaimDaily: { model.claimDailyReward() },
                             onOpenChest: { model.openChest() },
                             loadout: LoadoutStrip(model: model),
                             onHowToPlay: { showHowToPlayInfo = true })
                }
            case .over:
                GameOverView(snapshot: model.core.snapshot,
                             coinsEarned: model.lastCoinsEarned,
                             canRestart: model.canRestart,
                             canRevive: model.canRevive,
                             reviveCost: model.reviveCost,
                             onRevive: { model.reviveForCoins() },
                             onRestart: { model.startRun() },
                             onHome: { model.returnToMenu() },
                             previousBest: model.previousBest,
                             runDistance: model.core.traveledDistance,
                             timeSurvived: model.lastRunDuration,
                             bestStreak: model.core.bestStreak,
                             nearMisses: model.nearMisses,
                             coinsFromGems: model.lastCoinsFromGems,
                             coinsFromDistance: model.lastCoinsFromDistance,
                             coinsFromWorlds: model.lastCoinsFromWorlds,
                             revivesLeft: model.isChallengeRun ? 0 : 2 - model.core.revivesUsed,
                             restartCountdown: model.restartCountdown,
                             onGetCoins: { model.open(.shop) },
                             levelUp: model.lastLevelUp,
                             styleCoins: model.lastCoinsFromStyle,
                             challengePayout: model.lastChallengePayout,
                             isChallengeRun: model.isChallengeRun,
                             onCharacters: { model.open(.characters) },
                             onFullStats: { model.open(.stats) })
            case .play:
                EmptyView()
            }

            // Meta sheets render over the menu AND over the death panel. The panel's deep links
            // (GET COINS → Shop, NEW CHARACTER → Characters, FULL STATS → Profile — uiux §6.7)
            // open sheets that themselves route onward (Profile → gear → Settings / WORLDS tile →
            // Worlds; CharacterSelect locked-tap → Missions), so a per-sheet allowlist would
            // vanish the visible sheet on those in-sheet routes (clickability audit, uiux §5).
            // Never during play — gameplay input owns the screen there.
            if let sheet = model.activeSheet, model.core.snapshot.mode != .play {
                metaSheet(sheet).transition(.move(edge: .bottom))
            }

            // First-run tutorial, interposed by the model gate before ANY first run — PLAY,
            // Daily Rush, or Worlds (AUDIT D6-1). Only LET'S GO commits to the chosen run;
            // the ✕ cancels back to where the player was (D6-2).
            if model.pendingFirstRunStart != nil {
                HowToPlayView(onClose: { model.cancelFirstRunTutorial() },
                              onDone: { model.confirmFirstRunTutorial() },
                              doneLabel: "LET'S GO")
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            } else if showHowToPlayInfo {
                // Info-mode (FIRST RUN chip): ✕ and GOT IT both just return to the menu.
                HowToPlayView(onClose: { showHowToPlayInfo = false })
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }

            EffectsOverlay(model: model)

            // First-run just-in-time control hints — a calm prompt the first time each obstacle
            // type appears on a new player's first run.
            if let hint = model.tutorialHint, model.core.snapshot.mode == .play {
                tutorialBanner(hint)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }

            // Manual deploy buttons — SLOW-MO (left) + SPEED UP (right) in the bottom corners,
            // thumb-reachable, above the XP bar. Above the gesture catcher so taps don't jump. NEVER
            // on a Daily Rush: the shared competitive board stays consumable-free (decree 5).
            if model.core.snapshot.mode == .play && !model.isChallengeRun {
                VStack {
                    Spacer()
                    deployControls
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
                .zIndex(4)
            }

            if model.paused {
                PauseOverlay(onResume: { model.resume() }, onQuit: { model.returnToMenu() })
                    .transition(.opacity)
            }

            if let toast = model.rewardToast {
                VStack {
                    Text(toast)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(LinearGradient(colors: [Theme.color(0xFFD23D), Theme.color(0xFF9F1C)],
                                                   startPoint: .leading, endPoint: .trailing), in: Capsule())
                        .shadow(color: Theme.color(0xFFD23D).opacity(0.5), radius: 16)
                        .padding(.top, 80)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Launch splash — topmost, covering the booting RealityKit scene. The calm hub bed
            // already plays (started in `install`); the first tap fades through to the menu.
            if showSplash {
                SplashView(onStart: { withAnimation(.easeOut(duration: 0.45)) { showSplash = false } })
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .statusBarHidden(true)
        .animation(.spring(duration: 0.3), value: model.rewardToast)
        .animation(.easeInOut(duration: 0.3), value: model.tutorialHint)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseForBackground() }
        }
    }
}
