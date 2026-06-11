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
    @ObservationIgnored private var overTime: Double = 0
    @ObservationIgnored private var demoElapsed: Double = 0
    @ObservationIgnored private var demoDied = false
    @ObservationIgnored private var uiClock: Double = 0
    @ObservationIgnored private var popupCounter = 0

    // Run-recording state (revive economy): a revived run dies more than once, so everything
    // cumulative is awarded as a delta over what this run has already paid out, and the lifetime
    // run counter is folded exactly once. All reset in `startRun`.
    @ObservationIgnored private var coinsAwardedThisRun = 0
    @ObservationIgnored private var distanceRecordedThisRun: Double = 0
    @ObservationIgnored private var gemsRecordedThisRun = 0
    @ObservationIgnored private var statsRecorded = false
    @ObservationIgnored private var newBestCelebrated = false
    @ObservationIgnored private var runStartWorld = 0

    /// True while the current run is today's shared challenge (revive is disabled — fair, shared
    /// track; checkpoint starts are structurally impossible, the entry point always seeds world 0).
    private(set) var isChallengeRun = false
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
        IAPManager.shared.start()
        GameCenterService.shared.authenticate()
        if ProcessInfo.processInfo.environment["PR_DEMOPROFILE"] == "1" {
            ProfileStore.shared.mutate {
                $0.coins = max($0.coins, 8000)
                $0.maxWorldReached = max($0.maxWorldReached, 6)
                $0.ownedSkins.formUnion(["ember", "void", "bolt"])
                $0.selectedSkin = "default"   // deterministic start state for UI tests/screenshots
                $0.lastDailyClaim = nil       // daily + chest always claimable in the demo profile
                $0.lastChestOpen = nil
            }
        }
        // One-shot launch reads (not a body snapshot — G3 applies to SwiftUI body observation).
        let saved = ProfileStore.shared.profile
        synth.muted = saved.muted
        muted = saved.muted
        // Settings persistence: SettingsView applies changes live (model.synth / model.haptics);
        // these lines make them stick across launches (AGENT_meta.md §4).
        synth.musicVolume = Float(saved.musicVolume)
        synth.sfxVolume = Float(saved.sfxVolume)
        haptics.enabled = saved.hapticsEnabled
        core.best = saved.bestScore
        applyCurrentSkin()
        checkSkinUnlocks()   // launch catch-up: cloud merges/level-ups earned while away grant here
        core.onFX = { [weak self] fx in self?.handleFX(fx) }
        if autoplay || demo { core.startRun(seed: 7) }
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
                    self.synth.musicPump(dt: dt, world: self.core.snapshot.worldTo)
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
                self.synth.musicPump(dt: dt, world: self.core.snapshot.worldTo)
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
    func startRun(fromWorld: Int = 0, seed: UInt64? = nil) {
        applyCurrentSkin()
        core.startRun(seed: seed, startDistance: Double(fromWorld) * Tuning.worldLength)
        renderer.resetEntities()
        // PLAY / RUN AGAIN must never inherit the challenge flag — `startDailyChallenge` re-sets
        // it AFTER this returns (AGENT_meta.md §3).
        isChallengeRun = false
        playTimeThisRun = 0
        previousBest = ProfileStore.shared.profile.bestScore
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
        activeSheet = nil
        synth.musicStart()
        synth.play(.startChime)
    }

    /// Start today's shared challenge run: seeded from the UTC date so the whole world plays the
    /// same track. Revive is disabled for fairness (see `canRevive`); a checkpoint start is
    /// structurally impossible (`fromWorld` stays 0).
    func startDailyChallenge() {
        startRun(seed: ProfileStore.shared.todaysChallengeSeed())
        isChallengeRun = true
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
        synth.musicStop()
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
        case let .worldChanged(index, ordinal):
            bannerName = Theme.worlds[index % 3].name
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
    /// Ownership guard: a cloud merge or stale save can select a skin this device doesn't own —
    /// fall back to the default rather than render an unowned cosmetic.
    func applyCurrentSkin() {
        let store = ProfileStore.shared
        let selected = SkinCatalog.skin(store.profile.selectedSkin)
        renderer.applySkin(store.owns(skin: selected.id) ? selected : SkinCatalog.skin("default"))
    }

    /// Auto-grant every newly earned character (XP level / achievement / challenge-days — R2) and
    /// celebrate each exactly once: `ownedSkins` insertion inside `refreshSkinUnlocks` is the
    /// dedupe, so a popup can never repeat. Called at install (launch catch-up), after run/
    /// challenge recording, and on sheet close (mission claims bump achievement tiers).
    private func checkSkinUnlocks() {
        let granted = ProfileStore.shared.refreshSkinUnlocks(level: ProfileStore.shared.playerLevel)
        for skin in granted {
            addPopup("NEW CHARACTER — \(skin.name.uppercased())",
                     color: Theme.color(skin.bodyHex == 0 ? 0x00F5FF : skin.bodyHex), worldX: 0)
            synth.play(.purchaseChime)
            haptics.levelUp()
        }
    }

    func open(_ screen: MetaScreen) { activeSheet = screen; synth.play(.uiTick) }

    func closeSheet() {
        activeSheet = nil
        synth.play(.uiTick)
        // MissionsView claims straight on ProfileStore (G3 store reads), so achievement-unlocked
        // characters (Drift/Wisp) are granted on the way back to the hub — popup lands on the menu.
        checkSkinUnlocks()
    }

    /// Equip an owned skin, or buy it with coins (premium skins require IAP — handled in the shop).
    @discardableResult
    func buyOrEquipSkin(_ skin: Skin) -> Bool {
        let store = ProfileStore.shared
        if store.owns(skin: skin.id) {
            store.select(skin: skin.id); applyCurrentSkin()
            synth.play(.equipClick)
            return true
        }
        guard !skin.premium, store.spendCoins(skin.cost) else { return false }
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

        if statsRecorded {
            // Post-revive death: pay only what's new; totalRuns was already counted for this run.
            store.mutate {
                $0.coins += coinsDelta
                $0.totalCoinsEarned += coinsDelta
                $0.bestScore = max($0.bestScore, core.score)
                $0.totalDistance += distanceDelta
                $0.totalGems += gemsDelta
                $0.bestStreak = max($0.bestStreak, core.bestStreak)
                $0.maxWorldReached = max($0.maxWorldReached, core.maxWorld)
            }
        } else {
            statsRecorded = true
            store.recordRun(score: core.score, distance: distanceDelta, gems: gemsDelta,
                            bestStreak: core.bestStreak, maxWorld: core.maxWorld, coinsEarned: coinsDelta)

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
            summary.worldsCrossed = core.maxWorld + 1      // 1-based, matches ach.worlds targets
            summary.startWorld = runStartWorld             // checkpoint start: zeroes skipped-world XP
            summary.revives = core.revivesUsed
            summary.duration = lastRunDuration
            // Captured as model state for the death panel (G3) — applyRunSummary stays
            // exactly-once-per-run behind this statsRecorded branch (rule 9).
            let result = store.applyRunSummary(summary)
            lastLevelUp = result
            if result.levelAfter > result.levelBefore {
                addPopup("LEVEL UP — \(result.levelAfter)", color: Theme.color(0x00F5FF), worldX: 0)
                synth.play(.levelUp)
                haptics.levelUp()
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
    @State private var showFirstRunTutorial = false
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    private func metaSheet(_ sheet: GameModel.MetaScreen) -> some View {
        switch sheet {
        case .characters:
            CharacterSelectView(model: model)
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
            // start below it — see HUDView's top padding) instead of floating top-centre.
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

            switch model.core.snapshot.mode {
            case .menu:
                if model.activeSheet == nil {
                    // Final v1.3 signature: settings ride inside Profile, Daily Rush inside the
                    // rewards rail — their legacy params are gone from this call site (R13).
                    MenuView(best: model.core.snapshot.best,
                             coins: ProfileStore.shared.profile.coins,
                             onPlay: {
                                 // First-ever PLAY routes through the tutorial (AGENT_meta.md §6).
                                 if ProfileStore.shared.profile.totalRuns == 0 { showFirstRunTutorial = true }
                                 else { model.startRun() }
                             },
                             onCharacters: { model.open(.characters) },
                             onShop: { model.open(.shop) },
                             onLevels: { model.open(.levels) },
                             onProfile: { model.open(.stats) },
                             rewards: AnyView(RewardsBar(model: model, onMissions: { model.open(.missions) })),
                             onHowToPlay: { showFirstRunTutorial = true })
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

            // Meta sheets render over the menu; over the death panel only the panel's own deep
            // links open (GET COINS/EARN ×2 → Shop, NEW CHARACTER → Characters, FULL STATS →
            // Profile — uiux §6.7; everything else stays menu-only).
            if let sheet = model.activeSheet,
               model.core.snapshot.mode == .menu
                || (model.core.snapshot.mode == .over
                    && (sheet == .shop || sheet == .characters || sheet == .stats)) {
                metaSheet(sheet).transition(.move(edge: .bottom))
            }

            // First-run tutorial: shown instead of the first PLAY, then starts the run on dismiss.
            if showFirstRunTutorial {
                HowToPlayView(onClose: { showFirstRunTutorial = false; model.startRun() },
                              doneLabel: "LET'S GO")
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
        }
        .statusBarHidden(true)
        .animation(.spring(duration: 0.3), value: model.rewardToast)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseForBackground() }
        }
    }
}
