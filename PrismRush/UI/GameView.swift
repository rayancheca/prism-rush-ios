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
    enum MetaScreen { case characters, shop, levels, stats }
    var activeSheet: MetaScreen?
    @ObservationIgnored private var overTime: Double = 0
    @ObservationIgnored private var demoElapsed: Double = 0
    @ObservationIgnored private var demoDied = false
    @ObservationIgnored private var uiClock: Double = 0
    @ObservationIgnored private var popupCounter = 0

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

    /// Restart is allowed a beat after death (lets the death moment land; avoids accidental restart).
    var canRestart: Bool { overTime > 1.0 }

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
                $0.ownedSkins.formUnion(["ember", "void"])
                $0.selectedSkin = "default"   // deterministic start state for UI tests/screenshots
                $0.lastDailyClaim = nil       // daily + chest always claimable in the demo profile
                $0.lastChestOpen = nil
            }
        }
        let profile = ProfileStore.shared.profile
        synth.muted = profile.muted
        muted = profile.muted
        core.best = profile.bestScore
        applyCurrentSkin()
        core.onFX = { [weak self] fx in self?.handleFX(fx) }
        if autoplay || demo { core.startRun(seed: 7) }
        // Debug: jump straight to a meta screen for screenshots.
        switch ProcessInfo.processInfo.environment["PR_SCREEN"] {
        case "characters": activeSheet = .characters
        case "shop": activeSheet = .shop
        case "levels": activeSheet = .levels
        case "stats": activeSheet = .stats
        default: break
        }

        sub = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dt = event.deltaTime
                self.uiClock += dt
                self.haptics.tick(dt)

                if self.paused {
                    self.synth.musicPump(dt: dt, world: self.core.snapshot.worldTo)
                    return   // freeze the simulation while paused; keep music + UI alive
                }

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
                self.ageEffects()
            }
        }
    }

    func startRun(fromWorld: Int = 0) {
        applyCurrentSkin()
        core.startRun(startDistance: Double(fromWorld) * Tuning.worldLength)
        renderer.resetEntities()
        overTime = 0
        paused = false
        popups.removeAll()
        activeSheet = nil
        synth.musicStart()
        synth.playSFX(Synth.startChime())
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
        core.mode == .over && core.revivesUsed < 2 && ProfileStore.shared.profile.coins >= reviveCost
    }

    @discardableResult
    func reviveForCoins() -> Bool {
        guard canRevive, ProfileStore.shared.spendCoins(reviveCost) else { return false }
        core.revive()
        overTime = 0
        synth.musicStart()
        synth.playSFX(Synth.shieldChime())
        return true
    }

    // Retention rewards (menu).
    func claimDailyReward() {
        guard let r = ProfileStore.shared.claimDailyReward() else { return }
        showToast("DAY \(r.streak)  ·  +\(r.coins)")
        synth.playSFX(Synth.chime())
    }

    func openChest() {
        guard let amount = ProfileStore.shared.openFreeChest() else { return }
        showToast("CHEST  ·  +\(amount)")
        synth.playSFX(Synth.shieldChime())
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
    }

    // MARK: effects

    private func handleFX(_ fx: FXEvent) {
        renderer.fire(fx)
        haptics.handle(fx)
        switch fx {
        case let .gemCollected(x, _, streak):
            let mult = min(5, 1 + streak / 8)
            addPopup("+\(10 * mult)", color: Theme.color(0xFFD23D), worldX: x)
            synth.playSFX(Synth.gem(streak: streak))
        case let .nearMiss(kind, x):
            addPopup(kind, color: kind == "CLOSE" ? Theme.color(0x00F5FF) : Theme.color(0xFFD23D), worldX: x)
            synth.playSFX(Synth.close())
        case let .pickup(kind, x, _):
            addPopup(kind == .shield ? "SHIELD" : "MAGNET", color: .white, worldX: x)
            flash(0.28)
            synth.playSFX(kind == .shield ? Synth.shieldChime() : Synth.magnetChime())
        case let .shieldAbsorbed(x):
            addPopup("SHIELDED", color: .white, worldX: x)
            flash(0.25)
            synth.playSFX(Synth.chime())
        case .died:
            flash(0.5)
            synth.playSFX(Synth.crash())
            synth.musicStop()
            recordRunResults()
        case let .worldChanged(index, ordinal):
            bannerName = Theme.worlds[index % 3].name
            bannerOrdinal = ordinal
            bannerID += 1
            synth.playSFX(Synth.worldSweep())
        case .jumped:
            synth.playSFX(Synth.jump())
        case .slid:
            synth.playSFX(Synth.slide())
        case .landed, .laneChanged:
            break
        }
    }

    func toggleMute() {
        muted.toggle()
        synth.muted = muted
        ProfileStore.shared.mutate { $0.muted = muted }
    }

    func applyCurrentSkin() {
        let skin = SkinCatalog.skin(ProfileStore.shared.profile.selectedSkin)
        renderer.applySkin(bodyHex: skin.bodyHex, antennaHex: skin.antennaHex, followsWorld: skin.followsWorld)
    }

    func open(_ screen: MetaScreen) { activeSheet = screen }
    func closeSheet() { activeSheet = nil }

    /// Equip an owned skin, or buy it with coins (premium skins require IAP — handled in the shop).
    @discardableResult
    func buyOrEquipSkin(_ skin: Skin) -> Bool {
        let store = ProfileStore.shared
        if store.owns(skin: skin.id) {
            store.select(skin: skin.id); applyCurrentSkin(); return true
        }
        guard !skin.premium, store.spendCoins(skin.cost) else { return false }
        store.unlock(skin: skin.id); store.select(skin: skin.id); applyCurrentSkin()
        return true
    }

    /// Fold the just-finished run into the profile and award coins (gems + a distance bonus).
    private func recordRunResults() {
        let store = ProfileStore.shared
        // Earn = gems + distance/35 + a small per-world bonus, then the Double-Coins multiplier.
        let base = core.gemCount + Int(core.traveledDistance / 35) + core.maxWorld * 5
        let coins = base * store.profile.coinMultiplier
        lastCoinsEarned = coins
        store.recordRun(score: core.score, distance: core.distance, gems: core.gemCount,
                        bestStreak: core.bestStreak, maxWorld: core.maxWorld, coinsEarned: coins)
        GameCenterService.shared.submit(store.profile.bestScore)
    }

    private func addPopup(_ text: String, color: Color, worldX: Double) {
        popupCounter += 1
        popups.append(Popup(id: popupCounter, text: text, color: color, worldX: worldX, born: uiClock))
        if popups.count > 12 { popups.removeFirst(popups.count - 12) }
    }

    private func flash(_ strength: Double) { flashStrength = strength; flashID += 1 }

    private func ageEffects() {
        if !popups.isEmpty { popups.removeAll { uiClock - $0.born > 0.9 } }
        if rewardToast != nil, uiClock > toastClearAt { rewardToast = nil }
    }

    /// Translate a finished drag/tap into game input. 22pt threshold separates tap from swipe.
    func handleGesture(_ t: CGSize) {
        let adx = abs(t.width), ady = abs(t.height)
        if max(adx, ady) < 22 {
            switch core.mode {
            case .menu: break                       // the menu PLAY button starts a run
            case .over: if canRestart { startRun() }
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

            VStack {
                HStack(spacing: 10) {
                    Button { model.toggleMute() } label: {
                        Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                    }
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
                    }
                }
                Spacer()
            }
            .padding(.top, 14)

            switch model.core.snapshot.mode {
            case .menu:
                if model.activeSheet == nil {
                    MenuView(best: model.core.snapshot.best,
                             coins: ProfileStore.shared.profile.coins,
                             onPlay: { model.startRun() },
                             onCharacters: { model.open(.characters) },
                             onShop: { model.open(.shop) },
                             onLevels: { model.open(.levels) },
                             onProfile: { model.open(.stats) },
                             rewards: AnyView(RewardsBar(model: model)))
                }
            case .over:
                GameOverView(snapshot: model.core.snapshot,
                             coinsEarned: model.lastCoinsEarned,
                             canRestart: model.canRestart,
                             canRevive: model.canRevive,
                             reviveCost: model.reviveCost,
                             onRevive: { model.reviveForCoins() },
                             onRestart: { model.startRun() },
                             onHome: { model.returnToMenu() })
            case .play:
                EmptyView()
            }

            if model.core.snapshot.mode == .menu, let sheet = model.activeSheet {
                metaSheet(sheet).transition(.move(edge: .bottom))
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
