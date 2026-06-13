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
    @ObservationIgnored private var gemCoinsAwarded = 0
    @ObservationIgnored private var distCoinsAwarded = 0
    @ObservationIgnored private var worldCoinsAwarded = 0
    @ObservationIgnored private var styleCoinsAwarded = 0
    /// XP/level outcome of this run, captured ONCE from `applyRunSummary` and held as model state
    /// (G3: the panel must animate the run's result, never a re-derived live-store snapshot).
    private(set) var lastLevelUp: LevelUpResult?
    /// Challenge-tier payout from `recordChallengeRun` (R16) — feeds the game-over tier line.
    private(set) var lastChallengePayout = 0
    // Per-run FX counters (missions feed + game-over stats), reset in `startRun`.
    @ObservationIgnored private var nearMissesThisRun = 0
    @ObservationIgnored private var closesThisRun = 0
    @ObservationIgnored private var slicksThisRun = 0
    @ObservationIgnored private var slidesThisRun = 0
    var nearMisses: Int { nearMissesThisRun }

    @ObservationIgnored private let autoplay = ProcessInfo.processInfo.environment["PR_AUTOPLAY"] == "1"
    @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["PR_DEMO"] == "1"

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
        // Debug: drop a shield just ahead so the HUD shield indicator is verifiable on the sim.
        if ProcessInfo.processInfo.environment["PR_SHIELD"] == "1" {
            core.debugSpawn(.shield(d: core.distance + 5, lane: 1))
        }
        // Debug/UITest: pin a true zero-run profile (first-run gate + FIRST RUN chip flows),
        // regardless of what earlier autoplay/CI cycles banked on this simulator.
        if ProcessInfo.processInfo.environment["PR_FIRSTRUN"] == "1" {
            ProfileStore.shared.mutate { $0.totalRuns = 0; $0.bestScore = 0 }
            core.best = 0
        }
        // Debug: jump straight to a meta screen for screenshots.
        switch ProcessInfo.processInfo.environment["PR_SCREEN"] {
        case "characters": activeSheet = .characters
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

                self.core.advance(realDt: dt)
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

    /// The actual run start — everything below the first-run gate.
    private func beginRun(fromWorld: Int, seed: UInt64?) {
        applyCurrentSkin()
        core.startRun(seed: seed, startDistance: Double(fromWorld) * Tuning.worldLength)
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
        lastLevelUp = nil
        lastChallengePayout = 0
        nearMissesThisRun = 0
        closesThisRun = 0
        slicksThisRun = 0
        slidesThisRun = 0
        statsRecorded = false
        newBestCelebrated = false
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
            beginRun(fromWorld: 0, seed: ProfileStore.shared.todaysChallengeSeed())
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
            addPopup("+\(Tuning.gemBaseScore * mult)", color: Theme.color(0xFFD23D), worldX: x)
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
            }
            flash(0.28)
        case let .shieldAbsorbed(x):
            addPopup("SHIELDED", color: .white, worldX: x)
            flash(0.25)
            synth.play(.chime)
        case .chronoEnded:
            synth.play(.frenzyStart)     // rising whoosh: time resumes
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

    func toggleMute() {
        muted.toggle()
        synth.muted = muted
        ProfileStore.shared.mutate { $0.muted = muted }
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
        let mult = store.profile.coinMultiplier
        let worldsCrossed = max(0, core.maxWorld - runStartWorld)
        lastCoinsFromGems = max(0, core.gemCount * mult - gemCoinsAwarded)
        gemCoinsAwarded += lastCoinsFromGems
        lastCoinsFromDistance = max(0, Int(core.traveledDistance / 35) * mult - distCoinsAwarded)
        distCoinsAwarded += lastCoinsFromDistance
        lastCoinsFromWorlds = max(0, worldsCrossed * 5 * mult - worldCoinsAwarded)
        worldCoinsAwarded += lastCoinsFromWorlds
        // 4th component (v1.3): CLOSE/SLICK style coins — same watermark shape as the other three
        // (XPCurve.styleCoins is cumulative-this-run, so post-revive deaths pay only the new part).
        lastCoinsFromStyle = max(0, XPCurve.styleCoins(closes: closesThisRun, slicks: slicksThisRun,
                                                       multiplier: mult) - styleCoinsAwarded)
        styleCoinsAwarded += lastCoinsFromStyle
        let coinsDelta = lastCoinsFromGems + lastCoinsFromDistance + lastCoinsFromWorlds + lastCoinsFromStyle
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

    /// Translate a finished drag/tap into game input. 22pt threshold separates tap from swipe.
    func handleGesture(_ t: CGSize) {
        let adx = abs(t.width), ady = abs(t.height)
        if max(adx, ady) < 22 {
            switch core.mode {
            case .menu: break    // the menu PLAY button starts a run
            case .over: break    // game-over uses explicit CONTINUE / RUN AGAIN / MENU buttons
            case .play: core.jump()
            }
            return
        }
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

    var body: some View {
        ZStack {
            Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255).ignoresSafeArea()

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
                    HStack(spacing: 10) {
                        Spacer()
                        Button { model.toggleMute() } label: {
                            Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                        }
                        .accessibilityLabel(model.muted ? "Unmute" : "Mute")
                        if model.core.snapshot.mode == .play {
                            Button { model.togglePause() } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 38, height: 38)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                            }
                            .accessibilityIdentifier("pauseButton")
                            .accessibilityLabel("Pause")
                        }
                    }
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.trailing, 16)
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
                             rewards: AnyView(RewardsBar(model: model, onMissions: { model.open(.missions) })),
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseForBackground() }
        }
    }
}
